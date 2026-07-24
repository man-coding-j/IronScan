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
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable, Final, Sequence, cast

import numpy as np
from numpy.typing import NDArray

IMAGE_SIZE: Final = 224
SPLIT_FRACTIONS: Final = (0.70, 0.15, 0.15)
MODEL_IDENTIFIER: Final = "org.ironscan.engineering.anemia-risk"
INPUT_NAME: Final = "image"
RAW_OUTPUT_NAME: Final = "raw_score"
PROBABILITY_OUTPUT_NAME: Final = "calibrated_probability"
PREPROCESSING_VERSION: Final = "2.0.0"


@dataclass(frozen=True)
class Sample:
    image_path: Path
    participant_group: str
    label: int


@dataclass(frozen=True)
class TrainingConfiguration:
    metadata_csv: Path
    image_root: Path
    output_directory: Path
    image_column: str
    participant_column: str
    label_column: str
    dataset_version: str
    semantic_version: str
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


@dataclass(frozen=True)
class EvaluationMetrics:
    roc_auc: float
    balanced_accuracy: float
    sensitivity: float
    specificity: float
    brier_score: float


def parse_arguments() -> TrainingConfiguration:
    parser = argparse.ArgumentParser(
        description="Train and export the IronScan research anemia-screening risk model."
    )
    parser.add_argument("--metadata-csv", type=Path, required=True)
    parser.add_argument("--image-root", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--image-column", default="image_path")
    parser.add_argument("--participant-column", default="participant_id")
    parser.add_argument("--label-column", default="anemia_label")
    parser.add_argument("--dataset-version", required=True)
    parser.add_argument("--semantic-version", required=True)
    parser.add_argument("--training-commit")
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--patience", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=20260716)
    parser.add_argument("--device", choices=("cpu", "cuda", "mps"), default="cpu")
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    arguments = parser.parse_args()

    training_commit = arguments.training_commit or current_git_commit()
    configuration = TrainingConfiguration(
        metadata_csv=arguments.metadata_csv.resolve(),
        image_root=arguments.image_root.resolve(),
        output_directory=arguments.output_directory.resolve(),
        image_column=arguments.image_column,
        participant_column=arguments.participant_column,
        label_column=arguments.label_column,
        dataset_version=arguments.dataset_version,
        semantic_version=arguments.semantic_version,
        training_commit=training_commit,
        epochs=arguments.epochs,
        patience=arguments.patience,
        batch_size=arguments.batch_size,
        learning_rate=arguments.learning_rate,
        weight_decay=arguments.weight_decay,
        seed=arguments.seed,
        device=arguments.device,
        pretrained=not arguments.no_pretrained,
        allow_dirty=arguments.allow_dirty,
    )
    validate_configuration(configuration)
    return configuration


def current_git_commit() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def repository_is_dirty() -> bool:
    completed = subprocess.run(
        ["git", "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
    )
    return bool(completed.stdout.strip())


def validate_configuration(configuration: TrainingConfiguration) -> None:
    if not configuration.metadata_csv.is_file():
        raise ValueError(f"Metadata CSV does not exist: {configuration.metadata_csv}")
    if not configuration.image_root.is_dir():
        raise ValueError(f"Image root does not exist: {configuration.image_root}")
    if configuration.epochs < 1 or configuration.patience < 1 or configuration.batch_size < 1:
        raise ValueError("Epochs, patience, and batch size must be positive")
    if configuration.learning_rate <= 0 or configuration.weight_decay < 0:
        raise ValueError("Learning rate must be positive and weight decay cannot be negative")
    if not configuration.dataset_version.strip():
        raise ValueError("Dataset version is required")
    if not is_semantic_version(configuration.semantic_version):
        raise ValueError("Semantic version must follow MAJOR.MINOR.PATCH with an optional prerelease")
    if not configuration.allow_dirty and repository_is_dirty():
        raise ValueError("Training requires a clean Git worktree; commit changes or pass --allow-dirty")


def is_semantic_version(value: str) -> bool:
    import re

    return re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?",
        value,
    ) is not None


def read_samples(configuration: TrainingConfiguration) -> list[Sample]:
    required_columns = {
        configuration.image_column,
        configuration.participant_column,
        configuration.label_column,
    }
    samples: list[Sample] = []
    seen_paths: dict[Path, tuple[str, int]] = {}
    with configuration.metadata_csv.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        available_columns = set(reader.fieldnames or [])
        missing_columns = required_columns - available_columns
        if missing_columns:
            raise ValueError(f"Metadata CSV is missing required columns: {sorted(missing_columns)}")
        for row_number, row in enumerate(reader, start=2):
            relative_path = Path(require_value(row, configuration.image_column, row_number))
            if relative_path.is_absolute():
                raise ValueError(f"Image path must be relative to --image-root at CSV row {row_number}")
            image_path = (configuration.image_root / relative_path).resolve()
            if not image_path.is_relative_to(configuration.image_root):
                raise ValueError(f"Image path escapes --image-root at CSV row {row_number}")
            if not image_path.is_file():
                raise ValueError(f"Image file is missing at CSV row {row_number}: {relative_path}")
            participant_group = require_value(row, configuration.participant_column, row_number)
            label_text = require_value(row, configuration.label_column, row_number)
            try:
                label = int(label_text)
            except ValueError as error:
                raise ValueError(f"Label must be 0 or 1 at CSV row {row_number}") from error
            if label not in (0, 1):
                raise ValueError(f"Label must be 0 or 1 at CSV row {row_number}")
            previous = seen_paths.get(image_path)
            if previous is not None and previous != (participant_group, label):
                raise ValueError(f"Conflicting duplicate image metadata at CSV row {row_number}")
            if previous is None:
                seen_paths[image_path] = (participant_group, label)
                samples.append(Sample(image_path=image_path, participant_group=participant_group, label=label))

    validate_samples(samples)
    return samples


def require_value(row: dict[str, str], column: str, row_number: int) -> str:
    value = (row.get(column) or "").strip()
    if not value:
        raise ValueError(f"Column {column!r} is empty at CSV row {row_number}")
    return value


def validate_samples(samples: Sequence[Sample]) -> None:
    if len(samples) < 30:
        raise ValueError("At least 30 images are required for a three-way grouped split")
    labels = {sample.label for sample in samples}
    if labels != {0, 1}:
        raise ValueError("Both binary screening labels must be represented")
    groups_by_label = {
        label: {sample.participant_group for sample in samples if sample.label == label}
        for label in (0, 1)
    }
    if min(len(groups) for groups in groups_by_label.values()) < 3:
        raise ValueError("Each label requires at least three participant groups")
    labels_by_group: dict[str, set[int]] = {}
    for sample in samples:
        labels_by_group.setdefault(sample.participant_group, set()).add(sample.label)
    conflicting_groups = [group for group, group_labels in labels_by_group.items() if len(group_labels) > 1]
    if conflicting_groups:
        raise ValueError("Every participant group must have one consistent screening label")


def grouped_split(samples: Sequence[Sample], seed: int) -> dict[str, list[Sample]]:
    grouped: dict[str, list[Sample]] = {}
    for sample in samples:
        grouped.setdefault(sample.participant_group, []).append(sample)

    random_generator = random.Random(seed)
    groups = list(grouped.items())
    random_generator.shuffle(groups)
    groups.sort(key=lambda item: len(item[1]), reverse=True)

    total_count = len(samples)
    total_positive = sum(sample.label for sample in samples)
    targets = {
        name: (total_count * fraction, total_positive * fraction)
        for name, fraction in zip(("train", "validation", "test"), SPLIT_FRACTIONS, strict=True)
    }
    assignments: dict[str, list[Sample]] = {"train": [], "validation": [], "test": []}
    positive_counts = {name: 0 for name in assignments}

    for _, group_samples in groups:
        group_positive = sum(sample.label for sample in group_samples)
        best_split = min(
            assignments,
            key=lambda name: split_assignment_cost(
                current_count=len(assignments[name]),
                current_positive=positive_counts[name],
                added_count=len(group_samples),
                added_positive=group_positive,
                target_count=targets[name][0],
                target_positive=targets[name][1],
            ),
        )
        assignments[best_split].extend(group_samples)
        positive_counts[best_split] += group_positive

    validate_grouped_split(assignments)
    return assignments


def split_assignment_cost(
    *,
    current_count: int,
    current_positive: int,
    added_count: int,
    added_positive: int,
    target_count: float,
    target_positive: float,
) -> float:
    projected_count = current_count + added_count
    projected_positive = current_positive + added_positive
    count_error = (projected_count - target_count) / max(target_count, 1)
    positive_error = (projected_positive - target_positive) / max(target_positive, 1)
    overflow = max(0.0, projected_count - target_count) / max(target_count, 1)
    return count_error * count_error + positive_error * positive_error + overflow * 0.35


def validate_grouped_split(assignments: dict[str, list[Sample]]) -> None:
    group_sets = {
        name: {sample.participant_group for sample in split_samples}
        for name, split_samples in assignments.items()
    }
    if group_sets["train"] & group_sets["validation"]:
        raise ValueError("Participant leakage between train and validation splits")
    if group_sets["train"] & group_sets["test"]:
        raise ValueError("Participant leakage between train and test splits")
    if group_sets["validation"] & group_sets["test"]:
        raise ValueError("Participant leakage between validation and test splits")
    for name, split_samples in assignments.items():
        if {sample.label for sample in split_samples} != {0, 1}:
            raise ValueError(f"The {name} split must contain both labels; collect more participant groups")


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


def make_dataset(samples: Sequence[Sample], training: bool) -> Any:
    import torch
    from PIL import Image
    from torch.utils.data import Dataset
    from torchvision.transforms import InterpolationMode
    from torchvision.transforms import v2

    transforms: list[Any] = [
        v2.Resize((IMAGE_SIZE, IMAGE_SIZE), interpolation=InterpolationMode.BICUBIC, antialias=True),
    ]
    if training:
        transforms.extend(
            [
                v2.RandomHorizontalFlip(p=0.5),
                v2.RandomAffine(degrees=4, translate=(0.025, 0.025), scale=(0.98, 1.02)),
            ]
        )
    transforms.extend([v2.ToImage(), v2.ToDtype(torch.float32, scale=True)])
    transform = v2.Compose(transforms)

    class TongueDataset(Dataset[Any]):
        def __len__(self) -> int:
            return len(samples)

        def __getitem__(self, index: int) -> tuple[Any, Any]:
            sample = samples[index]
            with Image.open(sample.image_path) as image:
                rgb_image = image.convert("RGB")
                tensor = transform(rgb_image)
            return tensor, torch.tensor(float(sample.label), dtype=torch.float32)

    return TongueDataset()


def make_model(pretrained: bool) -> Any:
    import torch
    from torch import nn
    from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

    weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None

    class RiskNetwork(nn.Module):
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

    return RiskNetwork()


def make_data_loader(dataset: Any, batch_size: int, shuffle: bool, seed: int) -> Any:
    import torch
    from torch.utils.data import DataLoader

    generator = torch.Generator()
    generator.manual_seed(seed)
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=0,
        pin_memory=False,
        generator=generator,
    )


def train_model(configuration: TrainingConfiguration, splits: dict[str, list[Sample]]) -> tuple[Any, dict[str, Any]]:
    import torch
    from sklearn.metrics import roc_auc_score

    device = torch.device(configuration.device)
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
    positive_count = sum(sample.label for sample in splits["train"])
    negative_count = len(splits["train"]) - positive_count
    positive_weight = torch.tensor([negative_count / positive_count], dtype=torch.float32, device=device)
    loss_function = torch.nn.BCEWithLogitsLoss(pos_weight=positive_weight)
    optimizer_type = cast(Callable[..., Any], getattr(torch.optim, "AdamW"))
    optimizer = optimizer_type(
        model.parameters(),
        lr=configuration.learning_rate,
        weight_decay=configuration.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="max", patience=2, factor=0.5)

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
        validation_auc = float(roc_auc_score(validation_labels, validation_logits))
        scheduler.step(validation_auc)
        epoch_loss = total_loss / max(total_examples, 1)
        history.append({"epoch": float(epoch), "trainLoss": epoch_loss, "validationROC_AUC": validation_auc})

        if validation_auc > best_auc + 1e-6:
            best_auc = validation_auc
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
    return model.cpu(), {"history": history, "bestValidationROC_AUC": best_auc}


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


def fit_probability_calibration(
    logits: NDArray[np.float64],
    labels: NDArray[np.int64],
    seed: int,
) -> tuple[float, float]:
    from sklearn.linear_model import LogisticRegression

    calibrator = LogisticRegression(random_state=seed, solver="lbfgs")
    calibrator.fit(logits.reshape(-1, 1), labels)
    return float(calibrator.coef_[0, 0]), float(calibrator.intercept_[0])


def calibrated_probabilities(
    logits: NDArray[np.float64],
    slope: float,
    intercept: float,
) -> NDArray[np.float64]:
    transformed = np.clip(logits * slope + intercept, -40, 40)
    return np.asarray(1.0 / (1.0 + np.exp(-transformed)), dtype=np.float64)


def select_locked_threshold(probabilities: NDArray[np.float64], labels: NDArray[np.int64]) -> float:
    from sklearn.metrics import balanced_accuracy_score

    candidates = np.unique(np.concatenate((np.linspace(0.01, 0.99, 991), probabilities)))
    scored = [
        (float(balanced_accuracy_score(labels, probabilities >= threshold)), float(threshold))
        for threshold in candidates
    ]
    best_score = max(score for score, _ in scored)
    best_thresholds = [threshold for score, threshold in scored if math.isclose(score, best_score, abs_tol=1e-12)]
    return float(np.median(best_thresholds))


def evaluate(
    probabilities: NDArray[np.float64],
    labels: NDArray[np.int64],
    threshold: float,
) -> EvaluationMetrics:
    from sklearn.metrics import balanced_accuracy_score, brier_score_loss, confusion_matrix, roc_auc_score

    predictions = probabilities >= threshold
    true_negative, false_positive, false_negative, true_positive = confusion_matrix(
        labels,
        predictions,
        labels=[0, 1],
    ).ravel()
    sensitivity = true_positive / max(true_positive + false_negative, 1)
    specificity = true_negative / max(true_negative + false_positive, 1)
    return EvaluationMetrics(
        roc_auc=float(roc_auc_score(labels, probabilities)),
        balanced_accuracy=float(balanced_accuracy_score(labels, predictions)),
        sensitivity=float(sensitivity),
        specificity=float(specificity),
        brier_score=float(brier_score_loss(labels, probabilities)),
    )


def export_core_ml(
    model: Any,
    slope: float,
    intercept: float,
    threshold: float,
    configuration: TrainingConfiguration,
) -> Path:
    import coremltools as ct
    import torch
    from torch import nn

    class ExportWrapper(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.risk_model = model
            self.register_buffer("calibration_slope", torch.tensor(slope, dtype=torch.float32))
            self.register_buffer("calibration_intercept", torch.tensor(intercept, dtype=torch.float32))

        def forward(self, image: Any) -> tuple[Any, Any]:
            raw_score = self.risk_model(image).reshape(1)
            probability = torch.sigmoid(raw_score * self.calibration_slope + self.calibration_intercept)
            return raw_score, probability

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
    core_ml_model.license = "See repository LICENSE and dataset provenance records"
    core_ml_model.short_description = "Research prototype model estimating possible anemia risk from an accepted calibrated tongue sample."
    core_ml_model.input_description[INPUT_NAME] = "Calibrated central tongue ROI in sRGB."
    core_ml_model.output_description[RAW_OUTPUT_NAME] = "Uncalibrated screening-model logit."
    core_ml_model.output_description[PROBABILITY_OUTPUT_NAME] = "Validation-calibrated possible anemia risk probability."

    package_path = configuration.output_directory / "AnemiaRisk.mlpackage"
    if package_path.exists():
        if package_path.is_dir():
            shutil.rmtree(package_path)
        else:
            package_path.unlink()
    core_ml_model.save(str(package_path))
    return package_path


def package_sha256(package_path: Path) -> str:
    hasher = hashlib.sha256()
    for file_path in sorted(path for path in package_path.rglob("*") if path.is_file()):
        relative_path = file_path.relative_to(package_path).as_posix()
        hasher.update(relative_path.encode("utf-8"))
        hasher.update(b"\0")
        hasher.update(file_path.read_bytes())
        hasher.update(b"\0")
    return hasher.hexdigest()


def write_manifest(
    package_path: Path,
    threshold: float,
    configuration: TrainingConfiguration,
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
    manifest_path = configuration.output_directory / "risk_manifest.json"
    write_json(manifest_path, manifest)
    return manifest_path


def anonymized_split_manifest(
    splits: dict[str, list[Sample]],
    dataset_version: str,
    seed: int,
) -> dict[str, Any]:
    def hash_group(group: str) -> str:
        return hashlib.sha256(f"{dataset_version}\0{group}".encode()).hexdigest()

    return {
        "datasetVersion": dataset_version,
        "seed": seed,
        "splits": {
            name: {
                "imageCount": len(split_samples),
                "positiveCount": sum(sample.label for sample in split_samples),
                "participantGroupHashes": sorted({hash_group(sample.participant_group) for sample in split_samples}),
            }
            for name, split_samples in splits.items()
        },
    }


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def compact_json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def run(configuration: TrainingConfiguration) -> None:
    import torch

    configuration.output_directory.mkdir(parents=True, exist_ok=True)
    set_determinism(configuration.seed)
    samples = read_samples(configuration)
    splits = grouped_split(samples, configuration.seed)
    write_json(
        configuration.output_directory / "split_manifest.json",
        anonymized_split_manifest(splits, configuration.dataset_version, configuration.seed),
    )

    model, training_report = train_model(configuration, splits)
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
    validation_probabilities = calibrated_probabilities(validation_logits, calibration_slope, calibration_intercept)
    threshold = select_locked_threshold(validation_probabilities, validation_labels)

    test_logits, test_labels = collect_logits(model, test_loader, torch.device("cpu"))
    test_probabilities = calibrated_probabilities(test_logits, calibration_slope, calibration_intercept)
    test_metrics = evaluate(test_probabilities, test_labels, threshold)

    checkpoint_path = configuration.output_directory / "risk_model_checkpoint.pt"
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
    package_path = export_core_ml(model, calibration_slope, calibration_intercept, threshold, configuration)
    manifest_path = write_manifest(package_path, threshold, configuration)
    write_json(
        configuration.output_directory / "evaluation_metrics.json",
        {
            **training_report,
            "test": asdict(test_metrics),
            "lockedDecisionThreshold": threshold,
            "calibration": {"method": "Platt", "slope": calibration_slope, "intercept": calibration_intercept},
            "deploymentStatus": "engineeringFixture",
            "limitations": [
                "The model is a research prototype and is not a diagnostic system.",
                "Hemoglobin-only labels do not establish iron-deficiency anemia.",
                "Independent cohort and physical-device validation remain required before deployment status can change.",
            ],
        },
    )
    print(f"Core ML package: {package_path}")
    print(f"Model manifest: {manifest_path}")
    print(f"Locked threshold: {threshold:.6f}")


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
