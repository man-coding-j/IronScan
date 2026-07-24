#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
from collections import Counter
from dataclasses import dataclass, replace
from enum import StrEnum
from pathlib import Path, PurePosixPath
from typing import Final, Sequence, cast

import numpy as np
from numpy.typing import NDArray

DEFAULT_DATASET_ROOT: Final = Path.home() / "Documents" / "IronScanPrivate" / "TongueDx2"
REQUIRED_CSV_NAMES: Final = {
    "test.csv",
    *(f"train_fold{index}.csv" for index in range(1, 6)),
    *(f"val_fold{index}.csv" for index in range(1, 5)),
}
INDICATOR_COLUMNS: Final = ("TonguePale", "FurThick", "FurYellow", "Toothmark", "TipSideRed")


class PhenotypeGroup(StrEnum):
    PALE_OBSERVED = "pale_observed"
    COATING_OR_TOOTHMARK_OBSERVED = "coating_or_toothmark_observed"
    REFERENCE_NEGATIVE = "reference_negative"
    OTHER_OBSERVED = "other_observed"
    ANNOTATION_CONFLICT = "annotation_conflict"


@dataclass(frozen=True)
class IndicatorValues:
    tongue_pale: int
    fur_thick: int
    fur_yellow: int
    toothmark: int
    tip_side_red: int


@dataclass(frozen=True)
class SourceRecord:
    relative_path: PurePosixPath
    source_path: Path
    segmentation_path: Path
    indicators: IndicatorValues
    phenotype_group: PhenotypeGroup
    fold_memberships: tuple[str, ...]


@dataclass(frozen=True)
class FeatureBundle:
    lab_features: NDArray[np.uint8]
    valid_tissue_mask: NDArray[np.uint8]


@dataclass(frozen=True)
class RunConfiguration:
    dataset_root: Path
    output_root: Path
    preprocess: bool


def parse_arguments() -> RunConfiguration:
    parser = argparse.ArgumentParser(
        description=(
            "Create a de-duplicated private TongueDX phenotype review set and optional Lab feature tensors. "
            "Appearance groups are not anemia-risk labels."
        )
    )
    parser.add_argument("--dataset-root", type=Path)
    parser.add_argument("--output-root", type=Path)
    parser.add_argument(
        "--skip-preprocessing",
        action="store_true",
        help="Copy originals and write the private index without creating Lab feature tensors.",
    )
    arguments = parser.parse_args()

    dataset_root = locate_dataset_root(arguments.dataset_root)
    output_root = (arguments.output_root or dataset_root / "sorted_dataset").expanduser().resolve()
    if output_root == dataset_root or not output_root.is_relative_to(dataset_root):
        raise ValueError("--output-root must be a child directory of the private TongueDx2 root")
    return RunConfiguration(
        dataset_root=dataset_root,
        output_root=output_root,
        preprocess=not arguments.skip_preprocessing,
    )


def locate_dataset_root(explicit_root: Path | None, current_directory: Path | None = None) -> Path:
    if explicit_root is not None:
        candidate = explicit_root.expanduser().resolve()
        validate_dataset_root(candidate)
        return candidate

    working_directory = (current_directory or Path.cwd()).resolve()
    if working_directory.name.casefold() == "tonguedx2":
        validate_dataset_root(working_directory)
        return working_directory

    validate_dataset_root(DEFAULT_DATASET_ROOT)
    return DEFAULT_DATASET_ROOT.resolve()


def validate_dataset_root(dataset_root: Path) -> None:
    if not dataset_root.is_dir():
        raise ValueError(f"TongueDX root does not exist: {dataset_root}")
    if not (dataset_root / "release" / "list").is_dir():
        raise ValueError("TongueDX root must contain release/list")
    if not (dataset_root / "release" / "origin").is_dir():
        raise ValueError("TongueDX root must contain release/origin")
    if not (dataset_root / "release" / "seg").is_dir():
        raise ValueError("TongueDX root must contain release/seg")


def discover_csv_files(dataset_root: Path) -> list[Path]:
    list_root = dataset_root / "release" / "list"
    csv_files = sorted(list_root.glob("*.csv"))
    available_names = {path.name for path in csv_files}
    missing_names = REQUIRED_CSV_NAMES - available_names
    if missing_names:
        raise ValueError(f"TongueDX list directory is missing required CSV files: {sorted(missing_names)}")
    return csv_files


def read_source_records(dataset_root: Path, csv_files: Sequence[Path]) -> list[SourceRecord]:
    records_by_path: dict[PurePosixPath, SourceRecord] = {}
    for csv_path in csv_files:
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            validate_columns(reader.fieldnames, csv_path.name)
            for row_number, row in enumerate(reader, start=2):
                relative_path = parse_relative_path(row.get("image_path"), csv_path.name, row_number)
                indicators = parse_indicators(row, csv_path.name, row_number)
                source_path = resolve_private_image(dataset_root, "origin", relative_path)
                segmentation_path = resolve_private_image(dataset_root, "seg", relative_path)
                record = SourceRecord(
                    relative_path=relative_path,
                    source_path=source_path,
                    segmentation_path=segmentation_path,
                    indicators=indicators,
                    phenotype_group=classify_phenotype(indicators),
                    fold_memberships=(csv_path.name,),
                )
                previous = records_by_path.get(relative_path)
                if previous is None:
                    records_by_path[relative_path] = record
                    continue
                if previous.indicators != indicators:
                    raise ValueError(
                        f"Conflicting indicator values for a duplicate image in {csv_path.name} row {row_number}"
                    )
                memberships = tuple(sorted({*previous.fold_memberships, csv_path.name}))
                records_by_path[relative_path] = replace(previous, fold_memberships=memberships)
    return sorted(records_by_path.values(), key=lambda record: record.relative_path.as_posix())


def validate_columns(fieldnames: Sequence[str] | None, csv_name: str) -> None:
    available = set(fieldnames or [])
    required = {"image_path", *INDICATOR_COLUMNS}
    missing = required - available
    if missing:
        raise ValueError(f"{csv_name} is missing required columns: {sorted(missing)}")


def parse_relative_path(value: str | None, csv_name: str, row_number: int) -> PurePosixPath:
    normalized = (value or "").strip().replace("\\", "/")
    relative_path = PurePosixPath(normalized)
    if not normalized or relative_path.is_absolute() or ".." in relative_path.parts:
        raise ValueError(f"Unsafe or empty image_path in {csv_name} row {row_number}")
    return relative_path


def parse_indicators(row: dict[str, str], csv_name: str, row_number: int) -> IndicatorValues:
    values: list[int] = []
    for column in INDICATOR_COLUMNS:
        raw_value = (row.get(column) or "").strip()
        try:
            value = int(raw_value)
        except ValueError as error:
            raise ValueError(f"{column} must be binary in {csv_name} row {row_number}") from error
        if value not in (0, 1):
            raise ValueError(f"{column} must be binary in {csv_name} row {row_number}")
        values.append(value)
    return IndicatorValues(*values)


def resolve_private_image(dataset_root: Path, image_directory: str, relative_path: PurePosixPath) -> Path:
    directory = (dataset_root / "release" / image_directory).resolve()
    candidate = directory.joinpath(*relative_path.parts).resolve()
    if not candidate.is_relative_to(directory):
        raise ValueError("Image path escapes the private dataset directory")
    if not candidate.is_file():
        raise ValueError(f"Referenced {image_directory} image is missing")
    return candidate


def classify_phenotype(indicators: IndicatorValues) -> PhenotypeGroup:
    if indicators.tongue_pale == 1:
        return PhenotypeGroup.PALE_OBSERVED
    if indicators.fur_thick == 1 or indicators.fur_yellow == 1 or indicators.toothmark == 1:
        return PhenotypeGroup.COATING_OR_TOOTHMARK_OBSERVED
    if indicators == IndicatorValues(0, 0, 0, 0, 0):
        return PhenotypeGroup.REFERENCE_NEGATIVE
    return PhenotypeGroup.OTHER_OBSERVED


def extract_lab_features(
    image_bgr: NDArray[np.uint8],
    tongue_mask: NDArray[np.uint8],
) -> FeatureBundle:
    import cv2

    if image_bgr.dtype != np.uint8 or image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("image_bgr must be an HxWx3 uint8 array")
    if tongue_mask.dtype != np.uint8 or tongue_mask.ndim != 2:
        raise ValueError("tongue_mask must be an HxW uint8 array")
    if tongue_mask.shape != image_bgr.shape[:2]:
        raise ValueError("tongue_mask dimensions must match image_bgr")

    binary_mask = np.where(tongue_mask > 127, 255, 0).astype(np.uint8)
    if np.count_nonzero(binary_mask) < 64:
        raise ValueError("tongue_mask contains too few accepted pixels")

    lab_image = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB)
    smoothed_lab = cv2.bilateralFilter(lab_image, d=7, sigmaColor=35, sigmaSpace=35)
    split_channels = cv2.split(smoothed_lab)
    lightness = cast(NDArray[np.uint8], split_channels[0])
    redness = cast(NDArray[np.uint8], split_channels[1])
    yellowness = cast(NDArray[np.uint8], split_channels[2])
    enhanced_lightness = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(lightness)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    interior_mask = cast(NDArray[np.uint8], cv2.erode(binary_mask, kernel, iterations=1))
    valid_tissue_mask = robust_lab_inlier_mask(
        lightness=lightness,
        redness=redness,
        yellowness=yellowness,
        tongue_mask=interior_mask,
    )
    lab_features = cast(NDArray[np.uint8], cv2.merge((enhanced_lightness, redness, yellowness)))
    lab_features[valid_tissue_mask == 0] = 0
    return FeatureBundle(lab_features=lab_features, valid_tissue_mask=valid_tissue_mask)


def robust_lab_inlier_mask(
    *,
    lightness: NDArray[np.uint8],
    redness: NDArray[np.uint8],
    yellowness: NDArray[np.uint8],
    tongue_mask: NDArray[np.uint8],
) -> NDArray[np.uint8]:
    import cv2

    accepted = tongue_mask > 0
    if np.count_nonzero(accepted) < 64:
        raise ValueError("tongue_mask contains too few interior pixels")

    inlier_mask = accepted.copy()
    for channel in (lightness, redness, yellowness):
        values = channel[accepted].astype(np.float32)
        median = float(np.median(values))
        median_absolute_deviation = float(np.median(np.abs(values - median)))
        robust_scale = max(1.4826 * median_absolute_deviation, 1.0)
        inlier_mask &= np.abs(channel.astype(np.float32) - median) <= 3.5 * robust_scale

    inlier_mask &= lightness > 3
    inlier_mask &= lightness < 252
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    result = np.where(inlier_mask, 255, 0).astype(np.uint8)
    return cast(NDArray[np.uint8], cv2.morphologyEx(result, cv2.MORPH_OPEN, kernel))


def preprocess_private_image(record: SourceRecord, destination: Path) -> None:
    import cv2

    image_value = cv2.imread(os.fspath(record.source_path), cv2.IMREAD_COLOR)
    mask_value = cv2.imread(os.fspath(record.segmentation_path), cv2.IMREAD_GRAYSCALE)
    if image_value is None or mask_value is None:
        raise ValueError("OpenCV could not decode a private source image or segmentation mask")
    image = cast(NDArray[np.uint8], image_value)
    mask = cast(NDArray[np.uint8], mask_value)
    if mask.shape != image.shape[:2]:
        mask = cast(
            NDArray[np.uint8],
            cv2.resize(mask, (image.shape[1], image.shape[0]), interpolation=cv2.INTER_NEAREST),
        )
    features = extract_lab_features(image, mask)
    np.savez_compressed(
        destination,
        lab_features=features.lab_features,
        valid_tissue_mask=features.valid_tissue_mask,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_private_review_set(configuration: RunConfiguration) -> dict[str, object]:
    csv_files = discover_csv_files(configuration.dataset_root)
    records = read_source_records(configuration.dataset_root, csv_files)
    if configuration.output_root.exists():
        raise ValueError(
            f"Output directory already exists; choose a new --output-root to avoid overwriting data: "
            f"{configuration.output_root}"
        )

    staging_root = configuration.output_root.with_name(f".{configuration.output_root.name}.staging-{os.getpid()}")
    staging_root.mkdir(parents=True)
    try:
        report = write_review_set(records, staging_root, configuration.preprocess)
        staging_root.replace(configuration.output_root)
    except BaseException:
        shutil.rmtree(staging_root, ignore_errors=True)
        raise
    return report


def write_review_set(
    records: Sequence[SourceRecord],
    output_root: Path,
    preprocess: bool,
) -> dict[str, object]:
    category_counts: Counter[str] = Counter()
    content_records: dict[str, tuple[SourceRecord, bool]] = {}
    duplicate_content_count = 0
    conflicting_content_hashes: set[str] = set()

    for record in records:
        content_hash = sha256_file(record.source_path)
        previous_entry = content_records.get(content_hash)
        if previous_entry is not None:
            previous, has_conflict = previous_entry
            memberships = tuple(sorted({*previous.fold_memberships, *record.fold_memberships}))
            has_conflict = has_conflict or previous.indicators != record.indicators
            if has_conflict:
                conflicting_content_hashes.add(content_hash)
            merged = replace(
                previous,
                phenotype_group=(
                    PhenotypeGroup.ANNOTATION_CONFLICT if has_conflict else previous.phenotype_group
                ),
                fold_memberships=memberships,
            )
            content_records[content_hash] = (merged, has_conflict)
            duplicate_content_count += 1
            continue
        content_records[content_hash] = (record, False)

    index_path = output_root / "dataset_index.csv"
    with index_path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = [
            "sample_sha256",
            "phenotype_group",
            "TonguePale",
            "FurThick",
            "FurYellow",
            "Toothmark",
            "TipSideRed",
            "fold_memberships",
            "lab_feature_archive",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for content_hash, (record, has_conflict) in sorted(content_records.items()):
            category_root = output_root / record.phenotype_group.value
            original_root = category_root / "original"
            feature_root = category_root / "lab_features"
            original_root.mkdir(parents=True, exist_ok=True)
            if preprocess:
                feature_root.mkdir(parents=True, exist_ok=True)

            suffix = record.source_path.suffix.lower()
            destination_image = original_root / f"{content_hash}{suffix}"
            shutil.copyfile(record.source_path, destination_image)
            feature_relative = ""
            if preprocess:
                feature_path = feature_root / f"{content_hash}.npz"
                preprocess_private_image(record, feature_path)
                feature_relative = feature_path.relative_to(output_root).as_posix()

            indicators = record.indicators
            indicator_value = "" if has_conflict else None
            writer.writerow(
                {
                    "sample_sha256": content_hash,
                    "phenotype_group": record.phenotype_group.value,
                    "TonguePale": indicator_value if has_conflict else indicators.tongue_pale,
                    "FurThick": indicator_value if has_conflict else indicators.fur_thick,
                    "FurYellow": indicator_value if has_conflict else indicators.fur_yellow,
                    "Toothmark": indicator_value if has_conflict else indicators.toothmark,
                    "TipSideRed": indicator_value if has_conflict else indicators.tip_side_red,
                    "fold_memberships": ";".join(record.fold_memberships),
                    "lab_feature_archive": feature_relative,
                }
            )
            category_counts[record.phenotype_group.value] += 1

    report: dict[str, object] = {
        "schema_version": 1,
        "purpose": "private phenotype review and preprocessing; not anemia-risk labeling",
        "csv_file_count": len({membership for record in records for membership in record.fold_memberships}),
        "fold_row_unique_path_count": len(records),
        "overlapping_path_count": sum(len(record.fold_memberships) > 1 for record in records),
        "duplicate_content_count": duplicate_content_count,
        "conflicting_content_count": len(conflicting_content_hashes),
        "unique_content_count": len(content_records),
        "preprocessing_enabled": preprocess,
        "phenotype_distribution": dict(sorted(category_counts.items())),
        "limitations": [
            "Tongue appearance annotations do not establish anemia or iron-deficiency anemia.",
            "Identical image contents with conflicting annotations are quarantined with blank indicator values.",
            "Lab feature extraction separates channels but cannot recover tissue color hidden by opaque coating.",
            "CLAHE is applied only to the lightness feature and must not replace the locked iOS model input contract.",
            "Fold membership is preserved for audit; this combined review set must not be randomly split for training.",
        ],
    }
    (output_root / "processing_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def print_report(report: dict[str, object]) -> None:
    print("TongueDX private preprocessing complete")
    print(f"Unique source paths: {report['fold_row_unique_path_count']}")
    print(f"Unique image contents: {report['unique_content_count']}")
    print(f"Overlapping fold paths: {report['overlapping_path_count']}")
    distribution = report["phenotype_distribution"]
    if isinstance(distribution, dict):
        for group, count in distribution.items():
            print(f"{group}: {count}")
    print("These are appearance phenotype groups, not anemia-risk labels.")


def main() -> None:
    configuration = parse_arguments()
    report = build_private_review_set(configuration)
    print_report(report)


if __name__ == "__main__":
    main()
