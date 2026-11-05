"""In-memory WebSocket connection manager for the device channel.

One connection per registered device, identified by `device_uid`, carrying
the playback protocol (sync/command) and the power commands
(`power.command`). This is deliberately process-local state (no
Redis/external brokers for the MVP):

- Real-time notifications therefore require a SINGLE backend process
  (one uvicorn worker); connections are not shared between workers.
- PostgreSQL remains the source of truth: on reconnect, the `playback.sync`
  message is built from the persisted assignment, so the state is fully
  reconstructed after a restart or a lost notification.

All sends are isolated: a failing or abruptly-closed client never breaks
HTTP requests, heartbeats or other clients.

ACK watchdog: every `playback.command` delivered to a live socket arms a
per-device timer correlated with (socket, assignment_id, revision). A
matching `playback.ack`/`playback.error` cancels it; an ACK for an older
command does NOT (it is validated against the pending command, not just
the device). On expiry the dead channel is closed (4001) and dropped from
the inventory, so `ws_connected` stops lying about half-open sockets. The
client then reconnects with its existing backoff and recovers through
`playback.sync`.
"""

import asyncio
import json
import logging

from fastapi import WebSocket

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Close codes (application-level conventions documented in the README).
WSC_POLICY_VIOLATION = 1008  # unregistered device
WSC_MESSAGE_TOO_LARGE = 1009
WSC_INTERNAL_ERROR = 1011  # handshake failure (e.g. database access)
WSC_REPLACED = 4000  # same device connected again: newest wins
WSC_ACK_TIMEOUT = 4001  # playback command never acked: dead channel

# Deadline for a delivered playback.command to be acked/errored. Only
# armed when the send actually reached a live socket. Defaults from
# settings (CAUCE_PLAYBACK_ACK_TIMEOUT_S) but stays a module constant so
# tests can monkeypatch it.
ACK_TIMEOUT_SECONDS = get_settings().CAUCE_PLAYBACK_ACK_TIMEOUT_S


class _PendingAck:
    """Watchdog state for one delivered playback.command."""

    __slots__ = ("timer", "websocket", "assignment_id", "revision")

    def __init__(
        self,
        timer: asyncio.TimerHandle,
        websocket: WebSocket,
        assignment_id: int | None,
        revision: int | None,
    ) -> None:
        self.timer = timer
        self.websocket = websocket
        self.assignment_id = assignment_id
        self.revision = revision


class DeviceConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, WebSocket] = {}
        # Last playback command sent per device (used to validate inbound
        # ACKs).
        self._last_command: dict[str, dict] = {}
        # ACK watchdog per device: only one delivered command is ever
        # pending; a newer delivery supersedes (re-arms) the previous.
        self._pending_acks: dict[str, _PendingAck] = {}
        # Monotonic per-device power command ids and the last power command
        # sent (same validation and newest-wins semantics as playback).
        self._power_seq: dict[str, int] = {}
        self._last_power_command: dict[str, dict] = {}

    # --- Connection lifecycle ---

    async def connect(self, device_uid: str, websocket: WebSocket) -> bool:
        """Register a connection, replacing any previous one for the same
        device (the newest connection wins). Returns True when an older
        connection was replaced."""
        old = self._connections.get(device_uid)
        self._connections[device_uid] = websocket
        # A fresh connection implies a fresh `playback.sync` with the
        # persisted assignment: any pending unconfirmed command of the
        # old socket is superseded, never a reason to close the new one.
        self._clear_pending_ack(device_uid)
        if old is not None and old is not websocket:
            try:
                await old.close(code=WSC_REPLACED, reason="Replaced by a newer connection")
            except Exception:
                logger.debug("Old socket for %s was already gone", device_uid)
            return True
        return False

    def disconnect(self, device_uid: str, websocket: WebSocket) -> None:
        """Drop the connection only if it is still the current one for the
        device (a dying old socket must never unregister the new one)."""
        if self._connections.get(device_uid) is websocket:
            del self._connections[device_uid]
        if self._pending_acks.get(device_uid) is not None:
            pending = self._pending_acks[device_uid]
            if pending.websocket is websocket:
                self._clear_pending_ack(device_uid)

    def has(self, device_uid: str) -> bool:
        return device_uid in self._connections

    @property
    def connection_count(self) -> int:
        return len(self._connections)

    # --- Notifications ---

    async def send_command(self, device_uid: str, message: dict) -> bool:
        """Send a playback command to the device if connected. Never
        raises: failures are logged and the broken connection is cleaned
        up. The message is always remembered as the last desired state,
        connected or not.

        Returns True ONLY when the write to the socket completed without
        error: this is "sent", never "received" or "executed" (that is
        confirmed by heartbeats). On a successful send the ACK watchdog
        is armed for this exact command.
        """
        self._last_command[device_uid] = message
        websocket = self._connections.get(device_uid)
        if websocket is None:
            return False
        try:
            await websocket.send_text(json.dumps(message))
        except Exception:
            logger.warning(
                "Playback notification failed for %s; dropping connection",
                device_uid,
                exc_info=True,
            )
            self.disconnect(device_uid, websocket)
            return False
        self._arm_ack_watchdog(device_uid, websocket, message)
        return True

    def _arm_ack_watchdog(
        self, device_uid: str, websocket: WebSocket, message: dict
    ) -> None:
        """Arm (or re-arm) the per-device ACK deadline for THIS command."""
        self._clear_pending_ack(device_uid)
        assignment = message.get("assignment") or {}
        loop = asyncio.get_running_loop()
        timer = loop.call_later(
            ACK_TIMEOUT_SECONDS,
            lambda: asyncio.create_task(
                self._ack_timeout(device_uid, websocket)
            ),
        )
        self._pending_acks[device_uid] = _PendingAck(
            timer=timer,
            websocket=websocket,
            assignment_id=assignment.get("assignment_id"),
            revision=assignment.get("revision"),
        )

    def _clear_pending_ack(self, device_uid: str) -> None:
        pending = self._pending_acks.pop(device_uid, None)
        if pending is not None:
            pending.timer.cancel()

    async def _ack_timeout(self, device_uid: str, websocket: WebSocket) -> None:
        """Deadline expired for the command delivered to this socket."""
        pending = self._pending_acks.get(device_uid)
        # Identity guard: never close a socket that replaced the one the
        # pending command was sent to (it already got a fresh sync).
        if pending is None or pending.websocket is not websocket:
            return
        logger.warning(
            "Playback ACK timeout for %s; closing dead channel "
            "(assignment %s revision %s)",
            device_uid,
            pending.assignment_id,
            pending.revision,
        )
        self._clear_pending_ack(device_uid)
        try:
            await websocket.close(code=WSC_ACK_TIMEOUT, reason="Playback ACK timeout")
        except Exception:
            logger.debug("Timed-out socket for %s was already gone", device_uid)
        self.disconnect(device_uid, websocket)

    def note_response(
        self, device_uid: str, assignment_id: int, revision: int
    ) -> bool:
        """Cancel the ACK watchdog when the device answers THIS pending
        command (matching assignment_id AND revision). An ACK for an
        older command never cancels the watchdog of a newer delivery.
        Returns True when a pending watchdog was cancelled.
        """
        pending = self._pending_acks.get(device_uid)
        if pending is None:
            return False
        if pending.assignment_id == assignment_id and pending.revision == revision:
            self._clear_pending_ack(device_uid)
            return True
        return False

    def matches_last_command(
        self, device_uid: str, assignment_id: int, revision: int
    ) -> bool:
        """Validate an inbound ACK/error against the last command of THIS
        device: stale confirmations (older revision) or foreign
        assignment ids are rejected."""
        command = self._last_command.get(device_uid)
        if command is None or command.get("assignment") is None:
            return False
        assignment = command["assignment"]
        return (
            assignment["assignment_id"] == assignment_id
            and assignment["revision"] == revision
        )

    def next_power_command_id(self, device_uid: str) -> int:
        """Allocate a fresh monotonic command id for a power command.
        Process-local: it only feeds in-memory ACK validation, so a
        restart may reuse ids (stale ACKs from the old process are
        already meaningless)."""
        seq = self._power_seq.get(device_uid, 0) + 1
        self._power_seq[device_uid] = seq
        return seq

    async def send_power_command(self, device_uid: str, message: dict) -> bool:
        """Send a power command to the device if connected. Same
        isolation contract as send_command: never raises, drops broken
        connections, and always remembers the command as the last one of
        this device (the newest wins; ACKs validate against it)."""
        self._last_power_command[device_uid] = message
        websocket = self._connections.get(device_uid)
        if websocket is None:
            return False
        try:
            await websocket.send_text(json.dumps(message))
            return True
        except Exception:
            logger.warning(
                "Power notification failed for %s; dropping connection",
                device_uid,
                exc_info=True,
            )
            self.disconnect(device_uid, websocket)
            return False

    def matches_power_command(self, device_uid: str, command_id: int) -> bool:
        """Validate an inbound power ACK/error against the last power
        command of THIS device: stale confirmations (older command ids)
        are rejected."""
        command = self._last_power_command.get(device_uid)
        return command is not None and command.get("command_id") == command_id

    def reset(self) -> None:
        """Test helper: forget every connection and command."""
        for pending in self._pending_acks.values():
            pending.timer.cancel()
        self._pending_acks.clear()
        self._connections.clear()
        self._last_command.clear()
        self._power_seq.clear()
        self._last_power_command.clear()


# Application-level singleton shared by the WS endpoint and the
# assignment service (single-process notifications).
connection_manager = DeviceConnectionManager()
