from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Iterable
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from Server.app.models.entities import DebugArtifact, ScanRecord, TestRun


def percentile(values: Iterable[float], percentage: float) -> float | None:
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * percentage
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def all_scans(session: Session) -> list[ScanRecord]:
    return list(session.scalars(select(ScanRecord).order_by(ScanRecord.captured_at)))


def summary_metrics(scans: list[ScanRecord]) -> dict[str, object]:
    latencies = [scan.total_latency_ms for scan in scans]
    decisions = Counter(scan.decision for scan in scans)
    return {
        "scanCount": len(scans),
        "testRunCount": len({scan.test_run_id for scan in scans}),
        "decisionCounts": dict(sorted(decisions.items())),
        "latencyP50Ms": percentile(latencies, 0.50),
        "latencyP95Ms": percentile(latencies, 0.95),
        "meanQualityScore": sum(scan.quality_score for scan in scans) / len(scans) if scans else None,
    }


def calibration_metrics(scans: list[ScanRecord]) -> dict[str, object]:
    residuals = [scan.calibration_residual for scan in scans if scan.calibration_residual is not None]
    condition_numbers = [scan.condition_number for scan in scans if scan.condition_number is not None]
    rejection_counts = Counter(reason for scan in scans for reason in scan.rejection_reasons)
    return {
        "residuals": residuals,
        "conditionNumbers": condition_numbers,
        "specularFractions": [scan.specular_fraction for scan in scans],
        "rejectionReasonCounts": dict(sorted(rejection_counts.items())),
    }


def model_metrics(scans: list[ScanRecord]) -> dict[str, object]:
    groups: dict[str, list[ScanRecord]] = defaultdict(list)
    for scan in scans:
        groups[scan.test_run.model_version].append(scan)
    result: list[dict[str, object]] = []
    for model_version in sorted(groups):
        group = groups[model_version]
        scores = [scan.risk_score for scan in group if scan.risk_score is not None]
        matches = [scan for scan in group if scan.expected_label is not None]
        result.append({
            "modelVersion": model_version,
            "scanCount": len(group),
            "meanRiskScore": sum(scores) / len(scores) if scores else None,
            "expectedMatchRate": (
                sum(scan.expected_label == scan.decision for scan in matches) / len(matches) if matches else None
            ),
        })
    return {"models": result}


def device_metrics(scans: list[ScanRecord]) -> dict[str, object]:
    groups: dict[str, list[ScanRecord]] = defaultdict(list)
    for scan in scans:
        groups[scan.test_run.device_model].append(scan)
    devices: list[dict[str, object]] = []
    for device_model in sorted(groups):
        group = groups[device_model]
        latencies = [scan.total_latency_ms for scan in group]
        devices.append({
            "deviceModel": device_model,
            "scanCount": len(group),
            "latencyP50Ms": percentile(latencies, 0.50),
            "latencyP95Ms": percentile(latencies, 0.95),
        })
    return {"devices": devices}


def safe_artifact_path(root: Path, relative_path: str) -> Path:
    resolved_root = root.resolve()
    candidate = (resolved_root / relative_path).resolve()
    if not candidate.is_relative_to(resolved_root):
        raise ValueError("artifact path escapes configured root")
    return candidate


def delete_artifact_file(root: Path, artifact: DebugArtifact) -> None:
    try:
        path = safe_artifact_path(root, artifact.relative_path)
    except ValueError:
        return
    if path.is_file():
        path.unlink()


def delete_test_run(session: Session, run: TestRun, artifact_root: Path) -> None:
    artifacts = list(session.scalars(
        select(DebugArtifact)
        .join(ScanRecord)
        .where(ScanRecord.test_run_id == run.id)
    ))
    for artifact in artifacts:
        delete_artifact_file(artifact_root, artifact)
    session.delete(run)
    session.commit()
