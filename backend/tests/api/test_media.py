"""Media (RF-008 phase 1) tests: uploads, URLs, listing, file access,
deletion, validation failures, oversize, DB-failure cleanup and
persistence of files across service restarts."""

import os

from app.core.config import Settings
from app.models import Media
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIA_TEST_DIR,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

PNG_BYTES = b"\x89PNG\r\n\x1a\n-fake-image-payload-"
MP4_BYTES = b"\x00\x00\x00\x18ftypmp42-fake-video-payload-"


async def upload(client, token, *, filename="foto.png", content=b"", mime=None,
                 media_type="image", name=None):
    data = {"media_type": media_type}
    if name is not None:
        data["name"] = name
    files = {"file": (filename, content, mime or "application/octet-stream")}
    return await client.post(
        "/api/media", data=data, files=files, headers=bearer(token)
    )


async def register_url(client, token, url="https://example.com/video/1", name="Ext"):
    return await client.post(
        "/api/media/urls", json={"name": name, "url": url}, headers=bearer(token)
    )


def stored_files():
    found = []
    for root, _dirs, files in os.walk(MEDIA_TEST_DIR):
        for f in files:
            found.append(os.path.join(root, f))
    return found


# --- Uploads (image / video) ---


async def test_upload_image_persists_metadata_and_file(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await upload(
        client, token, filename="portada.png", content=PNG_BYTES,
        mime="image/png", name="Portada sala",
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["media_type"] == "image"
    assert body["mime_type"] == "image/png"
    assert body["file_size"] == len(PNG_BYTES)
    assert body["name"] == "Portada sala"
    assert body["storage_key"].startswith("images/")
    assert body["external_url"] is None

    # The binary lives under the configured directory, at the storage key.
    path = os.path.join(MEDIA_TEST_DIR, *body["storage_key"].split("/"))
    assert os.path.isfile(path)
    with open(path, "rb") as f:
        assert f.read() == PNG_BYTES

    record = await db_session.get(Media, body["id"])
    assert record is not None


async def test_upload_video(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await upload(
        client, token, filename="loop.mp4", content=MP4_BYTES,
        mime="video/mp4", media_type="video",
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["media_type"] == "video"
    assert body["mime_type"] == "video/mp4"
    assert body["storage_key"].startswith("videos/")
    # No explicit name: the original filename is kept as metadata.
    assert body["name"] == "loop.mp4"


async def test_file_survives_service_restart(client, admin, db_session):
    """Storage keys resolve against the configured root (independent of
    the working directory), so files remain reachable after restarting
    uvicorn: a fresh Settings instance resolves the same physical path."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await upload(
        client, token, filename="persist.png", content=PNG_BYTES, mime="image/png"
    )
    assert response.status_code == 201
    storage_key = response.json()["storage_key"]

    # Simulated restart: brand-new settings + fresh resolution (env vars
    # only, never the real .env file).
    fresh_settings = Settings(_env_file=None)
    path = fresh_settings.media_dir.joinpath(*storage_key.split("/"))
    assert path.is_file()
    with open(path, "rb") as f:
        assert f.read() == PNG_BYTES


# --- External URLs ---


async def test_register_url(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await register_url(client, token)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["media_type"] == "url"
    assert body["external_url"] == "https://example.com/video/1"
    assert body["storage_key"] is None
    assert body["file_size"] is None
    assert stored_files() == []  # URLs never write files

    record = await db_session.get(Media, body["id"])
    assert record is not None


async def test_register_url_rejects_non_http_scheme(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(
        "/api/media/urls",
        json={"name": "X", "url": "ftp://example.com/file"},
        headers=bearer(token),
    )
    assert response.status_code == 422


# --- Listing / detail / file access ---


async def test_list_with_basic_pagination(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    for i in range(3):
        response = await register_url(client, token, name=f"URL {i}")
        assert response.status_code == 201

    page1 = await client.get("/api/media?limit=2", headers=bearer(token))
    assert page1.status_code == 200
    assert len(page1.json()) == 2

    rest = await client.get("/api/media?limit=2&offset=2", headers=bearer(token))
    assert rest.status_code == 200
    assert len(rest.json()) == 1


async def test_get_detail_and_file_bytes(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    created = (await upload(
        client, token, filename="a.png", content=PNG_BYTES, mime="image/png"
    )).json()

    detail = await client.get(
        f"/api/media/{created['id']}", headers=bearer(token)
    )
    assert detail.status_code == 200
    assert detail.json()["name"] == "a.png"

    content = await client.get(
        f"/api/media/{created['id']}/file", headers=bearer(token)
    )
    assert content.status_code == 200
    assert content.content == PNG_BYTES
    assert content.headers["content-type"].startswith("image/png")


async def test_url_media_has_no_file(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    created = (await register_url(client, token)).json()

    response = await client.get(
        f"/api/media/{created['id']}/file", headers=bearer(token)
    )
    assert response.status_code == 404


# --- Deletion ---


async def test_delete_removes_record_and_file(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    created = (await upload(
        client, token, filename="del.png", content=PNG_BYTES, mime="image/png"
    )).json()

    response = await client.delete(
        f"/api/media/{created['id']}", headers=bearer(token)
    )
    assert response.status_code == 204

    assert await db_session.get(Media, created["id"]) is None
    assert stored_files() == []  # the binary went away with the record

    again = await client.delete(
        f"/api/media/{created['id']}", headers=bearer(token)
    )
    assert again.status_code == 404


async def test_delete_url_leaves_no_files(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    created = (await register_url(client, token)).json()

    response = await client.delete(
        f"/api/media/{created['id']}", headers=bearer(token)
    )
    assert response.status_code == 204
    assert stored_files() == []


# --- Validation failures ---


async def test_invalid_media_type_rejected(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await upload(
        client, token, filename="song.mp3", content=b"id3", media_type="audio"
    )
    assert response.status_code == 422  # form enum: image|video


async def test_invalid_extension_rejected_and_nothing_written(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await upload(
        client, token, filename="notas.txt", content=b"hi", media_type="image"
    )
    assert response.status_code == 400
    assert response.json()["code"] == "bad_request"
    assert stored_files() == []


async def test_mime_mismatch_rejected(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await upload(
        client, token, filename="a.png", content=PNG_BYTES, mime="video/mp4",
        media_type="image",
    )
    assert response.status_code == 400
    assert stored_files() == []


async def test_oversize_rejected_without_partial_file(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    big = b"x" * (1024 * 1024 + 1)  # limit is 1 MB in the test env
    response = await upload(
        client, token, filename="big.mp4", content=big, mime="video/mp4",
        media_type="video",
    )
    assert response.status_code == 413
    assert response.json()["code"] == "payload_too_large"
    assert stored_files() == []  # no partial .part or final file


# --- Failure consistency: DB down after saving the file ---


async def test_db_failure_after_save_cleans_file(client, admin, db_session, monkeypatch):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    async def _boom():
        raise RuntimeError("database down")

    monkeypatch.setattr(db_session, "commit", _boom)

    response = await upload(
        client, token, filename="ghost.png", content=PNG_BYTES, mime="image/png"
    )
    assert response.status_code == 500
    assert stored_files() == []  # the saved file was rolled back/cleaned


# --- Permissions ---


async def test_permissions(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)

    no_token = await client.get("/api/media")
    assert no_token.status_code == 401

    # Mediator holds content.view: read-only access.
    listing = await client.get("/api/media", headers=bearer(mediator_token))
    assert listing.status_code == 200

    forbidden_create = await register_url(
        client, mediator_token, url="https://example.com/x", name="Nope"
    )
    assert forbidden_create.status_code == 403

    created = (await register_url(client, token, name="Admin")).json()
    forbidden_delete = await client.delete(
        f"/api/media/{created['id']}", headers=bearer(mediator_token)
    )
    assert forbidden_delete.status_code == 403


async def test_upload_pdf_persists_metadata_and_file(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    pdf_bytes = b"%PDF-1.4 fake-pdf-payload"

    response = await upload(
        client, token, filename="ficha.pdf", content=pdf_bytes,
        mime="application/pdf", media_type="pdf", name="Ficha sala",
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["media_type"] == "pdf"
    assert body["mime_type"] == "application/pdf"
    assert body["file_size"] == len(pdf_bytes)
    assert body["storage_key"].startswith("pdfs/")
    assert body["storage_key"].endswith(".pdf")

    path = os.path.join(MEDIA_TEST_DIR, *body["storage_key"].split("/"))
    with open(path, "rb") as f:
        assert f.read() == pdf_bytes


async def test_upload_pdf_rejects_wrong_extension(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await upload(
        client, token, filename="ficha.png", content=b"%PDF-1.4",
        mime="application/pdf", media_type="pdf",
    )
    assert response.status_code == 400
