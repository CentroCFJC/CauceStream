"""Centralized application configuration.

All settings are loaded from environment variables (optionally from a .env
file) through Pydantic Settings. No other module should read os.getenv()
directly; import `get_settings()` from here instead.
"""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEV_SECRET = "dev-secret-key-change-me-0123456789"


class Settings(BaseSettings):
    """Application settings.

    Attributes are populated from environment variables (case-insensitive),
    falling back to the defaults defined here.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Application
    APP_NAME: str = "Cauce API"
    APP_DESCRIPTION: str = (
        "Backend del sistema Cauce: administracion de usuarios y roles, "
        "dispositivos cliente, estado y disponibilidad, heartbeats, "
        "configuracion de dispositivos, experiencias de la Sala Cauce, "
        "distribucion y reproduccion de contenido, programaciones y "
        "comunicacion servidor-dispositivos."
    )
    APP_VERSION: str = "0.1.0"
    APP_ENV: Literal["development", "testing", "production"] = "development"
    DEBUG: bool = True

    # Database (PostgreSQL, async driver)
    DATABASE_URL: str = "postgresql+asyncpg://cauce:cauce@localhost:5432/cauce"
    # Echo every SQL statement to the logs. Deliberately independent of
    # DEBUG: the periodic device sweep would otherwise flood the console.
    DB_ECHO: bool = False

    # CORS: comma-separated list of allowed origins, e.g.
    # "http://localhost:3000,http://localhost:5173". Empty disables CORS.
    CORS_ORIGINS: str = ""

    # Logging: DEBUG | INFO | WARNING | ERROR | CRITICAL
    LOG_LEVEL: str = "INFO"

    # Authentication (local JWT, no external providers)
    SECRET_KEY: str = _DEV_SECRET
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480
    BCRYPT_ROUNDS: int = 12

    # Bootstrap administrator, created by the seed only when no
    # ADMINISTRADOR user exists yet.
    BOOTSTRAP_ADMIN_NAME: str = "Administrador"
    BOOTSTRAP_ADMIN_EMAIL: str = "admin@example.com"
    BOOTSTRAP_ADMIN_PASSWORD: str = "0000"

    # Shared secret between the server and every Cauce Stream client
    # (X-Device-Key header on device endpoints: heartbeat, playback WS,
    # media file download). Empty = device authentication disabled
    # (transition mode); the same value must be configured on all
    # clients.
    CAUCE_DEVICE_SECRET: str = ""

    # Devices: a device goes offline after this many seconds without a
    # valid heartbeat; the sweep task checks every few seconds.
    DEVICE_OFFLINE_AFTER_SECONDS: int = 30
    DEVICE_SWEEP_INTERVAL_SECONDS: int = 10

    # Autoconfig: a discovered device stays in the pending list only
    # while it keeps sending heartbeats within this window.
    AUTOCONFIG_PENDING_TTL_SECONDS: int = 30

    # Media storage (RF-008): root directory for uploaded binaries.
    # - Absolute path: used as-is (Docker: /app/data/media with a volume).
    # - Relative path: resolved against the backend project root.
    # - Empty: stable default <backend>/data/media (independent of the
    #   working directory uvicorn is started from).
    CAUCE_MEDIA_DIR: str = ""
    # Maximum accepted upload size in MB.
    CAUCE_MEDIA_MAX_SIZE_MB: int = 200

    # TEMPORAL room power (see backend/docs/room_power_temporal.md):
    # names of the Windows Scheduled Tasks that turn the whole room on
    # and off. Only used while the backend runs natively on the Windows
    # server; replaced by the per-device master control later.
    CAUCE_ROOM_ON_TASK: str = "Cauce_ON"
    CAUCE_ROOM_OFF_TASK: str = "Cauce_OFF"

    # Per-device power control executed BY THE SERVER against the IP the
    # device itself reports in its heartbeat (see app/power/). The backend
    # runs natively on the Windows server, so it shells out to adb.
    CAUCE_ADB_PATH: str = "adb"
    # TCP port of the on-device adb daemon (adb tcpip 5555).
    CAUCE_ADB_PORT: int = 5555
    CAUCE_ADB_CONNECT_TIMEOUT_S: float = 10.0
    CAUCE_ADB_SHELL_TIMEOUT_S: float = 10.0
    CAUCE_PING_TIMEOUT_S: float = 5.0
    # How long `on` waits for the device to answer ping after Wake-on-LAN,
    # and the interval between ping attempts.
    CAUCE_POWER_ON_BOOT_WAIT_S: float = 60.0
    CAUCE_POWER_ON_PING_INTERVAL_S: float = 3.0
    # Global deadline for one per-device power command (HTTP 504 past it).
    CAUCE_POWER_TOTAL_TIMEOUT_S: float = 90.0
    # UDP ports for Wake-on-LAN magic packets (comma-separated).
    CAUCE_WOL_PORTS: str = "9,7"

    # Deadline for a delivered playback.command to be acked/errored by the
    # device (the watchdog closes the dead channel after it). Generous
    # default: the client may still be downloading a large media file.
    CAUCE_PLAYBACK_ACK_TIMEOUT_S: float = 30.0

    @property
    def media_dir(self) -> Path:
        """Resolve the media root directory (never the working dir)."""
        root = Path(__file__).resolve().parents[2]
        raw = self.CAUCE_MEDIA_DIR.strip()
        if not raw:
            return root / "data" / "media"
        candidate = Path(raw).expanduser()
        return candidate if candidate.is_absolute() else root / candidate

    @property
    def media_max_size_bytes(self) -> int:
        return self.CAUCE_MEDIA_MAX_SIZE_MB * 1024 * 1024

    @property
    def cors_origins_list(self) -> list[str]:
        """Parse CORS_ORIGINS into a list of origins."""
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @property
    def wol_ports(self) -> list[int]:
        """Parse CAUCE_WOL_PORTS into a list of UDP ports."""
        ports = []
        for part in self.CAUCE_WOL_PORTS.split(","):
            part = part.strip()
            if part.isdigit():
                ports.append(int(part))
        return ports or [9]

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"

    @model_validator(mode="after")
    def _validate_production_secrets(self) -> "Settings":
        if self.is_production and self.SECRET_KEY == _DEV_SECRET:
            raise ValueError(
                "SECRET_KEY must be set to a real secret when APP_ENV=production"
            )
        return self


@lru_cache
def get_settings() -> Settings:
    """Return the cached application settings instance."""
    return Settings()
