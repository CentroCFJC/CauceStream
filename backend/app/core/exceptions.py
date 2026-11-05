"""Basic exception handling strategy for consistent HTTP error responses.

Domain-specific errors are not defined yet. When they are, they should
subclass `AppError`, declaring their own `status_code` and `code`.
"""

import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class AppError(Exception):
    """Base class for application errors.

    Raising an AppError (or a subclass) always produces a consistent JSON
    response: {"code": "<machine readable code>", "detail": "<message>"}.
    """

    status_code: int = 500
    code: str = "internal_error"

    def __init__(self, message: str = "Internal server error") -> None:
        self.message = message
        super().__init__(message)


class BadRequestError(AppError):
    """Malformed or invalid input (400)."""

    status_code = 400
    code = "bad_request"


class NotAuthenticatedError(AppError):
    """Missing or invalid credentials (401)."""

    status_code = 401
    code = "not_authenticated"


class DeviceAuthError(AppError):
    """Missing or invalid device key on a device-protocol endpoint (401)."""

    status_code = 401
    code = "device_key_invalid"


class PermissionDeniedError(AppError):
    """Authenticated user lacking a required permission (403)."""

    status_code = 403
    code = "permission_denied"


class UserInactiveError(AppError):
    """Account is logically disabled (403)."""

    status_code = 403
    code = "user_inactive"


class NotFoundError(AppError):
    """Resource not found (404)."""

    status_code = 404
    code = "not_found"


class ConflictError(AppError):
    """Uniqueness or state conflict, e.g. duplicated email (409)."""

    status_code = 409
    code = "conflict"


class PayloadTooLargeError(AppError):
    """Request body or upload exceeds the configured limit (413)."""

    status_code = 413
    code = "payload_too_large"


class HostCommandError(AppError):
    """A host-side command (PowerShell / Task Scheduler) failed or timed out (502)."""

    status_code = 502
    code = "host_command_failed"


def register_exception_handlers(app: FastAPI) -> None:
    """Register application-wide exception handlers on the FastAPI app."""

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
        if exc.status_code >= 500:
            logger.error(
                "Application error on %s %s",
                request.method,
                request.url.path,
                exc_info=exc,
            )
        else:
            logger.info(
                "Client error on %s %s: %s",
                request.method,
                request.url.path,
                exc.message,
            )
        return JSONResponse(
            status_code=exc.status_code,
            content={"code": exc.code, "detail": exc.message},
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """Return a consistent JSON 500 for unexpected errors."""
        logger.error(
            "Unhandled error on %s %s",
            request.method,
            request.url.path,
            exc_info=exc,
        )
        return JSONResponse(
            status_code=500,
            content={"code": "internal_error", "detail": "Internal server error"},
        )
