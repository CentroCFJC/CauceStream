"""Filesystem storage for media binaries (RF-008).

Keys are relative (`images/<uuid>.png`); physical paths are resolved
against the configured media directory. The original filename is never
used as a path, uploads are written atomically (temp file + rename) so
failures never leave partial files, and every resolved path is checked
for containment to make traversal impossible.
"""

import os
import uuid
from pathlib import Path

from fastapi import UploadFile

from app.core.exceptions import BadRequestError, PayloadTooLargeError

# Bytes read per chunk while streaming an upload.
CHUNK_SIZE = 1024 * 1024

# Extension -> canonical MIME, per uploadable media type. The extension
# is authoritative for validation; the declared MIME is checked against
# it when the client provides one.
ALLOWED_EXTENSIONS: dict[str, dict[str, str]] = {
    "image": {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    },
    "video": {
        ".mp4": "video/mp4",
        ".webm": "video/webm",
        ".ogg": "video/ogg",
        ".mov": "video/quicktime",
        ".mkv": "video/x-matroska",
    },
    "pdf": {
        ".pdf": "application/pdf",
    },
}


def validate_upload(media_type: str, filename: str, content_type: str | None) -> tuple[str, str]:
    """Validate extension/MIME for the media type; return the canonical
    MIME that will be persisted and the validated extension."""
    allowed = ALLOWED_EXTENSIONS.get(media_type)
    if allowed is None:
        raise BadRequestError(f"Media type {media_type!r} does not accept file uploads")

    extension = Path(filename or "").suffix.lower()
    if extension not in allowed:
        raise BadRequestError(
            f"Extension {extension or '(none)'} not allowed for {media_type}; "
            f"allowed: {', '.join(sorted(allowed))}"
        )
    canonical_mime = allowed[extension]
    if (
        content_type
        and content_type not in (canonical_mime, "application/octet-stream")
    ):
        raise BadRequestError(
            f"Declared MIME {content_type!r} does not match the extension "
            f"{extension} ({canonical_mime})"
        )
    return canonical_mime, extension


def storage_key_for(media_type: str, extension: str) -> str:
    """Unique, unpredictable storage key; the original filename never
    takes part in the physical path."""
    return f"{media_type}s/{uuid.uuid4().hex}{extension}"


def resolve_path(media_dir: Path, storage_key: str) -> Path:
    """Resolve a storage key to a physical path inside `media_dir`.

    Raises if the key would escape the media root (directory traversal).
    """
    root = media_dir.resolve()
    path = (root / storage_key).resolve()
    if not path.is_relative_to(root):
        raise BadRequestError("Invalid storage key")
    return path


async def save_stream(
    media_dir: Path, storage_key: str, file: UploadFile, max_bytes: int
) -> int:
    """Stream an upload to disk atomically; return the written size.

    Writes to a `.part` sibling first and renames on success, so a failure
    (including exceeding the size limit mid-stream) never leaves a
    partial file under the final name.
    """
    target = resolve_path(media_dir, storage_key)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_name(target.name + ".part")

    size = 0
    try:
        with open(temp, "wb") as out:
            while True:
                chunk = await file.read(CHUNK_SIZE)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes:
                    raise PayloadTooLargeError(
                        f"File exceeds the maximum size of "
                        f"{max_bytes // (1024 * 1024)} MB"
                    )
                out.write(chunk)
        os.replace(temp, target)
    except Exception:
        temp.unlink(missing_ok=True)
        raise
    return size


def delete_file(media_dir: Path, storage_key: str) -> bool:
    """Delete the file of a record, only if it resolves inside the media
    root (i.e. it provably belongs to that record's storage)."""
    path = resolve_path(media_dir, storage_key)
    if path.is_file():
        path.unlink()
        return True
    return False
