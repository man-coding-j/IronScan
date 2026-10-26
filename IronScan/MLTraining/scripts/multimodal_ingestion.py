#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from enum import StrEnum
from pathlib import Path, PurePosixPath
from typing import Any, Final, Sequence, cast
from xml.etree import ElementTree

import numpy as np
from numpy.typing import NDArray

from MLTraining.scripts.sort_and_preprocess import PhenotypeGroup, discover_csv_files, read_source_records

DEFAULT_DOCUMENTS_ROOT: Final = Path.home() / "Documents"
DEFAULT_OUTPUT_ROOT: Final = DEFAULT_DOCUMENTS_ROOT / "IronScanMultiModalDataset"
SUPPORTED_EXTENSIONS: Final = {".jpg", ".jpeg", ".png"}
SIMILARITY_CLUSTER_DISTANCE: Final = 0.08
SIMILARITY_FEATURE_VERSION: Final = "appearance-cluster-1.0.0"
EYES_DEFY_ANEMIA_SOURCE_KEY: Final = "eyes_defy_anemia"
CLINICAL_EYE_LABEL_KIND: Final = "laboratory_hemoglobin_anemia_screening_label"
EXCLUDED_PATH_TOKENS: Final = {
    "accuracy",
    "architecture",
    "assets",
    "build",
    "cache",
    "caches",
    "chart",
    "charts",
    "checkpoint",
    "checkpoints",
    "confusion",
    "diagram",
    "docs",
    "env",
    "evaluation",
    "figure",
    "figures",
    "git",
    "graph",
    "loss",
    "mode",
    "model",
    "models",
    "plot",
    "pycache",
    "readme",
    "report",
    "result",
    "results",
    "saved_outputs",
    "screenshot",
    "screenshots",
    "static",
    "templates",
    "uploads",
    "venv",
    "weight",
    "weights",
}
LABEL_COLUMNS: Final = (
    "output_path",
    "tissue",
    "target_label",
    "target_value",
    "source_key",
    "source_relative_path",
    "source_label",
    "label_kind",
    "participant_group",
    "participant_group_kind",
    "training_eligible",
    "permission_reference",
    "sha256",
    "perceptual_hash",
    "width",
    "height",
)


class Tissue(StrEnum):
    EYE = "Eye"
    NAIL = "Nail"
    TONGUE = "Tongue"


class TargetLabel(StrEnum):
    ANEMIC = "anemic"
    NON_ANEMIC = "non_anemic"

    @property
    def value_int(self) -> int:
        return 1 if self is TargetLabel.ANEMIC else 0


@dataclass(frozen=True)
class SourceSpecification:
    key: str
    root_candidates: tuple[Path, ...]
    allowed_tissues: tuple[Tissue, ...]


SOURCE_SPECIFICATIONS: Final = (
    SourceSpecification(
        key="eye_nail_tongue_github",
        root_candidates=(Path("anemia_detection_eye_nail_tongue"), Path("anemia_detection_eye_nail_tongue-main")),
        allowed_tissues=(Tissue.EYE, Tissue.NAIL, Tissue.TONGUE),
    ),
    SourceSpecification(
        key="tatiana_conjunctiva",
        root_candidates=(Path("Anemia_detection"),),
        allowed_tissues=(Tissue.EYE,),
    ),
    SourceSpecification(
        key="kirpal_conjunctiva",
        root_candidates=(Path("Detection-of-Anemia-Using-Conjuctiva-Images"),),
        allowed_tissues=(Tissue.EYE,),
    ),
    SourceSpecification(
        key="mbedmutha_multisite",
        root_candidates=(Path("anemia-detection"),),
        allowed_tissues=(Tissue.EYE, Tissue.NAIL),
    ),
    SourceSpecification(
        key="aiquest_conjunctiva",
        root_candidates=(Path("AIQuest_DATATHON"),),
        allowed_tissues=(Tissue.EYE,),
    ),
)


@dataclass(frozen=True)
class Configuration:
    documents_root: Path
    output_root: Path
    apply: bool
    allow_visual_proxy_labels: bool
    permissions: dict[str, str]
    allow_synthetic_participant_groups: bool = False


@dataclass(frozen=True)
class ImageInformation:
    sha256: str
    perceptual_hash: str
    width: int
    height: int
    similarity_features: tuple[float, ...] = ()
    requires_lossless_normalization: bool = False


@dataclass(frozen=True)
class Candidate:
    source_key: str
    source_root: Path
    source_path: Path
    tissue: Tissue
    target_label: TargetLabel
    source_label: str
    label_kind: str
    participant_group: str
    image: ImageInformation


@dataclass(frozen=True)
class PlannedSample:
    candidate: Candidate
    output_relative_path: PurePosixPath
    permission_reference: str


def parse_arguments() -> Configuration:
    parser = argparse.ArgumentParser(
        description=(
            "Create a dry-run-first, de-duplicated multimodal research dataset. Output folder names preserve "
            "source classes but do not convert visual proxy labels into clinical ground truth."
        )
    )
    parser.add_argument("--documents-root", type=Path, default=DEFAULT_DOCUMENTS_ROOT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--apply", action="store_true", help="Copy eligible images; default is a read-only dry run.")
    parser.add_argument(
        "--allow-visual-proxy-labels",
        action="store_true",
        help="Allow TongueDX TonguePale annotations to populate the requested proxy class folders.",
    )
    parser.add_argument(
        "--permission",
        action="append",
        default=[],
        metavar="SOURCE_KEY=REFERENCE",
        help="Record reviewed reuse permission or license for a source; may be repeated.",
    )
    parser.add_argument(
        "--allow-synthetic-participant-groups",
        action="store_true",
        help=(
            "Assign deterministic appearance-similarity groups to external eye/nail images for research-demo "
            "training. This reduces near-duplicate leakage but does not establish participant identity."
        ),
    )
    arguments = parser.parse_args()
    configuration = Configuration(
        documents_root=arguments.documents_root.expanduser().resolve(),
        output_root=arguments.output_root.expanduser().resolve(),
        apply=arguments.apply,
        allow_visual_proxy_labels=arguments.allow_visual_proxy_labels,
        permissions=parse_permissions(arguments.permission),
        allow_synthetic_participant_groups=arguments.allow_synthetic_participant_groups,
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
    if configuration.output_root == configuration.documents_root:
        raise ValueError("Output root cannot replace the Documents directory")
    if configuration.apply and configuration.output_root.exists():
        raise ValueError("Output root already exists; refusing to overwrite it")


def source_roots(documents_root: Path, specification: SourceSpecification) -> list[Path]:
    return [
        (documents_root / candidate).resolve()
        for candidate in specification.root_candidates
        if (documents_root / candidate).is_dir()
    ]


def split_tokens(value: str) -> set[str]:
    return {token for token in re.split(r"[^a-z0-9]+", value.casefold()) if token}


def should_exclude(relative_path: Path) -> bool:
    tokens = split_tokens(relative_path.as_posix())
    return bool(tokens & EXCLUDED_PATH_TOKENS)


def candidate_image_paths(source_root: Path) -> list[Path]:
    paths: list[Path] = []
    for current_root, directory_names, filenames in os.walk(source_root):
        current_path = Path(current_root)
        directory_names[:] = sorted(
            directory_name
            for directory_name in directory_names
            if not should_exclude((current_path / directory_name).relative_to(source_root))
        )
        for filename in sorted(filenames):
            source_path = current_path / filename
            if source_path.suffix.casefold() in SUPPORTED_EXTENSIONS:
                paths.append(source_path)
    return paths


def infer_tissue(relative_path: Path, allowed_tissues: Sequence[Tissue]) -> Tissue | None:
    tokens = split_tokens(relative_path.as_posix())
    matches: list[Tissue] = []
    if tokens & {"eye", "eyes", "eyelid", "eyelids", "conjunctiva", "conjuctiva"}:
        matches.append(Tissue.EYE)
    if tokens & {"nail", "nails", "nailbed", "nailbeds"}:
        matches.append(Tissue.NAIL)
    if tokens & {"tongue", "tongues"}:
        matches.append(Tissue.TONGUE)
    allowed_matches = [tissue for tissue in matches if tissue in allowed_tissues]
    if len(allowed_matches) == 1:
        return allowed_matches[0]
    if not allowed_matches and len(allowed_tissues) == 1:
        return allowed_tissues[0]
    return None


def infer_label(relative_path: Path) -> tuple[TargetLabel, str] | None:
    normalized = relative_path.as_posix().casefold().replace("-", "_").replace(" ", "_")
    tokens = split_tokens(normalized)
    non_anemic = "non_anemic" in normalized or bool(tokens & {"healthy", "normal", "nonanemic"})
    anemic = bool(tokens & {"anemia", "anemic", "pale", "pallor"}) and not non_anemic
    if non_anemic == anemic:
        return None
    return (TargetLabel.NON_ANEMIC, "source_normal_class") if non_anemic else (
        TargetLabel.ANEMIC,
        "source_anemia_class",
    )


def inspect_image(path: Path) -> ImageInformation:
    from PIL import Image, UnidentifiedImageError

    requires_lossless_normalization = False
    try:
        with Image.open(path) as image:
            image.load()
            image_format = (image.format or "").upper()
            width, height = image.size
            grayscale = image.convert("L").resize((9, 8), resample=Image.Resampling.LANCZOS)
            values = list(grayscale.getdata())
            similarity_features = extract_similarity_features(image)
    except (OSError, SyntaxError, UnidentifiedImageError) as error:
        if path.suffix.casefold() != ".png":
            raise ValueError("Image is corrupt or unsupported") from error
        import cv2

        decoded = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
        if decoded is None:
            raise ValueError("Image is corrupt or unsupported") from error
        decoded = normalized_cv_pixels(decoded)
        if decoded.ndim == 2:
            decoded = cv2.cvtColor(decoded, cv2.COLOR_GRAY2RGB)
        elif decoded.shape[2] == 4:
            decoded = cv2.cvtColor(decoded, cv2.COLOR_BGRA2RGBA)
        else:
            decoded = cv2.cvtColor(decoded, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(decoded)
        image_format = "PNG"
        width, height = image.size
        grayscale = image.convert("L").resize((9, 8), resample=Image.Resampling.LANCZOS)
        values = list(grayscale.getdata())
        similarity_features = extract_similarity_features(image)
        requires_lossless_normalization = True
    if image_format not in {"JPEG", "PNG"}:
        raise ValueError(f"Unsupported image format: {image_format or 'unknown'}")
    if width < 64 or height < 64 or max(width / height, height / width) > 5:
        raise ValueError("Image dimensions are not suitable for tissue-model training")
    difference_bits = [values[row * 9 + column] > values[row * 9 + column + 1] for row in range(8) for column in range(8)]
    perceptual_value = sum((1 << index) for index, enabled in enumerate(difference_bits) if enabled)
    return ImageInformation(
        sha256=sha256_file(path),
        perceptual_hash=f"{perceptual_value:016x}",
        width=width,
        height=height,
        similarity_features=similarity_features,
        requires_lossless_normalization=requires_lossless_normalization,
    )


def normalized_cv_pixels(decoded: NDArray[Any]) -> NDArray[np.uint8]:
    if decoded.dtype == np.uint8:
        return decoded
    if decoded.dtype == np.uint16:
        return ((decoded.astype(np.uint32) + 128) // 257).astype(np.uint8)
    clipped = np.clip(decoded, 0, 255)
    return cast(NDArray[np.uint8], clipped.astype(np.uint8))


def extract_similarity_features(image: object) -> tuple[float, ...]:
    from PIL import Image

    if not isinstance(image, Image.Image):
        raise TypeError("Expected a decoded PIL image")
    rgb = image.convert("RGB").resize((24, 24), resample=Image.Resampling.BILINEAR)
    pixels = np.asarray(rgb, dtype=np.float64) / 255.0
    grayscale = np.asarray(rgb.convert("L"), dtype=np.float64) / 255.0
    standardized = (grayscale - grayscale.mean()) / max(float(grayscale.std()), 0.05)
    structure = standardized.reshape(-1)
    structure /= max(float(np.linalg.norm(structure)), 1e-12)

    color_features: list[float] = []
    for channel in range(3):
        values = pixels[:, :, channel]
        color_features.extend((float(values.mean()), float(values.std())))
        histogram, _ = np.histogram(values, bins=8, range=(0.0, 1.0), density=False)
        color_features.extend((histogram / max(int(histogram.sum()), 1)).tolist())
    color = np.asarray(color_features, dtype=np.float64)
    color /= max(float(np.linalg.norm(color)), 1e-12)
    combined = np.concatenate((structure * 0.8, color * 0.2))
    combined /= max(float(np.linalg.norm(combined)), 1e-12)
    return tuple(float(value) for value in combined)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def collect_repository_candidates(
    documents_root: Path,
    specification: SourceSpecification,
    exclusions: Counter[str],
    allow_synthetic_participant_groups: bool = False,
) -> list[Candidate]:
    candidates: list[Candidate] = []
    for source_root in source_roots(documents_root, specification):
        for source_path in candidate_image_paths(source_root):
            relative_path = source_path.relative_to(source_root)
            if should_exclude(relative_path):
                exclusions["diagram_graph_or_non_dataset_path"] += 1
                continue
            tissue = infer_tissue(relative_path, specification.allowed_tissues)
            label = infer_label(relative_path)
            if tissue is None or label is None:
                exclusions["missing_explicit_tissue_or_class"] += 1
                continue
            try:
                image = inspect_image(source_path)
            except ValueError:
                exclusions["invalid_image"] += 1
                continue
            candidates.append(Candidate(
                source_key=specification.key,
                source_root=source_root,
                source_path=source_path,
                tissue=tissue,
                target_label=label[0],
                source_label=label[1],
                label_kind="source_repository_proxy_class",
                participant_group="",
                image=image,
            ))
    return candidates


def tonguedx_root(documents_root: Path) -> Path | None:
    for relative in (Path("IronScanPrivate/TongueDx2"), Path("TongueDx2")):
        candidate = (documents_root / relative).resolve()
        if candidate.is_dir():
            return candidate
    return None


def tonguedx_participant_groups(dataset_root: Path) -> dict[PurePosixPath, str]:
    groups: dict[PurePosixPath, str] = {}
    conflicts: set[PurePosixPath] = set()
    for csv_path in discover_csv_files(dataset_root):
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            if not {"id", "image_path"}.issubset(reader.fieldnames or []):
                raise ValueError(f"{csv_path.name} lacks participant grouping metadata")
            for row in reader:
                relative = PurePosixPath((row.get("image_path") or "").strip().replace("\\", "/"))
                participant = (row.get("id") or "").strip()
                if not participant:
                    continue
                previous = groups.get(relative)
                if previous is not None and previous != participant:
                    conflicts.add(relative)
                groups[relative] = participant
    return {path: group for path, group in groups.items() if path not in conflicts}


def collect_tonguedx_candidates(
    documents_root: Path,
    allow_visual_proxy_labels: bool,
    exclusions: Counter[str],
) -> list[Candidate]:
    dataset_root = tonguedx_root(documents_root)
    if dataset_root is None:
        return []
    if not allow_visual_proxy_labels:
        exclusions["tonguedx_visual_proxy_requires_explicit_opt_in"] += 1
        return []
    participant_groups = tonguedx_participant_groups(dataset_root)
    candidates: list[Candidate] = []
    for record in read_source_records(dataset_root, discover_csv_files(dataset_root)):
        if record.phenotype_group == PhenotypeGroup.ANNOTATION_CONFLICT:
            exclusions["tonguedx_annotation_conflict"] += 1
            continue
        label = TargetLabel.ANEMIC if record.phenotype_group == PhenotypeGroup.PALE_OBSERVED else TargetLabel.NON_ANEMIC
        try:
            image = inspect_image(record.source_path)
        except ValueError:
            exclusions["invalid_image"] += 1
            continue
        candidates.append(Candidate(
            source_key="tonguedx2",
            source_root=dataset_root,
            source_path=record.source_path,
            tissue=Tissue.TONGUE,
            target_label=label,
            source_label=f"TonguePale={record.indicators.tongue_pale}",
            label_kind="visual_pallor_proxy_not_anemia_ground_truth",
            participant_group=pseudonymous_group("tonguedx2", participant_groups.get(record.relative_path, "")),
            image=image,
        ))
    return candidates


def read_first_xlsx_sheet(path: Path) -> list[dict[str, str]]:
    namespace = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as archive:
        shared_strings: list[str] = []
        if "xl/sharedStrings.xml" in archive.namelist():
            shared_root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in shared_root.findall("x:si", namespace):
                shared_strings.append("".join(node.text or "" for node in item.findall(".//x:t", namespace)))
        worksheet = ElementTree.fromstring(archive.read("xl/worksheets/sheet1.xml"))

    values_by_row: list[dict[int, str]] = []
    for row in worksheet.findall(".//x:sheetData/x:row", namespace):
        values: dict[int, str] = {}
        for cell in row.findall("x:c", namespace):
            reference = cell.attrib.get("r", "")
            letters = "".join(character for character in reference if character.isalpha())
            column_index = 0
            for character in letters:
                column_index = column_index * 26 + ord(character.upper()) - ord("A") + 1
            value_node = cell.find("x:v", namespace)
            inline_node = cell.find("x:is/x:t", namespace)
            value = inline_node.text if inline_node is not None else (value_node.text if value_node is not None else "")
            if cell.attrib.get("t") == "s" and value:
                value = shared_strings[int(value)]
            values[column_index - 1] = value or ""
        values_by_row.append(values)
    if not values_by_row:
        return []
    headers = {index: value.strip() for index, value in values_by_row[0].items() if value.strip()}
    return [
        {header: values.get(index, "").strip() for index, header in headers.items()}
        for values in values_by_row[1:]
    ]


def parse_decimal(value: str) -> float | None:
    normalized = value.strip().replace(",", ".")
    if not normalized or normalized == "_":
        return None
    try:
        return float(normalized)
    except ValueError:
        return None


def hemoglobin_screening_label(hemoglobin: float, gender: str, age: float) -> TargetLabel | None:
    if age < 18:
        return None
    normalized_gender = gender.strip().casefold()
    if normalized_gender == "m":
        return TargetLabel.ANEMIC if hemoglobin < 13.0 else TargetLabel.NON_ANEMIC
    if normalized_gender == "f":
        return TargetLabel.ANEMIC if hemoglobin < 12.0 else TargetLabel.NON_ANEMIC
    return None


def palpebral_image(participant_root: Path) -> Path | None:
    candidates = [
        path
        for path in participant_root.iterdir()
        if path.is_file()
        and path.suffix.casefold() == ".png"
        and (path.name.casefold().endswith("_palpebral.png") or path.name.casefold().endswith("_papebral.png"))
        and "forniceal_palpebral" not in path.name.casefold()
    ]
    return min(candidates) if candidates else None


def collect_eyes_defy_anemia_candidates(
    documents_root: Path,
    exclusions: Counter[str],
) -> list[Candidate]:
    dataset_root = documents_root / "Eyes-Defy-Anemia"
    if not dataset_root.is_dir():
        return []
    candidates: list[Candidate] = []
    for country in ("India", "Italy"):
        country_root = dataset_root / country
        workbook_path = country_root / f"{country}.xlsx"
        if not workbook_path.is_file():
            exclusions["eyes_defy_anemia_missing_country_workbook"] += 1
            continue
        for row in read_first_xlsx_sheet(workbook_path):
            if not any(row.values()):
                continue
            participant_number = row.get("Number", "").strip()
            hemoglobin = parse_decimal(row.get("Hgb", ""))
            age = parse_decimal(row.get("Age", ""))
            if not participant_number or hemoglobin is None or age is None:
                exclusions["eyes_defy_anemia_missing_required_lab_metadata"] += 1
                continue
            label = hemoglobin_screening_label(hemoglobin, row.get("Gender", ""), age)
            if label is None:
                exclusions["eyes_defy_anemia_unsupported_demographic_threshold"] += 1
                continue
            participant_root = country_root / participant_number.removesuffix(".0")
            image_path = palpebral_image(participant_root) if participant_root.is_dir() else None
            if image_path is None:
                exclusions["eyes_defy_anemia_missing_palpebral_image"] += 1
                continue
            try:
                image = inspect_image(image_path)
            except ValueError:
                exclusions["invalid_image"] += 1
                continue
            if image.requires_lossless_normalization:
                exclusions["eyes_defy_anemia_lossless_png_normalization_required"] += 1
            candidates.append(Candidate(
                source_key=EYES_DEFY_ANEMIA_SOURCE_KEY,
                source_root=dataset_root,
                source_path=image_path,
                tissue=Tissue.EYE,
                target_label=label,
                source_label="adult_sex_specific_laboratory_hemoglobin_threshold",
                label_kind=CLINICAL_EYE_LABEL_KIND,
                participant_group=pseudonymous_group(
                    EYES_DEFY_ANEMIA_SOURCE_KEY,
                    f"{country.casefold()}-{participant_number}",
                ),
                image=image,
            ))
    return candidates


def pseudonymous_group(source_key: str, participant_group: str) -> str:
    if not participant_group:
        return ""
    digest = hashlib.sha256(f"{source_key}\0{participant_group}".encode()).hexdigest()
    return f"{safe_slug(source_key)}-{digest}"


def synthetic_participant_group(source_key: str, tissue: Tissue, content_sha256: str) -> str:
    return synthetic_similarity_group(source_key, tissue, [content_sha256])


def synthetic_similarity_group(source_key: str, tissue: Tissue, content_hashes: Sequence[str]) -> str:
    payload = "\0".join(sorted(content_hashes))
    digest = hashlib.sha256(
        f"synthetic-similarity\0{SIMILARITY_FEATURE_VERSION}\0{source_key}\0{tissue.value}\0{payload}".encode()
    ).hexdigest()
    return f"synthetic-similarity-{digest}"


def participant_group_kind(candidate: Candidate) -> str:
    if candidate.participant_group.startswith("synthetic-similarity-"):
        return "synthetic_similarity_cluster_demo_only"
    if candidate.participant_group:
        return "source_provided_pseudonymized"
    return "missing"


def deduplicate(candidates: Sequence[Candidate], exclusions: Counter[str]) -> list[Candidate]:
    exact_groups: dict[str, list[Candidate]] = defaultdict(list)
    for candidate in candidates:
        exact_groups[candidate.image.sha256].append(candidate)
    exact_unique: list[Candidate] = []
    for group in exact_groups.values():
        metadata = {(candidate.tissue, candidate.target_label) for candidate in group}
        if len(metadata) != 1:
            exclusions["duplicate_content_conflicting_label_or_tissue"] += len(group)
            continue
        exact_unique.append(min(group, key=candidate_priority))
        exclusions["exact_duplicate"] += len(group) - 1

    perceptual_groups: dict[tuple[Tissue, str], list[Candidate]] = defaultdict(list)
    for candidate in exact_unique:
        perceptual_groups[(candidate.tissue, candidate.image.perceptual_hash)].append(candidate)
    unique: list[Candidate] = []
    for group in perceptual_groups.values():
        if len({candidate.target_label for candidate in group}) != 1:
            exclusions["perceptual_duplicate_conflicting_label"] += len(group)
            continue
        unique.append(min(group, key=candidate_priority))
        exclusions["perceptual_duplicate"] += len(group) - 1
    return sorted(unique, key=lambda item: (item.tissue.value, item.target_label.value, item.image.sha256))


def assign_similarity_groups(candidates: Sequence[Candidate], exclusions: Counter[str]) -> list[Candidate]:
    from sklearn.cluster import AgglomerativeClustering

    grouped: dict[Tissue, list[Candidate]] = defaultdict(list)
    unchanged: list[Candidate] = []
    for candidate in candidates:
        if candidate.tissue in {Tissue.EYE, Tissue.NAIL}:
            grouped[candidate.tissue].append(candidate)
        else:
            unchanged.append(candidate)

    assigned = list(unchanged)
    for tissue, values in sorted(grouped.items(), key=lambda item: item[0].value):
        ordered = sorted(values, key=lambda candidate: candidate.image.sha256)
        if any(not candidate.image.similarity_features for candidate in ordered):
            raise ValueError("Similarity clustering requires decoded appearance features")
        if len(ordered) == 1:
            cluster_labels: NDArray[np.int64] = np.zeros(1, dtype=np.int64)
        else:
            features = np.asarray([candidate.image.similarity_features for candidate in ordered], dtype=np.float64)
            cluster_labels = AgglomerativeClustering(
                n_clusters=None,
                metric="cosine",
                linkage="complete",
                distance_threshold=SIMILARITY_CLUSTER_DISTANCE,
            ).fit_predict(features)
        clusters: dict[int, list[Candidate]] = defaultdict(list)
        for candidate, cluster_label in zip(ordered, cluster_labels, strict=True):
            clusters[int(cluster_label)].append(candidate)
        for cluster in clusters.values():
            anchor_groups = sorted({item.participant_group for item in cluster if item.participant_group})
            if len(anchor_groups) == 1:
                group = anchor_groups[0]
            else:
                group = synthetic_similarity_group(
                    "cross-source-anchors" if anchor_groups else "cross-source",
                    tissue,
                    [*anchor_groups, *(item.image.sha256 for item in cluster)],
                )
            if len(cluster) > 1:
                exclusions["similarity_clustered_images"] += len(cluster)
            if len({item.target_label for item in cluster}) > 1:
                exclusions["similarity_cluster_conflicting_proxy_labels"] += len(cluster)
            assigned.extend(replace(
                item,
                participant_group=group,
                label_kind=(
                    item.label_kind
                    if item.label_kind == CLINICAL_EYE_LABEL_KIND
                    else "source_repository_proxy_class_with_similarity_grouping"
                ),
            ) for item in cluster)
    return sorted(assigned, key=lambda item: (item.tissue.value, item.target_label.value, item.image.sha256))


def candidate_priority(candidate: Candidate) -> tuple[bool, str, str]:
    return (not bool(candidate.participant_group), candidate.source_key, candidate.source_path.as_posix())


def manifest_source_locator(candidate: Candidate) -> str:
    relative_path = candidate.source_path.relative_to(candidate.source_root).as_posix()
    if candidate.source_key not in {"tonguedx2", EYES_DEFY_ANEMIA_SOURCE_KEY}:
        return relative_path
    digest = hashlib.sha256(relative_path.encode()).hexdigest()
    return f"private-path-{digest}"


def safe_slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.casefold()).strip("_") or "source"


def plan_samples(candidates: Sequence[Candidate], configuration: Configuration) -> list[PlannedSample]:
    plans: list[PlannedSample] = []
    missing_permissions = sorted({candidate.source_key for candidate in candidates} - configuration.permissions.keys())
    if configuration.apply and missing_permissions:
        raise ValueError(f"--apply requires reviewed --permission entries for: {missing_permissions}")
    for candidate in candidates:
        extension = ".png" if candidate.source_path.suffix.casefold() == ".png" else ".jpg"
        filename = f"{safe_slug(candidate.source_key)}_{candidate.image.sha256[:20]}{extension}"
        relative = PurePosixPath(candidate.tissue.value, candidate.target_label.value, filename)
        plans.append(PlannedSample(
            candidate=candidate,
            output_relative_path=relative,
            permission_reference=configuration.permissions.get(candidate.source_key, "unreviewed"),
        ))
    return plans


def write_dataset(plans: Sequence[PlannedSample], configuration: Configuration) -> None:
    configuration.output_root.mkdir(parents=False)
    for tissue in Tissue:
        for label in TargetLabel:
            (configuration.output_root / tissue.value / label.value).mkdir(parents=True)
    with (configuration.output_root / "dataset_manifest.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=LABEL_COLUMNS)
        writer.writeheader()
        for plan in plans:
            candidate = plan.candidate
            destination = configuration.output_root.joinpath(*plan.output_relative_path.parts)
            if candidate.image.requires_lossless_normalization:
                import cv2

                decoded = cv2.imread(str(candidate.source_path), cv2.IMREAD_UNCHANGED)
                if decoded is None or not cv2.imwrite(str(destination), normalized_cv_pixels(decoded)):
                    raise ValueError(f"Unable to normalize image: {candidate.source_path}")
            else:
                shutil.copyfile(candidate.source_path, destination)
            destination_sha256 = sha256_file(destination)
            training_eligible = bool(candidate.participant_group) and plan.permission_reference != "unreviewed"
            writer.writerow({
                "output_path": plan.output_relative_path.as_posix(),
                "tissue": candidate.tissue.value,
                "target_label": candidate.target_label.value,
                "target_value": candidate.target_label.value_int,
                "source_key": candidate.source_key,
                "source_relative_path": manifest_source_locator(candidate),
                "source_label": candidate.source_label,
                "label_kind": candidate.label_kind,
                "participant_group": candidate.participant_group,
                "participant_group_kind": participant_group_kind(candidate),
                "training_eligible": str(training_eligible).lower(),
                "permission_reference": plan.permission_reference,
                "sha256": destination_sha256,
                "perceptual_hash": candidate.image.perceptual_hash,
                "width": candidate.image.width,
                "height": candidate.image.height,
            })


def run(configuration: Configuration) -> dict[str, object]:
    exclusions: Counter[str] = Counter()
    candidates: list[Candidate] = []
    discovered_sources: dict[str, int] = {}
    for specification in SOURCE_SPECIFICATIONS:
        source_candidates = collect_repository_candidates(
            configuration.documents_root,
            specification,
            exclusions,
            configuration.allow_synthetic_participant_groups,
        )
        discovered_sources[specification.key] = len(source_candidates)
        candidates.extend(source_candidates)
    tonguedx_candidates = collect_tonguedx_candidates(
        configuration.documents_root,
        configuration.allow_visual_proxy_labels,
        exclusions,
    )
    discovered_sources["tonguedx2"] = len(tonguedx_candidates)
    candidates.extend(tonguedx_candidates)
    clinical_eye_candidates = collect_eyes_defy_anemia_candidates(configuration.documents_root, exclusions)
    discovered_sources[EYES_DEFY_ANEMIA_SOURCE_KEY] = len(clinical_eye_candidates)
    candidates.extend(clinical_eye_candidates)
    unique = deduplicate(candidates, exclusions)
    if configuration.allow_synthetic_participant_groups:
        unique = assign_similarity_groups(unique, exclusions)
    plans = plan_samples(unique, configuration)
    if configuration.apply:
        write_dataset(plans, configuration)
    distribution = Counter(f"{plan.candidate.tissue.value}/{plan.candidate.target_label.value}" for plan in plans)
    summary: dict[str, object] = {
        "mode": "apply" if configuration.apply else "dry-run",
        "outputRoot": str(configuration.output_root),
        "sourceCandidateCounts": dict(sorted(discovered_sources.items())),
        "plannedDistribution": dict(sorted(distribution.items())),
        "plannedImages": len(plans),
        "exclusions": dict(sorted((key, count) for key, count in exclusions.items() if count)),
        "limitations": [
            "Folder classes and TonguePale annotations remain proxy labels.",
            "Eyes-Defy-Anemia labels use laboratory hemoglobin with adult sex-specific anemia-screening thresholds; "
            "hemoglobin-only labels do not establish iron-deficiency anemia.",
            "Images without reviewed participant groups remain ineligible for participant-grouped model training.",
            "Source participant groups are authoritative; appearance similarity links ungrouped cross-source variants "
            "to those anchors when possible and otherwise cannot establish identity.",
            f"Similarity grouping uses {SIMILARITY_FEATURE_VERSION} with distance {SIMILARITY_CLUSTER_DISTANCE}.",
            "No source image is modified or deleted; apply mode copies files and writes provenance metadata.",
        ],
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
