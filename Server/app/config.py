from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    database_url: str
    artifact_root: Path
    lan_mode: bool = False
    container_mode: bool = False
    api_token: str | None = None
    debug_image_uploads: bool = False
    artifact_retention_days: int = 7

    def __post_init__(self) -> None:
        if self.lan_mode and not self.api_token:
            raise ValueError("IRONSCAN_API_TOKEN is required when IRONSCAN_LAN_MODE=true")
        if not 1 <= self.artifact_retention_days <= 30:
            raise ValueError("IRONSCAN_ARTIFACT_RETENTION_DAYS must be between 1 and 30")

    @property
    def host(self) -> str:
        container_bind = self.container_mode and Path("/.dockerenv").exists()
        return "0.0.0.0" if self.lan_mode or container_bind else "127.0.0.1"

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            database_url=os.getenv("IRONSCAN_DATABASE_URL", "sqlite:///./ironscan_debug.sqlite3"),
            artifact_root=Path(os.getenv("IRONSCAN_ARTIFACT_ROOT", "./debug-artifacts")),
            lan_mode=_flag("IRONSCAN_LAN_MODE"),
            container_mode=_flag("IRONSCAN_CONTAINER_MODE"),
            api_token=os.getenv("IRONSCAN_API_TOKEN"),
            debug_image_uploads=_flag("DEBUG_IMAGE_UPLOADS"),
            artifact_retention_days=int(os.getenv("IRONSCAN_ARTIFACT_RETENTION_DAYS", "7")),
        )
