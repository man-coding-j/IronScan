from pathlib import Path

from MLTraining.scripts.train_and_convert import Sample, grouped_split, is_semantic_version, package_sha256


def test_grouped_split_is_deterministic_and_has_no_participant_leakage(tmp_path: Path) -> None:
    samples = make_samples(tmp_path)

    first = grouped_split(samples, seed=42)
    second = grouped_split(samples, seed=42)

    assert first == second
    group_sets = {
        name: {sample.participant_group for sample in split_samples}
        for name, split_samples in first.items()
    }
    assert group_sets["train"].isdisjoint(group_sets["validation"])
    assert group_sets["train"].isdisjoint(group_sets["test"])
    assert group_sets["validation"].isdisjoint(group_sets["test"])
    assert all({sample.label for sample in split_samples} == {0, 1} for split_samples in first.values())


def test_package_checksum_includes_relative_paths_and_contents(tmp_path: Path) -> None:
    package = tmp_path / "AnemiaRisk.mlpackage"
    (package / "Data").mkdir(parents=True)
    (package / "Manifest.json").write_text("manifest", encoding="utf-8")
    (package / "Data" / "weights.bin").write_bytes(b"weights")

    first = package_sha256(package)
    (package / "Data" / "weights.bin").write_bytes(b"updated")
    second = package_sha256(package)

    assert len(first) == 64
    assert first != second


def test_semantic_version_validation_matches_model_contract() -> None:
    assert is_semantic_version("1.2.3")
    assert is_semantic_version("1.2.3-research.1")
    assert not is_semantic_version("v1.2")
    assert not is_semantic_version("1.2.03")


def make_samples(tmp_path: Path) -> list[Sample]:
    samples: list[Sample] = []
    for group_index in range(12):
        label = group_index % 2
        for image_index in range(3):
            image_path = tmp_path / f"fixture-{group_index}-{image_index}.bin"
            image_path.write_bytes(bytes([group_index, image_index]))
            samples.append(
                Sample(
                    image_path=image_path,
                    participant_group=f"group-{group_index}",
                    label=label,
                )
            )
    return samples
