from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text())
    assert isinstance(value, dict)
    return value


def package_sha256(package: Path) -> str:
    digest = hashlib.sha256()
    for file_path in sorted(path for path in package.rglob("*") if path.is_file()):
        digest.update(file_path.relative_to(package).as_posix().encode())
        digest.update(b"\0")
        digest.update(file_path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def test_manifest_checksums_and_locked_contracts() -> None:
    cases = (
        ("segmentation_manifest.json", "TongueSegmentation.mlpackage", [1, 64, 64, 3], 0.5),
        ("risk_manifest.json", "AnemiaRisk.mlpackage", [1, 32, 32, 3], 0.42),
        (
            "pallor_manifest.json",
            "IronScanPallorClassifier.mlpackage",
            [1, 224, 224, 3],
            0.16261848541234136,
        ),
    )
    for manifest_name, package_name, dimensions, threshold in cases:
        manifest = load_json(ROOT / "Models" / "Manifests" / manifest_name)
        package = ROOT / "Models" / "CoreML" / package_name
        assert manifest["schemaVersion"] == 1
        assert manifest["deploymentStatus"] == "engineeringFixture"
        assert manifest["input"]["dimensions"] == dimensions
        assert manifest["input"]["pixelFormat"] == "32BGRA"
        assert manifest["input"]["colorSpace"] == "sRGB"
        assert manifest["decisionThreshold"] == threshold
        assert manifest["sha256"] == package_sha256(package)


def test_multi_screen_manifest_has_named_outputs_and_thresholds() -> None:
    manifest = load_json(ROOT / "Models/Manifests/multi_screen_manifest.json")
    package = ROOT / "Models/CoreML/IronScanMultiScreen.mlpackage"
    expected_outputs = {
        "tongue_pale_probability",
        "toothmark_probability",
        "crack_probability",
        "tip_side_red_probability",
        "fur_thick_probability",
    }

    assert manifest["deploymentStatus"] == "engineeringFixture"
    assert manifest["input"]["dimensions"] == [1, 224, 224, 3]
    assert {output["name"] for output in manifest["outputs"]} == expected_outputs
    assert set(manifest["decisionThresholds"]) == expected_outputs
    assert all(0 < threshold < 1 for threshold in manifest["decisionThresholds"].values())
    assert manifest["sha256"] == package_sha256(package)


def test_multimodal_manifests_lock_uncertainty_contracts() -> None:
    cases = (
        ("eye_clinical_manifest.json", "IronScanEye_Clinical.mlpackage", 30),
        ("nail_manifest.json", "IronScanNail.mlpackage", 30),
        ("tongue_manifest.json", "IronScanTongue.mlpackage", 30),
    )
    for manifest_name, package_name, expected_passes in cases:
        manifest = load_json(ROOT / "Models/Manifests" / manifest_name)
        package = ROOT / "Models/CoreML" / package_name

        assert manifest["uncertaintyPassCount"] == expected_passes
        assert 0 < manifest["uncertaintyThreshold"] < 1
        assert "predictive_uncertainty" in {
            output["name"] for output in manifest["outputs"]
        }
        assert manifest["sha256"] == package_sha256(package)


def test_golden_inputs_and_outputs_are_self_consistent() -> None:
    input_directory = ROOT / "TestFixtures" / "GoldenInputs" / "ML"
    output_directory = ROOT / "TestFixtures" / "GoldenOutputs" / "ML"
    cases = (
        ("segmentation_input.bgra", "segmentation_output.json", 64, 64),
        ("risk_input.bgra", "risk_output.json", 32, 32),
    )
    for input_name, output_name, width, height in cases:
        input_data = (input_directory / input_name).read_bytes()
        output = load_json(output_directory / output_name)
        assert len(input_data) == width * height * 4
        assert output["width"] == width
        assert output["height"] == height
        assert output["inputSHA256"] == hashlib.sha256(input_data).hexdigest()


def test_segmentation_golden_mask_dimensions() -> None:
    output = load_json(
        ROOT / "TestFixtures" / "GoldenOutputs" / "ML" / "segmentation_output.json"
    )
    rows = output["expectedMaskRows"]
    assert isinstance(rows, list)
    assert len(rows) == 64
    assert all(isinstance(row, str) and len(row) == 64 and set(row) <= {"0", "1"} for row in rows)


def test_risk_fixture_uses_locked_non_default_threshold() -> None:
    output = load_json(ROOT / "TestFixtures" / "GoldenOutputs" / "ML" / "risk_output.json")
    assert output["lockedDecisionThreshold"] == 0.42
    assert output["lockedDecisionThreshold"] != 0.5
    assert output["expectedDecision"] == "unableToAssess"
