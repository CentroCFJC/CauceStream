"""Main API router. All /api routes are aggregated here."""

from fastapi import APIRouter

from app.api.routes import (
    assignments,
    auth,
    devices,
    health,
    media,
    roles,
    room,
    users,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(roles.router)
api_router.include_router(devices.router)
api_router.include_router(media.router)
api_router.include_router(assignments.router)
api_router.include_router(room.router)
