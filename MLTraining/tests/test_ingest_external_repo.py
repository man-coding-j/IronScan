import base64
import csv
from pathlib import Path

import pytest

from MLTraining.scripts.ingest_external_repo import (
    Configuration,
    ExternalLabel,
    discover_tongue_images,
    plan_ingestion,
    validate_configuration,
    validate_image,
)

SYNTHETIC_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAIklEQVR4nGPcEpXCQApgIkk1w6gG4gATkergYFQDMYBkDQCe2AGSqKGTtAAAAABJRU5ErkJggg=="
)


def test_discovery_reads_only_tongue_classes(tmp_path: Path) -> None:
    source_root = make_external_fixture(tmp_path)

    candidates = discover_tongue_images(source_root)

    assert len(candidates) == 2
    assert {candidate.external_label for candidate in candidates} == {
        ExternalLabel.CLAIMED_ANEMIA,
        ExternalLabel.CLAIMED_NORMAL,
    }
    assert all("eye" not in candidate.source_path.parts for candidate in candidates)
    assert all("nail" not in candidate.source_path.parts for candidate in candidates)


def test_apply_requires_label_acknowledgement_and_license_reference(tmp_path: Path) -> None:
    source_root = make_external_fixture(tmp_path)
    destination_root = make_destination_fixture(tmp_path)

    with pytest.raises(ValueError, match="acknowledge"):
        validate_configuration(
            Configuration(source_root, destination_root, True, False, None)
        )
    with pytest.raises(ValueError, match="license"):
        validate_configuration(
            Configuration(source_root, destination_root, True, True, None)
        )


def test_validation_and_planning_are_deterministic(tmp_path: Path) -> None:
    pytest.importorskip("PIL")
    source_root = make_external_fixture(tmp_path)
    validated = [validate_image(candidate) for candidate in discover_tongue_images(source_root)]

    first, first_counts = plan_ingestion(validated, known_hashes=set())
    second, second_counts = plan_ingestion(list(reversed(validated)), known_hashes=set())

    assert first == second
    assert first_counts == second_counts
    assert len(first) == 2
    assert all("external_engineering_fixture" in image.destination_relative_path for image in first)


def test_master_hash_prevents_duplicate_ingestion(tmp_path: Path) -> None:
    pytest.importorskip("PIL")
    source_root = make_external_fixture(tmp_path)
    validated = [validate_image(candidate) for candidate in discover_tongue_images(source_root)]

    planned, counters = plan_ingestion(validated, known_hashes={validated[0].sha256})

    assert len(planned) == 1
    assert counters["already_present"] == 1


def make_external_fixture(tmp_path: Path) -> Path:
    source_root = tmp_path / "external"
    paths = {
        source_root / "dataset" / "tongue" / "anemia" / "one.png": SYNTHETIC_PNG,
        source_root / "dataset" / "tongue" / "normal" / "two.png": SYNTHETIC_PNG + b"normal",
        source_root / "dataset" / "eye" / "anemia" / "ignored.png": SYNTHETIC_PNG,
        source_root / "dataset" / "nail" / "normal" / "ignored.png": SYNTHETIC_PNG,
    }
    for path, contents in paths.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    return source_root


def make_destination_fixture(tmp_path: Path) -> Path:
    destination_root = tmp_path / "sorted_dataset"
    destination_root.mkdir()
    with (destination_root / "dataset_index.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["sample_sha256"])
        writer.writeheader()
    return destination_root
