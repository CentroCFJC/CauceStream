"""Device schemas (API input/output)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, IPvAnyAddress, field_validator, model_validator

# Canonical MAC format accepted at registration and in heartbeats.
_MAC_PATTERN = r"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"


def _normalize_mac(value: str | None) -> str | None:
    """Normalize a MAC to upper-case colon-separated form."""
    return value.upper() if value else value

# Client-reported operational state. Generalizes screens and headless
# devices: `active` (in use / screen on) vs `idle` (standby / screen off).
# Independent of connectivity: an idle device keeps sending heartbeats and
# stays online.
DeviceState = Literal["active", "idle"]

# Keys a heartbeat `payload` may never carry: general-contract fields
# (including the retired `display_state` name), server-controlled data and
# the `current_app` alias. Keeps dynamic data from overriding device state.
# `current_application` is NOT reserved on purpose: legacy clients still
# send it, and it must pass through as an inert extra attribute instead
# of breaking their heartbeats.
_RESERVED_PAYLOAD_KEYS = frozenset(
    {
        "id",
        "device_uid",
        "name",
        "type",
        "status",
        "ip_address",
        "mac_address",
        "device_state",
        "display_state",
        "current_app",
        "last_seen",
        "payload",
    }
)


class DeviceRegister(BaseModel):
    """Payload for POST /api/devices.

    `device_uid` is the OS-configured device name, taken as the device
    exposes it (autoconfig flow): spaces and other characters are valid
    and it is never normalized.
    """

    device_uid: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)
    type: str = Field(min_length=1, max_length=50)
    ip_address: IPvAnyAddress | None = None
    port: int | None = Field(default=None, ge=1, le=65535)
    # MAC for server-side Wake-on-LAN power-on (app/power/). Optional:
    # devices that are never WoL targets can leave it empty.
    mac_address: str | None = Field(default=None, pattern=_MAC_PATTERN)

    @field_validator("mac_address")
    @classmethod
    def _upper_mac(cls, value: str | None) -> str | None:
        return _normalize_mac(value)


class DeviceUpdate(BaseModel):
    """Partial update of a registered device (PATCH /api/devices/{uid}).

    All fields optional; at least one must be present. `None` means
    "do not change" (nothing is ever cleared to null by a PATCH: the IP
    and MAC are client-reported live data).
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    # Canonical type that drives the server-side power controller
    # (app/power/): "google_tv"/"android_tv" -> ADB, etc.
    type: str | None = Field(default=None, min_length=1, max_length=50)
    ip_address: IPvAnyAddress | None = None
    mac_address: str | None = Field(default=None, pattern=_MAC_PATTERN)

    @field_validator("mac_address")
    @classmethod
    def _upper_mac(cls, value: str | None) -> str | None:
        return _normalize_mac(value)

    @model_validator(mode="after")
    def _at_least_one_field(self) -> "DeviceUpdate":
        if all(
            getattr(self, f) is None
            for f in ("name", "type", "ip_address", "mac_address")
        ):
            raise ValueError("at least one field must be provided")
        return self


class HeartbeatData(BaseModel):
    """Device-specific dynamic attributes of a heartbeat.

    Extensible: unknown attributes are accepted as-is so each device type
    reports only what it can measure reliably. Known attributes are
    validated when present; all of them are optional (a missing attribute
    never means false/zero/null).

    Reserved keys are rejected so no dynamic attribute can masquerade as a
    general field or server-controlled data (device identity, type,
    connectivity, etc.).
    """

    model_config = ConfigDict(extra="allow")

    port: int | None = Field(default=None, ge=1, le=65535)
    battery_level: int | None = Field(default=None, ge=0, le=100)
    is_charging: bool | None = None
    power_source: str | None = Field(default=None, max_length=50)
    # Media the device reports playing: the Media.id (integer) from the
    # library. Absent, null or non-identifying values are stored by the
    # server as "unknown". The retired `current_application` (an
    # application-name string) is NOT a media and is never interpreted
    # as one: legacy clients may keep sending it as an inert extra
    # attribute.
    current_media: int | str | None = Field(default=None)

    @model_validator(mode="after")
    def _reject_reserved_keys(self) -> "HeartbeatData":
        reserved = _RESERVED_PAYLOAD_KEYS & set(self.model_extra or {})
        if reserved:
            raise ValueError(
                f"payload keys are reserved for the general contract: "
                f"{sorted(reserved)}"
            )
        return self


class HeartbeatPayload(BaseModel):
    """Payload for POST /api/devices/{device_uid}/heartbeat.

    General transversal fields are `ip_address`, `mac_address` and
    `device_state` (valid for any device type, with or without a screen).
    Everything else - including `current_media` - is a device-specific
    attribute in the optional `payload` object (see HeartbeatData). The
    device never reports `status` (connectivity) - the server derives it
    from heartbeat recency.
    """

    ip_address: IPvAnyAddress
    # Optional: reported once by clients that support server-side
    # Wake-on-LAN power-on; a missing value never clears the stored MAC.
    mac_address: str | None = Field(default=None, pattern=_MAC_PATTERN)
    device_state: DeviceState
    payload: HeartbeatData = Field(default_factory=HeartbeatData)

    @field_validator("mac_address")
    @classmethod
    def _upper_mac(cls, value: str | None) -> str | None:
        return _normalize_mac(value)


class DeviceRead(BaseModel):
    """Device representation."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    device_uid: str
    name: str
    type: str
    ip_address: str | None
    mac_address: str | None
    port: int | None
    status: str
    device_state: str | None
    current_media: str | None
    payload: dict | None = None
    last_seen: datetime | None
    created_at: datetime
    updated_at: datetime
    # Live playback WebSocket channel (server -> device). This is
    # process-local connection state, not persisted data: False simply
    # means the device is not connected right now (commands are
    # delivered via `playback.sync` on its next connection). Never
    # derived from the heartbeat-based `status`.
    ws_connected: bool = False


class HeartbeatResponse(BaseModel):
    """Small, useful confirmation for the device client."""

    device_uid: str
    status: str
    device_state: str | None
    current_media: str | None
    payload: dict | None = None
    last_seen: datetime | None


class DevicePowerAction(BaseModel):
    """Payload for POST /api/devices/{device_uid}/power.

    `on` = leave standby (screen on), `off` = enter standby (screen
    off). The server executes the action through the power controller
    registered for the device's `type` (e.g. ADB for Android TV boxes,
    using the IP the device reported in its heartbeat); types without a
    native controller fall back to the device's live WebSocket channel.
    The resulting state keeps arriving through heartbeats.
    """

    action: Literal["on", "off"]


class DevicePowerResult(BaseModel):
    """Outcome of a power command executed through the device's type
    controller (or the WebSocket fallback).

    - `method`: controller that ran ("adb", "wol+adb", "websocket", ...).
    - `executed`: True when the action was actually carried out, False
      when the device was already in the requested state (idempotent).
    - `success`/`detail`: outcome of the attempt. `success=False` is a
      normal business answer (device unreachable, no IP, ...), not an
      HTTP error.
    - `command_id`/`delivered`: only meaningful for `method="websocket"`
      (kept for compatibility with the previous contract).
    """

    device_uid: str
    action: Literal["on", "off"]
    method: str
    executed: bool
    success: bool
    detail: str = ""
    command_id: int | None = None
    delivered: bool = False


class AutoconfigToggle(BaseModel):
    """Payload for POST /api/devices/autoconfig."""

    enabled: bool


class AutoconfigStatus(BaseModel):
    """Current autoconfig mode after a toggle (or query)."""

    enabled: bool


class PendingDeviceRead(BaseModel):
    """A device detected via heartbeats while autoconfig is enabled,
    still unregistered. `payload` is deliberately NOT exposed."""

    model_config = ConfigDict(from_attributes=True)

    device_uid: str
    ip_address: str
    device_state: str
    last_seen: datetime


class PendingDeviceList(BaseModel):
    """Response of GET /api/devices/autoconfig/pending."""

    devices: list[PendingDeviceRead]


class DeviceEventRead(BaseModel):
    """A relevant change in a device's state."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    event_type: str
    previous_value: str | None
    new_value: str | None
    created_at: datetime
