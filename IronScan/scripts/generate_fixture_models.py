from __future__ import annotations

import hashlib
import json
import math
import shutil
import subprocess
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DIRECTORY = ROOT / "Models" / "CoreML"
MANIFEST_DIRECTORY = ROOT / "Models" / "Manifests"
GOLDEN_INPUT_DIRECTORY = ROOT / "TestFixtures" / "GoldenInputs" / "ML"
GOLDEN_OUTPUT_DIRECTORY = ROOT / "TestFixtures" / "GoldenOutputs" / "ML"
TEMPORARY_DIRECTORY = ROOT / ".model-generation"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def package_sha256(package: Path) -> str:
    digest = hashlib.sha256()
    for file_path in sorted(path for path in package.rglob("*") if path.is_file()):
        relative_path = file_path.relative_to(package).as_posix().encode()
        digest.update(relative_path)
        digest.update(b"\0")
        digest.update(file_path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def metadata_for(manifest: dict[str, object]) -> dict[str, str]:
    input_contract = manifest["input"]
    if not isinstance(input_contract, dict):
        raise TypeError("Manifest input must be an object")
    return {
        "manifestSchemaVersion": str(manifest["schemaVersion"]),
        "modelIdentifier": str(manifest["modelIdentifier"]),
        "semanticVersion": str(manifest["semanticVersion"]),
        "inputFeatureName": str(input_contract["name"]),
        "inputDimensions": canonical_json(input_contract["dimensions"]),
        "pixelFormat": str(input_contract["pixelFormat"]),
        "colorSpace": str(input_contract["colorSpace"]),
        "normalization": canonical_json(manifest["normalization"]),
        "outputFeatures": canonical_json(manifest["outputs"]),
        "decisionThreshold": str(manifest["decisionThreshold"]),
        "preprocessingVersion": str(manifest["preprocessingVersion"]),
    }


def finalize_spec(builder: NeuralNetworkBuilder, manifest: dict[str, object]) -> object:
    spec = builder.spec
    spec.description.metadata.author = "IronScan engineering fixture generator"
    spec.description.metadata.shortDescription = "Deterministic engineering fixture; not a trained screening model"
    spec.description.metadata.versionString = str(manifest["semanticVersion"])
    spec.description.metadata.userDefined.update(metadata_for(manifest))
    return spec


def segmentation_manifest() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "modelIdentifier": "org.ironscan.engineering.tongue-segmentation",
        "semanticVersion": "0.1.0-engineering.1",
        "sha256": "pending",
        "deploymentStatus": "engineeringFixture",
        "input": {
            "name": "image",
            "dimensions": [1, 64, 64, 3],
            "dataType": "uint8",
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
        },
        "resize": {"method": "scaleFill", "interpolation": "vImageHighQuality"},
        "normalization": {"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]},
        "outputs": [{"name": "probability_mask", "dimensions": [1, 64, 64], "dataType": "float32"}],
        "decisionThreshold": 0.5,
        "trainingCommit": "synthetic-engineering-fixture",
        "datasetVersion": "synthetic-v1",
        "preprocessingVersion": "1.0.0",
        "postprocessing": {
            "largestConnectedComponent": True,
            "maximumHoleAreaPixels": 24,
            "closingRadiusPixels": 1,
            "minimumComponentAreaPixels": 32,
            "boundaryErosionPercentage": 0.01,
        },
    }


def risk_manifest() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "modelIdentifier": "org.ironscan.engineering.anemia-risk",
        "semanticVersion": "0.1.0-engineering.1",
        "sha256": "pending",
        "deploymentStatus": "engineeringFixture",
        "input": {
            "name": "image",
            "dimensions": [1, 32, 32, 3],
            "dataType": "uint8",
            "pixelFormat": "32BGRA",
            "colorSpace": "sRGB",
        },
        "resize": {"method": "scaleFill", "interpolation": "vImageHighQuality"},
        "normalization": {"kind": "scale", "scale": 1.0 / 255.0, "biases": [0.0, 0.0, 0.0]},
        "outputs": [
            {"name": "raw_score", "dimensions": [1], "dataType": "float32"},
            {"name": "calibrated_probability", "dimensions": [1], "dataType": "float32"},
        ],
        "decisionThreshold": 0.42,
        "trainingCommit": "synthetic-engineering-fixture",
        "datasetVersion": "synthetic-v1",
        "preprocessingVersion": "1.0.0",
    }


def build_segmentation_model(manifest: dict[str, object], destination: Path) -> None:
    builder = NeuralNetworkBuilder(
        [("image", datatypes.Array(3, 64, 64))],
        [("probability_mask", datatypes.Array(1, 64, 64))],
        disable_rank5_shape_mapping=True,
        use_float_arraytype=True,
    )
    builder.add_convolution(
        name="red_dominance",
        kernel_channels=3,
        output_channels=1,
        height=1,
        width=1,
        stride_height=1,
        stride_width=1,
        border_mode="valid",
        groups=1,
        W=np.array([4.0, -2.0, -2.0], dtype=np.float32).reshape(1, 1, 3, 1),
        b=np.array([-0.2], dtype=np.float32),
        has_bias=True,
        input_name="image",
        output_name="logits",
    )
    builder.add_activation("probability", "SIGMOID", "logits", "probability_mask")
    builder.set_pre_processing_parameters(image_input_names=["image"], image_scale=1.0 / 255.0)
    ct.models.utils.save_spec(finalize_spec(builder, manifest), str(destination))


def build_risk_model(manifest: dict[str, object], destination: Path) -> None:
    builder = NeuralNetworkBuilder(
        [("image", datatypes.Array(3, 32, 32))],
        [("raw_score", datatypes.Array(1)), ("calibrated_probability", datatypes.Array(1))],
        disable_rank5_shape_mapping=True,
        use_float_arraytype=True,
    )
    builder.add_pooling(
        name="global_average",
        height=1,
        width=1,
        stride_height=1,
        stride_width=1,
        layer_type="AVERAGE",
        padding_type="VALID",
        input_name="image",
        output_name="pooled",
        is_global=True,
    )
    builder.add_flatten("flatten", 0, "pooled", "features")
    builder.add_inner_product(
        name="risk_score",
        W=np.array([0.8, -0.2, -0.6], dtype=np.float32),
        b=np.array([0.1], dtype=np.float32),
        input_channels=3,
        output_channels=1,
        has_bias=True,
        input_name="features",
        output_name="raw_score",
    )
    builder.add_activation("probability", "SIGMOID", "raw_score", "calibrated_probability")
    builder.set_pre_processing_parameters(image_input_names=["image"], image_scale=1.0 / 255.0)
    ct.models.utils.save_spec(finalize_spec(builder, manifest), str(destination))


def upgrade_to_package(source: Path, package_name: str) -> Path:
    package = PACKAGE_DIRECTORY / f"{package_name}.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    subprocess.run(
        ["xcrun", "coremlcompiler", "upgrade", str(source), str(PACKAGE_DIRECTORY)],
        check=True,
    )
    generated_package = PACKAGE_DIRECTORY / f"{source.stem}.mlpackage"
    if generated_package != package:
        generated_package.rename(package)
    return package


def segmentation_pixels() -> np.ndarray:
    pixels = np.zeros((64, 64, 4), dtype=np.uint8)
    for row in range(64):
        for column in range(64):
            distance = math.hypot(column - 31.5, row - 31.5)
            if distance <= 20:
                red, green, blue = 210, 75, 80
            else:
                red, green, blue = 92, 92, 92
            pixels[row, column] = [blue, green, red, 255]
    return pixels


def risk_pixels() -> np.ndarray:
    pixels = np.zeros((32, 32, 4), dtype=np.uint8)
    for row in range(32):
        for column in range(32):
            red = 145 + ((row + column) % 11)
            green = 91 + (row % 7)
            blue = 88 + (column % 5)
            pixels[row, column] = [blue, green, red, 255]
    return pixels


def dilate(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    result = mask.copy()
    for row in range(height):
        for column in range(width):
            if mask[row, column] == 0:
                neighbors = [
                    mask[candidate_row, candidate_column]
                    for candidate_row, candidate_column in (
                        (row - 1, column),
                        (row + 1, column),
                        (row, column - 1),
                        (row, column + 1),
                    )
                    if 0 <= candidate_row < height and 0 <= candidate_column < width
                ]
                if 1 in neighbors:
                    result[row, column] = 1
    return result


def erode(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    result = mask.copy()
    for row in range(height):
        for column in range(width):
            if mask[row, column] == 1:
                if row == 0 or column == 0 or row == height - 1 or column == width - 1:
                    result[row, column] = 0
                    continue
                if any(
                    mask[candidate_row, candidate_column] == 0
                    for candidate_row, candidate_column in (
                        (row - 1, column),
                        (row + 1, column),
                        (row, column - 1),
                        (row, column + 1),
                    )
                ):
                    result[row, column] = 0
    return result


def write_golden_fixtures() -> None:
    GOLDEN_INPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    GOLDEN_OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    segmentation = segmentation_pixels()
    risk = risk_pixels()
    (GOLDEN_INPUT_DIRECTORY / "segmentation_input.bgra").write_bytes(segmentation.tobytes())
    (GOLDEN_INPUT_DIRECTORY / "risk_input.bgra").write_bytes(risk.tobytes())

    segmentation_rgb = segmentation[:, :, [2, 1, 0]].astype(np.float64) / 255.0
    logits = (
        4.0 * segmentation_rgb[:, :, 0]
        - 2.0 * segmentation_rgb[:, :, 1]
        - 2.0 * segmentation_rgb[:, :, 2]
        - 0.2
    )
    probabilities = 1.0 / (1.0 + np.exp(-logits))
    binary_mask = erode(dilate((probabilities >= 0.5).astype(np.uint8)))
    binary_mask = erode(binary_mask)
    segmentation_output = {
        "fixture": "synthetic red ellipse",
        "width": 64,
        "height": 64,
        "inputSHA256": hashlib.sha256(segmentation.tobytes()).hexdigest(),
        "threshold": 0.5,
        "expectedForegroundPixels": int(binary_mask.sum()),
        "expectedMaskRows": ["".join(str(value) for value in row) for row in binary_mask.tolist()],
        "probabilitySamples": {
            "center": float(probabilities[32, 32]),
            "corner": float(probabilities[0, 0]),
        },
        "floatTolerance": 0.0001,
        "minimumDice": 0.99,
    }
    (GOLDEN_OUTPUT_DIRECTORY / "segmentation_output.json").write_text(
        json.dumps(segmentation_output, indent=2, sort_keys=True) + "\n"
    )

    risk_rgb = risk[:, :, [2, 1, 0]].astype(np.float64) / 255.0
    means = risk_rgb.mean(axis=(0, 1))
    raw_score = 0.8 * means[0] - 0.2 * means[1] - 0.6 * means[2] + 0.1
    probability = 1.0 / (1.0 + math.exp(-raw_score))
    risk_output = {
        "fixture": "synthetic calibrated tongue colors",
        "width": 32,
        "height": 32,
        "inputSHA256": hashlib.sha256(risk.tobytes()).hexdigest(),
        "expectedRawScore": float(raw_score),
        "expectedCalibratedProbability": float(probability),
        "probabilityTolerance": 0.01,
        "tensorFloatTolerance": 0.0001,
        "lockedDecisionThreshold": 0.42,
        "expectedDecision": "unableToAssess",
    }
    (GOLDEN_OUTPUT_DIRECTORY / "risk_output.json").write_text(
        json.dumps(risk_output, indent=2, sort_keys=True) + "\n"
    )


def main() -> None:
    PACKAGE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    MANIFEST_DIRECTORY.mkdir(parents=True, exist_ok=True)
    TEMPORARY_DIRECTORY.mkdir(parents=True, exist_ok=True)
    segmentation = segmentation_manifest()
    risk = risk_manifest()
    segmentation_source = TEMPORARY_DIRECTORY / "TongueSegmentation.mlmodel"
    risk_source = TEMPORARY_DIRECTORY / "AnemiaRisk.mlmodel"
    build_segmentation_model(segmentation, segmentation_source)
    build_risk_model(risk, risk_source)
    segmentation_package = upgrade_to_package(segmentation_source, "TongueSegmentation")
    risk_package = upgrade_to_package(risk_source, "AnemiaRisk")
    segmentation["sha256"] = package_sha256(segmentation_package)
    risk["sha256"] = package_sha256(risk_package)
    (MANIFEST_DIRECTORY / "segmentation_manifest.json").write_text(
        json.dumps(segmentation, indent=2, sort_keys=True) + "\n"
    )
    (MANIFEST_DIRECTORY / "risk_manifest.json").write_text(
        json.dumps(risk, indent=2, sort_keys=True) + "\n"
    )
    write_golden_fixtures()
    shutil.rmtree(TEMPORARY_DIRECTORY)


if __name__ == "__main__":
    main()
