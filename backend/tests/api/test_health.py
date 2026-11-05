"""Tests for the health check and root endpoints."""


async def test_health_check(client):
    response = await client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_root(client):
    response = await client.get("/")

    assert response.status_code == 200
    assert response.json()["message"] == "Cauce backend is running"


async def test_openapi_schema_available(client):
    """The automatic documentation is served from the OpenAPI schema."""
    response = await client.get("/openapi.json")

    assert response.status_code == 200
    assert response.json()["info"]["title"] == "Cauce API"
