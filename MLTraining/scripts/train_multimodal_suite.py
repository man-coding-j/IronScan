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
from dataclasses import asdict, dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any, Callable, Final, Sequence, cast

import numpy as np
from numpy.typing import NDArray

from MLTraining.scripts.train_and_convert import (
    compact_json,
    current_git_commit,
    fit_probability_calibration,
    package_sha256,
    repository_is_dirty,
    select_locked_threshold,
)
from MLTraining.scripts.train_pallor_model import metric_values

IMAGE_SIZE: Final = 224
DEFAULT_SEED: Final = 20260721
SPLIT_ATTEMPTS: Final = 256
DROPOUT_PROBABILITY: Final = 0.2
MC_DROPOUT_PASSES: Final = 30
UNCERTAINTY_QUANTILE: Final = 0.75
CLINICAL_EYE_LABEL_KIND: Final = "laboratory_hemoglobin_anemia_screening_label"


class Tissue(StrEnum):
    EYE = "Eye"
    NAIL = "Nail"
    TONGUE = "Tongue"


@dataclass(frozen=True)
class TissueContract:
    tissue: Tissue
    model_identifier: str
    package_name: str
    manifest_name: str
    preprocessing_version: str
    resize_method: str


TISSUE_CONTRACTS: Final = {
    Tissue.EYE: TissueContract(
        tissue=Tissue.EYE,
        model_identifier="org.ironscan.engineering.eye-laboratory-hgb-screening",
        package_name="IronScanEye_Clinical.mlpackage",
        manifest_name="eye_clinical_manifest.json",
        preprocessing_version="multimodal-eye-clinical-2.1.0",
        resize_method="centerCrop",
    ),
    Tissue.NAIL: TissueContract(
        tissue=Tissue.NAIL,
        model_identifier="org.ironscan.engineering.nail-pallor-proxy",
        package_name="IronScanNail.mlpackage",
        manifest_name="nail_manifest.json",
        preprocessing_version="multimodal-nail-1.0.0",
        resize_method="scaleFill",
    ),
    Tissue.TONGUE: TissueContract(
        tissue=Tissue.TONGUE,
        model_identifier="org.ironscan.engineering.tongue-pallor-proxy",
        package_name="IronScanTongue.mlpackage",
        manifest_name="tongue_manifest.json",
        preprocessing_version="multimodal-tongue-1.0.0",
        resize_method="scaleFill",
    ),
}


@dataclass(frozen=True)
class Configuration:
    dataset_root: Path
    output_root: Path
    repository_root: Path
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
    install: bool
    replace_existing: bool
    parity_sample_count: int
    allow_synthetic_participant_groups: bool
    tissues: tuple[Tissue, ...]


@dataclass(frozen=True)
class MultimodalSample:
    image_path: Path
    content_sha256: str
    participant_group: str
    source_key: str
    label_kind: str
    label: int
    participant_group_kind: str = "source_provided_pseudonymized"


def parse_arguments() -> Configuration:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description=(
            "Train three engineering-fixture visual proxy models with participant-grouped splits. "
            "Folder labels are not laboratory-confirmed anemia or iron-status ground truth."
        )
    )
    parser.add_argument(
        "--dataset-root",
        type=Path,
        default=Path.home() / "Documents" / "IronScanMultiModalDataset",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path.home() / "Documents" / "IronScanPrivate" / "TrainingArtifacts" / "multimodal-v0.1.0",
    )
    parser.add_argument("--semantic-version", default="0.1.0-engineering.1")
    parser.add_argument("--dataset-version", default="multimodal-proxy-v1")
    parser.add_argument("--epochs", type=int, default=18)
    parser.add_argument("--patience", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--device", choices=("auto", "cpu", "mps", "cuda"), default="auto")
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--install", action="store_true", help="Copy verified packages and manifests into the repository.")
    parser.add_argument("--replace-existing", action="store_true")
    parser.add_argument("--parity-sample-count", type=int, default=20)
    parser.add_argument(
        "--allow-synthetic-participant-groups",
        action="store_true",
        help="Permit demo-only appearance-similarity groups. Packages remain engineering fixtures.",
    )
    parser.add_argument(
        "--tissue",
        action="append",
        choices=tuple(tissue.value for tissue in Tissue),
        help="Train only the selected tissue; may be repeated. The default trains all tissues.",
    )
    arguments = parser.parse_args()
    configuration = Configuration(
        dataset_root=arguments.dataset_root.expanduser().resolve(),
        output_root=arguments.output_root.expanduser().resolve(),
        repository_root=repository_root,
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
        install=arguments.install,
        replace_existing=arguments.replace_existing,
        parity_sample_count=arguments.parity_sample_count,
        allow_synthetic_participant_groups=arguments.allow_synthetic_participant_groups,
        tissues=tuple(Tissue(value) for value in arguments.tissue) if arguments.tissue else tuple(Tissue),
    )
    validate_configuration(configuration)
    return configuration


def validate_configuration(configuration: Configuration) -> None:
    if not (configuration.dataset_root / "dataset_manifest.csv").is_file():
        raise ValueError("Multimodal dataset manifest is missing; run multimodal_ingestion.py first")
    if configuration.output_root.exists() and not configuration.replace_existing:
        raise ValueError("Training output exists; pass --replace-existing to replace it")
    if configuration.epochs < 1 or configuration.patience < 1 or configuration.batch_size < 1:
        raise ValueError("Epochs, patience, and batch size must be positive")
    if configuration.learning_rate <= 0 or configuration.weight_decay < 0:
        raise ValueError("Learning rate must be positive and weight decay cannot be negative")
    if configuration.parity_sample_count < 1:
        raise ValueError("Parity sample count must be positive")
    if not configuration.allow_dirty and repository_is_dirty():
        raise ValueError("Training requires a clean Git worktree or --allow-dirty")
    if configuration.install:
        for tissue in configuration.tissues:
            contract = TISSUE_CONTRACTS[tissue]
            destinations = (
                configuration.repository_root / "Models" / "CoreML" / contract.package_name,
                configuration.repository_root / "Models" / "Manifests" / contract.manifest_name,
            )
            if any(path.exists() for path in destinations) and not configuration.replace_existing:
                raise ValueError("Install destination exists; pass --replace-existing to replace it")


def read_samples(
    dataset_root: Path,
    allow_synthetic_participant_groups: bool = False,
) -> dict[Tissue, list[MultimodalSample]]:
    manifest_path = dataset_root / "dataset_manifest.csv"
    required = {
        "output_path",
        "tissue",
        "target_value",
        "source_key",
        "label_kind",
        "participant_group",
        "participant_group_kind",
        "training_eligible",
        "sha256",
    }
    samples: dict[Tissue, list[MultimodalSample]] = {tissue: [] for tissue in Tissue}
    seen_hashes: set[str] = set()
    with manifest_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Dataset manifest is missing columns: {sorted(missing)}")
        for row_number, row in enumerate(reader, start=2):
            if row.get("training_eligible") != "true":
                continue
            tissue_text = (row.get("tissue") or "").strip()
            try:
                tissue = Tissue(tissue_text)
            except ValueError as error:
                raise ValueError(f"Unsupported tissue at row {row_number}: {tissue_text}") from error
            label_text = (row.get("target_value") or "").strip()
            if label_text not in {"0", "1"}:
                raise ValueError(f"Target must be binary at row {row_number}")
            participant_group = (row.get("participant_group") or "").strip()
            if not participant_group:
                raise ValueError(f"Training-eligible row {row_number} lacks a participant group")
            group_kind = (row.get("participant_group_kind") or "").strip()
            if group_kind == "synthetic_similarity_cluster_demo_only" and not allow_synthetic_participant_groups:
                raise ValueError(
                    "Dataset contains synthetic participant groups; pass --allow-synthetic-participant-groups "
                    "for Prototype Demo training"
                )
            if group_kind not in {"source_provided_pseudonymized", "synthetic_similarity_cluster_demo_only"}:
                raise ValueError(f"Unsupported participant group kind at row {row_number}")
            digest = (row.get("sha256") or "").strip().casefold()
            if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
                raise ValueError(f"Invalid content hash at row {row_number}")
            if digest in seen_hashes:
                raise ValueError("Duplicate content hash in training-eligible manifest rows")
            relative_path = Path((row.get("output_path") or "").strip())
            if relative_path.is_absolute() or ".." in relative_path.parts:
                raise ValueError(f"Unsafe image path at row {row_number}")
            image_path = (dataset_root / relative_path).resolve()
            if not image_path.is_relative_to(dataset_root) or not image_path.is_file():
                raise ValueError(f"Missing image at row {row_number}")
            if sha256_file(image_path) != digest:
                raise ValueError(f"Image checksum mismatch at row {row_number}")
            seen_hashes.add(digest)
            samples[tissue].append(MultimodalSample(
                image_path=image_path,
                content_sha256=digest,
                participant_group=participant_group,
                source_key=(row.get("source_key") or "").strip(),
                label_kind=(row.get("label_kind") or "").strip(),
                label=int(label_text),
                participant_group_kind=group_kind,
            ))
    for tissue, tissue_samples in samples.items():
        if not tissue_samples:
            raise ValueError(
                f"{tissue.value} has no training-eligible samples with reviewed permission and participant groups"
            )
    return samples


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def grouped_split(samples: Sequence[MultimodalSample], seed: int) -> dict[str, list[MultimodalSample]]:
    from sklearn.model_selection import GroupShuffleSplit

    labels = np.asarray([sample.label for sample in samples], dtype=np.int64)
    groups = np.asarray([sample.participant_group for sample in samples])
    indices = np.arange(len(samples))
    for attempt in range(SPLIT_ATTEMPTS):
        first = GroupShuffleSplit(n_splits=1, train_size=0.7, random_state=seed + attempt)
        train_indices, remainder_indices = next(first.split(indices, labels, groups))
        remainder_labels = labels[remainder_indices]
        remainder_groups = groups[remainder_indices]
        second = GroupShuffleSplit(n_splits=1, train_size=0.5, random_state=seed + 10_000 + attempt)
        validation_relative, test_relative = next(
            second.split(remainder_indices, remainder_labels, remainder_groups)
        )
        assignments = {
            "train": [samples[index] for index in train_indices],
            "validation": [samples[remainder_indices[index]] for index in validation_relative],
            "test": [samples[remainder_indices[index]] for index in test_relative],
        }
        try:
            validate_grouped_split(assignments)
        except ValueError:
            continue
        return assignments
    raise ValueError("Unable to create participant-grouped train/validation/test splits containing both labels")


def validate_grouped_split(splits: dict[str, list[MultimodalSample]]) -> None:
    expected = {"train", "validation", "test"}
    if set(splits) != expected:
        raise ValueError("Split names must be train, validation, and test")
    hashes = {name: {sample.content_sha256 for sample in values} for name, values in splits.items()}
    groups = {name: {sample.participant_group for sample in values} for name, values in splits.items()}
    for first, second in (("train", "validation"), ("train", "test"), ("validation", "test")):
        if hashes[first] & hashes[second]:
            raise ValueError(f"Content leakage between {first} and {second}")
        if groups[first] & groups[second]:
            raise ValueError(f"Participant leakage between {first} and {second}")
    for name, values in splits.items():
        if {sample.label for sample in values} != {0, 1}:
            raise ValueError(f"{name} split must contain both source proxy labels")


def tissue_transform_specification(tissue: Tissue, training: bool) -> tuple[str, ...]:
    if not training:
        return ("center_crop", "resize") if tissue is Tissue.EYE else ("resize",)
    if tissue is Tissue.EYE:
        return ("random_resized_crop", "horizontal_flip", "rotation_5")
    if tissue is Tissue.NAIL:
        return ("resize", "horizontal_flip", "rotation_12", "affine_translate")
    return ("resize", "horizontal_flip", "rotation_7")


def make_dataset(samples: Sequence[MultimodalSample], tissue: Tissue, *, training: bool) -> Any:
    import torch
    from PIL import Image
    from torch.utils.data import Dataset
    from torchvision.transforms import InterpolationMode
    from torchvision.transforms import v2

    operations: list[Any] = []
    specification = tissue_transform_specification(tissue, training)
    if "random_resized_crop" in specification:
        operations.append(v2.RandomResizedCrop(
            (IMAGE_SIZE, IMAGE_SIZE),
            scale=(0.72, 1.0),
            ratio=(0.85, 1.3),
            interpolation=InterpolationMode.BICUBIC,
            antialias=True,
        ))
    elif "center_crop" in specification:
        operations.extend([
            v2.Resize(IMAGE_SIZE, interpolation=InterpolationMode.BICUBIC, antialias=True),
            v2.CenterCrop((IMAGE_SIZE, IMAGE_SIZE)),
        ])
    else:
        operations.append(v2.Resize(
            (IMAGE_SIZE, IMAGE_SIZE),
            interpolation=InterpolationMode.BICUBIC,
            antialias=True,
        ))
    if "horizontal_flip" in specification:
        operations.append(v2.RandomHorizontalFlip(p=0.5))
    if "rotation_5" in specification:
        operations.append(v2.RandomRotation(5, interpolation=InterpolationMode.BILINEAR))
    if "rotation_7" in specification:
        operations.append(v2.RandomRotation(7, interpolation=InterpolationMode.BILINEAR))
    if "rotation_12" in specification:
        operations.append(v2.RandomRotation(12, interpolation=InterpolationMode.BILINEAR))
    if "affine_translate" in specification:
        operations.append(v2.RandomAffine(0, translate=(0.05, 0.05)))
    operations.extend([v2.ToImage(), v2.ToDtype(torch.float32, scale=True)])
    transform = v2.Compose(operations)

    class TissueDataset(Dataset[Any]):
        def __len__(self) -> int:
            return len(samples)

        def __getitem__(self, index: int) -> tuple[Any, Any]:
            sample = samples[index]
            with Image.open(sample.image_path) as image:
                tensor = transform(image.convert("RGB"))
            return tensor, torch.tensor(float(sample.label), dtype=torch.float32)

    return TissueDataset()


def make_model(pretrained: bool) -> Any:
    import torch
    from torch import nn
    from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

    weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None

    class TissueProxyNetwork(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.backbone = mobilenet_v3_small(weights=weights)
            final_layer = self.backbone.classifier[-1]
            if not isinstance(final_layer, nn.Linear):
                raise TypeError("Unexpected MobileNet classifier layout")
            self.backbone.classifier[-1] = nn.Linear(final_layer.in_features, 1)
            dropout = self.backbone.classifier[-2]
            if not isinstance(dropout, nn.Dropout):
                raise TypeError("Unexpected MobileNet dropout layout")
            dropout.p = DROPOUT_PROBABILITY
            self.register_buffer("channel_mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
            self.register_buffer("channel_std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

        def hidden_features(self, image: Any) -> Any:
            normalized = (image - self.channel_mean) / self.channel_std
            features = self.backbone.features(normalized)
            pooled = self.backbone.avgpool(features)
            flattened = torch.flatten(pooled, 1)
            hidden = self.backbone.classifier[0](flattened)
            return self.backbone.classifier[1](hidden)

        def forward(self, image: Any) -> Any:
            hidden = self.backbone.classifier[2](self.hidden_features(image))
            return self.backbone.classifier[3](hidden).reshape(-1)

        def mc_logits(self, image: Any, masks: Any) -> Any:
            hidden = self.hidden_features(image)
            masked = hidden.unsqueeze(0) * masks.unsqueeze(1)
            return self.backbone.classifier[3](masked).squeeze(-1)

    return TissueProxyNetwork()


def model_hidden_width(model: Any) -> int:
    return int(model.backbone.classifier[-1].in_features)


def mc_dropout_masks(hidden_width: int, seed: int) -> Any:
    import torch

    generator = np.random.default_rng(seed)
    masks = generator.binomial(
        1,
        1.0 - DROPOUT_PROBABILITY,
        size=(MC_DROPOUT_PASSES, hidden_width),
    ).astype(np.float32)
    masks /= 1.0 - DROPOUT_PROBABILITY
    return torch.from_numpy(masks)


def set_determinism(seed: int) -> None:
    import torch

    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)
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


def positive_weight(samples: Sequence[MultimodalSample]) -> float:
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
            logits.append(model(images.to(device)).detach().cpu().numpy().astype(np.float64))
            labels.append(batch_labels.numpy().astype(np.int64))
    return np.concatenate(logits), np.concatenate(labels)


def collect_mc_logits(
    model: Any,
    data_loader: Any,
    device: Any,
    masks: Any,
) -> tuple[NDArray[np.float64], NDArray[np.int64], NDArray[np.float64]]:
    import torch

    model.eval()
    mean_logits: list[NDArray[np.float64]] = []
    pass_logits: list[NDArray[np.float64]] = []
    labels: list[NDArray[np.int64]] = []
    device_masks = masks.to(device)
    with torch.no_grad():
        for images, batch_labels in data_loader:
            batch_pass_logits = model.mc_logits(images.to(device), device_masks)
            pass_values = batch_pass_logits.detach().cpu().numpy().astype(np.float64)
            pass_logits.append(pass_values)
            mean_logits.append(pass_values.mean(axis=0))
            labels.append(batch_labels.numpy().astype(np.int64))
    return np.concatenate(mean_logits), np.concatenate(labels), np.concatenate(pass_logits, axis=1)


def calibrated_mc_statistics(
    pass_logits: NDArray[np.float64],
    slope: float,
    intercept: float,
) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    probabilities = 1.0 / (1.0 + np.exp(-np.clip(pass_logits * slope + intercept, -40, 40)))
    return probabilities.mean(axis=0), probabilities.std(axis=0)


def train_tissue_model(
    configuration: Configuration,
    tissue: Tissue,
    splits: dict[str, list[MultimodalSample]],
    device_name: str,
) -> tuple[Any, dict[str, Any]]:
    import torch

    device = torch.device(device_name)
    model = make_model(configuration.pretrained).to(device)
    train_loader = make_data_loader(
        make_dataset(splits["train"], tissue, training=True),
        configuration.batch_size,
        True,
        configuration.seed,
    )
    validation_loader = make_data_loader(
        make_dataset(splits["validation"], tissue, training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    weight_value = positive_weight(splits["train"])
    loss_function = torch.nn.BCEWithLogitsLoss(
        pos_weight=torch.tensor([weight_value], dtype=torch.float32, device=device)
    )
    optimizer_type = cast(Callable[..., Any], getattr(torch.optim, "Adam"))
    optimizer = optimizer_type(
        model.parameters(),
        lr=configuration.learning_rate,
        weight_decay=configuration.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="max", patience=2, factor=0.5)

    best_auc = -math.inf
    best_state: dict[str, Any] | None = None
    epochs_without_improvement = 0
    history: list[dict[str, float | str]] = []
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
        probabilities = 1.0 / (1.0 + np.exp(-np.clip(validation_logits, -40, 40)))
        validation_metrics = metric_values(probabilities, validation_labels, 0.5)
        scheduler.step(validation_metrics.roc_auc)
        epoch_values: dict[str, float | str] = {
            "tissue": tissue.value,
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
        raise RuntimeError(f"{tissue.value} training did not produce a checkpoint")
    model.load_state_dict(best_state)
    model.eval()
    return model.cpu(), {
        "history": history,
        "bestValidationROC_AUC": best_auc,
        "trainPositiveWeight": weight_value,
        "device": device_name,
    }


def export_core_ml(
    model: Any,
    contract: TissueContract,
    calibration_slope: float,
    calibration_intercept: float,
    threshold: float,
    uncertainty_threshold: float,
    masks: Any,
    configuration: Configuration,
) -> tuple[Path, Any]:
    import coremltools as ct
    import torch
    from torch import nn

    class ExportWrapper(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.model = model
            self.register_buffer("calibration_slope", torch.tensor(calibration_slope, dtype=torch.float32))
            self.register_buffer("calibration_intercept", torch.tensor(calibration_intercept, dtype=torch.float32))
            self.register_buffer("mc_masks", masks.to(dtype=torch.float32))

        def forward(self, image: Any) -> tuple[Any, Any, Any]:
            pass_logits = self.model.mc_logits(image, self.mc_masks)
            raw_logit = pass_logits.mean().reshape(1)
            pass_probabilities = torch.sigmoid(
                pass_logits * self.calibration_slope + self.calibration_intercept
            )
            probability = pass_probabilities.mean().reshape(1)
            centered = pass_probabilities - probability
            uncertainty = torch.sqrt((centered * centered).mean()).reshape(1)
            return raw_logit, probability, uncertainty

    example_input = torch.zeros((1, 3, IMAGE_SIZE, IMAGE_SIZE), dtype=torch.float32)
    trace_model = cast(Callable[[Any, Any], Any], torch.jit.trace)
    traced_model = trace_model(ExportWrapper().eval(), example_input)
    core_ml_model = ct.convert(
        traced_model,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS18,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example_input.shape,
                color_layout=ct.colorlayout.RGB,
                scale=1.0 / 255.0,
                bias=[0.0, 0.0, 0.0],
            )
        ],
        outputs=[
            ct.TensorType(name="raw_proxy_logit", dtype=np.float32),
            ct.TensorType(name="calibrated_proxy_probability", dtype=np.float32),
            ct.TensorType(name="predictive_uncertainty", dtype=np.float32),
        ],
    )
    normalization = compact_json({"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]})
    core_ml_model.user_defined_metadata.update({
        "manifestSchemaVersion": "1",
        "modelIdentifier": contract.model_identifier,
        "semanticVersion": configuration.semantic_version,
        "inputFeatureName": "image",
        "pixelFormat": "32BGRA",
        "colorSpace": "sRGB",
        "normalization": normalization,
        "decisionThreshold": repr(threshold),
        "preprocessingVersion": contract.preprocessing_version,
        "uncertaintyMethod": f"deterministic_mc_dropout_{MC_DROPOUT_PASSES}_masks_p_{DROPOUT_PROBABILITY}",
        "uncertaintyThreshold": repr(uncertainty_threshold),
        "uncertaintyPassCount": str(MC_DROPOUT_PASSES),
    })
    core_ml_model.author = "IronScan research team"
    core_ml_model.license = "See repository and private dataset provenance records"
    core_ml_model.short_description = (
        f"Engineering fixture predicting the {contract.tissue.value.lower()} source proxy class."
    )
    core_ml_model.input_description["image"] = (
        f"Orientation-normalized {contract.tissue.value.lower()} image in sRGB."
    )
    core_ml_model.output_description["raw_proxy_logit"] = "Uncalibrated source-proxy model logit."
    core_ml_model.output_description["calibrated_proxy_probability"] = (
        "Validation-calibrated probability of the source proxy class."
    )
    core_ml_model.output_description["predictive_uncertainty"] = (
        "Predictive standard deviation across the fixed MC-dropout mask ensemble."
    )
    package_path = configuration.output_root / contract.package_name
    if package_path.exists():
        shutil.rmtree(package_path)
    core_ml_model.save(str(package_path))
    return package_path, core_ml_model


def prepared_pil_image(path: Path, tissue: Tissue) -> Any:
    from PIL import Image
    from torchvision.transforms import InterpolationMode
    from torchvision.transforms import v2

    with Image.open(path) as image:
        converted = image.convert("RGB")
        if tissue is Tissue.EYE:
            return v2.Compose([
                v2.Resize(IMAGE_SIZE, interpolation=InterpolationMode.BICUBIC, antialias=True),
                v2.CenterCrop((IMAGE_SIZE, IMAGE_SIZE)),
            ])(converted)
        return v2.Resize(
            (IMAGE_SIZE, IMAGE_SIZE),
            interpolation=InterpolationMode.BICUBIC,
            antialias=True,
        )(converted)


def verify_coreml_parity(
    model: Any,
    core_ml_model: Any,
    tissue: Tissue,
    samples: Sequence[MultimodalSample],
    sample_count: int,
    calibration_slope: float,
    calibration_intercept: float,
    masks: Any,
) -> dict[str, float | int]:
    import torch

    selected = list(samples[: min(sample_count, len(samples))])
    dataset = make_dataset(selected, tissue, training=False)
    maximum_probability_difference = 0.0
    maximum_logit_difference = 0.0
    maximum_uncertainty_difference = 0.0
    for index, sample in enumerate(selected):
        tensor, _ = dataset[index]
        with torch.no_grad():
            pass_logits = model.mc_logits(tensor.unsqueeze(0), masks).detach().cpu().numpy().astype(np.float64)
        pytorch_logit = float(pass_logits.mean())
        expected_probability_values = 1.0 / (1.0 + np.exp(-np.clip(
            pass_logits * calibration_slope + calibration_intercept,
            -40,
            40,
        )))
        expected_probability = float(expected_probability_values.mean())
        expected_uncertainty = float(expected_probability_values.std())
        prediction = core_ml_model.predict({"image": prepared_pil_image(sample.image_path, tissue)})
        coreml_logit = float(np.asarray(prediction["raw_proxy_logit"]).reshape(-1)[0])
        coreml_probability = float(np.asarray(prediction["calibrated_proxy_probability"]).reshape(-1)[0])
        coreml_uncertainty = float(np.asarray(prediction["predictive_uncertainty"]).reshape(-1)[0])
        maximum_logit_difference = max(maximum_logit_difference, abs(pytorch_logit - coreml_logit))
        maximum_probability_difference = max(
            maximum_probability_difference,
            abs(expected_probability - coreml_probability),
        )
        maximum_uncertainty_difference = max(
            maximum_uncertainty_difference,
            abs(expected_uncertainty - coreml_uncertainty),
        )
    if max(maximum_logit_difference, maximum_probability_difference, maximum_uncertainty_difference) > 0.01:
        raise ValueError(
            f"{tissue.value} Core ML parity tolerance exceeded: "
            f"logit={maximum_logit_difference:.6f}, probability={maximum_probability_difference:.6f}, "
            f"uncertainty={maximum_uncertainty_difference:.6f}"
        )
    return {
        "sampleCount": len(selected),
        "maximumLogitAbsoluteDifference": maximum_logit_difference,
        "maximumProbabilityAbsoluteDifference": maximum_probability_difference,
        "maximumUncertaintyAbsoluteDifference": maximum_uncertainty_difference,
    }


def compile_coreml_package(package_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="ironscan-multimodal-compile-") as temporary_directory:
        subprocess.run(
            ["xcrun", "coremlcompiler", "compile", str(package_path), temporary_directory],
            check=True,
            capture_output=True,
            text=True,
        )


def anonymized_split_summary(
    splits: dict[str, list[MultimodalSample]],
    dataset_version: str,
) -> dict[str, Any]:
    def group_hash(group: str) -> str:
        return hashlib.sha256(f"{dataset_version}\0{group}".encode()).hexdigest()

    return {
        split_name: {
            "imageCount": len(samples),
            "positiveProxyCount": sum(sample.label for sample in samples),
            "participantGroupHashes": sorted({group_hash(sample.participant_group) for sample in samples}),
            "contentHashes": sorted(sample.content_sha256 for sample in samples),
            "sourceKeys": sorted({sample.source_key for sample in samples}),
            "labelKinds": sorted({sample.label_kind for sample in samples}),
            "participantGroupKinds": sorted({sample.participant_group_kind for sample in samples}),
        }
        for split_name, samples in splits.items()
    }


def write_model_manifest(
    package_path: Path,
    contract: TissueContract,
    threshold: float,
    uncertainty_threshold: float,
    configuration: Configuration,
) -> Path:
    manifest = {
        "schemaVersion": 1,
        "modelIdentifier": contract.model_identifier,
        "semanticVersion": configuration.semantic_version,
        "sha256": package_sha256(package_path),
        "deploymentStatus": "engineeringFixture",
        "input": {
            "name": "image",
            "dimensions": [1, IMAGE_SIZE, IMAGE_SIZE, 3],
            "dataType": "uint8",
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
        },
        "resize": {"method": contract.resize_method, "interpolation": "vImageHighQuality"},
        "normalization": {"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]},
        "outputs": [
            {"name": "raw_proxy_logit", "dimensions": [1], "dataType": "float32"},
            {"name": "calibrated_proxy_probability", "dimensions": [1], "dataType": "float32"},
            {"name": "predictive_uncertainty", "dimensions": [1], "dataType": "float32"},
        ],
        "decisionThreshold": threshold,
        "uncertaintyThreshold": uncertainty_threshold,
        "uncertaintyPassCount": MC_DROPOUT_PASSES,
        "trainingCommit": configuration.training_commit,
        "datasetVersion": configuration.dataset_version,
        "preprocessingVersion": contract.preprocessing_version,
    }
    manifest_path = configuration.output_root / contract.manifest_name
    write_json(manifest_path, manifest)
    return manifest_path


def install_artifacts(
    package_path: Path,
    manifest_path: Path,
    contract: TissueContract,
    configuration: Configuration,
) -> None:
    package_destination = configuration.repository_root / "Models" / "CoreML" / contract.package_name
    manifest_destination = configuration.repository_root / "Models" / "Manifests" / contract.manifest_name
    if package_destination.exists():
        shutil.rmtree(package_destination)
    if manifest_destination.exists():
        manifest_destination.unlink()
    shutil.copytree(package_path, package_destination)
    shutil.copyfile(manifest_path, manifest_destination)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def train_one_tissue(
    tissue: Tissue,
    samples: Sequence[MultimodalSample],
    configuration: Configuration,
    device_name: str,
) -> dict[str, Any]:
    import torch

    contract = TISSUE_CONTRACTS[tissue]
    splits = grouped_split(samples, configuration.seed + list(Tissue).index(tissue) * 1_000)
    model, training_summary = train_tissue_model(configuration, tissue, splits, device_name)
    masks = mc_dropout_masks(model_hidden_width(model), configuration.seed + list(Tissue).index(tissue) * 1_000)
    validation_loader = make_data_loader(
        make_dataset(splits["validation"], tissue, training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    test_loader = make_data_loader(
        make_dataset(splits["test"], tissue, training=False),
        configuration.batch_size,
        False,
        configuration.seed,
    )
    validation_logits, validation_labels, validation_pass_logits = collect_mc_logits(
        model,
        validation_loader,
        torch.device("cpu"),
        masks,
    )
    calibration_slope, calibration_intercept = fit_probability_calibration(
        validation_logits,
        validation_labels,
        configuration.seed,
    )
    validation_probabilities, validation_uncertainties = calibrated_mc_statistics(
        validation_pass_logits,
        calibration_slope,
        calibration_intercept,
    )
    uncertainty_threshold = float(np.quantile(validation_uncertainties, UNCERTAINTY_QUANTILE))
    locked_threshold = select_locked_threshold(validation_probabilities, validation_labels)
    validation_metrics = metric_values(validation_probabilities, validation_labels, locked_threshold)
    _, test_labels, test_pass_logits = collect_mc_logits(
        model,
        test_loader,
        torch.device("cpu"),
        masks,
    )
    test_probabilities, test_uncertainties = calibrated_mc_statistics(
        test_pass_logits,
        calibration_slope,
        calibration_intercept,
    )
    test_metrics = metric_values(test_probabilities, test_labels, locked_threshold)
    torch.save(
        {
            "stateDict": model.state_dict(),
            "tissue": tissue.value,
            "semanticVersion": configuration.semantic_version,
            "datasetVersion": configuration.dataset_version,
        },
        configuration.output_root / f"{tissue.value.casefold()}_checkpoint.pt",
    )

    package_path, core_ml_model = export_core_ml(
        model,
        contract,
        calibration_slope,
        calibration_intercept,
        locked_threshold,
        uncertainty_threshold,
        masks,
        configuration,
    )
    parity = verify_coreml_parity(
        model,
        core_ml_model,
        tissue,
        splits["test"],
        configuration.parity_sample_count,
        calibration_slope,
        calibration_intercept,
        masks,
    )
    compile_coreml_package(package_path)
    manifest_path = write_model_manifest(
        package_path,
        contract,
        locked_threshold,
        uncertainty_threshold,
        configuration,
    )
    if configuration.install:
        install_artifacts(package_path, manifest_path, contract, configuration)
    summary = {
        "tissue": tissue.value,
        "modelIdentifier": contract.model_identifier,
        "package": str(package_path),
        "manifest": str(manifest_path),
        "deploymentStatus": "engineeringFixture",
        "lockedThreshold": locked_threshold,
        "calibration": {"slope": calibration_slope, "intercept": calibration_intercept},
        "validationMetrics": asdict(validation_metrics),
        "testMetrics": asdict(test_metrics),
        "uncertainty": {
            "method": "deterministic_fixed-mask_mc_dropout",
            "dropoutProbability": DROPOUT_PROBABILITY,
            "passes": MC_DROPOUT_PASSES,
            "validationQuantile": UNCERTAINTY_QUANTILE,
            "lockedStandardDeviationThreshold": uncertainty_threshold,
            "validationMeanStandardDeviation": float(validation_uncertainties.mean()),
            "testMeanStandardDeviation": float(test_uncertainties.mean()),
        },
        "coreMLParity": parity,
        "training": training_summary,
        "splits": anonymized_split_summary(splits, configuration.dataset_version),
        "limitations": [
            "Eye uses a laboratory-hemoglobin anemia-screening label; nail and tongue use source proxy labels.",
            "Hemoglobin-only labels do not establish iron-deficiency anemia.",
            "The package remains an engineering fixture until external and device validation are complete.",
            "Appearance-similarity groups reduce duplicate leakage but do not establish participant independence.",
            "Core ML uses 30 fixed Bernoulli masks so uncertainty is reproducible; repeated package calls are not "
            "new stochastic draws.",
        ],
    }
    write_json(configuration.output_root / f"{tissue.value.casefold()}_training_summary.json", summary)
    return summary


def run(configuration: Configuration) -> None:
    if configuration.output_root.exists():
        shutil.rmtree(configuration.output_root)
    configuration.output_root.mkdir(parents=True)
    set_determinism(configuration.seed)
    samples_by_tissue = read_samples(
        configuration.dataset_root,
        configuration.allow_synthetic_participant_groups,
    )
    device_name = resolve_device(configuration.device)
    summaries: dict[str, Any] = {}
    for tissue in configuration.tissues:
        tissue_samples = samples_by_tissue[tissue]
        if tissue is Tissue.EYE:
            clinical_samples = [sample for sample in tissue_samples if sample.label_kind == CLINICAL_EYE_LABEL_KIND]
            if clinical_samples:
                tissue_samples = clinical_samples
        summaries[tissue.value] = train_one_tissue(
            tissue,
            tissue_samples,
            configuration,
            device_name,
        )
    suite_summary = {
        "semanticVersion": configuration.semantic_version,
        "datasetVersion": configuration.dataset_version,
        "trainingCommit": configuration.training_commit,
        "installedInRepository": configuration.install,
        "models": summaries,
        "researchUseOnly": True,
    }
    write_json(configuration.output_root / "suite_summary.json", suite_summary)
    print(json.dumps(suite_summary, indent=2, sort_keys=True))


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
