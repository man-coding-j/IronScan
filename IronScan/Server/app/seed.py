from __future__ import annotations

import base64
import hashlib
import random
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from Server.app.config import Settings
from Server.app.db.database import make_engine, make_session_factory
from Server.app.models.entities import DebugArtifact, ScanRecord, TestRun
from Server.app.services.diagnostics import safe_artifact_path

SEED_STARTED_AT = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
PNG_FIXTURE = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def seed(settings: Settings | None = None) -> int:
    active_settings = settings or Settings.from_env()
    factory = make_session_factory(make_engine(active_settings.database_url))
    with factory() as session:
        existing = session.scalar(select(TestRun).where(
            TestRun.started_at == SEED_STARTED_AT,
            TestRun.notes == "deterministic synthetic dashboard seed",
        ))
        if existing is not None:
            return existing.id
        run = TestRun(
            started_at=SEED_STARTED_AT,
            app_version="1.0.0-engineering",
            device_model="Synthetic iPhone Fixture",
            ios_version="18.0-fixture",
            model_version="engineering-fixture-1.0.0",
            preprocessing_version="1.0.0",
            notes="deterministic synthetic dashboard seed",
        )
        session.add(run)
        session.flush()
        random_generator = random.Random(20260715)
        decisions = ["lowerObservedRisk", "possibleRisk", "unableToAssess"]
        scans: list[ScanRecord] = []
        for index in range(12):
            rejected = index % 5 == 4
            risk_score = None if rejected else round(0.12 + index * 0.065, 4)
            scan = ScanRecord(
                test_run_id=run.id,
                captured_at=SEED_STARTED_AT + timedelta(minutes=index),
                anonymous_fixture_id=f"synthetic-{index + 1:03d}",
                calibration_mode="uncalibratedRejected" if rejected else "multiPatchReference",
                quality_score=round(0.72 + random_generator.random() * 0.24, 4),
                rejection_reasons=["syntheticUnstableReference"] if rejected else [],
                segmentation_confidence=round(0.82 + random_generator.random() * 0.15, 4),
                calibration_residual=round(1.2 + random_generator.random() * 3.4, 4),
                condition_number=round(4 + random_generator.random() * 18, 4),
                specular_fraction=round(0.01 + random_generator.random() * 0.07, 4),
                risk_score=risk_score,
                decision="unableToAssess" if rejected else decisions[index % 2],
                segmentation_latency_ms=round(18 + random_generator.random() * 5, 3),
                calibration_latency_ms=round(24 + random_generator.random() * 8, 3),
                risk_latency_ms=round(11 + random_generator.random() * 4, 3),
                total_latency_ms=round(56 + random_generator.random() * 12, 3),
                expected_label="unableToAssess" if rejected else decisions[index % 2],
                expected_hemoglobin=round(10.5 + index * 0.28, 2),
                created_at=SEED_STARTED_AT + timedelta(minutes=index, seconds=1),
            )
            scans.append(scan)
            session.add(scan)
        session.flush()
        digest = hashlib.sha256(PNG_FIXTURE).hexdigest()
        for artifact_type in ("original", "calibrated", "maskOverlay"):
            relative_path = f"scan-{scans[0].id}/seed-{artifact_type}.png"
            destination = safe_artifact_path(active_settings.artifact_root, relative_path)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(PNG_FIXTURE)
            session.add(DebugArtifact(
                scan_record_id=scans[0].id,
                artifact_type=artifact_type,
                relative_path=relative_path,
                sha256=digest,
                width=1,
                height=1,
                retention_expires_at=datetime.now(UTC) + timedelta(days=active_settings.artifact_retention_days),
            ))
        session.commit()
        return run.id


def main() -> None:
    run_id = seed()
    print(f"Synthetic test run ready: {run_id}")


if __name__ == "__main__":
    main()
