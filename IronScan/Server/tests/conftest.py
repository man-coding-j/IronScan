from __future__ import annotations

from collections.abc import Generator
from dataclasses import dataclass
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session, sessionmaker

from Server.app.config import Settings
from Server.app.db.database import Base, make_engine, make_session_factory
from Server.app.main import create_app


@dataclass
class ServerHarness:
    client: TestClient
    factory: sessionmaker[Session]
    settings: Settings


@pytest.fixture
def harness(tmp_path: Path) -> Generator[ServerHarness, None, None]:
    settings = Settings(
        database_url=f"sqlite:///{tmp_path / 'test.sqlite3'}",
        artifact_root=tmp_path / "artifacts",
    )
    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    factory = make_session_factory(engine)
    with TestClient(create_app(settings=settings, session_factory=factory)) as client:
        yield ServerHarness(client=client, factory=factory, settings=settings)
    engine.dispose()


@pytest.fixture
def test_run_payload() -> dict[str, object]:
    return {
        "startedAt": "2026-07-15T12:00:00Z",
        "appVersion": "1.0.0",
        "deviceModel": "Synthetic Device",
        "iOSVersion": "18.0",
        "modelVersion": "fixture-1.0.0",
        "preprocessingVersion": "1.0.0",
        "notes": "synthetic validation run",
    }


def scan_payload(run_id: int, fixture_id: str = "synthetic-001") -> dict[str, object]:
    return {
        "testRunId": run_id,
        "capturedAt": "2026-07-15T12:01:00Z",
        "anonymousFixtureId": fixture_id,
        "calibrationMode": "multiPatchReference",
        "qualityScore": 0.92,
        "rejectionReasons": [],
        "segmentationConfidence": 0.94,
        "calibrationResidual": 2.1,
        "conditionNumber": 8.2,
        "specularFraction": 0.04,
        "riskScore": 0.31,
        "decision": "lowerObservedRisk",
        "segmentationLatencyMs": 20.0,
        "calibrationLatencyMs": 30.0,
        "riskLatencyMs": 12.0,
        "totalLatencyMs": 62.0,
        "expectedLabel": "lowerObservedRisk",
        "expectedHemoglobin": 13.4,
    }
