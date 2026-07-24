from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import TypeDecorator

from Server.app.db.database import Base


class UTCDateTime(TypeDecorator[datetime]):
    impl = DateTime
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("timestamp must include a timezone")
        normalized = value.astimezone(UTC)
        return normalized.replace(tzinfo=None) if dialect.name == "sqlite" else normalized

    def process_result_value(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None or value.tzinfo is not None:
            return value
        return value.replace(tzinfo=UTC)


class TestRun(Base):
    __tablename__ = "test_runs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    started_at: Mapped[datetime] = mapped_column(UTCDateTime(timezone=True), nullable=False)
    app_version: Mapped[str] = mapped_column(String(50), nullable=False)
    device_model: Mapped[str] = mapped_column(String(100), nullable=False)
    ios_version: Mapped[str] = mapped_column(String(50), nullable=False)
    model_version: Mapped[str] = mapped_column(String(100), nullable=False)
    preprocessing_version: Mapped[str] = mapped_column(String(100), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    scans: Mapped[list[ScanRecord]] = relationship(back_populates="test_run", cascade="all, delete-orphan")


class ScanRecord(Base):
    __tablename__ = "scan_records"
    __table_args__ = (UniqueConstraint("test_run_id", "anonymous_fixture_id", name="uq_scan_run_fixture"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    test_run_id: Mapped[int] = mapped_column(ForeignKey("test_runs.id", ondelete="CASCADE"), nullable=False)
    captured_at: Mapped[datetime] = mapped_column(UTCDateTime(timezone=True), nullable=False)
    anonymous_fixture_id: Mapped[str] = mapped_column(String(128), nullable=False)
    calibration_mode: Mapped[str] = mapped_column(String(40), nullable=False)
    quality_score: Mapped[float] = mapped_column(Float, nullable=False)
    rejection_reasons: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    segmentation_confidence: Mapped[float] = mapped_column(Float, nullable=False)
    calibration_residual: Mapped[float | None] = mapped_column(Float)
    condition_number: Mapped[float | None] = mapped_column(Float)
    specular_fraction: Mapped[float] = mapped_column(Float, nullable=False)
    risk_score: Mapped[float | None] = mapped_column(Float)
    decision: Mapped[str] = mapped_column(String(40), nullable=False)
    segmentation_latency_ms: Mapped[float] = mapped_column(Float, nullable=False)
    calibration_latency_ms: Mapped[float] = mapped_column(Float, nullable=False)
    risk_latency_ms: Mapped[float] = mapped_column(Float, nullable=False)
    total_latency_ms: Mapped[float] = mapped_column(Float, nullable=False)
    expected_label: Mapped[str | None] = mapped_column(String(40))
    expected_hemoglobin: Mapped[float | None] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(timezone=True), nullable=False)
    test_run: Mapped[TestRun] = relationship(back_populates="scans")
    artifacts: Mapped[list[DebugArtifact]] = relationship(back_populates="scan_record", cascade="all, delete-orphan")


class DebugArtifact(Base):
    __tablename__ = "debug_artifacts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_record_id: Mapped[int] = mapped_column(ForeignKey("scan_records.id", ondelete="CASCADE"), nullable=False)
    artifact_type: Mapped[str] = mapped_column(String(40), nullable=False)
    relative_path: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    width: Mapped[int] = mapped_column(Integer, nullable=False)
    height: Mapped[int] = mapped_column(Integer, nullable=False)
    retention_expires_at: Mapped[datetime] = mapped_column(UTCDateTime(timezone=True), nullable=False)
    scan_record: Mapped[ScanRecord] = relationship(back_populates="artifacts")
