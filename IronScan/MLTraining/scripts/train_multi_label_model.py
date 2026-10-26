#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Final, Sequence, cast

import numpy as np
from numpy.typing import NDArray

from MLTraining.scripts.train_and_convert import (
    calibrated_probabilities,
    compact_json,
    current_git_commit,
    fit_probability_calibration,
    package_sha256,
    repository_is_dirty,
    select_locked_threshold,
)
from MLTraining.scripts.train_pallor_model import (
    IMAGE_SIZE,
    FOLD_FILES,
    compile_coreml_package,
    make_data_loader,
    metric_values,
    read_master_manifest,
    resolve_device,
    set_determinism,
    sha256_file,
)

LABEL_NAMES: Final = ("TonguePale", "Toothmark", "Crack", "TipSideRed", "FurThick")
MODEL_IDENTIFIER: Final = "org.ironscan.engineering.tongue-attributes"
MODEL_FILENAME: Final = "IronScanMultiScreen.mlpackage"
INPUT_NAME: Final = "image"
RAW_OUTPUT_NAME: Final = "raw_attribute_logits"
PROBABILITY_OUTPUT_NAME: Final = "calibrated_attribute_probabilities"
OUTPUT_NAMES: Final = (
    "tongue_pale_probability",
    "toothmark_probability",
    "crack_probability",
    "tip_side_red_probability",
    "fur_thick_probability",
)
MANIFEST_FILENAME: Final = "multi_screen_manifest.json"
PREPROCESSING_VERSION: Final = "1.0.0"
DEFAULT_SEED: Final = 20260720
FloatArray = NDArray[np.float64]
IntArray = NDArray[np.int64]


@dataclass(frozen=True)
class Configuration:
    master_root: Path
    tonguedx_root: Path
    output_directory: Path
    coreml_destination: Path
    manifest_destination: Path
    semantic_version: str
    dataset_version: str
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
class MultiLabelSample:
    image_path: Path
    content_sha256: str
    participant_group: str
    labels: tuple[int, ...]


@dataclass(frozen=True)
class FoldObservation:
    split: str
    participant_group: str
    labels: tuple[int, ...]


def parse_arguments() -> Configuration:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description=(
            "Train an engineering model for five visual tongue annotations. Outputs do not establish diseases, "
            "nutrient deficiencies, hydration status, inflammation, or oral-health conditions."
        )
    )
    parser.add_argument("--master-root", type=Path, default=Path.home() / "Documents/IronScanMasterDataset")
    parser.add_argument(
        "--tonguedx-root",
        type=Path,
        default=Path.home() / "Documents/IronScanPrivate/TongueDx2",
    )
    parser.add_argument(
        "--coreml-destination",
        type=Path,
        default=repository_root / "Models/CoreML" / MODEL_FILENAME,
    )
    parser.add_argument(
        "--manifest-destination",
        type=Path,
        default=repository_root / "Models/Manifests" / MANIFEST_FILENAME,
    )
    parser.add_argument("--semantic-version", default="0.1.0-engineering.1")
    parser.add_argument("--dataset-version", default="tonguedx2-five-visual-attributes-fold1-v1")
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=Path.home() / "Documents/IronScanPrivate/TrainingArtifacts/multi-label-v0.1.0",
    )
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
    if not (configuration.tonguedx_root / "release/list").is_dir():
        raise ValueError("TongueDX fold metadata directory is missing")
    if configuration.epochs < 1 or configuration.patience < 1 or configuration.batch_size < 1:
        raise ValueError("Epochs, patience, and batch size must be positive")
    if configuration.learning_rate <= 0 or configuration.weight_decay < 0:
        raise ValueError("Learning rate must be positive and weight decay cannot be negative")
    if not configuration.allow_dirty and repository_is_dirty():
        raise ValueError("Training requires a clean Git worktree or --allow-dirty")
    if configuration.parity_sample_count < 1:
        raise ValueError("Parity sample count must be positive")
    if configuration.coreml_destination.exists() and not configuration.replace_existing:
        raise ValueError("Core ML destination exists; pass --replace-existing to replace it")
    if configuration.manifest_destination.exists() and not configuration.replace_existing:
        raise ValueError("Model manifest destination exists; pass --replace-existing to replace it")


def read_fold_observations(
    tonguedx_root: Path,
    eligible_hashes: set[str],
) -> dict[str, set[FoldObservation]]:
    observations: dict[str, set[FoldObservation]] = defaultdict(set)
    source_root = (tonguedx_root / "release/origin").resolve()
    required = {"id", "image_path", *LABEL_NAMES}
    for split, filename in FOLD_FILES.items():
        csv_path = tonguedx_root / "release/list" / filename
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
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
                values = tuple(int((row.get(name) or "").strip()) for name in LABEL_NAMES)
                if not participant_group or any(value not in (0, 1) for value in values):
                    raise ValueError(f"Invalid visual annotation in {filename} row {row_number}")
                observations[digest].add(FoldObservation(split, participant_group, values))
    return observations


def build_splits(
    master_images: dict[str, Path],
    observations: dict[str, set[FoldObservation]],
) -> tuple[dict[str, list[MultiLabelSample]], dict[str, int]]:
    if set(master_images) != set(observations):
        raise ValueError("Fold metadata does not cover every eligible master image")
    splits: dict[str, list[MultiLabelSample]] = {name: [] for name in FOLD_FILES}
    exclusions: Counter[str] = Counter()
    for digest, metadata in sorted(observations.items()):
        split_names = {item.split for item in metadata}
        groups = {item.participant_group for item in metadata}
        labels = {item.labels for item in metadata}
        if len(split_names) != 1:
            exclusions["cross_split_duplicate_content"] += 1
            continue
        if len(groups) != 1:
            exclusions["ambiguous_participant_group"] += 1
            continue
        if len(labels) != 1:
            exclusions["conflicting_visual_annotations"] += 1
            continue
        split = next(iter(split_names))
        splits[split].append(
            MultiLabelSample(master_images[digest], digest, next(iter(groups)), next(iter(labels)))
        )
    validate_splits(splits)
    return splits, dict(sorted(exclusions.items()))


def validate_splits(splits: dict[str, list[MultiLabelSample]]) -> None:
    hashes = {name: {sample.content_sha256 for sample in samples} for name, samples in splits.items()}
    groups = {name: {sample.participant_group for sample in samples} for name, samples in splits.items()}
    for first, second in (("train", "validation"), ("train", "test"), ("validation", "test")):
        if hashes[first] & hashes[second]:
            raise ValueError(f"Content leakage between {first} and {second}")
        if groups[first] & groups[second]:
            raise ValueError(f"Participant leakage between {first} and {second}")
    for split, samples in splits.items():
        labels = np.asarray([sample.labels for sample in samples], dtype=np.int64)
        if labels.shape[1:] != (len(LABEL_NAMES),):
            raise ValueError(f"Invalid label shape in {split}")
        if any(len(np.unique(labels[:, index])) != 2 for index in range(len(LABEL_NAMES))):
            raise ValueError(f"Every {split} label must contain both classes")


def load_splits(configuration: Configuration) -> tuple[dict[str, list[MultiLabelSample]], dict[str, int]]:
    pallor_manifest = read_master_manifest(configuration.master_root)
    master_images = {digest: image_path for digest, (image_path, _) in pallor_manifest.items()}
    observations = read_fold_observations(configuration.tonguedx_root, set(master_images))
    return build_splits(master_images, observations)


def make_dataset(samples: Sequence[MultiLabelSample], *, training: bool) -> Any:
    import torch
    from PIL import Image
    from torch.utils.data import Dataset
    from torchvision.transforms import InterpolationMode
    from torchvision.transforms import v2

    transforms: list[Any] = [
        v2.ToImage(),
        v2.Resize((IMAGE_SIZE, IMAGE_SIZE), interpolation=InterpolationMode.BICUBIC, antialias=True),
    ]
    if training:
        transforms.extend(
            [
                v2.RandomHorizontalFlip(p=0.5),
                v2.RandomRotation(degrees=10, interpolation=InterpolationMode.BILINEAR),
                v2.RandomAffine(
                    degrees=0,
                    translate=(0.04, 0.04),
                    scale=(0.92, 1.0),
                    interpolation=InterpolationMode.BILINEAR,
                ),
            ]
        )
    transforms.append(v2.ToDtype(torch.float32, scale=True))
    transform = v2.Compose(transforms)

    class MultiLabelDataset(Dataset[Any]):
        def __len__(self) -> int:
            return len(samples)

        def __getitem__(self, index: int) -> tuple[Any, Any]:
            sample = samples[index]
            with Image.open(sample.image_path) as image:
                tensor = transform(image.convert("RGB"))
            return tensor, torch.tensor(sample.labels, dtype=torch.float32)

    return MultiLabelDataset()


def make_model(pretrained: bool) -> Any:
    import torch
    from torch import nn
    from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

    weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None

    class MultiLabelNetwork(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.backbone = mobilenet_v3_small(weights=weights)
            final_layer = self.backbone.classifier[-1]
            if not isinstance(final_layer, nn.Linear):
                raise TypeError("Unexpected MobileNet classifier layout")
            self.backbone.classifier[-1] = nn.Linear(final_layer.in_features, len(LABEL_NAMES))
            self.register_buffer("channel_mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
            self.register_buffer("channel_std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

        def forward(self, image: Any) -> Any:
            return self.backbone((image - self.channel_mean) / self.channel_std)

    return MultiLabelNetwork()


def compute_positive_weights(label_matrix: IntArray) -> FloatArray:
    if label_matrix.ndim != 2 or label_matrix.shape[1] != len(LABEL_NAMES):
        raise ValueError("Expected an N by 5 binary label matrix")
    positives = label_matrix.sum(axis=0)
    negatives = label_matrix.shape[0] - positives
    if np.any(positives == 0) or np.any(negatives == 0):
        raise ValueError("Every training label must contain both classes")
    return np.asarray(negatives.astype(np.float64) / positives.astype(np.float64), dtype=np.float64)


def collect_logits(model: Any, data_loader: Any, device: Any) -> tuple[FloatArray, IntArray]:
    import torch

    model.eval()
    logits: list[FloatArray] = []
    labels: list[IntArray] = []
    with torch.no_grad():
        for images, batch_labels in data_loader:
            logits.append(model(images.to(device)).detach().cpu().numpy().astype(np.float64))
            labels.append(batch_labels.numpy().astype(np.int64))
    return np.concatenate(logits), np.concatenate(labels)


def train_model(
    configuration: Configuration,
    splits: dict[str, list[MultiLabelSample]],
    device_name: str,
) -> tuple[Any, dict[str, Any]]:
    import torch
    from torch.optim.adam import Adam

    device = torch.device(device_name)
    model = make_model(configuration.pretrained).to(device)
    train_loader = make_data_loader(
        make_dataset(splits["train"], training=True), configuration.batch_size, True, configuration.seed
    )
    validation_loader = make_data_loader(
        make_dataset(splits["validation"], training=False), configuration.batch_size, False, configuration.seed
    )
    train_labels = np.asarray([sample.labels for sample in splits["train"]], dtype=np.int64)
    positive_weights = compute_positive_weights(train_labels)
    loss_function = torch.nn.BCEWithLogitsLoss(
        pos_weight=torch.tensor(positive_weights, dtype=torch.float32, device=device)
    )
    optimizer = Adam(model.parameters(), lr=configuration.learning_rate, weight_decay=configuration.weight_decay)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="max", patience=2, factor=0.5)
    best_macro_auc = -math.inf
    best_state: dict[str, Any] | None = None
    epochs_without_improvement = 0
    history: list[dict[str, Any]] = []
    for epoch in range(1, configuration.epochs + 1):
        model.train()
        total_loss = 0.0
        total_examples = 0
        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            loss = loss_function(model(images), labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach().cpu()) * labels.shape[0]
            total_examples += labels.shape[0]
        validation_logits, validation_labels = collect_logits(model, validation_loader, device)
        probabilities = 1.0 / (1.0 + np.exp(-np.clip(validation_logits, -40, 40)))
        aucs = [metric_values(probabilities[:, index], validation_labels[:, index], 0.5).roc_auc for index in range(5)]
        macro_auc = float(np.mean(aucs))
        scheduler.step(macro_auc)
        epoch_report = {
            "epoch": epoch,
            "trainLoss": total_loss / max(total_examples, 1),
            "validationMacroROC_AUC": macro_auc,
            "validationROC_AUCByLabel": dict(zip(LABEL_NAMES, aucs, strict=True)),
            "learningRate": float(optimizer.param_groups[0]["lr"]),
        }
        history.append(epoch_report)
        print(json.dumps(epoch_report, sort_keys=True), flush=True)
        if macro_auc > best_macro_auc + 1e-6:
            best_macro_auc = macro_auc
            best_state = {name: value.detach().cpu().clone() for name, value in model.state_dict().items()}
            epochs_without_improvement = 0
        else:
            epochs_without_improvement += 1
        if epochs_without_improvement >= configuration.patience:
            break
    if best_state is None:
        raise RuntimeError("Training did not produce a checkpoint")
    model.load_state_dict(best_state)
    return model.cpu().eval(), {
        "history": history,
        "bestValidationMacroROC_AUC": best_macro_auc,
        "trainPositiveWeights": dict(zip(LABEL_NAMES, positive_weights.tolist(), strict=True)),
        "device": device_name,
    }


def fit_per_label_calibration(
    logits: FloatArray,
    labels: IntArray,
    seed: int,
) -> tuple[FloatArray, FloatArray, FloatArray, FloatArray]:
    slopes: list[float] = []
    intercepts: list[float] = []
    probabilities = np.empty_like(logits, dtype=np.float64)
    thresholds: list[float] = []
    for index in range(len(LABEL_NAMES)):
        slope, intercept = fit_probability_calibration(logits[:, index], labels[:, index], seed)
        calibrated = calibrated_probabilities(logits[:, index], slope, intercept)
        slopes.append(slope)
        intercepts.append(intercept)
        probabilities[:, index] = calibrated
        thresholds.append(select_locked_threshold(calibrated, labels[:, index]))
    return np.asarray(slopes), np.asarray(intercepts), probabilities, np.asarray(thresholds)


def evaluate_labels(
    probabilities: FloatArray,
    labels: IntArray,
    thresholds: FloatArray,
) -> dict[str, Any]:
    return {
        name: asdict(metric_values(probabilities[:, index], labels[:, index], float(thresholds[index])))
        for index, name in enumerate(LABEL_NAMES)
    }


def export_core_ml(
    model: Any,
    slopes: FloatArray,
    intercepts: FloatArray,
    thresholds: FloatArray,
    configuration: Configuration,
) -> tuple[Path, Any]:
    import coremltools as ct
    import torch
    from torch import nn

    class ExportWrapper(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.attribute_model = model
            self.register_buffer("calibration_slopes", torch.tensor(slopes, dtype=torch.float32))
            self.register_buffer("calibration_intercepts", torch.tensor(intercepts, dtype=torch.float32))

        def forward(self, image: Any) -> tuple[Any, ...]:
            logits = self.attribute_model(image).reshape(len(LABEL_NAMES))
            probabilities = torch.sigmoid(logits * self.calibration_slopes + self.calibration_intercepts)
            return tuple(probabilities[index : index + 1] for index in range(len(LABEL_NAMES)))

    example_input = torch.zeros((1, 3, IMAGE_SIZE, IMAGE_SIZE), dtype=torch.float32)
    trace = cast(Any, torch.jit.trace)
    traced = trace(ExportWrapper().eval(), example_input)
    core_ml_model = ct.convert(
        traced,
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
        outputs=[ct.TensorType(name=name, dtype=np.float32) for name in OUTPUT_NAMES],
    )
    core_ml_model.user_defined_metadata.update(
        {
            "modelIdentifier": MODEL_IDENTIFIER,
            "manifestSchemaVersion": "1",
            "semanticVersion": configuration.semantic_version,
            "inputFeatureName": INPUT_NAME,
            "visualAttributeNames": compact_json(list(LABEL_NAMES)),
            "decisionThresholds": compact_json(
                dict(zip(OUTPUT_NAMES, thresholds.tolist(), strict=True))
            ),
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
            "preprocessingVersion": PREPROCESSING_VERSION,
            "normalization": compact_json({"kind": "scale", "scale": 1.0 / 255.0, "biases": [0, 0, 0]}),
        }
    )
    core_ml_model.short_description = "Engineering fixture for five source-dataset visual tongue annotations."
    for output_name, label_name in zip(OUTPUT_NAMES, LABEL_NAMES, strict=True):
        core_ml_model.output_description[output_name] = f"Calibrated probability for visual annotation {label_name}."
    output_path = configuration.output_directory / MODEL_FILENAME
    if output_path.exists():
        shutil.rmtree(output_path)
    core_ml_model.save(str(output_path))
    return output_path, core_ml_model


def verify_coreml_parity(
    model: Any,
    core_ml_model: Any,
    samples: Sequence[MultiLabelSample],
    slopes: FloatArray,
    intercepts: FloatArray,
    sample_count: int,
) -> dict[str, Any]:
    import torch
    from PIL import Image

    selected = list(samples[: min(sample_count, len(samples))])
    dataset = make_dataset(selected, training=False)
    maximum_differences = np.zeros(len(LABEL_NAMES), dtype=np.float64)
    for index, sample in enumerate(selected):
        tensor, _ = dataset[index]
        with torch.no_grad():
            logits = model(tensor.unsqueeze(0)).reshape(-1).numpy().astype(np.float64)
        expected = 1.0 / (1.0 + np.exp(-np.clip(logits * slopes + intercepts, -40, 40)))
        with Image.open(sample.image_path) as image:
            resized = image.convert("RGB").resize((IMAGE_SIZE, IMAGE_SIZE), resample=Image.Resampling.BICUBIC)
            prediction = core_ml_model.predict({INPUT_NAME: resized})
        actual = np.asarray(
            [float(np.asarray(prediction[name]).reshape(-1)[0]) for name in OUTPUT_NAMES],
            dtype=np.float64,
        )
        maximum_differences = np.maximum(maximum_differences, np.abs(expected - actual))
    if np.any(maximum_differences > 0.01):
        raise ValueError("Multi-label Core ML parity tolerance exceeded")
    return {
        "sampleCount": len(selected),
        "maximumProbabilityAbsoluteDifference": dict(
            zip(LABEL_NAMES, maximum_differences.tolist(), strict=True)
        ),
    }


def write_model_manifest(
    package_path: Path,
    thresholds: FloatArray,
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
            {"name": name, "dimensions": [1], "dataType": "float32"}
            for name in OUTPUT_NAMES
        ],
        "decisionThresholds": dict(zip(OUTPUT_NAMES, thresholds.tolist(), strict=True)),
        "trainingCommit": current_git_commit(),
        "datasetVersion": configuration.dataset_version,
        "preprocessingVersion": PREPROCESSING_VERSION,
    }
    manifest_path = configuration.output_directory / MANIFEST_FILENAME
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest_path


def install_artifacts(package_path: Path, manifest_path: Path, configuration: Configuration) -> None:
    configuration.coreml_destination.parent.mkdir(parents=True, exist_ok=True)
    configuration.manifest_destination.parent.mkdir(parents=True, exist_ok=True)
    if configuration.coreml_destination.exists():
        shutil.rmtree(configuration.coreml_destination)
    if configuration.manifest_destination.exists():
        configuration.manifest_destination.unlink()
    shutil.copytree(package_path, configuration.coreml_destination)
    shutil.copyfile(manifest_path, configuration.manifest_destination)


def run(configuration: Configuration) -> None:
    import torch

    configuration.output_directory.mkdir(parents=True, exist_ok=True)
    set_determinism(configuration.seed)
    splits, exclusions = load_splits(configuration)
    device_name = resolve_device(configuration.device)
    model, training_report = train_model(configuration, splits, device_name)
    validation_loader = make_data_loader(
        make_dataset(splits["validation"], training=False), configuration.batch_size, False, configuration.seed
    )
    test_loader = make_data_loader(
        make_dataset(splits["test"], training=False), configuration.batch_size, False, configuration.seed
    )
    validation_logits, validation_labels = collect_logits(model, validation_loader, torch.device("cpu"))
    slopes, intercepts, validation_probabilities, thresholds = fit_per_label_calibration(
        validation_logits, validation_labels, configuration.seed
    )
    test_logits, test_labels = collect_logits(model, test_loader, torch.device("cpu"))
    test_probabilities = np.column_stack(
        [
            calibrated_probabilities(test_logits[:, index], float(slopes[index]), float(intercepts[index]))
            for index in range(len(LABEL_NAMES))
        ]
    )
    checkpoint_path = configuration.output_directory / "multi_label_checkpoint.pt"
    torch.save(
        {
            "state_dict": model.state_dict(),
            "label_names": LABEL_NAMES,
            "calibration_slopes": slopes,
            "calibration_intercepts": intercepts,
            "decision_thresholds": thresholds,
            "training_commit": current_git_commit(),
        },
        checkpoint_path,
    )
    package_path, core_ml_model = export_core_ml(model, slopes, intercepts, thresholds, configuration)
    parity = verify_coreml_parity(
        model,
        core_ml_model,
        splits["test"],
        slopes,
        intercepts,
        configuration.parity_sample_count,
    )
    compile_coreml_package(package_path)
    manifest_path = write_model_manifest(package_path, thresholds, configuration)
    install_artifacts(package_path, manifest_path, configuration)
    report = {
        **training_report,
        "labels": list(LABEL_NAMES),
        "splitCounts": {name: len(samples) for name, samples in splits.items()},
        "excludedAmbiguousContent": exclusions,
        "calibration": {
            "method": "per-label Platt scaling",
            "slopes": dict(zip(LABEL_NAMES, slopes.tolist(), strict=True)),
            "intercepts": dict(zip(LABEL_NAMES, intercepts.tolist(), strict=True)),
            "lockedThresholds": dict(zip(LABEL_NAMES, thresholds.tolist(), strict=True)),
        },
        "validation": evaluate_labels(validation_probabilities, validation_labels, thresholds),
        "test": evaluate_labels(test_probabilities, test_labels, thresholds),
        "deploymentStatus": "engineeringFixture",
        "semanticVersion": configuration.semantic_version,
        "datasetVersion": configuration.dataset_version,
        "coreMLParity": parity,
        "augmentations": ["randomHorizontalFlip", "randomRotation10Degrees", "randomAffineCrop"],
        "excludedAugmentations": ["colorJitter excluded because color is a visual target signal"],
        "repositoryDirtyDuringTraining": repository_is_dirty(),
        "limitations": [
            "Outputs reproduce source-dataset visual annotations only.",
            "Outputs do not establish diseases, nutrient deficiencies, hydration status, inflammation, or oral health.",
            "Independent cohort and standardized physical-device validation remain required.",
        ],
    }
    (configuration.output_directory / "evaluation_metrics.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("\nValidation visual-attribute summary", flush=True)
    for label_name, metrics in report["validation"].items():
        print(
            f"{label_name}: ROC-AUC={metrics['roc_auc']:.4f} "
            f"Precision={metrics['precision']:.4f} Recall={metrics['recall']:.4f} "
            f"F1={metrics['f1_score']:.4f}",
            flush=True,
        )


def main() -> None:
    run(parse_arguments())


if __name__ == "__main__":
    main()
