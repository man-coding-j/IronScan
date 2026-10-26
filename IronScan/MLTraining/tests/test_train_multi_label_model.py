from pathlib import Path

import numpy as np

from MLTraining.scripts.train_multi_label_model import (
    FoldObservation,
    MultiLabelSample,
    build_splits,
    compute_positive_weights,
)


def test_positive_weights_are_computed_per_visual_attribute() -> None:
    labels = np.asarray(
        [
            [0, 0, 0, 0, 0],
            [0, 1, 0, 1, 0],
            [0, 0, 1, 0, 1],
            [1, 0, 0, 0, 0],
        ],
        dtype=np.int64,
    )

    assert np.allclose(compute_positive_weights(labels), [3, 3, 3, 3, 3])


def test_multi_label_splits_exclude_cross_split_duplicate_content(tmp_path: Path) -> None:
    all_zero = (0, 0, 0, 0, 0)
    all_one = (1, 1, 1, 1, 1)
    master_images = {
        "train-zero": make_image(tmp_path, "train-zero"),
        "train-one": make_image(tmp_path, "train-one"),
        "validation-zero": make_image(tmp_path, "validation-zero"),
        "validation-one": make_image(tmp_path, "validation-one"),
        "test-zero": make_image(tmp_path, "test-zero"),
        "test-one": make_image(tmp_path, "test-one"),
        "duplicate": make_image(tmp_path, "duplicate"),
    }
    observations = {
        "train-zero": {FoldObservation("train", "train-zero", all_zero)},
        "train-one": {FoldObservation("train", "train-one", all_one)},
        "validation-zero": {FoldObservation("validation", "validation-zero", all_zero)},
        "validation-one": {FoldObservation("validation", "validation-one", all_one)},
        "test-zero": {FoldObservation("test", "test-zero", all_zero)},
        "test-one": {FoldObservation("test", "test-one", all_one)},
        "duplicate": {
            FoldObservation("train", "duplicate", all_zero),
            FoldObservation("validation", "duplicate", all_zero),
        },
    }

    splits, exclusions = build_splits(master_images, observations)

    assert exclusions == {"cross_split_duplicate_content": 1}
    assert {name: len(samples) for name, samples in splits.items()} == {
        "train": 2,
        "validation": 2,
        "test": 2,
    }
    assert all(isinstance(sample, MultiLabelSample) for samples in splits.values() for sample in samples)


def make_image(tmp_path: Path, name: str) -> Path:
    path = tmp_path / f"{name}.jpg"
    path.write_bytes(name.encode())
    return path
