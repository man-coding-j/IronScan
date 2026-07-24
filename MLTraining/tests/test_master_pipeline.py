import base64
import csv
from pathlib import Path

import pytest

from MLTraining.scripts.master_pipeline import (
    ImageDetails,
    MasterSample,
    discover_custom_csv_tongue_images,
    discover_custom_tongue_directories,
    plan_copies,
    resolve_external_repository,
    resolve_tonguedx_root,
    training_target_fields,
    validate_output_category,
)

SYNTHETIC_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAIklEQVR4nGPcEpXCQApgIkk1w6gG4gATkergYFQDMYBkDQCe2AGSqKGTtAAAAABJRU5ErkJggg=="
)


def test_external_repository_main_suffix_is_supported(tmp_path: Path) -> None:
    repository = tmp_path / "anemia_detection_eye_nail_tongue-main"
    repository.mkdir()

    assert resolve_external_repository(tmp_path) == repository


def test_preferred_repository_and_direct_tonguedx_paths_are_deterministic(tmp_path: Path) -> None:
    preferred_repository = tmp_path / "anemia_detection_eye_nail_tongue"
    duplicate_repository = tmp_path / "anemia_detection_eye_nail_tongue-main"
    direct_tonguedx = tmp_path / "TongueDx2"
    preferred_repository.mkdir()
    duplicate_repository.mkdir()
    direct_tonguedx.mkdir()

    assert resolve_external_repository(tmp_path) == preferred_repository
    assert resolve_tonguedx_root(tmp_path) == direct_tonguedx


def test_custom_discovery_only_selects_named_tongue_directories(tmp_path: Path) -> None:
    tongue_directory = tmp_path / "custom_source" / "dataset" / "tongue"
    eye_directory = tmp_path / "custom_source" / "dataset" / "eye"
    tongue_directory.mkdir(parents=True)
    eye_directory.mkdir(parents=True)
    (tongue_directory / "tongue.png").write_bytes(SYNTHETIC_PNG)
    (eye_directory / "eye.png").write_bytes(SYNTHETIC_PNG)

    discovered = discover_custom_tongue_directories(tmp_path, excluded_roots=[])

    assert discovered == [tongue_directory]


def test_custom_csv_requires_tongue_context_and_resolves_relative_images(tmp_path: Path) -> None:
    source_root = tmp_path / "custom_source"
    metadata_root = source_root / "metadata"
    image_root = source_root / "raw"
    metadata_root.mkdir(parents=True)
    image_root.mkdir()
    tongue_image = image_root / "sample.png"
    tongue_image.write_bytes(SYNTHETIC_PNG)
    with (metadata_root / "tongue_fold.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["image_path"])
        writer.writeheader()
        writer.writerow({"image_path": "raw/sample.png"})

    discovered = discover_custom_csv_tongue_images(tmp_path, excluded_roots=[])

    assert discovered == [(source_root, tongue_image)]


def test_unreviewed_source_is_blocked_without_permission(tmp_path: Path) -> None:
    sample = make_sample(tmp_path, permission_required=True)

    planned, counters = plan_copies([sample], permissions={})

    assert planned == []
    assert counters["blocked::external_custom_sources/example"] == 1


def test_planning_never_creates_risk_tier_directories(tmp_path: Path) -> None:
    sample = make_sample(tmp_path, permission_required=False)

    planned, _ = plan_copies([sample], permissions={})

    assert len(planned) == 1
    assert "pallor_absent_clean_reference" in planned[0].destination_relative_path
    assert "low_risk" not in planned[0].destination_relative_path
    with pytest.raises(ValueError, match="risk tiers"):
        validate_output_category("high_risk")


def test_tongue_pale_target_is_explicit_and_conflicts_are_excluded(tmp_path: Path) -> None:
    negative = make_sample(tmp_path, permission_required=False)
    positive = MasterSample(
        **{
            **negative.__dict__,
            "source_category": "pallor_present",
        }
    )
    conflict = MasterSample(
        **{
            **negative.__dict__,
            "source_category": "annotation_conflict",
        }
    )

    assert training_target_fields(negative) == {
        "target_name": "TonguePale",
        "target_value": 0,
        "training_eligible": "true",
    }
    assert training_target_fields(positive)["target_value"] == 1
    assert training_target_fields(conflict)["training_eligible"] == "false"


def make_sample(tmp_path: Path, *, permission_required: bool) -> MasterSample:
    image_path = tmp_path / "synthetic.png"
    image_path.write_bytes(SYNTHETIC_PNG)
    return MasterSample(
        source_key=("external_custom_sources/example" if permission_required else "TongueDx2"),
        source_path=image_path,
        source_category=(
            "unreviewed_unlabeled" if permission_required else "pallor_absent_clean_reference"
        ),
        validation_status="synthetic_test_fixture",
        permission_required=permission_required,
        details=ImageDetails(
            sha256="a" * 64,
            image_format="PNG",
            width=16,
            height=16,
        ),
    )
