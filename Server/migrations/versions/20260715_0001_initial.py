"""Create local diagnostics tables."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260715_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "test_runs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("app_version", sa.String(length=50), nullable=False),
        sa.Column("device_model", sa.String(length=100), nullable=False),
        sa.Column("ios_version", sa.String(length=50), nullable=False),
        sa.Column("model_version", sa.String(length=100), nullable=False),
        sa.Column("preprocessing_version", sa.String(length=100), nullable=False),
        sa.Column("notes", sa.Text()),
    )
    op.create_table(
        "scan_records",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("test_run_id", sa.Integer(), sa.ForeignKey("test_runs.id", ondelete="CASCADE"), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("anonymous_fixture_id", sa.String(length=128), nullable=False),
        sa.Column("calibration_mode", sa.String(length=40), nullable=False),
        sa.Column("quality_score", sa.Float(), nullable=False),
        sa.Column("rejection_reasons", sa.JSON(), nullable=False),
        sa.Column("segmentation_confidence", sa.Float(), nullable=False),
        sa.Column("calibration_residual", sa.Float()),
        sa.Column("condition_number", sa.Float()),
        sa.Column("specular_fraction", sa.Float(), nullable=False),
        sa.Column("risk_score", sa.Float()),
        sa.Column("decision", sa.String(length=40), nullable=False),
        sa.Column("segmentation_latency_ms", sa.Float(), nullable=False),
        sa.Column("calibration_latency_ms", sa.Float(), nullable=False),
        sa.Column("risk_latency_ms", sa.Float(), nullable=False),
        sa.Column("total_latency_ms", sa.Float(), nullable=False),
        sa.Column("expected_label", sa.String(length=40)),
        sa.Column("expected_hemoglobin", sa.Float()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("test_run_id", "anonymous_fixture_id", name="uq_scan_run_fixture"),
    )
    op.create_table(
        "debug_artifacts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "scan_record_id",
            sa.Integer(),
            sa.ForeignKey("scan_records.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("artifact_type", sa.String(length=40), nullable=False),
        sa.Column("relative_path", sa.String(length=255), nullable=False, unique=True),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False),
        sa.Column("height", sa.Integer(), nullable=False),
        sa.Column("retention_expires_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("debug_artifacts")
    op.drop_table("scan_records")
    op.drop_table("test_runs")
