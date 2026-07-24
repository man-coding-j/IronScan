from __future__ import annotations

import csv
from pathlib import Path

import pytest

from MLTraining.scripts.train_multimodal_suite import (
    DROPOUT_PROBABILITY,
    MC_DROPOUT_PASSES,
    MultimodalSample,
    TISSUE_CONTRACTS,
    Tissue,
    grouped_split,
    mc_dropout_masks,
    positive_weight,
    read_samples,
    tissue_transform_specification,
    validate_grouped_split,
)


def test_grouped_split_is_deterministic_and_has_no_participant_leakage(tmp_path: Path) -> None:
    samples = [make_sample(tmp_path, index, index % 2) for index in range(40)]

    first = grouped_split(samples, seed=20260721)
    second = grouped_split(list(samples), seed=20260721)

    assert {
        name: [sample.content_sha256 for sample in values]
        for name, values in first.items()
    } == {
        name: [sample.content_sha256 for sample in values]
        for name, values in second.items()
    }
    validate_grouped_split(first)
    assert sum(len(values) for values in first.values()) == len(samples)


def test_grouped_split_rejects_participant_leakage(tmp_path: Path) -> None:
    negative = make_sample(tmp_path, 0, 0)
    positive = make_sample(tmp_path, 1, 1)
    leaked = MultimodalSample(
        image_path=positive.image_path,
        content_sha256="f" * 64,
        participant_group=negative.participant_group,
        source_key=positive.source_key,
        label_kind=positive.label_kind,
        label=positive.label,
    )
    splits = {
        "train": [negative, positive],
        "validation": [leaked, make_sample(tmp_path, 2, 0)],
        "test": [make_sample(tmp_path, 3, 0), make_sample(tmp_path, 4, 1)],
    }

    with pytest.raises(ValueError, match="Participant leakage"):
        validate_grouped_split(splits)


def test_training_eligible_manifest_row_requires_participant_group(tmp_path: Path) -> None:
    manifest = tmp_path / "dataset_manifest.csv"
    columns = [
        "output_path",
        "tissue",
        "target_value",
        "source_key",
        "label_kind",
        "participant_group",
        "participant_group_kind",
        "training_eligible",
        "sha256",
    ]
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerow({
            "output_path": "Eye/anemic/test.jpg",
            "tissue": "Eye",
            "target_value": "1",
            "source_key": "test",
            "label_kind": "source_repository_proxy_class",
            "participant_group": "",
            "participant_group_kind": "source_provided_pseudonymized",
            "training_eligible": "true",
            "sha256": "a" * 64,
        })

    with pytest.raises(ValueError, match="participant group"):
        read_samples(tmp_path)


def test_synthetic_group_requires_explicit_training_opt_in(tmp_path: Path) -> None:
    manifest = tmp_path / "dataset_manifest.csv"
    columns = [
        "output_path",
        "tissue",
        "target_value",
        "source_key",
        "label_kind",
        "participant_group",
        "participant_group_kind",
        "training_eligible",
        "sha256",
    ]
    with manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerow({
            "output_path": "Eye/anemic/test.jpg",
            "tissue": "Eye",
            "target_value": "1",
            "source_key": "test",
            "label_kind": "source_repository_proxy_class_with_similarity_grouping",
            "participant_group": "synthetic-similarity-group",
            "participant_group_kind": "synthetic_similarity_cluster_demo_only",
            "training_eligible": "true",
            "sha256": "a" * 64,
        })

    with pytest.raises(ValueError, match="--allow-synthetic-participant-groups"):
        read_samples(tmp_path)


def test_tissue_augmentations_preserve_color_and_are_tissue_specific() -> None:
    eye = tissue_transform_specification(Tissue.EYE, training=True)
    nail = tissue_transform_specification(Tissue.NAIL, training=True)
    tongue = tissue_transform_specification(Tissue.TONGUE, training=True)

    assert "random_resized_crop" in eye
    assert "rotation_12" in nail
    assert "rotation_7" in tongue
    assert all("color" not in operation for values in (eye, nail, tongue) for operation in values)


def test_positive_weight_uses_training_split_only(tmp_path: Path) -> None:
    samples = [make_sample(tmp_path, index, int(index == 0)) for index in range(8)]

    assert positive_weight(samples) == 7.0


def test_mc_dropout_masks_are_deterministic_and_scaled() -> None:
    first = mc_dropout_masks(1_024, 42)
    second = mc_dropout_masks(1_024, 42)

    assert first.shape == (MC_DROPOUT_PASSES, 1_024)
    assert first.equal(second)
    assert set(first.unique().tolist()) == {0.0, 1.0 / (1.0 - DROPOUT_PROBABILITY)}


def test_clinical_eye_export_has_separate_package_name() -> None:
    assert TISSUE_CONTRACTS[Tissue.EYE].package_name == "IronScanEye_Clinical.mlpackage"


def test_uncertainty_contract_uses_exported_mask_count() -> None:
    assert MC_DROPOUT_PASSES == 30


def make_sample(tmp_path: Path, index: int, label: int) -> MultimodalSample:
    return MultimodalSample(
        image_path=tmp_path / f"synthetic-{index}.jpg",
        content_sha256=f"{index:064x}",
        participant_group=f"participant-{index}",
        source_key="synthetic-test",
        label_kind="synthetic_test_fixture",
        label=label,
    )
