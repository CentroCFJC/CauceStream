"""Shared pytest fixtures.

API tests run the FastAPI app in-process (httpx ASGITransport) against an
in-memory SQLite database. `get_session` is overridden so every request and
the seed use the same session. JWT and bcrypt settings are pinned via env
vars BEFORE importing the app for speed and hermeticity.
"""

import os
import shutil
import tempfile

# Must run before app imports: fast hashes and a fixed signing secret.
os.environ.setdefault("BCRYPT_ROUNDS", "4")
os.environ.setdefault("SECRET_KEY", "test-secret-key-0123456789abcdef")
os.environ.setdefault("LOG_LEVEL", "WARNING")

# Media storage: isolated temp dir and a tiny upload limit so oversize
# tests are cheap. Never the real backend/data/media directory.
MEDIA_TEST_DIR = os.path.join(tempfile.gettempdir(), "cauce-media-tests")
os.environ.setdefault("CAUCE_MEDIA_DIR", MEDIA_TEST_DIR)
os.environ.setdefault("CAUCE_MEDIA_MAX_SIZE_MB", "1")

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.api.deps import get_session
from app.core.security import hash_password
from app.core.seed import seed_initial_data
from app.core.database import Base
from app.main import app
from app.models import Role, User

ADMIN_EMAIL = "admin-user@example.com"
ADMIN_PASSWORD = "1234"
MEDIATOR_EMAIL = "mediator@example.com"
MEDIATOR_PASSWORD = "5678"


@pytest.fixture
async def db_engine():
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture(autouse=True)
def _clean_media_storage():
    """Wipe the test media directory around every test so files never
    leak between tests."""
    shutil.rmtree(MEDIA_TEST_DIR, ignore_errors=True)
    os.makedirs(MEDIA_TEST_DIR, exist_ok=True)
    yield
    shutil.rmtree(MEDIA_TEST_DIR, ignore_errors=True)


@pytest.fixture
async def db_session(db_engine):
    factory = async_sessionmaker(db_engine, expire_on_commit=False)
    async with factory() as session:
        await seed_initial_data(session)
        yield session


@pytest.fixture
async def client(db_session):
    async def override_get_session():
        yield db_session

    app.dependency_overrides[get_session] = override_get_session
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        yield test_client
    app.dependency_overrides.clear()


async def create_user_direct(
    db_session,
    email: str,
    password: str,
    role_name: str,
    *,
    is_active: bool = True,
    name: str | None = None,
) -> User:
    """Create a user straight through the ORM (test setup, not under test).

    Returns the user re-fetched through the repository so `role` and its
    `permissions` are loaded (async sessions cannot lazy-load).
    """
    role = await db_session.scalar(select(Role).where(Role.name == role_name))
    user = User(
        name=name or email,
        email=email,
        password_hash=await hash_password(password),
        role_id=role.id,
        is_active=is_active,
    )
    db_session.add(user)
    await db_session.commit()
    from app.repositories import UserRepository

    return await UserRepository(db_session).get_by_id(user.id)


async def login(client: httpx.AsyncClient, email: str, password: str) -> str:
    response = await client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def admin(db_session):
    return await create_user_direct(db_session, ADMIN_EMAIL, ADMIN_PASSWORD, "ADMINISTRADOR")


@pytest.fixture
async def mediator(db_session):
    return await create_user_direct(db_session, MEDIATOR_EMAIL, MEDIATOR_PASSWORD, "MEDIADOR")
