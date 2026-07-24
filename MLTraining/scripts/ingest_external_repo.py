#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
from collections import Counter
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Final, Sequence

DEFAULT_SOURCE_ROOT: Final = Path.home() / "Documents" / "anemia_detection_eye_nail_tongue-main"
DEFAULT_DESTINATION_ROOT: Final = (
    Path.home() / "Documents" / "IronScanPrivate" / "TongueDx2" / "sorted_dataset"
)
SUPPORTED_EXTENSIONS: Final = {".jpg", ".jpeg", ".png"}
SUPPORTED_FORMATS: Final = {"JPEG", "PNG"}
REPOSITORY_IDENTIFIER: Final = "anemia_detection_eye_nail_tongue"


class ExternalLabel(StrEnum):
    CLAIMED_ANEMIA = "claimed_anemia"
    CLAIMED_NORMAL = "claimed_normal"


@dataclass(frozen=True)
class Configuration:
    source_root: Path
    destination_root: Path
    apply: bool
    acknowledge_unvalidated_labels: bool
    license_reference: str | None


@dataclass(frozen=True)
class CandidateImage:
    source_path: Path
    external_label: ExternalLabel


@dataclass(frozen=True)
class ValidatedImage:
    source_path: Path
    external_label: ExternalLabel
    sha256: str
    image_format: str
    width: int
    height: int


@dataclass(frozen=True)
class PlannedImage:
    source: ValidatedImage
    destination_relative_path: str


def parse_arguments() -> Configuration:
    parser = argparse.ArgumentParser(
        description=(
            "Validate and optionally copy tongue-only engineering fixtures from the external prototype repository. "
            "External proxy labels are never converted into IronScan risk labels."
        )
    )
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--destination-root", type=Path, default=DEFAULT_DESTINATION_ROOT)
    parser.add_argument("--apply", action="store_true", help="Write validated copies; the default is a dry run.")
    parser.add_argument(
        "--acknowledge-unvalidated-labels",
        action="store_true",
        help="Confirm that the source labels are augmented proxy labels suitable only for engineering fixtures.",
    )
    parser.add_argument(
        "--license-reference",
        help="Required with --apply; provide the reviewed license or permission record reference.",
    )
    arguments = parser.parse_args()
    configuration = Configuration(
        source_root=arguments.source_root.expanduser().resolve(),
        destination_root=arguments.destination_root.expanduser().resolve(),
        apply=arguments.apply,
        acknowledge_unvalidated_labels=arguments.acknowledge_unvalidated_labels,
        license_reference=arguments.license_reference,
    )
    validate_configuration(configuration)
    return configuration


def validate_configuration(configuration: Configuration) -> None:
    if not configuration.source_root.is_dir():
        raise ValueError(f"External repository does not exist: {configuration.source_root}")
    if not configuration.destination_root.is_dir():
        raise ValueError(f"IronScan private sorted dataset does not exist: {configuration.destination_root}")
    if configuration.apply and not configuration.acknowledge_unvalidated_labels:
        raise ValueError("--apply requires --acknowledge-unvalidated-labels")
    if configuration.apply and not (configuration.license_reference or "").strip():
        raise ValueError("--apply requires --license-reference after license or permission review")


def discover_tongue_images(source_root: Path) -> list[CandidateImage]:
    tongue_root = (source_root / "dataset" / "tongue").resolve()
    if not tongue_root.is_dir():
        raise ValueError("External repository must contain dataset/tongue")

    class_directories = {
        ExternalLabel.CLAIMED_ANEMIA: tongue_root / "anemia",
        ExternalLabel.CLAIMED_NORMAL: tongue_root / "normal",
    }
    candidates: list[CandidateImage] = []
    for external_label, class_directory in class_directories.items():
        if not class_directory.is_dir():
            raise ValueError(f"External tongue class directory is missing: {class_directory.name}")
        for path in sorted(class_directory.rglob("*")):
            if not path.is_file() or path.name.startswith("."):
                continue
            if path.suffix.casefold() not in SUPPORTED_EXTENSIONS:
                continue
            resolved_path = path.resolve()
            if not resolved_path.is_relative_to(class_directory.resolve()):
                raise ValueError("External image path escapes its tongue class directory")
            candidates.append(CandidateImage(source_path=resolved_path, external_label=external_label))

    if not candidates:
        raise ValueError("No supported tongue images were found")
    return candidates


def validate_image(candidate: CandidateImage) -> ValidatedImage:
    from PIL import Image, UnidentifiedImageError

    try:
        with Image.open(candidate.source_path) as image:
            image.verify()
        with Image.open(candidate.source_path) as image:
            image_format = (image.format or "").upper()
            width, height = image.size
            image.load()
    except (OSError, SyntaxError, UnidentifiedImageError) as error:
        raise ValueError("External tongue image is corrupt or unsupported") from error

    if image_format not in SUPPORTED_FORMATS:
        raise ValueError(f"External tongue image format is not supported: {image_format or 'unknown'}")
    if width < 16 or height < 16:
        raise ValueError("External tongue image dimensions are too small")
    return ValidatedImage(
        source_path=candidate.source_path,
        external_label=candidate.external_label,
        sha256=sha256_file(candidate.source_path),
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


def load_master_hashes(destination_root: Path) -> set[str]:
    index_path = destination_root / "dataset_index.csv"
    if not index_path.is_file():
        raise ValueError("IronScan private dataset_index.csv is missing")
    with index_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if "sample_sha256" not in (reader.fieldnames or []):
            raise ValueError("IronScan dataset index does not contain sample_sha256")
        hashes = {(row.get("sample_sha256") or "").strip() for row in reader}

    external_manifest = destination_root / "external_engineering_fixture" / "ingestion_manifest.csv"
    if external_manifest.is_file():
        with external_manifest.open(newline="", encoding="utf-8") as handle:
            hashes.update((row.get("sha256") or "").strip() for row in csv.DictReader(handle))
    hashes.discard("")
    return hashes


def plan_ingestion(
    validated_images: Sequence[ValidatedImage],
    known_hashes: set[str],
) -> tuple[list[PlannedImage], Counter[str]]:
    counters: Counter[str] = Counter()
    incoming_labels_by_hash: dict[str, ExternalLabel] = {}
    accepted_by_label: dict[ExternalLabel, list[ValidatedImage]] = {
        label: [] for label in ExternalLabel
    }

    for image in validated_images:
        previous_label = incoming_labels_by_hash.get(image.sha256)
        if previous_label is not None:
            if previous_label != image.external_label:
                counters["cross_class_content_conflict"] += 1
            else:
                counters["duplicate_incoming_content"] += 1
            continue
        incoming_labels_by_hash[image.sha256] = image.external_label
        if image.sha256 in known_hashes:
            counters["already_present"] += 1
            continue
        accepted_by_label[image.external_label].append(image)

    planned: list[PlannedImage] = []
    for external_label in ExternalLabel:
        for index, image in enumerate(sorted(accepted_by_label[external_label], key=lambda item: item.sha256), start=1):
            suffix = ".jpg" if image.image_format == "JPEG" else ".png"
            filename = f"ext_repo_tongue_{external_label.value}_{index:04d}_{image.sha256[:12]}{suffix}"
            relative_path = Path("external_engineering_fixture") / external_label.value / "original" / filename
            planned.append(
                PlannedImage(
                    source=image,
                    destination_relative_path=relative_path.as_posix(),
                )
            )
            counters[f"planned_{external_label.value}"] += 1
    return planned, counters


def apply_ingestion(
    configuration: Configuration,
    planned_images: Sequence[PlannedImage],
    counters: Counter[str],
) -> None:
    external_root = configuration.destination_root / "external_engineering_fixture"
    external_root.mkdir(parents=True, exist_ok=True)
    manifest_path = external_root / "ingestion_manifest.csv"
    existing_rows = read_existing_manifest(manifest_path)
    new_rows: list[dict[str, str | int]] = []

    for planned in planned_images:
        destination = configuration.destination_root / planned.destination_relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if sha256_file(destination) != planned.source.sha256:
                raise ValueError("Destination filename collision contains different image content")
            counters["already_present"] += 1
            continue
        temporary = destination.with_suffix(destination.suffix + ".partial")
        shutil.copyfile(planned.source.source_path, temporary)
        if sha256_file(temporary) != planned.source.sha256:
            temporary.unlink(missing_ok=True)
            raise ValueError("Copied image checksum verification failed")
        temporary.replace(destination)
        counters[f"copied_{planned.source.external_label.value}"] += 1
        new_rows.append(
            {
                "repository_identifier": REPOSITORY_IDENTIFIER,
                "external_label": planned.source.external_label.value,
                "validation_status": "engineering_fixture_unvalidated_proxy_label",
                "sha256": planned.source.sha256,
                "relative_path": planned.destination_relative_path,
                "image_format": planned.source.image_format,
                "width": planned.source.width,
                "height": planned.source.height,
                "license_reference": configuration.license_reference or "",
            }
        )

    write_manifest(manifest_path, [*existing_rows, *new_rows])
    write_report(external_root / "ingestion_report.json", configuration, planned_images, counters)


def read_existing_manifest(path: Path) -> list[dict[str, str | int]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def write_manifest(path: Path, rows: Sequence[dict[str, str | int]]) -> None:
    fieldnames = [
        "repository_identifier",
        "external_label",
        "validation_status",
        "sha256",
        "relative_path",
        "image_format",
        "width",
        "height",
        "license_reference",
    ]
    temporary = path.with_suffix(".csv.partial")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def write_report(
    path: Path,
    configuration: Configuration,
    planned_images: Sequence[PlannedImage],
    counters: Counter[str],
) -> None:
    report = {
        "schema_version": 1,
        "repository_identifier": REPOSITORY_IDENTIFIER,
        "validation_status": "engineering_fixture_unvalidated_proxy_label",
        "source_disclosure": "augmented prototype images with proxy/simulated labels",
        "license_reference": configuration.license_reference,
        "planned_image_count": len(planned_images),
        "counts": dict(sorted(counters.items())),
        "limitations": [
            "The source repository states that labels are proxy/simulated and are not clinically validated.",
            "External class names are preserved as claimed labels and are not IronScan risk decisions.",
            "These images cannot train or validate the deployable IronScan anemia-risk model.",
            "Eye and nail directories are excluded from ingestion.",
        ],
    }
    temporary = path.with_suffix(".json.partial")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def print_summary(planned_images: Sequence[PlannedImage], counters: Counter[str], *, applied: bool) -> None:
    action = "copied" if applied else "planned"
    print("External tongue engineering-fixture ingestion summary")
    print(f"Mode: {'apply' if applied else 'dry-run'}")
    print(f"Validated candidates: {sum(1 for _ in planned_images) + counters['already_present']}")
    print(f"Claimed anemia images {action}: {counters[f'{action}_claimed_anemia']}")
    print(f"Claimed normal images {action}: {counters[f'{action}_claimed_normal']}")
    print(f"Already present: {counters['already_present']}")
    print(f"Incoming duplicates: {counters['duplicate_incoming_content']}")
    print(f"Cross-class conflicts rejected: {counters['cross_class_content_conflict']}")
    print("No images were assigned to IronScan low, moderate, or high risk folders.")


def run(configuration: Configuration) -> None:
    candidates = discover_tongue_images(configuration.source_root)
    validated_images = [validate_image(candidate) for candidate in candidates]
    planned_images, counters = plan_ingestion(
        validated_images,
        load_master_hashes(configuration.destination_root),
    )
    if counters["cross_class_content_conflict"]:
        raise ValueError("Identical external image content appears in both source classes")
    if configuration.apply:
        apply_ingestion(configuration, planned_images, counters)
    print_summary(planned_images, counters, applied=configuration.apply)


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
