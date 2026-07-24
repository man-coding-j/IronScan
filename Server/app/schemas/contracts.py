from __future__ import annotations

import re
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


def _camel(value: str) -> str:
    head, *tail = value.split("_")
    return head + "".join(part.capitalize() for part in tail)


PROHIBITED_KEYS = {
    "address",
    "dateofbirth",
    "dob",
    "email",
    "medicalrecordid",
    "medicalrecordnumber",
    "mrn",
    "name",
    "firstname",
    "fullname",
    "lastname",
    "participantname",
    "participantid",
    "patientname",
    "patientid",
    "streetaddress",
}


class StrictSchema(BaseModel):
    model_config = ConfigDict(alias_generator=_camel, populate_by_name=True, extra="forbid", from_attributes=True)

    @model_validator(mode="before")
    @classmethod
    def reject_prohibited_fields(cls, value: Any) -> Any:
        if isinstance(value, dict):
            normalized = {re.sub(r"[^a-z]", "", str(key).lower()) for key in value}
            prohibited = sorted(normalized & PROHIBITED_KEYS)
            if prohibited:
                raise ValueError(f"prohibited personal fields: {', '.join(prohibited)}")
        return value


class CalibrationMode(StrEnum):
    multi_patch_reference = "multiPatchReference"
    neutral_patch_reference = "neutralPatchReference"
    teeth_pseudo_reference = "teethPseudoReference"
    uncalibrated_rejected = "uncalibratedRejected"


class Decision(StrEnum):
    lower_observed_risk = "lowerObservedRisk"
    possible_risk = "possibleRisk"
    unable_to_assess = "unableToAssess"


class ArtifactType(StrEnum):
    original = "original"
    calibrated = "calibrated"
    mask_overlay = "maskOverlay"


class TestRunCreate(StrictSchema):
    started_at: datetime
    app_version: str = Field(min_length=1, max_length=50)
    device_model: str = Field(min_length=1, max_length=100)
    ios_version: str = Field(alias="iOSVersion", min_length=1, max_length=50)
    model_version: str = Field(min_length=1, max_length=100)
    preprocessing_version: str = Field(min_length=1, max_length=100)
    notes: str | None = Field(default=None, max_length=500)

    @field_validator("started_at")
    @classmethod
    def timezone_required(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("timestamp must include a timezone")
        return value

    @field_validator("notes")
    @classmethod
    def notes_must_not_contain_personal_data(cls, value: str | None) -> str | None:
        if value is None:
            return value
        lowered = value.lower()
        labels = ("patient", "participant", "name", "email", "address", "date of birth", "dob", "mrn")
        if any(label in lowered for label in labels) or re.search(r"\b[^\s@]+@[^\s@]+\.[^\s@]+\b", value):
            raise ValueError("notes must not contain personal data")
        return value


class TestRunRead(TestRunCreate):
    id: int


class TestRunDetail(TestRunRead):
    scans: list[ScanRead]


class ScanCreate(StrictSchema):
    test_run_id: int = Field(gt=0)
    captured_at: datetime
    anonymous_fixture_id: str = Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
    calibration_mode: CalibrationMode
    quality_score: float = Field(ge=0, le=1)
    rejection_reasons: list[str] = Field(default_factory=list, max_length=32)
    segmentation_confidence: float = Field(ge=0, le=1)
    calibration_residual: float | None = Field(default=None, ge=0)
    condition_number: float | None = Field(default=None, ge=0)
    specular_fraction: float = Field(ge=0, le=1)
    risk_score: float | None = Field(default=None, ge=0, le=1)
    decision: Decision
    segmentation_latency_ms: float = Field(ge=0)
    calibration_latency_ms: float = Field(ge=0)
    risk_latency_ms: float = Field(ge=0)
    total_latency_ms: float = Field(ge=0)
    expected_label: Decision | None = None
    expected_hemoglobin: float | None = Field(default=None, ge=0, le=30)

    @field_validator("captured_at")
    @classmethod
    def scan_timezone_required(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("timestamp must include a timezone")
        return value

    @field_validator("rejection_reasons")
    @classmethod
    def bounded_rejection_reasons(cls, value: list[str]) -> list[str]:
        if any(not reason or len(reason) > 100 for reason in value):
            raise ValueError("rejection reasons must contain 1 to 100 characters")
        return value


class ScanRead(ScanCreate):
    id: int
    created_at: datetime


class ArtifactCreate(StrictSchema):
    artifact_type: ArtifactType
    filename: str = Field(min_length=1, max_length=100)
    content_base64: str = Field(min_length=1, max_length=14_000_000)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    width: int = Field(gt=0, le=20_000)
    height: int = Field(gt=0, le=20_000)
    retention_days: int | None = Field(default=None, ge=1, le=30)
    synthetic_fixture: bool = True

    @field_validator("filename")
    @classmethod
    def safe_filename(cls, value: str) -> str:
        if value in {".", ".."} or "/" in value or "\\" in value or ".." in value:
            raise ValueError("path traversal is not allowed")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", value):
            raise ValueError("filename contains unsupported characters")
        return value


class ArtifactRead(StrictSchema):
    id: int
    scan_record_id: int
    artifact_type: ArtifactType
    relative_path: str
    sha256: str
    width: int
    height: int
    retention_expires_at: datetime


class PurgeResult(StrictSchema):
    purged_artifacts: int


def utc_now() -> datetime:
    return datetime.now(UTC)


TestRunDetail.model_rebuild()
