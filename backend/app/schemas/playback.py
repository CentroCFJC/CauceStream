"""Playback WebSocket protocol schemas (server -> device and device -> server).

Protocol version 1. All messages are JSON with an explicit `type` and,
for server messages, the `protocol` number. `current_media` (what the
device actually plays) is still reported through heartbeats only: an
ACK here never changes the sync state.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.assignment import SyncStatus
from app.schemas.media import MediaType

PROTOCOL_VERSION = 1


class PlaybackMedia(BaseModel):
    """Library metadata of the assigned media, plus the real download
    reference available today: the existing HTTP file endpoint for
    image/video, or the external URL for `url` media. No URLs are
    invented."""

    name: str
    media_type: MediaType
    mime_type: str | None
    file_size: int | None
    file_url: str | None
    external_url: str | None


class PlaybackAssignment(BaseModel):
    """The desired assignment with its monotonic per-device revision."""

    assignment_id: int
    media_id: int
    revision: int = Field(ge=1)
    sync_status: SyncStatus
    media: PlaybackMedia


class PlaybackServerMessage(BaseModel):
    """`playback.sync` (on connect/reconnect: the current persisted
    state, `assignment: null` when there is none) and `playback.command`
    (after an assignment change is committed)."""

    type: Literal["playback.sync", "playback.command"]
    protocol: int = PROTOCOL_VERSION
    device_uid: str
    assignment: PlaybackAssignment | None
    sent_at: datetime


class PlaybackAck(BaseModel):
    """Client confirmation of receipt/processing of a command. Its only
    effect is logging: it never marks the assignment as played nor
    touches `current_media` (that stays in heartbeats)."""

    type: Literal["playback.ack"]
    assignment_id: int = Field(ge=1)
    revision: int = Field(ge=1)


class PlaybackErrorInfo(BaseModel):
    code: str = Field(max_length=50)
    message: str = Field(max_length=500)


class PlaybackClientError(BaseModel):
    """Client-side processing failure for a command. Logged; no state
    change."""

    type: Literal["playback.error"]
    assignment_id: int = Field(ge=1)
    revision: int = Field(ge=1)
    error: PlaybackErrorInfo


PowerAction = Literal["on", "off"]


class PowerServerMessage(BaseModel):
    """`power.command`: server-ordered screen state change. `on` means
    leaving standby, `off` entering it. The command is fire-and-forget
    over the live WS channel: the actual state keeps arriving through
    heartbeats (`device_state`), so an ACK here never marks anything.
    There is no `power.sync`: power commands are transient (nothing
    persisted to reconstruct), unlike assignments."""

    type: Literal["power.command"]
    protocol: int = PROTOCOL_VERSION
    device_uid: str
    command_id: int = Field(ge=1)
    action: PowerAction
    sent_at: datetime


class PowerAck(BaseModel):
    """Client confirmation of receipt/execution of a power command.
    Logged only: the authoritative state change arrives via heartbeat."""

    type: Literal["power.ack"]
    command_id: int = Field(ge=1)


class PowerClientError(BaseModel):
    """Client-side failure executing a power command (e.g. no
    permission to enter standby on this platform). Logged; no state
    change."""

    type: Literal["power.error"]
    command_id: int = Field(ge=1)
    error: PlaybackErrorInfo
