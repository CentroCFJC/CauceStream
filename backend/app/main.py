"""Cauce backend application entry point.

Run locally with:
    uvicorn app.main:app --reload
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import asyncio
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.core.database import AsyncSessionLocal, engine
from app.core.exceptions import register_exception_handlers
from app.core.logging import setup_logging
from app.core.seed import seed_initial_data
from app.core.tasks import offline_devices_sweep_loop
from app.services.device_service import DeviceService

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Manage startup/shutdown resources."""
    # Startup: ensure initial data (roles, permissions, bootstrap admin).
    try:
        async with AsyncSessionLocal() as session:
            await seed_initial_data(session)
    except Exception:
        logger.exception("Initial seed failed; is the database reachable?")

    # Startup: warn when device endpoints are open (transition mode).
    if not get_settings().CAUCE_DEVICE_SECRET:
        logger.warning(
            "CAUCE_DEVICE_SECRET is not set: device endpoints (heartbeat, "
            "playback WS, media download) accept unauthenticated clients"
        )

    # Startup: autoconfig discovery is always off after a restart, even
    # if it was enabled before shutting down.
    try:
        async with AsyncSessionLocal() as session:
            await DeviceService(session).reset_autoconfig()
    except Exception:
        logger.exception("Autoconfig startup reset failed")

    # Startup: offline detection must not depend on incoming requests.
    sweep_task = asyncio.create_task(offline_devices_sweep_loop())

    yield

    # Shutdown: stop the background sweep, then release connections.
    sweep_task.cancel()
    try:
        await sweep_task
    except asyncio.CancelledError:
        pass
    await engine.dispose()


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    settings = get_settings()
    setup_logging(settings)

    app = FastAPI(
        title=settings.APP_NAME,
        description=settings.APP_DESCRIPTION,
        version=settings.APP_VERSION,
        debug=settings.DEBUG,
        lifespan=lifespan,
    )

    # CORS is enabled only when CORS_ORIGINS is configured.
    if settings.cors_origins_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins_list,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    register_exception_handlers(app)

    app.include_router(api_router, prefix="/api")

    @app.get("/", include_in_schema=False)
    async def root() -> dict[str, str]:
        """Minimal root response indicating the backend is running."""
        return {"message": "Cauce backend is running", "docs": "/docs"}

    return app


app = create_app()
