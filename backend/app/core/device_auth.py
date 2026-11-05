"""Shared-secret authentication for device-protocol endpoints.

The server and every Cauce Stream client share a secret
(`CAUCE_DEVICE_SECRET`). It protects the endpoints devices - not users -
call: the heartbeat, the playback WebSocket and the media file download.

When the secret is not configured, device authentication is DISABLED
(transition mode): requests are accepted as today and a warning is
logged at startup. Setting the same secret on the server and the
clients enforces it everywhere.

The comparison is constant-time; the key is never logged.
"""

import hmac
import logging

from fastapi import Header

from app.core.config import get_settings
from app.core.exceptions import DeviceAuthError

logger = logging.getLogger(__name__)

DEVICE_KEY_HEADER = "X-Device-Key"


def verify_device_key(device_key: str | None) -> bool:
    """True when the request carries the configured device key.

    No secret configured -> authentication disabled (transition mode).
    """
    secret = get_settings().CAUCE_DEVICE_SECRET
    if not secret:
        return True
    return device_key is not None and hmac.compare_digest(
        device_key.strip(), secret
    )


def require_device_key(
    device_key: str | None = Header(default=None, alias=DEVICE_KEY_HEADER),
) -> None:
    """FastAPI dependency: reject the request unless the device key is
    valid (401 with a specific code)."""
    if not verify_device_key(device_key):
        logger.info("Rejected device request with missing/invalid key")
        raise DeviceAuthError("Missing or invalid device key")
