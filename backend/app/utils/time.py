"""Time helpers. All backend timestamps are timezone-aware UTC."""

from datetime import UTC, datetime


def utc_now() -> datetime:
    """Current timezone-aware UTC datetime."""
    return datetime.now(UTC)
