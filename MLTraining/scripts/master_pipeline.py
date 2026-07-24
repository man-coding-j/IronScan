#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
from collections import Counter
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Final, Sequence

from MLTraining.scripts.ingest_external_repo import discover_tongue_images
from MLTraining.scripts.sort_and_preprocess import discover_csv_files, read_source_records

DEFAULT_DOCUMENTS_ROOT: Final = Path.home() / "Documents"
DEFAULT_OUTPUT_ROOT: Final = DEFAULT_DOCUMENTS_ROOT / "IronScanMasterDataset"
TONGUEDX_RELATIVE_ROOT: Final = Path("IronScanPrivate") / "TongueDx2"
TONGUEDX_ROOT_CANDIDATES: Final = (TONGUEDX_RELATIVE_ROOT, Path("TongueDx2"))
EXTERNAL_REPOSITORY_NAMES: Final = (
    "anemia_detection_eye_nail_tongue",
    "anemia_detection_eye_nail_tongue-main",
)
EXPLICIT_NON_TONGUE_SOURCE_NAMES: Final = (
    "AIQuest_DATATHON",
    "hemoglobin-deficiency-detection",
)
SUPPORTED_EXTENSIONS: Final = {".jpg", ".jpeg", ".png"}
CUSTOM_TONGUE_PATTERNS: Final = (
    "tongue",
    "tongues",
    "dataset/tongue",
    "dataset/tongues",
    "data/tongue",
    "data/tongues",
    "images/tongue",
    "images/tongues",
)
CUSTOM_CSV_PATTERNS: Final = ("*.csv", "list/*.csv", "metadata/*.csv", "dataset/*.csv")
CUSTOM_IMAGE_PATH_COLUMNS: Final = ("image_path", "path", "filepath", "file_path")
TONGUEDX_PALLOR_CATEGORIES: Final = {
    "pale_observed": "pallor_present",
    "coating_or_toothmark_observed": "pallor_absent_surface_confounder",
    "reference_negative": "pallor_absent_clean_reference",
    "other_observed": "pallor_absent_other_appearance",
    "annotation_conflict": "annotation_conflict",
}


@dataclass(frozen=True)
class Configuration:
    documents_root: Path
    output_root: Path
    apply: bool
    permissions: dict[str, str]


@dataclass(frozen=True)
class ImageDetails:
    sha256: str
    image_format: str
    width: int
    height: int


@dataclass(frozen=True)
class MasterSample:
    source_key: str
    source_path: Path
    source_category: str
    validation_status: str
    permission_required: bool
    details: ImageDetails


@dataclass(frozen=True)
class PlannedCopy:
    sample: MasterSample
    destination_relative_path: str


def parse_arguments() -> Configuration:
    parser = argparse.ArgumentParser(
        description=(
            "Discover and structurally organize local tongue-image datasets without converting appearance or "
            "proxy labels into IronScan clinical-risk tiers. The default is a read-only dry run."
        )
    )
    parser.add_argument("--documents-root", type=Path, default=DEFAULT_DOCUMENTS_ROOT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--apply", action="store_true", help="Create the master dataset; default is dry-run.")
    parser.add_argument(
        "--permission",
        action="append",
        default=[],
        metavar="SOURCE_KEY=REFERENCE",
        help="Record reviewed reuse permission for an external/custom source; may be repeated.",
    )
    arguments = parser.parse_args()
    configuration = Configuration(
        documents_root=arguments.documents_root.expanduser().resolve(),
        output_root=arguments.output_root.expanduser().resolve(),
        apply=arguments.apply,
        permissions=parse_permissions(arguments.permission),
    )
    validate_configuration(configuration)
    return configuration


def parse_permissions(values: Sequence[str]) -> dict[str, str]:
    permissions: dict[str, str] = {}
    for value in values:
        source_key, separator, reference = value.partition("=")
        source_key = source_key.strip()
        reference = reference.strip()
        if not separator or not source_key or not reference:
            raise ValueError("Every --permission must use SOURCE_KEY=REFERENCE")
        if source_key in permissions:
            raise ValueError(f"Duplicate permission entry for {source_key}")
        permissions[source_key] = reference
    return permissions


def validate_configuration(configuration: Configuration) -> None:
    if not configuration.documents_root.is_dir():
        raise ValueError(f"Documents root does not exist: {configuration.documents_root}")
    if not configuration.output_root.parent.is_dir():
        raise ValueError(f"Master dataset parent does not exist: {configuration.output_root.parent}")
    if configuration.output_root == configuration.documents_root:
        raise ValueError("Master dataset output cannot replace the Documents root")
    if configuration.apply and configuration.output_root.exists():
        raise ValueError("Master dataset output already exists; refusing to overwrite it")


def inspect_image(path: Path) -> ImageDetails:
    from PIL import Image, UnidentifiedImageError

    try:
        with Image.open(path) as image:
            image_format = (image.format or "").upper()
            width, height = image.size
            image.verify()
    except (OSError, SyntaxError, UnidentifiedImageError) as error:
        raise ValueError("Tongue image is corrupt or unsupported") from error

    if image_format not in {"JPEG", "PNG"}:
        raise ValueError(f"Unsupported tongue image format: {image_format or 'unknown'}")
    if width < 16 or height < 16:
        raise ValueError("Tongue image dimensions are too small")
    return ImageDetails(
        sha256=sha256_file(path),
        image_format=image_format,
        width=width,
        height=height,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def collect_tonguedx_samples(documents_root: Path) -> list[MasterSample]:
    dataset_root = resolve_tonguedx_root(documents_root)
    if dataset_root is None:
        return []
    records = read_source_records(dataset_root, discover_csv_files(dataset_root))
    samples_by_hash: dict[str, MasterSample] = {}
    for record in records:
        details = inspect_image(record.source_path)
        sample = MasterSample(
            source_key="TongueDx2",
            source_path=record.source_path,
            source_category=TONGUEDX_PALLOR_CATEGORIES[record.phenotype_group.value],
            validation_status="tongue_pale_visual_annotation_not_anemia_ground_truth",
            permission_required=False,
            details=details,
        )
        previous = samples_by_hash.get(details.sha256)
        if previous is None:
            samples_by_hash[details.sha256] = sample
        elif previous.source_category != sample.source_category:
            samples_by_hash[details.sha256] = replace(
                previous,
                source_category="annotation_conflict",
                validation_status="conflicting_appearance_annotations",
            )
    return sorted(samples_by_hash.values(), key=lambda sample: sample.details.sha256)


def resolve_tonguedx_root(documents_root: Path) -> Path | None:
    matches = [documents_root / candidate for candidate in TONGUEDX_ROOT_CANDIDATES]
    existing = [path.resolve() for path in matches if path.is_dir()]
    return existing[0] if existing else None


def existing_external_repository_roots(documents_root: Path) -> list[Path]:
    return [
        (documents_root / name).resolve()
        for name in EXTERNAL_REPOSITORY_NAMES
        if (documents_root / name).is_dir()
    ]


def resolve_external_repository(documents_root: Path) -> Path | None:
    matches = existing_external_repository_roots(documents_root)
    return matches[0] if matches else None


def collect_external_repository_samples(documents_root: Path) -> list[MasterSample]:
    source_root = resolve_external_repository(documents_root)
    if source_root is None:
        return []
    samples: list[MasterSample] = []
    for candidate in discover_tongue_images(source_root):
        samples.append(
            MasterSample(
                source_key="anemia_detection_github",
                source_path=candidate.source_path,
                source_category=candidate.external_label.value,
                validation_status="engineering_fixture_unvalidated_proxy_label",
                permission_required=True,
                details=inspect_image(candidate.source_path),
            )
        )
    return deduplicate_source_samples(samples)


def discover_custom_tongue_directories(documents_root: Path, excluded_roots: Sequence[Path]) -> list[Path]:
    excluded = {path.resolve() for path in excluded_roots if path.exists()}
    tongue_directories: list[Path] = []
    for child in sorted(documents_root.iterdir()):
        if not child.is_dir() or child.name.startswith(".") or child.resolve() in excluded:
            continue
        for relative_pattern in CUSTOM_TONGUE_PATTERNS:
            candidate = child / relative_pattern
            if candidate.is_dir():
                tongue_directories.append(candidate.resolve())
        if "tongue" in child.name.casefold():
            direct_images = any(
                path.is_file() and path.suffix.casefold() in SUPPORTED_EXTENSIONS
                for path in child.iterdir()
            )
            if direct_images:
                tongue_directories.append(child.resolve())
    return sorted(set(tongue_directories))


def collect_custom_samples(documents_root: Path, excluded_roots: Sequence[Path]) -> list[MasterSample]:
    samples: list[MasterSample] = []
    for tongue_directory in discover_custom_tongue_directories(documents_root, excluded_roots):
        top_level_source = tongue_directory.relative_to(documents_root).parts[0]
        source_key = f"external_custom_sources/{safe_slug(top_level_source)}"
        for path in sorted(tongue_directory.rglob("*")):
            if not path.is_file() or path.name.startswith("."):
                continue
            if path.suffix.casefold() not in SUPPORTED_EXTENSIONS:
                continue
            samples.append(
                MasterSample(
                    source_key=source_key,
                    source_path=path.resolve(),
                    source_category="unreviewed_unlabeled",
                    validation_status="quarantined_pending_provenance_and_ground_truth",
                    permission_required=True,
                    details=inspect_image(path),
                )
            )
    for source_root, path in discover_custom_csv_tongue_images(documents_root, excluded_roots):
        source_key = f"external_custom_sources/{safe_slug(source_root.name)}"
        samples.append(
            MasterSample(
                source_key=source_key,
                source_path=path,
                source_category="unreviewed_unlabeled",
                validation_status="quarantined_pending_provenance_and_ground_truth",
                permission_required=True,
                details=inspect_image(path),
            )
        )
    return deduplicate_source_samples(samples)


def discover_custom_csv_tongue_images(
    documents_root: Path,
    excluded_roots: Sequence[Path],
) -> list[tuple[Path, Path]]:
    excluded = {path.resolve() for path in excluded_roots if path.exists()}
    discovered: set[tuple[Path, Path]] = set()
    for source_root in sorted(documents_root.iterdir()):
        if not source_root.is_dir() or source_root.name.startswith(".") or source_root.resolve() in excluded:
            continue
        csv_paths = {
            csv_path.resolve()
            for pattern in CUSTOM_CSV_PATTERNS
            for csv_path in source_root.glob(pattern)
            if csv_path.is_file()
        }
        for csv_path in sorted(csv_paths):
            with csv_path.open(newline="", encoding="utf-8-sig") as handle:
                reader = csv.DictReader(handle)
                fieldnames = set(reader.fieldnames or [])
                path_column = next(
                    (column for column in CUSTOM_IMAGE_PATH_COLUMNS if column in fieldnames),
                    None,
                )
                if path_column is None:
                    continue
                csv_has_tongue_context = "tongue" in csv_path.name.casefold()
                source_has_tongue_context = "tongue" in source_root.name.casefold()
                for row in reader:
                    raw_path = (row.get(path_column) or "").strip().replace("\\", "/")
                    relative_path = Path(raw_path)
                    if not raw_path or relative_path.is_absolute() or ".." in relative_path.parts:
                        continue
                    has_tongue_context = (
                        csv_has_tongue_context
                        or source_has_tongue_context
                        or any("tongue" in part.casefold() for part in relative_path.parts)
                    )
                    if not has_tongue_context:
                        continue
                    candidates = (source_root / relative_path, csv_path.parent / relative_path)
                    resolved = next(
                        (
                            candidate.resolve()
                            for candidate in candidates
                            if candidate.is_file()
                            and candidate.suffix.casefold() in SUPPORTED_EXTENSIONS
                            and candidate.resolve().is_relative_to(source_root.resolve())
                        ),
                        None,
                    )
                    if resolved is not None:
                        discovered.add((source_root.resolve(), resolved))
    return sorted(discovered)


def safe_slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.casefold()).strip("_")
    if not slug:
        raise ValueError("Custom source folder does not produce a safe source key")
    return slug


def deduplicate_source_samples(samples: Sequence[MasterSample]) -> list[MasterSample]:
    samples_by_source_and_hash: dict[tuple[str, str], MasterSample] = {}
    for sample in samples:
        key = (sample.source_key, sample.details.sha256)
        previous = samples_by_source_and_hash.get(key)
        if previous is None:
            samples_by_source_and_hash[key] = sample
        elif previous.source_category != sample.source_category:
            samples_by_source_and_hash[key] = replace(
                previous,
                source_category="annotation_conflict",
                validation_status="conflicting_source_annotations",
            )
    return sorted(
        samples_by_source_and_hash.values(),
        key=lambda sample: (sample.source_key, sample.source_category, sample.details.sha256),
    )


def collect_all_samples(configuration: Configuration) -> list[MasterSample]:
    ironscan_private_root = configuration.documents_root / "IronScanPrivate"
    direct_tonguedx_root = configuration.documents_root / "TongueDx2"
    external_roots = existing_external_repository_roots(configuration.documents_root)
    explicit_non_tongue_roots = [
        configuration.documents_root / name for name in EXPLICIT_NON_TONGUE_SOURCE_NAMES
    ]
    excluded_roots = [
        ironscan_private_root,
        direct_tonguedx_root,
        configuration.output_root,
        *external_roots,
        *explicit_non_tongue_roots,
    ]
    samples = [
        *collect_tonguedx_samples(configuration.documents_root),
        *collect_external_repository_samples(configuration.documents_root),
        *collect_custom_samples(configuration.documents_root, excluded_roots),
    ]
    if not samples:
        raise ValueError("No tongue-image dataset sources were found")
    return samples


def audit_explicit_non_tongue_sources(documents_root: Path) -> Counter[str]:
    counters: Counter[str] = Counter()
    for source_name in EXPLICIT_NON_TONGUE_SOURCE_NAMES:
        source_root = documents_root / source_name
        if not source_root.is_dir():
            counters[f"missing_source::{source_name}"] = 1
            continue
        image_count = sum(
            path.is_file() and path.suffix.casefold() in SUPPORTED_EXTENSIONS
            for path in source_root.rglob("*")
        )
        counters[f"skipped_non_tongue_media::{source_name}"] = image_count
    return counters


def plan_copies(
    samples: Sequence[MasterSample],
    permissions: dict[str, str],
) -> tuple[list[PlannedCopy], Counter[str]]:
    counters: Counter[str] = Counter()
    planned: list[PlannedCopy] = []
    grouped: dict[tuple[str, str], list[MasterSample]] = {}
    for sample in samples:
        if sample.permission_required and sample.source_key not in permissions:
            counters[f"blocked::{sample.source_key}"] += 1
            continue
        grouped.setdefault((sample.source_key, sample.source_category), []).append(sample)

    for (source_key, category), category_samples in sorted(grouped.items()):
        validate_output_category(category)
        for index, sample in enumerate(
            sorted(category_samples, key=lambda item: item.details.sha256),
            start=1,
        ):
            suffix = ".jpg" if sample.details.image_format == "JPEG" else ".png"
            source_slug = safe_slug(source_key)
            filename = f"{source_slug}_{safe_slug(category)}_{index:05d}_{sample.details.sha256[:12]}{suffix}"
            relative_path = Path(source_key) / category / "original" / filename
            planned.append(PlannedCopy(sample=sample, destination_relative_path=relative_path.as_posix()))
            counters[f"planned::{source_key}::{category}"] += 1
    return planned, counters


def validate_output_category(category: str) -> None:
    if category in {"low_risk", "moderate_risk", "high_risk"}:
        raise ValueError("Unvalidated source labels cannot be written as IronScan risk tiers")
    if safe_slug(category) != category:
        raise ValueError(f"Unsafe source category: {category}")


def apply_master_dataset(
    configuration: Configuration,
    planned_copies: Sequence[PlannedCopy],
    counters: Counter[str],
) -> None:
    staging_root = configuration.output_root.with_name(f".{configuration.output_root.name}.staging-{os.getpid()}")
    if staging_root.exists():
        raise ValueError(f"Staging directory already exists: {staging_root}")
    staging_root.mkdir(parents=True)
    try:
        manifest_rows: list[dict[str, str | int]] = []
        for planned in planned_copies:
            destination = staging_root / planned.destination_relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(planned.sample.source_path, destination)
            if sha256_file(destination) != planned.sample.details.sha256:
                raise ValueError("Master dataset copy checksum verification failed")
            permission_reference = configuration.permissions.get(
                planned.sample.source_key,
                "owner-reported TongueDX transformation approval dated 2026-07-16",
            )
            manifest_rows.append(
                {
                    "source_key": planned.sample.source_key,
                    "source_category": planned.sample.source_category,
                    "validation_status": planned.sample.validation_status,
                    "sha256": planned.sample.details.sha256,
                    "relative_path": planned.destination_relative_path,
                    "image_format": planned.sample.details.image_format,
                    "width": planned.sample.details.width,
                    "height": planned.sample.details.height,
                    "permission_reference": permission_reference,
                    **training_target_fields(planned.sample),
                }
            )
            counters[f"copied::{planned.sample.source_key}::{planned.sample.source_category}"] += 1
        write_manifest(staging_root / "master_manifest.csv", manifest_rows)
        write_report(staging_root / "master_report.json", planned_copies, counters)
        staging_root.replace(configuration.output_root)
    except BaseException:
        shutil.rmtree(staging_root, ignore_errors=True)
        raise


def write_manifest(path: Path, rows: Sequence[dict[str, str | int]]) -> None:
    fieldnames = [
        "source_key",
        "source_category",
        "validation_status",
        "sha256",
        "relative_path",
        "image_format",
        "width",
        "height",
        "permission_reference",
        "target_name",
        "target_value",
        "training_eligible",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def training_target_fields(sample: MasterSample) -> dict[str, str | int]:
    if sample.source_key != "TongueDx2" or sample.source_category == "annotation_conflict":
        return {"target_name": "", "target_value": "", "training_eligible": "false"}
    target_value = 1 if sample.source_category == "pallor_present" else 0
    return {
        "target_name": "TonguePale",
        "target_value": target_value,
        "training_eligible": "true",
    }


def write_report(path: Path, planned_copies: Sequence[PlannedCopy], counters: Counter[str]) -> None:
    report = {
        "schema_version": 1,
        "purpose": "source-separated private structural dataset; not deployable risk-model ground truth",
        "tonguedx_training_target": "binary visual TonguePale annotation",
        "planned_copy_count": len(planned_copies),
        "counts": dict(sorted(counters.items())),
        "limitations": [
            "TongueDX categories are observed appearance phenotypes, not anemia-risk tiers.",
            "Surface-coating strata remain TonguePale-negative confounders, not moderate-risk labels.",
            "Annotation-conflict images are excluded from training eligibility.",
            "Probability thresholds require validation calibration and are not defined by this ingestion step.",
            "The GitHub prototype uses augmented images and simulated/proxy labels.",
            "Custom sources remain unreviewed and unlabeled until provenance and ground truth are supplied.",
            "No source category is converted into low, moderate, or high IronScan risk.",
            "Deployable model training requires participant-grouped, laboratory-backed data.",
        ],
    }
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def print_summary(
    samples: Sequence[MasterSample],
    planned_copies: Sequence[PlannedCopy],
    counters: Counter[str],
    *,
    applied: bool,
) -> None:
    discovered = Counter(sample.source_key for sample in samples)
    print("IronScan master structural pipeline")
    print(f"Mode: {'apply' if applied else 'dry-run'}")
    for source_key, count in sorted(discovered.items()):
        blocked = counters[f"blocked::{source_key}"]
        print(f"{source_key}: discovered={count}, blocked_pending_permission={blocked}")
    for source_name in EXPLICIT_NON_TONGUE_SOURCE_NAMES:
        skipped = counters[f"skipped_non_tongue_media::{source_name}"]
        missing = counters[f"missing_source::{source_name}"]
        if missing:
            print(f"{source_name}: missing (skipped)")
        else:
            print(f"{source_name}: tongue_images=0, skipped_non_tongue_media={skipped}")
    action = "copied" if applied else "planned"
    for key, count in sorted(counters.items()):
        if key.startswith(f"{action}::") and count:
            _, source_key, category = key.split("::", maxsplit=2)
            print(f"{source_key}/{category}: {action}={count}")
    print(f"Copies {'created' if applied else 'planned'}: {len(planned_copies)}")
    print("No images were categorized as low, moderate, or high clinical risk.")


def run(configuration: Configuration) -> None:
    samples = collect_all_samples(configuration)
    planned_copies, counters = plan_copies(samples, configuration.permissions)
    counters.update(audit_explicit_non_tongue_sources(configuration.documents_root))
    if configuration.apply:
        apply_master_dataset(configuration, planned_copies, counters)
    print_summary(samples, planned_copies, counters, applied=configuration.apply)


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
