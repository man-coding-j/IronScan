from __future__ import annotations

import base64
import hashlib
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from Server.app.models.entities import DebugArtifact
from Server.tests.conftest import ServerHarness, scan_payload

PNG_FIXTURE = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def create_run_and_scan(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> tuple[int, int]:
    run_response = harness.client.post("/api/v1/test-runs", json=test_run_payload)
    assert run_response.status_code == 201
    run_id = int(run_response.json()["id"])
    scan_response = harness.client.post("/api/v1/scans", json=scan_payload(run_id))
    assert scan_response.status_code == 201
    return run_id, int(scan_response.json()["id"])


@pytest.mark.parametrize(
    "field",
    ["name", "patientName", "email", "dateOfBirth", "address", "medicalRecordId", "participantId"],
)
def test_prohibited_personal_fields_are_rejected(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
    field: str,
) -> None:
    payload = dict(test_run_payload)
    payload[field] = "not accepted"
    response = harness.client.post("/api/v1/test-runs", json=payload)
    assert response.status_code == 422


def test_unsupported_fields_and_personal_notes_are_rejected(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    unsupported = dict(test_run_payload, unexpected="value")
    assert harness.client.post("/api/v1/test-runs", json=unsupported).status_code == 422
    personal_notes = dict(test_run_payload, notes="patient email test@example.com")
    assert harness.client.post("/api/v1/test-runs", json=personal_notes).status_code == 422


def test_duplicate_fixture_returns_deterministic_conflict(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    run_response = harness.client.post("/api/v1/test-runs", json=test_run_payload)
    run_id = int(run_response.json()["id"])
    payload = scan_payload(run_id)
    assert harness.client.post("/api/v1/scans", json=payload).status_code == 201
    duplicate = harness.client.post("/api/v1/scans", json=payload)
    assert duplicate.status_code == 409
    assert duplicate.json() == {"detail": "Fixture already exists in this test run"}


def test_artifact_checksum_and_path_traversal_are_rejected(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    _, scan_id = create_run_and_scan(harness, test_run_payload)
    payload = {
        "artifactType": "original",
        "filename": "fixture.png",
        "contentBase64": base64.b64encode(PNG_FIXTURE).decode(),
        "sha256": "0" * 64,
        "width": 1,
        "height": 1,
    }
    assert harness.client.post(f"/api/v1/scans/{scan_id}/artifacts", json=payload).status_code == 422
    payload["filename"] = "../fixture.png"
    payload["sha256"] = hashlib.sha256(PNG_FIXTURE).hexdigest()
    assert harness.client.post(f"/api/v1/scans/{scan_id}/artifacts", json=payload).status_code == 422


def test_non_synthetic_artifact_requires_explicit_flag(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    _, scan_id = create_run_and_scan(harness, test_run_payload)
    payload = {
        "artifactType": "original",
        "filename": "fixture.png",
        "contentBase64": base64.b64encode(PNG_FIXTURE).decode(),
        "sha256": hashlib.sha256(PNG_FIXTURE).hexdigest(),
        "width": 1,
        "height": 1,
        "syntheticFixture": False,
    }
    assert harness.client.post(f"/api/v1/scans/{scan_id}/artifacts", json=payload).status_code == 403


def test_artifact_is_stored_verified_served_and_purged(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    _, scan_id = create_run_and_scan(harness, test_run_payload)
    digest = hashlib.sha256(PNG_FIXTURE).hexdigest()
    response = harness.client.post(
        f"/api/v1/scans/{scan_id}/artifacts",
        json={
            "artifactType": "maskOverlay",
            "filename": "fixture.png",
            "contentBase64": base64.b64encode(PNG_FIXTURE).decode(),
            "sha256": digest,
            "width": 1,
            "height": 1,
        },
    )
    assert response.status_code == 201
    artifact_id = int(response.json()["id"])
    assert harness.client.get(f"/api/v1/artifacts/{artifact_id}/content").content == PNG_FIXTURE
    with harness.factory() as session:
        artifact = session.scalar(select(DebugArtifact).where(DebugArtifact.id == artifact_id))
        assert artifact is not None
        artifact.retention_expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()
    purge = harness.client.post("/api/v1/maintenance/purge-expired")
    assert purge.json() == {"purgedArtifacts": 1}
    assert harness.client.get(f"/api/v1/artifacts/{artifact_id}/content").status_code == 404


def test_crud_metrics_dashboard_and_openapi(
    harness: ServerHarness,
    test_run_payload: dict[str, object],
) -> None:
    run_id, scan_id = create_run_and_scan(harness, test_run_payload)
    assert harness.client.get("/api/v1/test-runs").status_code == 200
    assert harness.client.get(f"/api/v1/test-runs/{run_id}").json()["scans"][0]["id"] == scan_id
    assert harness.client.get(f"/api/v1/scans/{scan_id}").status_code == 200
    summary = harness.client.get("/api/v1/metrics/summary").json()
    assert summary["scanCount"] == 1
    assert summary["latencyP95Ms"] == 62.0
    assert harness.client.get("/api/v1/metrics/calibration").status_code == 200
    assert harness.client.get("/api/v1/metrics/model").status_code == 200
    assert harness.client.get("/api/v1/metrics/devices").status_code == 200
    dashboard = harness.client.get("/dashboard")
    assert "Risk-score distribution" in dashboard.text
    assert harness.client.get(f"/dashboard/test-runs/{run_id}").status_code == 200
    assert harness.client.get(f"/dashboard/scans/{scan_id}").status_code == 200
    assert harness.client.get("/openapi.json").status_code == 200
    assert "/api/v1/scans" in harness.client.get("/openapi.json").json()["paths"]
    assert harness.client.delete(f"/api/v1/test-runs/{run_id}").status_code == 204
