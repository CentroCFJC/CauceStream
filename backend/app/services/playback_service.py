"""Playback message builders and inbound validation.

Server messages are always built from the PERSISTED state: `playback.sync`
reads the vigente assignment from the database, `playback.command` is built
after the assignment change is committed. No message ever claims the media
is playing: that is reported by the device through heartbeats.
"""

import json
import logging

from pydantic import ValidationError

from app.models import DeviceMediaAssignment, Media
from app.schemas.playback import (
    PROTOCOL_VERSION,
    PlaybackAck,
    PlaybackClientError,
    PlaybackServerMessage,
    PowerAck,
    PowerClientError,
    PowerServerMessage,
)
from app.utils.time import utc_now

logger = logging.getLogger(__name__)

# Hard cap for inbound client messages (ACKs/errors are tiny).
MAX_INBOUND_MESSAGE_BYTES = 8 * 1024

ClientMessage = PlaybackAck | PlaybackClientError | PowerAck | PowerClientError


def _assignment_payload(assignment: DeviceMediaAssignment, media: Media) -> dict:
    file_url = (
        f"/api/media/{media.id}/file"
        if media.media_type in ("image", "video", "pdf")
        else None
    )
    return {
        "assignment_id": assignment.id,
        "media_id": assignment.media_id,
        "revision": assignment.revision,
        "sync_status": assignment.sync_status,
        "media": {
            "name": media.name,
            "media_type": media.media_type,
            "mime_type": media.mime_type,
            "file_size": media.file_size,
            "file_url": file_url,
            "external_url": media.external_url,
        },
    }


def build_sync_message(device_uid: str, row) -> dict:
    """`playback.sync`: the current persisted assignment (or an explicit
    null) for a device reconnecting. `row` is the
    (assignment, device_uid, media) tuple or None."""
    assignment = None if row is None else _assignment_payload(row[0], row[2])
    message = PlaybackServerMessage(
        type="playback.sync",
        protocol=PROTOCOL_VERSION,
        device_uid=device_uid,
        assignment=assignment,
        sent_at=utc_now(),
    )
    return message.model_dump(mode="json")


def build_command_message(device_uid: str, row) -> dict:
    """`playback.command`: a fresh assignment change, sent only after the
    change is committed. Built from the row re-read after commit, so it
    always carries the newest persisted state and revision."""
    message = PlaybackServerMessage(
        type="playback.command",
        protocol=PROTOCOL_VERSION,
        device_uid=device_uid,
        assignment=_assignment_payload(row[0], row[2]),
        sent_at=utc_now(),
    )
    return message.model_dump(mode="json")


def build_power_command_message(device_uid: str, action: str, command_id: int) -> dict:
    """`power.command`: a screen power order for the device channel.
    `action` is `"on"` (leave standby) or `"off"` (enter standby). The
    command id is allocated by the connection manager and validated
    against its inbound ACKs."""
    message = PowerServerMessage(
        type="power.command",
        protocol=PROTOCOL_VERSION,
        device_uid=device_uid,
        command_id=command_id,
        action=action,
        sent_at=utc_now(),
    )
    return message.model_dump(mode="json")


def parse_client_message(raw: str) -> ClientMessage | None:
    """Validate an inbound client message. Malformed or unknown messages
    are ignored (None), never fatal: a bad client must not break the
    connection or the backend."""
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    message_type = data.get("type")
    try:
        if message_type == "playback.ack":
            return PlaybackAck.model_validate(data)
        if message_type == "playback.error":
            return PlaybackClientError.model_validate(data)
        if message_type == "power.ack":
            return PowerAck.model_validate(data)
        if message_type == "power.error":
            return PowerClientError.model_validate(data)
    except ValidationError:
        logger.info("Ignoring malformed playback message type=%s", message_type)
    return None
