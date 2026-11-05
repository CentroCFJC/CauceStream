"""Media endpoints (RF-008, phase 1).

Queries and file access require `content.view`; creation and deletion
require `content.manage`. Uploads come as multipart/form-data; external
URLs are registered with a JSON body. No assignment to devices,
playback or real-time delivery here: that is out of this phase.
"""

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    Header,
    Query,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse

from app.api.deps import get_media_service, get_optional_user, require_permission
from app.core.authorization import ensure_permission
from app.core.device_auth import verify_device_key
from app.core.exceptions import NotAuthenticatedError
from app.models.user import User
from app.schemas.media import MediaRead, MediaUrlCreate, UploadMediaType
from app.services.media_service import MAX_LIST_LIMIT, MediaService

router = APIRouter(prefix="/media", tags=["media"])


@router.post(
    "",
    response_model=MediaRead,
    status_code=status.HTTP_201_CREATED,
    summary="Upload an image, video or PDF",
)
async def create_media(
    media_type: Annotated[UploadMediaType, Form(description="image | video | pdf")],
    file: Annotated[UploadFile, File(description="Binary file")],
    name: Annotated[str | None, Form(max_length=255)] = None,
    actor: User = Depends(require_permission("content.manage")),
    service: MediaService = Depends(get_media_service),
):
    """Store the file on the server disk (atomic write, unique storage
    key, original filename kept only as metadata) and register its
    metadata. Validated: extension and declared MIME per type, and the
    configured maximum size (CAUCE_MEDIA_MAX_SIZE_MB)."""
    return await service.create_from_upload(media_type, name, file)


@router.post(
    "/urls",
    response_model=MediaRead,
    status_code=status.HTTP_201_CREATED,
    summary="Register an external URL",
)
async def create_media_url(
    payload: MediaUrlCreate,
    actor: User = Depends(require_permission("content.manage")),
    service: MediaService = Depends(get_media_service),
):
    """Register an external http/https URL with its metadata. The
    backend never downloads or follows it."""
    return await service.create_from_url(payload)


@router.get(
    "",
    response_model=list[MediaRead],
    summary="List media (basic pagination)",
)
async def list_media(
    limit: Annotated[int, Query(ge=1, le=MAX_LIST_LIMIT)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    actor: User = Depends(require_permission("content.view")),
    service: MediaService = Depends(get_media_service),
):
    """Newest first."""
    return await service.list_media(limit, offset)


@router.get(
    "/{media_id}",
    response_model=MediaRead,
    summary="Media detail",
)
async def get_media(
    media_id: int,
    actor: User = Depends(require_permission("content.view")),
    service: MediaService = Depends(get_media_service),
):
    return await service.get_media(media_id)


@router.get(
    "/{media_id}/file",
    response_class=FileResponse,
    summary="Download/view a stored file",
)
async def get_media_file(
    media_id: int,
    actor: Annotated[User | None, Depends(get_optional_user)] = None,
    device_key: Annotated[str | None, Header(alias="X-Device-Key")] = None,
    service: MediaService = Depends(get_media_service),
):
    """Streams the stored binary (uploads only; url media has no file).
    The `Content-Type` is the persisted MIME.

    Dual authentication: a user holding `content.view` OR a device
    client presenting the shared device key (X-Device-Key header,
    CAUCE_DEVICE_SECRET) - this is how Cauce Stream clients download
    the media the server assigns to them.

    The session is closed BEFORE returning the FileResponse: dependency
    teardown runs only after the response is fully sent, so the pooled
    connection would otherwise stay checked out for the whole duration
    of the file transfer (with many devices downloading at once the
    pool would starve heartbeats and WS handshakes). close() is safe
    to call again during teardown.
    """
    if not verify_device_key(device_key):
        if actor is None:
            raise NotAuthenticatedError("Not authenticated")
        ensure_permission(actor, "content.view")
    media = await service.get_media(media_id)
    path = await service.get_file_path(media_id)
    await service.session.close()
    return FileResponse(
        path,
        media_type=media.mime_type,
        filename=media.name,
        content_disposition_type="inline",
    )


@router.delete(
    "/{media_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a medium",
)
async def delete_media(
    media_id: int,
    actor: User = Depends(require_permission("content.manage")),
    service: MediaService = Depends(get_media_service),
):
    """Deletes the metadata record and, only after verifying it belongs
    to that record, the associated file. External URLs leave no file."""
    await service.delete_media(media_id)
