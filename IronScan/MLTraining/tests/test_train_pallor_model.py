from pathlib import Path

import numpy as np

from MLTraining.scripts.train_pallor_model import (
    FoldObservation,
    PallorSample,
    build_splits,
    compute_positive_weight,
    metric_values,
    select_precision_recall_threshold,
)


def test_ambiguous_content_is_excluded_from_predefined_splits(tmp_path: Path) -> None:
    master_samples = {
        "a": (make_image(tmp_path, "a"), 0),
        "b": (make_image(tmp_path, "b"), 1),
        "c": (make_image(tmp_path, "c"), 0),
        "d": (make_image(tmp_path, "d"), 1),
        "e": (make_image(tmp_path, "e"), 0),
        "f": (make_image(tmp_path, "f"), 1),
        "ambiguous": (make_image(tmp_path, "ambiguous"), 0),
    }
    observations = {
        "a": {FoldObservation("train", "train-negative", 0)},
        "b": {FoldObservation("train", "train-positive", 1)},
        "c": {FoldObservation("validation", "validation-negative", 0)},
        "d": {FoldObservation("validation", "validation-positive", 1)},
        "e": {FoldObservation("test", "test-negative", 0)},
        "f": {FoldObservation("test", "test-positive", 1)},
        "ambiguous": {
            FoldObservation("train", "duplicate", 0),
            FoldObservation("validation", "duplicate", 0),
        },
    }

    splits, exclusions = build_splits(master_samples, observations)

    assert exclusions == {"cross_split_duplicate_content": 1}
    assert {name: len(samples) for name, samples in splits.items()} == {
        "train": 2,
        "validation": 2,
        "test": 2,
    }


def test_positive_weight_uses_training_distribution_only(tmp_path: Path) -> None:
    samples = [make_sample(tmp_path, index, 0) for index in range(7)]
    samples.append(make_sample(tmp_path, 8, 1))

    assert compute_positive_weight(samples) == 7.0


def test_metrics_include_confusion_matrix_and_screening_statistics() -> None:
    probabilities = np.array([0.1, 0.8, 0.7, 0.2], dtype=np.float64)
    labels = np.array([0, 1, 0, 1], dtype=np.int64)

    metrics = metric_values(probabilities, labels, threshold=0.5)

    assert metrics.confusion_matrix == [[1, 1], [1, 1]]
    assert metrics.precision == 0.5
    assert metrics.recall == 0.5
    assert metrics.f1_score == 0.5


def test_threshold_selection_optimizes_precision_recall_f1() -> None:
    probabilities = np.array([0.1, 0.2, 0.6, 0.7], dtype=np.float64)
    labels = np.array([0, 1, 0, 1], dtype=np.int64)

    threshold = select_precision_recall_threshold(probabilities, labels)
    metrics = metric_values(probabilities, labels, threshold)

    assert metrics.f1_score == 0.8
    assert metrics.precision == 2 / 3
    assert metrics.recall == 1.0


def make_image(tmp_path: Path, name: str) -> Path:
    path = tmp_path / f"{name}.jpg"
    path.write_bytes(name.encode())
    return path


def make_sample(tmp_path: Path, index: int, label: int) -> PallorSample:
    return PallorSample(
        image_path=make_image(tmp_path, str(index)),
        content_sha256=f"{index:064x}",
        participant_group=f"group-{index}",
        label=label,
    )
