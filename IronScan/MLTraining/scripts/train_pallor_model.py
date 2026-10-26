#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import random
import shutil
import subprocess
import tempfile
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable, Final, Sequence, cast

import numpy as np
from numpy.typing import NDArray

from MLTraining.scripts.train_and_convert import (
    calibrated_probabilities,
    compact_json,
    current_git_commit,
    fit_probability_calibration,
    package_sha256,
    repository_is_dirty,
)

IMAGE_SIZE: Final = 224
MODEL_IDENTIFIER: Final = "org.ironscan.engineering.mucosal-pallor"
MODEL_FILENAME: Final = "IronScanPallorClassifier.mlpackage"
MANIFEST_FILENAME: Final = "pallor_manifest.json"
INPUT_NAME: Final = "image"
RAW_OUTPUT_NAME: Final = "raw_pallor_logit"
PROBABILITY_OUTPUT_NAME: Final = "calibrated_pallor_probability"
PREPROCESSING_VERSION: Final = "1.0.0"
DEFAULT_SEED: Final = 20260720
FOLD_FILES: Final = {
    "train": "train_fold1.csv",
    "validation": "val_fold1.csv",
    "test": "test.csv",
}


@dataclass(frozen=True)
class Configuration:
    master_root: Path
    tonguedx_root: Path
    output_directory: Path
    coreml_destination: Path
    manifest_destination: Path
    semantic_version: str
    dataset_version: str
    training_commit: str
    epochs: int
    patience: int
    batch_size: int
    learning_rate: float
    weight_decay: float
    seed: int
    device: str
    pretrained: bool
    allow_dirty: bool
    replace_existing: bool
    parity_sample_count: int


@dataclass(frozen=True)
class PallorSample:
    image_path: Path
    content_sha256: str
    participant_group: str
    label: int


@dataclass(frozen=True)
class FoldObservation:
    split: str
    participant_group: str
    label: int


@dataclass(frozen=True)
class EvaluationMetrics:
    roc_auc: float
    precision: float
    recall: float
    f1_score: float
    balanced_accuracy: float
    brier_score: float
    confusion_matrix: list[list[int]]


def parse_arguments() -> Configuration:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description=(
            "Train and export an engineering-fixture model for the visual TonguePale annotation. "
            "The output is not a hemoglobin, ferritin, anemia, or iron-status measurement."
        )
    )
    parser.add_argument(
        "--master-root",
        type=Path,
        default=Path.home() / "Documents" / "IronScanMasterDataset",
    )
    parser.add_argument(
        "--tonguedx-root",
        type=Path,
        default=Path.home() / "Documents" / "IronScanPrivate" / "TongueDx2",
    )
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=Path.home() / "Documents" / "IronScanPrivate" / "TrainingArtifacts" / "pallor-v0.1.0",
    )
    parser.add_argument(
        "--coreml-destination",
        type=Path,
        default=repository_root / "Models" / "CoreML" / MODEL_FILENAME,
    )
    parser.add_argument(
        "--manifest-destination",
        type=Path,
        default=repository_root / "Models" / "Manifests" / MANIFEST_FILENAME,
    )
    parser.add_argument("--semantic-version", default="0.1.1-engineering.1")
    parser.add_argument("--dataset-version", default="tonguedx2-tonguepale-fold1-v1")
    parser.add_argument("--epochs", type=int, default=18)
    parser.add_argument("--patience", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--device", choices=("auto", "cpu", "mps", "cuda"), default="auto")
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--replace-existing", action="store_true")
    parser.add_argument("--parity-sample-count", type=int, default=20)
    arguments = parser.parse_args()

    configuration = Configuration(
        master_root=arguments.master_root.expanduser().resolve(),
        tonguedx_root=arguments.tonguedx_root.expanduser().resolve(),
        output_directory=arguments.output_directory.expanduser().resolve(),
        coreml_destination=arguments.coreml_destination.expanduser().resolve(),
        manifest_destination=arguments.manifest_destination.expanduser().resolve(),
        semantic_version=arguments.semantic_version,
        dataset_version=arguments.dataset_version,
        training_commit=current_git_commit(),
        epochs=arguments.epochs,
        patience=arguments.patience,
        batch_size=arguments.batch_size,
        learning_rate=arguments.learning_rate,
        weight_decay=arguments.weight_decay,
        seed=arguments.seed,
        device=arguments.device,
        pretrained=not arguments.no_pretrained,
        allow_dirty=arguments.allow_dirty,
        replace_existing=arguments.replace_existing,
        parity_sample_count=arguments.parity_sample_count,
    )
    validate_configuration(configuration)
    return configuration


def validate_configuration(configuration: Configuration) -> None:
    if not (configuration.master_root / "master_manifest.csv").is_file():
        raise ValueError("Master dataset manifest is missing")
    if not (configuration.tonguedx_root / "release" / "list").is_dir():
        raise ValueError("TongueDX fold metadata directory is missing")
    if configuration.epochs < 1 or configuration.patience < 1 or configuration.batch_size < 1:
        raise ValueError("Epochs, patience, and batch size must be positive")
    if configuration.learning_rate <= 0 or configuration.weight_decay < 0:
        raise ValueError("Learning rate must be positive and weight decay cannot be negative")
    if configuration.parity_sample_count < 1:
        raise ValueError("Parity sample count must be positive")
    if not configuration.allow_dirty and repository_is_dirty():
        raise ValueError("Training requires a clean Git worktree or --allow-dirty")
    if configuration.coreml_destination.exists() and not configuration.replace_existing:
        raise ValueError("Core ML destination exists; pass --replace-existing to replace it")
    if configuration.manifest_destination.exists() and not configuration.replace_existing:
        raise ValueError("Pallor manifest destination exists; pass --replace-existing to replace it")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_master_manifest(master_root: Path) -> dict[str, tuple[Path, int]]:
    manifest_path = master_root / "master_manifest.csv"
    required = {"sha256", "relative_path", "target_name", "target_value", "training_eligible"}
    samples: dict[str, tuple[Path, int]] = {}
    with manifest_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Master manifest is missing columns: {sorted(missing)}")
        for row_number, row in enumerate(reader, start=2):
            if row.get("training_eligible") != "true":
                continue
            if row.get("target_name") != "TonguePale":
                raise ValueError(f"Unexpected training target at master manifest row {row_number}")
            digest = (row.get("sha256") or "").strip()
            relative_path = Path((row.get("relative_path") or "").strip())
            if len(digest) != 64 or relative_path.is_absolute() or ".." in relative_path.parts:
                raise ValueError(f"Unsafe master manifest row {row_number}")
            image_path = (master_root / relative_path).resolve()
            if not image_path.is_relative_to(master_root) or not image_path.is_file():
                raise ValueError(f"Master image is missing at row {row_number}")
            label = int((row.get("target_value") or "").strip())
            if label not in (0, 1):
                raise ValueError(f"TonguePale target must be binary at row {row_number}")
            if digest in samples:
                raise ValueError("Duplicate content hash in master manifest")
            samples[digest] = (image_path, label)
    return samples


def read_fold_observations(
    tonguedx_root: Path,
    eligible_hashes: set[str],
) -> dict[str, set[FoldObservation]]:
    observations: dict[str, set[FoldObservation]] = defaultdict(set)
    source_root = (tonguedx_root / "release" / "origin").resolve()
    for split, filename in FOLD_FILES.items():
        csv_path = tonguedx_root / "release" / "list" / filename
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            required = {"id", "image_path", "TonguePale"}
            missing = required - set(reader.fieldnames or [])
            if missing:
                raise ValueError(f"{filename} is missing columns: {sorted(missing)}")
            for row_number, row in enumerate(reader, start=2):
                relative_path = Path((row.get("image_path") or "").strip())
                if relative_path.is_absolute() or ".." in relative_path.parts:
                    raise ValueError(f"Unsafe image path in {filename} row {row_number}")
                source_path = (source_root / relative_path).resolve()
                if not source_path.is_relative_to(source_root) or not source_path.is_file():
                    raise ValueError(f"Missing source image in {filename} row {row_number}")
                digest = sha256_file(source_path)
                if digest not in eligible_hashes:
                    continue
                participant_group = (row.get("id") or "").strip()
                label_text = (row.get("TonguePale") or "").strip()
                if not participant_group or label_text not in {"0", "1"}:
                    raise ValueError(f"Invalid fold metadata in {filename} row {row_number}")
                observations[digest].add(
                    FoldObservation(
                        split=split,
                        participant_group=participant_group,
                        label=int(label_text),
                    )
                )
    return observations


def build_splits(
    master_samples: dict[str, tuple[Path, int]],
    observations: dict[str, set[FoldObservation]],
) -> tuple[dict[str, list[PallorSample]], dict[str, int]]:
    if set(master_samples) != set(observations):
        raise ValueError("Fold metadata does not cover every eligible master image")
    splits: dict[str, list[PallorSample]] = {name: [] for name in FOLD_FILES}
    exclusions: Counter[str] = Counter()

    for digest, metadata in sorted(observations.items()):
        split_names = {item.split for item in metadata}
        if len(split_names) != 1:
            exclusions["cross_split_duplicate_content"] += 1
            continue
        split = next(iter(split_names))
        groups = {item.participant_group for item in metadata}
        if len(groups) != 1:
            exclusions["ambiguous_participant_group"] += 1
            continue
        labels = {item.label for item in metadata}
        if len(labels) != 1:
            exclusions["conflicting_fold_target"] += 1
            continue
        image_path, master_label = master_samples[digest]
        fold_label = next(iter(labels))
        if master_label != fold_label:
            exclusions["master_fold_target_mismatch"] += 1
            continue
        splits[split].append(
            PallorSample(
                image_path=image_path,
                content_sha256=digest,
                participant_group=next(iter(groups)),
                label=master_label,
            )
        )

    validate_splits(splits)
    return splits, dict(sorted(exclusions.items()))


def validate_splits(splits: dict[str, list[PallorSample]]) -> None:
    hashes = {name: {sample.content_sha256 for sample in samples} for name, samples in splits.items()}
    groups = {name: {sample.participant_group for sample in samples} for name, samples in splits.items()}
    for first, second in (("train", "validation"), ("train", "test"), ("validation", "test")):
        if hashes[first] & hashes[second]:
            raise ValueError(f"Content leakage between {first} and {second}")
        if groups[first] & groups[second]:
            raise ValueError(f"Participant leakage between {first} and {second}")
    for name, samples in splits.items():
        if {sample.label for sample in samples} != {0, 1}:
            raise ValueError(f"The {name} split must contain both TonguePale labels")


def load_splits(configuration: Configuration) -> tuple[dict[str, list[PallorSample]], dict[str, int]]:
    master_samples = read_master_manifest(configuration.master_root)
    observations = read_fold_observations(configuration.tonguedx_root, set(master_samples))
    return build_splits(master_samples, observations)


def set_determinism(seed: int) -> None:
    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)
    import torch

    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.use_deterministic_algorithms(True)
    torch.backends.cudnn.benchmark = False


def resolve_device(requested: str) -> str:
    import torch

    if requested != "auto":
        return requested
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def make_dataset(samples: Sequence[PallorSample], *, training: bool) -> Any:
    import torch
    from PIL import Image
    from torch.utils.data import Dataset
    from torchvision.transforms import InterpolationMode
    from torchvision.transforms import v2

    transforms: list[Any] = [
        v2.Resize((IMAGE_SIZE, IMAGE_SIZE), interpolation=InterpolationMode.BICUBIC, antialias=True),
    ]
    if training:
        transforms.append(v2.RandomHorizontalFlip(p=0.5))
    transforms.extend([v2.ToImage(), v2.ToDtype(torch.float32, scale=True)])
    transform = v2.Compose(transforms)

    class PallorDataset(Dataset[Any]):
        def __len__(self) -> int:
            return len(samples)

        def __getitem__(self, index: int) -> tuple[Any, Any]:
            sample = samples[index]
            with Image.open(sample.image_path) as image:
                tensor = transform(image.convert("RGB"))
            return tensor, torch.tensor(float(sample.label), dtype=torch.float32)

    return PallorDataset()


def make_data_loader(dataset: Any, batch_size: int, shuffle: bool, seed: int) -> Any:
    import torch
    from torch.utils.data import DataLoader

    generator = torch.Generator().manual_seed(seed)
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=0,
        pin_memory=False,
        generator=generator,
    )


def make_model(pretrained: bool) -> Any:
    import torch
    from torch import nn
    from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

    weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None

    class PallorNetwork(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.backbone = mobilenet_v3_small(weights=weights)
            final_layer = self.backbone.classifier[-1]
            if not isinstance(final_layer, nn.Linear):
                raise TypeError("Unexpected MobileNet classifier layout")
            self.backbone.classifier[-1] = nn.Linear(final_layer.in_features, 1)
            self.register_buffer("channel_mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
            self.register_buffer("channel_std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

        def forward(self, image: Any) -> Any:
            normalized = (image - self.channel_mean) / self.channel_std
            return self.backbone(normalized).reshape(-1)

    return PallorNetwork()


def compute_positive_weight(samples: Sequence[PallorSample]) -> float:
    positives = sum(sample.label for sample in samples)
    negatives = len(samples) - positives
    if positives == 0 or negatives == 0:
        raise ValueError("Training split must contain both labels")
    return negatives / positives


def collect_logits(
    model: Any,
    data_loader: Any,
    device: Any,
) -> tuple[NDArray[np.float64], NDArray[np.int64]]:
    import torch

    model.eval()
    logits: list[NDArray[np.float64]] = []
    labels: list[NDArray[np.int64]] = []
    with torch.no_grad():
        for images, batch_labels in data_loader:
            batch_logits = model(images.to(device)).detach().cpu().numpy().astype(np.float64)
            logits.append(batch_logits)
            labels.append(batch_labels.numpy().astype(np.int64))
    return np.concatenate(logits), np.concatenate(labels)


def metric_values(
    probabilities: NDArray[np.float64],
    labels: NDArray[np.int64],
    threshold: float,
) -> EvaluationMetrics:
    predictions = probabilities >= threshold
    true_negative = int(np.sum((labels == 0) & ~predictions))
    false_positive = int(np.sum((labels == 0) & predictions))
    false_negative = int(np.sum((labels == 1) & ~predictions))
    true_positive = int(np.sum((labels == 1) & predictions))
    precision = true_positive / max(true_positive + false_positive, 1)
    recall = true_positive / max(true_positive + false_negative, 1)
    specificity = true_negative / max(true_negative + false_positive, 1)
    f1 = 2 * precision * recall / max(precision + recall, float(np.finfo(np.float64).eps))
    positive_probabilities = probabilities[labels == 1]
    negative_probabilities = probabilities[labels == 0]
    if len(positive_probabilities) == 0 or len(negative_probabilities) == 0:
        raise ValueError("ROC-AUC requires both labels")
    comparisons = positive_probabilities[:, None] - negative_probabilities[None, :]
    roc_auc = float(np.mean((comparisons > 0) + 0.5 * (comparisons == 0)))
    return EvaluationMetrics(
        roc_auc=roc_auc,
        precision=precision,
        recall=recall,
        f1_score=f1,
        balanced_accuracy=(recall + specificity) / 2,
        brier_score=float(np.mean(np.square(probabilities - labels))),
        confusion_matrix=[[true_negative, false_positive], [false_negative, true_positive]],
    )


def select_precision_recall_threshold(
    probabilities: NDArray[np.float64],
    labels: NDArray[np.int64],
) -> float:
    candidates = np.unique(np.concatenate((np.linspace(0.001, 0.999, 999), probabilities)))
    scored: list[tuple[float, float, float, float]] = []
    for threshold in candidates:
        predictions = probabilities >= threshold
        true_positive = int(np.sum((labels == 1) & predictions))
        false_positive = int(np.sum((labels == 0) & predictions))
        false_negative = int(np.sum((labels == 1) & ~predictions))
        precision = true_positive / max(true_positive + false_positive, 1)
        recall = true_positive / max(true_positive + false_negative, 1)
        f1 = 2 * precision * recall / max(precision + recall, float(np.finfo(np.float64).eps))
        scored.append((f1, precision, recall, float(threshold)))
    return max(scored)[3]


def train_model(
    configuration: Configuration,
    splits: dict[str, list[PallorSample]],
    device_name: str,
) -> tuple[Any, dict[str, Any]]:
    import torch

    device = torch.device(device_name)
    model = make_model(configuration.pretrained).to(device)
    train_loader = make_data_loader(
        make_dataset(splits["train"], training=True),
        configuration.batch_size,
        True,
        configuration.seed,
    )
    validation_loader = make_data_loader(
        make_dataset(splits["validation"], training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    positive_weight_value = compute_positive_weight(splits["train"])
    positive_weight = torch.tensor([positive_weight_value], dtype=torch.float32, device=device)
    loss_function = torch.nn.BCEWithLogitsLoss(pos_weight=positive_weight)
    optimizer_type = cast(Callable[..., Any], getattr(torch.optim, "Adam"))
    optimizer = optimizer_type(
        model.parameters(),
        lr=configuration.learning_rate,
        weight_decay=configuration.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer,
        mode="max",
        patience=2,
        factor=0.5,
    )

    best_auc = -math.inf
    best_state: dict[str, Any] | None = None
    epochs_without_improvement = 0
    history: list[dict[str, float]] = []
    for epoch in range(1, configuration.epochs + 1):
        model.train()
        total_loss = 0.0
        total_examples = 0
        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(images)
            loss = loss_function(logits, labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach().cpu()) * labels.shape[0]
            total_examples += labels.shape[0]

        validation_logits, validation_labels = collect_logits(model, validation_loader, device)
        validation_probabilities = 1.0 / (1.0 + np.exp(-np.clip(validation_logits, -40, 40)))
        validation_metrics = metric_values(validation_probabilities, validation_labels, threshold=0.5)
        scheduler.step(validation_metrics.roc_auc)
        epoch_values = {
            "epoch": float(epoch),
            "trainLoss": total_loss / max(total_examples, 1),
            "validationROC_AUC": validation_metrics.roc_auc,
            "validationPrecision": validation_metrics.precision,
            "validationRecall": validation_metrics.recall,
            "validationF1": validation_metrics.f1_score,
            "learningRate": float(optimizer.param_groups[0]["lr"]),
        }
        history.append(epoch_values)
        print(json.dumps(epoch_values, sort_keys=True), flush=True)

        if validation_metrics.roc_auc > best_auc + 1e-6:
            best_auc = validation_metrics.roc_auc
            best_state = {name: value.detach().cpu().clone() for name, value in model.state_dict().items()}
            epochs_without_improvement = 0
        else:
            epochs_without_improvement += 1
        if epochs_without_improvement >= configuration.patience:
            break

    if best_state is None:
        raise RuntimeError("Training did not produce a checkpoint")
    model.load_state_dict(best_state)
    model.eval()
    return model.cpu(), {
        "history": history,
        "bestValidationROC_AUC": best_auc,
        "trainPositiveWeight": positive_weight_value,
        "device": device_name,
    }


def anonymized_split_manifest(
    splits: dict[str, list[PallorSample]],
    exclusions: dict[str, int],
    dataset_version: str,
) -> dict[str, Any]:
    def hash_group(group: str) -> str:
        return hashlib.sha256(f"{dataset_version}\0{group}".encode()).hexdigest()

    return {
        "datasetVersion": dataset_version,
        "sourceFold": 1,
        "excludedAmbiguousContent": exclusions,
        "splits": {
            name: {
                "imageCount": len(samples),
                "positiveCount": sum(sample.label for sample in samples),
                "participantGroupHashes": sorted({hash_group(sample.participant_group) for sample in samples}),
                "contentHashes": sorted(sample.content_sha256 for sample in samples),
            }
            for name, samples in splits.items()
        },
    }


def export_core_ml(
    model: Any,
    calibration_slope: float,
    calibration_intercept: float,
    threshold: float,
    configuration: Configuration,
) -> tuple[Path, Any]:
    import coremltools as ct
    import torch
    from torch import nn

    class ExportWrapper(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.pallor_model = model
            self.register_buffer("calibration_slope", torch.tensor(calibration_slope, dtype=torch.float32))
            self.register_buffer("calibration_intercept", torch.tensor(calibration_intercept, dtype=torch.float32))

        def forward(self, image: Any) -> tuple[Any, Any]:
            raw_logit = self.pallor_model(image).reshape(1)
            probability = torch.sigmoid(raw_logit * self.calibration_slope + self.calibration_intercept)
            return raw_logit, probability

    export_model = ExportWrapper().eval()
    example_input = torch.zeros((1, 3, IMAGE_SIZE, IMAGE_SIZE), dtype=torch.float32)
    trace_model = cast(Callable[[Any, Any], Any], torch.jit.trace)
    traced_model = trace_model(export_model, example_input)
    core_ml_model = ct.convert(
        traced_model,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS18,
        inputs=[
            ct.ImageType(
                name=INPUT_NAME,
                shape=example_input.shape,
                color_layout=ct.colorlayout.RGB,
                scale=1.0 / 255.0,
                bias=[0.0, 0.0, 0.0],
            )
        ],
        outputs=[
            ct.TensorType(name=RAW_OUTPUT_NAME, dtype=np.float32),
            ct.TensorType(name=PROBABILITY_OUTPUT_NAME, dtype=np.float32),
        ],
    )
    normalization = compact_json({"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]})
    core_ml_model.user_defined_metadata.update(
        {
            "manifestSchemaVersion": "1",
            "modelIdentifier": MODEL_IDENTIFIER,
            "semanticVersion": configuration.semantic_version,
            "inputFeatureName": INPUT_NAME,
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
            "normalization": normalization,
            "decisionThreshold": repr(threshold),
            "preprocessingVersion": PREPROCESSING_VERSION,
        }
    )
    core_ml_model.author = "IronScan research team"
    core_ml_model.license = "See repository and private dataset provenance records"
    core_ml_model.short_description = "Engineering fixture predicting the source dataset's visual TonguePale annotation."
    core_ml_model.input_description[INPUT_NAME] = "Orientation-normalized tongue image in sRGB."
    core_ml_model.output_description[RAW_OUTPUT_NAME] = "Uncalibrated visual-pallor model logit."
    core_ml_model.output_description[PROBABILITY_OUTPUT_NAME] = "Validation-calibrated TonguePale probability."

    package_path = configuration.output_directory / MODEL_FILENAME
    if package_path.exists():
        shutil.rmtree(package_path)
    core_ml_model.save(str(package_path))
    return package_path, core_ml_model


def verify_coreml_parity(
    model: Any,
    core_ml_model: Any,
    samples: Sequence[PallorSample],
    sample_count: int,
    calibration_slope: float,
    calibration_intercept: float,
) -> dict[str, float | int]:
    import torch
    from PIL import Image

    selected = list(samples[: min(sample_count, len(samples))])
    dataset = make_dataset(selected, training=False)
    maximum_probability_difference = 0.0
    maximum_logit_difference = 0.0
    for index, sample in enumerate(selected):
        tensor, _ = dataset[index]
        with torch.no_grad():
            pytorch_logit = float(model(tensor.unsqueeze(0)).reshape(-1)[0])
        with Image.open(sample.image_path) as image:
            resized = image.convert("RGB").resize((IMAGE_SIZE, IMAGE_SIZE), resample=Image.Resampling.BICUBIC)
            prediction = core_ml_model.predict({INPUT_NAME: resized})
        coreml_logit = float(np.asarray(prediction[RAW_OUTPUT_NAME]).reshape(-1)[0])
        coreml_probability = float(np.asarray(prediction[PROBABILITY_OUTPUT_NAME]).reshape(-1)[0])
        maximum_logit_difference = max(maximum_logit_difference, abs(pytorch_logit - coreml_logit))
        calibrated_logit = np.clip(
            pytorch_logit * calibration_slope + calibration_intercept,
            -40,
            40,
        )
        expected_probability = float(1.0 / (1.0 + np.exp(-calibrated_logit)))
        maximum_probability_difference = max(
            maximum_probability_difference,
            abs(expected_probability - coreml_probability),
        )
    if maximum_logit_difference > 0.01 or maximum_probability_difference > 0.01:
        raise ValueError("Core ML parity tolerance exceeded")
    return {
        "sampleCount": len(selected),
        "maximumLogitAbsoluteDifference": maximum_logit_difference,
        "maximumProbabilityAbsoluteDifference": maximum_probability_difference,
    }


def compile_coreml_package(package_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="ironscan-pallor-compile-") as temporary_directory:
        subprocess.run(
            ["xcrun", "coremlcompiler", "compile", str(package_path), temporary_directory],
            check=True,
            capture_output=True,
            text=True,
        )


def write_model_manifest(
    package_path: Path,
    threshold: float,
    configuration: Configuration,
) -> Path:
    manifest = {
        "schemaVersion": 1,
        "modelIdentifier": MODEL_IDENTIFIER,
        "semanticVersion": configuration.semantic_version,
        "sha256": package_sha256(package_path),
        "deploymentStatus": "engineeringFixture",
        "input": {
            "name": INPUT_NAME,
            "dimensions": [1, IMAGE_SIZE, IMAGE_SIZE, 3],
            "dataType": "uint8",
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
        },
        "resize": {"method": "scaleFill", "interpolation": "vImageHighQuality"},
        "normalization": {"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]},
        "outputs": [
            {"name": RAW_OUTPUT_NAME, "dimensions": [1], "dataType": "float32"},
            {"name": PROBABILITY_OUTPUT_NAME, "dimensions": [1], "dataType": "float32"},
        ],
        "decisionThreshold": threshold,
        "trainingCommit": configuration.training_commit,
        "datasetVersion": configuration.dataset_version,
        "preprocessingVersion": PREPROCESSING_VERSION,
    }
    manifest_path = configuration.output_directory / MANIFEST_FILENAME
    write_json(manifest_path, manifest)
    return manifest_path


def install_artifacts(
    package_path: Path,
    manifest_path: Path,
    configuration: Configuration,
) -> None:
    configuration.coreml_destination.parent.mkdir(parents=True, exist_ok=True)
    configuration.manifest_destination.parent.mkdir(parents=True, exist_ok=True)
    if configuration.coreml_destination.exists():
        shutil.rmtree(configuration.coreml_destination)
    if configuration.manifest_destination.exists():
        configuration.manifest_destination.unlink()
    shutil.copytree(package_path, configuration.coreml_destination)
    shutil.copyfile(manifest_path, configuration.manifest_destination)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(configuration: Configuration) -> None:
    import torch

    configuration.output_directory.mkdir(parents=True, exist_ok=True)
    set_determinism(configuration.seed)
    splits, exclusions = load_splits(configuration)
    write_json(
        configuration.output_directory / "split_manifest.json",
        anonymized_split_manifest(splits, exclusions, configuration.dataset_version),
    )
    device_name = resolve_device(configuration.device)
    model, training_report = train_model(configuration, splits, device_name)

    validation_loader = make_data_loader(
        make_dataset(splits["validation"], training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    test_loader = make_data_loader(
        make_dataset(splits["test"], training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    validation_logits, validation_labels = collect_logits(model, validation_loader, torch.device("cpu"))
    calibration_slope, calibration_intercept = fit_probability_calibration(
        validation_logits,
        validation_labels,
        configuration.seed,
    )
    validation_probabilities = calibrated_probabilities(
        validation_logits,
        calibration_slope,
        calibration_intercept,
    )
    threshold = select_precision_recall_threshold(validation_probabilities, validation_labels)
    validation_metrics = metric_values(validation_probabilities, validation_labels, threshold)

    test_logits, test_labels = collect_logits(model, test_loader, torch.device("cpu"))
    test_probabilities = calibrated_probabilities(test_logits, calibration_slope, calibration_intercept)
    test_metrics = metric_values(test_probabilities, test_labels, threshold)

    checkpoint_path = configuration.output_directory / "pallor_model_checkpoint.pt"
    torch.save(
        {
            "state_dict": model.state_dict(),
            "configuration": asdict(configuration),
            "calibration_slope": calibration_slope,
            "calibration_intercept": calibration_intercept,
            "decision_threshold": threshold,
        },
        checkpoint_path,
    )
    package_path, core_ml_model = export_core_ml(
        model,
        calibration_slope,
        calibration_intercept,
        threshold,
        configuration,
    )
    parity = verify_coreml_parity(
        model,
        core_ml_model,
        splits["test"],
        configuration.parity_sample_count,
        calibration_slope,
        calibration_intercept,
    )
    compile_coreml_package(package_path)
    manifest_path = write_model_manifest(package_path, threshold, configuration)
    install_artifacts(package_path, manifest_path, configuration)

    evaluation_report = {
        **training_report,
        "splitCounts": {
            name: {"images": len(samples), "positive": sum(sample.label for sample in samples)}
            for name, samples in splits.items()
        },
        "excludedAmbiguousContent": exclusions,
        "validation": asdict(validation_metrics),
        "test": asdict(test_metrics),
        "lockedDecisionThreshold": threshold,
        "calibration": {
            "method": "Platt",
            "slope": calibration_slope,
            "intercept": calibration_intercept,
        },
        "coreMLParity": parity,
        "deploymentStatus": "engineeringFixture",
        "repositoryDirtyDuringTraining": repository_is_dirty(),
        "augmentations": ["randomHorizontalFlip"],
        "excludedAugmentations": [
            "colorJitter excluded because mucosal color is the visual target signal",
        ],
        "limitations": [
            "The model predicts the source dataset's visual TonguePale annotation only.",
            "The output is not a hemoglobin, ferritin, anemia, or iron-status measurement.",
            "Source images are not standardized IronScan captures and have no laboratory ground truth.",
            "Independent cohort, acquisition, calibration, and physical-device validation remain required.",
        ],
    }
    write_json(configuration.output_directory / "evaluation_metrics.json", evaluation_report)
    print(json.dumps(evaluation_report["test"], indent=2, sort_keys=True))
    print(f"Core ML package: {configuration.coreml_destination}")
    print(f"Model manifest: {configuration.manifest_destination}")
    print(f"Locked threshold: {threshold:.6f}")


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
