from __future__ import annotations

from datetime import UTC, datetime

from Server.app.models.entities import ScanRecord
from Server.app.models.entities import TestRun as RunModel
from Server.app.services.diagnostics import (
    calibration_metrics,
    device_metrics,
    model_metrics,
    percentile,
    summary_metrics,
)


def make_scan(total_latency: float, decision: str, residual: float) -> ScanRecord:
    run = RunModel(
        id=1,
        started_at=datetime(2026, 1, 1, tzinfo=UTC),
        app_version="1",
        device_model="Synthetic Device",
        ios_version="18",
        model_version="fixture-1",
        preprocessing_version="1",
        notes=None,
    )
    return ScanRecord(
        id=int(total_latency),
        test_run_id=1,
        captured_at=datetime(2026, 1, 1, tzinfo=UTC),
        anonymous_fixture_id=f"synthetic-{int(total_latency)}",
        calibration_mode="multiPatchReference",
        quality_score=0.9,
        rejection_reasons=[],
        segmentation_confidence=0.9,
        calibration_residual=residual,
        condition_number=10,
        specular_fraction=0.03,
        risk_score=0.2,
        decision=decision,
        segmentation_latency_ms=10,
        calibration_latency_ms=20,
        risk_latency_ms=10,
        total_latency_ms=total_latency,
        expected_label=decision,
        expected_hemoglobin=13,
        created_at=datetime(2026, 1, 1, tzinfo=UTC),
        test_run=run,
    )


def test_percentile_and_summary_calculations() -> None:
    scans = [
        make_scan(10, "lowerObservedRisk", 1.0),
        make_scan(20, "possibleRisk", 2.0),
        make_scan(30, "possibleRisk", 3.0),
        make_scan(40, "unableToAssess", 4.0),
    ]
    assert percentile([], 0.95) is None
    assert percentile([10, 20, 30, 40], 0.50) == 25
    assert percentile([10, 20, 30, 40], 0.95) == 38.5
    summary = summary_metrics(scans)
    assert summary["scanCount"] == 4
    assert summary["latencyP50Ms"] == 25
    assert summary["latencyP95Ms"] == 38.5
    assert calibration_metrics(scans)["residuals"] == [1.0, 2.0, 3.0, 4.0]
    assert model_metrics(scans)["models"]
    assert device_metrics(scans)["devices"]
