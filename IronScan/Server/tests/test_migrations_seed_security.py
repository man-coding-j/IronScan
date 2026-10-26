from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import inspect

from Server.app.config import Settings
from Server.app.db.database import Base, make_engine, make_session_factory
from Server.app.main import create_app
from Server.app.seed import seed


def migrate(database_url: str) -> None:
    configuration = Config("Server/migrations/alembic.ini")
    configuration.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(configuration, "head")


def test_migration_from_empty_database_and_synthetic_seed(tmp_path: Path) -> None:
    database_url = f"sqlite:///{tmp_path / 'migrated.sqlite3'}"
    settings = Settings(database_url=database_url, artifact_root=tmp_path / "artifacts")
    migrate(database_url)
    engine = make_engine(database_url)
    assert set(inspect(engine).get_table_names()) >= {"alembic_version", "test_runs", "scan_records", "debug_artifacts"}
    first_run_id = seed(settings)
    assert seed(settings) == first_run_id
    with TestClient(create_app(settings=settings, session_factory=make_session_factory(engine))) as client:
        assert client.get("/api/v1/metrics/summary").json()["scanCount"] == 12
        assert "synthetic-001" in client.get(f"/dashboard/test-runs/{first_run_id}").text
    engine.dispose()


def test_network_defaults_and_lan_token_authentication(tmp_path: Path) -> None:
    local = Settings(database_url="sqlite://", artifact_root=tmp_path / "local")
    assert local.host == "127.0.0.1"
    try:
        Settings(database_url="sqlite://", artifact_root=tmp_path / "lan", lan_mode=True)
    except ValueError as error:
        assert "API_TOKEN" in str(error)
    else:
        raise AssertionError("LAN mode must require a token")

    lan = Settings(
        database_url=f"sqlite:///{tmp_path / 'lan.sqlite3'}",
        artifact_root=tmp_path / "lan-artifacts",
        lan_mode=True,
        api_token="test-development-token",
    )
    engine = make_engine(lan.database_url)
    Base.metadata.create_all(engine)
    with TestClient(create_app(settings=lan, session_factory=make_session_factory(engine))) as client:
        assert client.get("/api/v1/test-runs").status_code == 401
        response = client.get(
            "/api/v1/test-runs",
            headers={"Authorization": "Bearer test-development-token"},
        )
        assert response.status_code == 200
    engine.dispose()
