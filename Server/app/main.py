from __future__ import annotations

import base64
import binascii
import hashlib
import json
from collections.abc import Generator
from datetime import timedelta
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload, sessionmaker

from Server.app.config import Settings
from Server.app.db.database import make_engine, make_session_factory
from Server.app.models.entities import DebugArtifact, ScanRecord, TestRun
from Server.app.schemas.contracts import (
    ArtifactCreate,
    ArtifactRead,
    PurgeResult,
    ScanCreate,
    ScanRead,
    TestRunCreate,
    TestRunDetail,
    TestRunRead,
    utc_now,
)
from Server.app.security import LanTokenMiddleware
from Server.app.services.diagnostics import (
    all_scans,
    calibration_metrics,
    delete_artifact_file,
    delete_test_run,
    device_metrics,
    model_metrics,
    safe_artifact_path,
    summary_metrics,
)

SERVER_ROOT = Path(__file__).parent
MAX_ARTIFACT_BYTES = 10 * 1024 * 1024


def create_app(
    settings: Settings | None = None,
    session_factory: sessionmaker[Session] | None = None,
) -> FastAPI:
    active_settings = settings or Settings.from_env()
    factory = session_factory or make_session_factory(make_engine(active_settings.database_url))
    templates = Jinja2Templates(directory=SERVER_ROOT / "templates")
    app = FastAPI(
        title="IronScan Local Engineering Diagnostics",
        version="1.0.0",
        description="Optional local dashboard; iOS inference remains entirely on-device.",
    )
    app.add_middleware(LanTokenMiddleware, settings=active_settings)
    app.mount("/static", StaticFiles(directory=SERVER_ROOT / "static"), name="static")
    app.state.settings = active_settings
    app.state.session_factory = factory

    def get_session() -> Generator[Session, None, None]:
        with factory() as session:
            yield session

    @app.post("/api/v1/test-runs", response_model=TestRunRead, status_code=status.HTTP_201_CREATED)
    def create_test_run(payload: TestRunCreate, session: Session = Depends(get_session)) -> TestRun:
        run = TestRun(**payload.model_dump())
        session.add(run)
        session.commit()
        session.refresh(run)
        return run

    @app.get("/api/v1/test-runs", response_model=list[TestRunRead])
    def list_test_runs(session: Session = Depends(get_session)) -> list[TestRun]:
        return list(session.scalars(select(TestRun).order_by(TestRun.started_at.desc())))

    @app.get("/api/v1/test-runs/{run_id}", response_model=TestRunDetail)
    def get_test_run(run_id: int, session: Session = Depends(get_session)) -> TestRun:
        run = session.scalar(
            select(TestRun).options(selectinload(TestRun.scans)).where(TestRun.id == run_id)
        )
        if run is None:
            raise HTTPException(status_code=404, detail="Test run not found")
        return run

    @app.post("/api/v1/scans", response_model=ScanRead, status_code=status.HTTP_201_CREATED)
    def create_scan(payload: ScanCreate, session: Session = Depends(get_session)) -> ScanRecord:
        if session.get(TestRun, payload.test_run_id) is None:
            raise HTTPException(status_code=404, detail="Test run not found")
        values = payload.model_dump()
        values["calibration_mode"] = payload.calibration_mode.value
        values["decision"] = payload.decision.value
        values["expected_label"] = payload.expected_label.value if payload.expected_label else None
        scan = ScanRecord(**values, created_at=utc_now())
        session.add(scan)
        try:
            session.commit()
        except IntegrityError as error:
            session.rollback()
            raise HTTPException(status_code=409, detail="Fixture already exists in this test run") from error
        session.refresh(scan)
        return scan

    @app.get("/api/v1/scans/{scan_id}", response_model=ScanRead)
    def get_scan(scan_id: int, session: Session = Depends(get_session)) -> ScanRecord:
        scan = session.get(ScanRecord, scan_id)
        if scan is None:
            raise HTTPException(status_code=404, detail="Scan not found")
        return scan

    @app.post(
        "/api/v1/scans/{scan_id}/artifacts",
        response_model=ArtifactRead,
        status_code=status.HTTP_201_CREATED,
    )
    def create_artifact(
        scan_id: int,
        payload: ArtifactCreate,
        session: Session = Depends(get_session),
    ) -> DebugArtifact:
        if session.get(ScanRecord, scan_id) is None:
            raise HTTPException(status_code=404, detail="Scan not found")
        if not payload.synthetic_fixture and not active_settings.debug_image_uploads:
            raise HTTPException(status_code=403, detail="Non-synthetic debug image uploads are disabled")
        try:
            content = base64.b64decode(payload.content_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise HTTPException(status_code=422, detail="Artifact content is not valid base64") from error
        if len(content) > MAX_ARTIFACT_BYTES:
            raise HTTPException(status_code=413, detail="Artifact exceeds 10 MiB limit")
        suffix = Path(payload.filename).suffix.lower()
        if suffix == ".png":
            valid_signature = content.startswith(b"\x89PNG\r\n\x1a\n")
        elif suffix in {".jpg", ".jpeg"}:
            valid_signature = content.startswith(b"\xff\xd8\xff")
        else:
            raise HTTPException(status_code=422, detail="Only PNG and JPEG artifacts are supported")
        if not valid_signature:
            raise HTTPException(status_code=422, detail="Artifact signature does not match its extension")
        digest = hashlib.sha256(content).hexdigest()
        if digest != payload.sha256:
            raise HTTPException(status_code=422, detail="Artifact checksum mismatch")
        relative_path = f"scan-{scan_id}/{uuid4().hex}{suffix}"
        destination = safe_artifact_path(active_settings.artifact_root, relative_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
        retention_days = payload.retention_days or active_settings.artifact_retention_days
        artifact = DebugArtifact(
            scan_record_id=scan_id,
            artifact_type=payload.artifact_type.value,
            relative_path=relative_path,
            sha256=digest,
            width=payload.width,
            height=payload.height,
            retention_expires_at=utc_now() + timedelta(days=retention_days),
        )
        session.add(artifact)
        try:
            session.commit()
        except Exception:
            destination.unlink(missing_ok=True)
            raise
        session.refresh(artifact)
        return artifact

    @app.get("/api/v1/scans/{scan_id}/artifacts", response_model=list[ArtifactRead])
    def list_artifacts(scan_id: int, session: Session = Depends(get_session)) -> list[DebugArtifact]:
        if session.get(ScanRecord, scan_id) is None:
            raise HTTPException(status_code=404, detail="Scan not found")
        return list(session.scalars(
            select(DebugArtifact)
            .where(DebugArtifact.scan_record_id == scan_id)
            .order_by(DebugArtifact.artifact_type)
        ))

    @app.get("/api/v1/artifacts/{artifact_id}/content", response_class=FileResponse)
    def artifact_content(artifact_id: int, session: Session = Depends(get_session)) -> FileResponse:
        artifact = session.get(DebugArtifact, artifact_id)
        if artifact is None:
            raise HTTPException(status_code=404, detail="Artifact not found")
        try:
            path = safe_artifact_path(active_settings.artifact_root, artifact.relative_path)
        except ValueError as error:
            raise HTTPException(status_code=404, detail="Artifact path is invalid") from error
        if not path.is_file():
            raise HTTPException(status_code=404, detail="Artifact file is missing")
        return FileResponse(path)

    @app.get("/api/v1/metrics/summary")
    def metrics_summary(session: Session = Depends(get_session)) -> dict[str, object]:
        return summary_metrics(all_scans(session))

    @app.get("/api/v1/metrics/calibration")
    def metrics_calibration(session: Session = Depends(get_session)) -> dict[str, object]:
        return calibration_metrics(all_scans(session))

    @app.get("/api/v1/metrics/model")
    def metrics_model(session: Session = Depends(get_session)) -> dict[str, object]:
        return model_metrics(all_scans(session))

    @app.get("/api/v1/metrics/devices")
    def metrics_devices(session: Session = Depends(get_session)) -> dict[str, object]:
        return device_metrics(all_scans(session))

    @app.delete("/api/v1/test-runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
    def remove_test_run(run_id: int, session: Session = Depends(get_session)) -> None:
        run = session.get(TestRun, run_id)
        if run is None:
            raise HTTPException(status_code=404, detail="Test run not found")
        delete_test_run(session, run, active_settings.artifact_root)

    @app.post("/api/v1/maintenance/purge-expired", response_model=PurgeResult)
    def purge_expired(session: Session = Depends(get_session)) -> PurgeResult:
        artifacts = list(session.scalars(
            select(DebugArtifact).where(DebugArtifact.retention_expires_at <= utc_now())
        ))
        for artifact in artifacts:
            delete_artifact_file(active_settings.artifact_root, artifact)
            session.delete(artifact)
        session.commit()
        return PurgeResult(purged_artifacts=len(artifacts))

    def dashboard_context(session: Session) -> dict[str, object]:
        scans = all_scans(session)
        return {
            "runs": list(session.scalars(select(TestRun).order_by(TestRun.started_at.desc()))),
            "summary": summary_metrics(scans),
            "calibration_json": json.dumps(calibration_metrics(scans)),
            "model_json": json.dumps(model_metrics(scans)),
            "devices_json": json.dumps(device_metrics(scans)),
            "scores_json": json.dumps([scan.risk_score for scan in scans if scan.risk_score is not None]),
            "expected_json": json.dumps([
                {"expected": scan.expected_label, "predicted": scan.decision}
                for scan in scans if scan.expected_label is not None
            ]),
        }

    @app.get("/", response_class=HTMLResponse)
    @app.get("/dashboard", response_class=HTMLResponse)
    def dashboard(request: Request, session: Session = Depends(get_session)) -> HTMLResponse:
        return templates.TemplateResponse(request=request, name="runs.html", context=dashboard_context(session))

    @app.get("/dashboard/partials/test-runs", response_class=HTMLResponse)
    def test_run_partial(request: Request, session: Session = Depends(get_session)) -> HTMLResponse:
        runs = list(session.scalars(select(TestRun).order_by(TestRun.started_at.desc())))
        return templates.TemplateResponse(request=request, name="_run_table.html", context={"runs": runs})

    @app.get("/dashboard/test-runs/{run_id}", response_class=HTMLResponse)
    def test_run_page(run_id: int, request: Request, session: Session = Depends(get_session)) -> HTMLResponse:
        run = session.scalar(
            select(TestRun).options(selectinload(TestRun.scans)).where(TestRun.id == run_id)
        )
        if run is None:
            raise HTTPException(status_code=404, detail="Test run not found")
        return templates.TemplateResponse(request=request, name="run_detail.html", context={"run": run})

    @app.get("/dashboard/scans/{scan_id}", response_class=HTMLResponse)
    def scan_page(scan_id: int, request: Request, session: Session = Depends(get_session)) -> HTMLResponse:
        scan = session.scalar(
            select(ScanRecord)
            .options(selectinload(ScanRecord.artifacts), selectinload(ScanRecord.test_run))
            .where(ScanRecord.id == scan_id)
        )
        if scan is None:
            raise HTTPException(status_code=404, detail="Scan not found")
        return templates.TemplateResponse(request=request, name="scan_detail.html", context={"scan": scan})

    return app


app = create_app()
