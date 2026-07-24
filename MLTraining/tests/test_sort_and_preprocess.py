import csv
from pathlib import Path, PurePosixPath

import numpy as np
import pytest

from MLTraining.scripts.sort_and_preprocess import (
    IndicatorValues,
    PhenotypeGroup,
    SourceRecord,
    classify_phenotype,
    extract_lab_features,
    read_source_records,
    write_review_set,
)


def test_phenotype_mapping_does_not_create_medical_risk_labels() -> None:
    assert classify_phenotype(IndicatorValues(1, 0, 0, 0, 0)) == PhenotypeGroup.PALE_OBSERVED
    assert classify_phenotype(IndicatorValues(0, 1, 0, 0, 0)) == PhenotypeGroup.COATING_OR_TOOTHMARK_OBSERVED
    assert classify_phenotype(IndicatorValues(0, 0, 1, 0, 0)) == PhenotypeGroup.COATING_OR_TOOTHMARK_OBSERVED
    assert classify_phenotype(IndicatorValues(0, 0, 0, 1, 0)) == PhenotypeGroup.COATING_OR_TOOTHMARK_OBSERVED
    assert classify_phenotype(IndicatorValues(0, 0, 0, 0, 0)) == PhenotypeGroup.REFERENCE_NEGATIVE
    assert classify_phenotype(IndicatorValues(0, 0, 0, 0, 1)) == PhenotypeGroup.OTHER_OBSERVED


def test_duplicate_fold_paths_are_merged_deterministically(tmp_path: Path) -> None:
    dataset_root = make_private_fixture(tmp_path)
    first_csv = dataset_root / "release" / "list" / "train_fold1.csv"
    second_csv = dataset_root / "release" / "list" / "val_fold1.csv"
    write_csv(first_csv, image_path="group/sample.jpg", tongue_pale=0)
    write_csv(second_csv, image_path="group/sample.jpg", tongue_pale=0)

    records = read_source_records(dataset_root, [second_csv, first_csv])

    assert len(records) == 1
    assert records[0].fold_memberships == ("train_fold1.csv", "val_fold1.csv")


def test_conflicting_duplicate_metadata_is_rejected(tmp_path: Path) -> None:
    dataset_root = make_private_fixture(tmp_path)
    first_csv = dataset_root / "release" / "list" / "train_fold1.csv"
    second_csv = dataset_root / "release" / "list" / "val_fold1.csv"
    write_csv(first_csv, image_path="group/sample.jpg", tongue_pale=0)
    write_csv(second_csv, image_path="group/sample.jpg", tongue_pale=1)

    with pytest.raises(ValueError, match="Conflicting indicator values"):
        read_source_records(dataset_root, [first_csv, second_csv])


def test_lab_features_preserve_shape_and_exclude_masked_pixels() -> None:
    pytest.importorskip("cv2")
    image = np.full((32, 32, 3), (90, 110, 150), dtype=np.uint8)
    image[12:20, 12:20] = (40, 60, 220)
    mask = np.zeros((32, 32), dtype=np.uint8)
    mask[4:28, 4:28] = 255

    result = extract_lab_features(image, mask)

    assert result.lab_features.shape == image.shape
    assert result.valid_tissue_mask.shape == mask.shape
    assert result.lab_features.dtype == np.uint8
    assert np.all(result.lab_features[result.valid_tissue_mask == 0] == 0)
    assert np.count_nonzero(result.valid_tissue_mask) > 0


def test_content_annotation_conflict_is_quarantined(tmp_path: Path) -> None:
    first_image = tmp_path / "first.jpg"
    second_image = tmp_path / "second.jpg"
    segmentation = tmp_path / "mask.jpg"
    first_image.write_bytes(b"same synthetic image")
    second_image.write_bytes(b"same synthetic image")
    segmentation.write_bytes(b"synthetic mask")
    records = [
        SourceRecord(
            relative_path=PurePosixPath("first.jpg"),
            source_path=first_image,
            segmentation_path=segmentation,
            indicators=IndicatorValues(0, 0, 0, 0, 0),
            phenotype_group=PhenotypeGroup.REFERENCE_NEGATIVE,
            fold_memberships=("train_fold1.csv",),
        ),
        SourceRecord(
            relative_path=PurePosixPath("second.jpg"),
            source_path=second_image,
            segmentation_path=segmentation,
            indicators=IndicatorValues(1, 0, 0, 0, 0),
            phenotype_group=PhenotypeGroup.PALE_OBSERVED,
            fold_memberships=("val_fold1.csv",),
        ),
    ]
    output_root = tmp_path / "output"
    output_root.mkdir()

    report = write_review_set(records, output_root, preprocess=False)

    assert report["conflicting_content_count"] == 1
    assert report["phenotype_distribution"] == {"annotation_conflict": 1}
    with (output_root / "dataset_index.csv").open(newline="", encoding="utf-8") as handle:
        row = next(csv.DictReader(handle))
    assert row["phenotype_group"] == "annotation_conflict"
    assert row["TonguePale"] == ""


def make_private_fixture(tmp_path: Path) -> Path:
    dataset_root = tmp_path / "TongueDx2"
    for directory in ("list", "origin/group", "seg/group"):
        (dataset_root / "release" / directory).mkdir(parents=True)
    (dataset_root / "release" / "origin" / "group" / "sample.jpg").write_bytes(b"synthetic image")
    (dataset_root / "release" / "seg" / "group" / "sample.jpg").write_bytes(b"synthetic mask")
    return dataset_root


def write_csv(path: Path, *, image_path: str, tongue_pale: int) -> None:
    fieldnames = ["image_path", "TonguePale", "FurThick", "FurYellow", "Toothmark", "TipSideRed"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow(
            {
                "image_path": image_path,
                "TonguePale": tongue_pale,
                "FurThick": 0,
                "FurYellow": 0,
                "Toothmark": 0,
                "TipSideRed": 0,
            }
        )
