from __future__ import annotations

import csv
import zipfile
from collections import Counter
from pathlib import Path

import pytest
from PIL import Image

from MLTraining.scripts.multimodal_ingestion import (
    Configuration,
    Candidate,
    ImageInformation,
    SOURCE_SPECIFICATIONS,
    TargetLabel,
    Tissue,
    assign_similarity_groups,
    collect_eyes_defy_anemia_candidates,
    collect_repository_candidates,
    deduplicate,
    infer_label,
    infer_tissue,
    hemoglobin_screening_label,
    manifest_source_locator,
    plan_samples,
    pseudonymous_group,
    run,
    should_exclude,
    synthetic_participant_group,
    write_dataset,
)


def test_path_contract_requires_explicit_tissue_and_class() -> None:
    path = Path("dataset/eye/non_anemic/example.jpg")

    assert infer_tissue(path, (Tissue.EYE, Tissue.NAIL, Tissue.TONGUE)) is Tissue.EYE
    assert infer_label(path) == (TargetLabel.NON_ANEMIC, "source_normal_class")
    assert infer_label(Path("screenshots/result.png")) is None
    assert should_exclude(Path("imgs/anemia_results.PNG"))


def test_eyes_defy_anemia_uses_participant_group_and_lab_screening_label(tmp_path: Path) -> None:
    root = tmp_path / "Eyes-Defy-Anemia" / "India"
    write_minimal_xlsx(
        root / "India.xlsx",
        [
            ["Number", "Hgb", "Gender", "Age", "Note"],
            ["1", "11.9", "F", "32", ""],
        ],
    )
    write_image(root / "1/capture_palpebral.png", (140, 75, 80))
    write_image(root / "1/capture_forniceal_palpebral.png", (145, 80, 85))

    candidates = collect_eyes_defy_anemia_candidates(tmp_path, Counter())

    assert len(candidates) == 1
    assert candidates[0].target_label is TargetLabel.ANEMIC
    assert candidates[0].participant_group.startswith("eyes_defy_anemia-")
    assert candidates[0].label_kind == "laboratory_hemoglobin_anemia_screening_label"
    assert candidates[0].source_path.name == "capture_palpebral.png"


def test_hemoglobin_screening_thresholds_are_adult_and_sex_specific() -> None:
    assert hemoglobin_screening_label(12.9, "M", 30) is TargetLabel.ANEMIC
    assert hemoglobin_screening_label(13.0, "M", 30) is TargetLabel.NON_ANEMIC
    assert hemoglobin_screening_label(11.9, "F", 30) is TargetLabel.ANEMIC
    assert hemoglobin_screening_label(12.0, "F", 30) is TargetLabel.NON_ANEMIC
    assert hemoglobin_screening_label(11.0, "F", 17) is None


def test_repository_collection_ignores_graphs_and_non_tongue_media(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    write_image(source / "dataset/eye/anemia/eye.jpg", (140, 80, 80))
    write_image(source / "dataset/nail/normal/nail.png", (170, 130, 120))
    write_image(source / "dataset/tongue/anemia/tongue.jpg", (150, 70, 90))
    write_image(source / "assets/loss_graph.png", (255, 255, 255))
    write_image(source / "dataset/palm/anemia/palm.jpg", (180, 140, 130))
    exclusions: dict[str, int] = {}

    from collections import Counter

    counter = Counter(exclusions)
    candidates = collect_repository_candidates(tmp_path, SOURCE_SPECIFICATIONS[0], counter)

    assert {candidate.tissue for candidate in candidates} == {Tissue.EYE, Tissue.NAIL, Tissue.TONGUE}
    assert len(candidates) == 3
    assert should_exclude(Path("assets/loss_graph.png"))
    assert counter["missing_explicit_tissue_or_class"] == 1


def test_demo_grouping_applies_only_to_external_eye_and_nail(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    write_image(source / "dataset/eye/anemia/eye.jpg", (140, 80, 80))
    write_image(source / "dataset/nail/normal/nail.jpg", (170, 130, 120))
    write_image(source / "dataset/tongue/anemia/tongue.jpg", (150, 70, 90))
    from collections import Counter

    candidates = collect_repository_candidates(
        tmp_path,
        SOURCE_SPECIFICATIONS[0],
        Counter(),
        allow_synthetic_participant_groups=True,
    )
    grouped = assign_similarity_groups(candidates, Counter())
    groups = {candidate.tissue: candidate.participant_group for candidate in grouped}

    assert groups[Tissue.EYE].startswith("synthetic-similarity-")
    assert groups[Tissue.NAIL].startswith("synthetic-similarity-")
    assert groups[Tissue.TONGUE] == ""
    assert synthetic_participant_group("source", Tissue.EYE, "a" * 64) == synthetic_participant_group(
        "source",
        Tissue.EYE,
        "a" * 64,
    )


def test_near_duplicate_images_share_similarity_group(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    first_path = source / "dataset/eye/anemia/eye-a.jpg"
    second_path = source / "dataset/eye/anemia/eye-b.jpg"
    first_path.parent.mkdir(parents=True)
    base = Image.new("RGB", (96, 72), color=(130, 75, 70))
    for x in range(28, 68):
        for y in range(20, 52):
            base.putpixel((x, y), (175, 105, 100))
    base.save(first_path, quality=95)
    brighter = base.point(lambda value: min(value + 4, 255))
    brighter.save(second_path, quality=90)
    from collections import Counter

    candidates = collect_repository_candidates(
        tmp_path,
        SOURCE_SPECIFICATIONS[0],
        Counter(),
        allow_synthetic_participant_groups=True,
    )
    grouped = assign_similarity_groups(candidates, Counter())

    assert len(grouped) == 2
    assert grouped[0].participant_group == grouped[1].participant_group


def test_conflicting_exact_duplicate_is_excluded(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    anemic = source / "dataset/eye/anemia/one.jpg"
    normal = source / "dataset/eye/normal/two.jpg"
    write_image(anemic, (125, 70, 70))
    normal.parent.mkdir(parents=True)
    normal.write_bytes(anemic.read_bytes())

    from collections import Counter

    counter: Counter[str] = Counter()
    candidates = collect_repository_candidates(tmp_path, SOURCE_SPECIFICATIONS[0], counter)
    unique = deduplicate(candidates, counter)

    assert unique == []
    assert counter["duplicate_content_conflicting_label_or_tissue"] == 2


def test_deduplication_preserves_participant_group_metadata(tmp_path: Path) -> None:
    image = ImageInformation("a" * 64, "b" * 16, 96, 72)
    ungrouped = Candidate(
        "external",
        tmp_path,
        tmp_path / "external.jpg",
        Tissue.TONGUE,
        TargetLabel.ANEMIC,
        "source_anemia_class",
        "source_repository_proxy_class",
        "",
        image,
    )
    grouped = Candidate(
        "tonguedx2",
        tmp_path,
        tmp_path / "tonguedx.jpg",
        Tissue.TONGUE,
        TargetLabel.ANEMIC,
        "TonguePale=1",
        "visual_pallor_proxy_not_anemia_ground_truth",
        "participant-1",
        image,
    )
    from collections import Counter

    unique = deduplicate([ungrouped, grouped], Counter())

    assert unique == [grouped]


def test_perceptual_duplicate_with_conflicting_label_is_excluded(tmp_path: Path) -> None:
    from collections import Counter

    anemic = Candidate(
        "source-a",
        tmp_path,
        tmp_path / "anemic.jpg",
        Tissue.EYE,
        TargetLabel.ANEMIC,
        "source_anemia_class",
        "source_repository_proxy_class",
        "",
        ImageInformation("a" * 64, "c" * 16, 96, 72),
    )
    non_anemic = Candidate(
        "source-b",
        tmp_path,
        tmp_path / "normal.jpg",
        Tissue.EYE,
        TargetLabel.NON_ANEMIC,
        "source_normal_class",
        "source_repository_proxy_class",
        "",
        ImageInformation("b" * 64, "c" * 16, 96, 72),
    )
    exclusions: Counter[str] = Counter()

    assert deduplicate([anemic, non_anemic], exclusions) == []
    assert exclusions["perceptual_duplicate_conflicting_label"] == 2


def test_private_group_and_source_path_are_pseudonymized(tmp_path: Path) -> None:
    participant = pseudonymous_group("tonguedx2", "private-participant-id")
    candidate = Candidate(
        "tonguedx2",
        tmp_path,
        tmp_path / "private-participant-id/image.jpg",
        Tissue.TONGUE,
        TargetLabel.ANEMIC,
        "TonguePale=1",
        "visual_pallor_proxy_not_anemia_ground_truth",
        participant,
        ImageInformation("a" * 64, "b" * 16, 96, 72),
    )

    assert participant.startswith("tonguedx2-")
    assert "private-participant-id" not in participant
    assert "private-participant-id" not in manifest_source_locator(candidate)


def test_apply_requires_permission_and_manifest_records_group_eligibility(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    write_image(source / "dataset/tongue/anemia/tongue.jpg", (130, 60, 70))
    from collections import Counter

    candidates = collect_repository_candidates(tmp_path, SOURCE_SPECIFICATIONS[0], Counter())
    configuration = Configuration(tmp_path, tmp_path / "output", True, False, {})

    with pytest.raises(ValueError, match="reviewed --permission"):
        plan_samples(candidates, configuration)

    allowed = Configuration(
        tmp_path,
        tmp_path / "output",
        True,
        False,
        {"eye_nail_tongue_github": "reviewed-test-license"},
    )
    plans = plan_samples(candidates, allowed)
    write_dataset(plans, allowed)

    with (allowed.output_root / "dataset_manifest.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 1
    assert rows[0]["permission_reference"] == "reviewed-test-license"
    assert rows[0]["training_eligible"] == "false"
    assert rows[0]["participant_group"] == ""


def test_demo_grouped_eye_becomes_training_eligible_only_with_permission(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    write_image(source / "dataset/eye/anemia/eye.jpg", (130, 60, 70))
    from collections import Counter

    candidates = collect_repository_candidates(
        tmp_path,
        SOURCE_SPECIFICATIONS[0],
        Counter(),
        allow_synthetic_participant_groups=True,
    )
    candidates = assign_similarity_groups(candidates, Counter())
    configuration = Configuration(
        tmp_path,
        tmp_path / "output",
        True,
        False,
        {"eye_nail_tongue_github": "project-owner-demo-authorization"},
        True,
    )
    write_dataset(plan_samples(candidates, configuration), configuration)

    with (configuration.output_root / "dataset_manifest.csv").open(newline="", encoding="utf-8") as handle:
        row = next(csv.DictReader(handle))
    assert row["training_eligible"] == "true"
    assert row["participant_group_kind"] == "synthetic_similarity_cluster_demo_only"


def test_dry_run_never_writes_output(tmp_path: Path) -> None:
    source = tmp_path / "anemia_detection_eye_nail_tongue"
    write_image(source / "dataset/tongue/normal/tongue.jpg", (155, 85, 95))
    output = tmp_path / "output"

    summary = run(Configuration(tmp_path, output, False, False, {}))

    assert summary["mode"] == "dry-run"
    assert summary["plannedImages"] == 1
    assert not output.exists()


def write_image(path: Path, color: tuple[int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (96, 72), color=color).save(path)


def write_minimal_xlsx(path: Path, rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    row_xml: list[str] = []
    for row_index, values in enumerate(rows, start=1):
        cells = []
        for column_index, value in enumerate(values, start=1):
            column = chr(ord("A") + column_index - 1)
            cells.append(
                f'<c r="{column}{row_index}" t="inlineStr"><is><t>{value}</t></is></c>'
            )
        row_xml.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    worksheet = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f'<sheetData>{"".join(row_xml)}</sheetData></worksheet>'
    )
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("xl/worksheets/sheet1.xml", worksheet)
