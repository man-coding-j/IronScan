"""Deterministic scalar reference for IronScan color-calibration math."""

from __future__ import annotations

import json
from pathlib import Path
from typing import TypedDict

import numpy as np
import numpy.typing as npt

FloatMatrix = npt.NDArray[np.float64]


class CalibrationGolden(TypedDict):
    matrix_row_major: list[float]
    condition_number: float
    maximum_linear_residual: float
    tolerance: float

PATCH_TARGETS = np.asarray(
    [
        [0.62, 0.12, 0.08],
        [0.08, 0.55, 0.10],
        [0.07, 0.13, 0.58],
        [0.48, 0.48, 0.48],
    ],
    dtype=np.float64,
)
LAMBDA = 0.001


def solve_weighted_matrix(
    observed: FloatMatrix,
    target: FloatMatrix,
    weights: FloatMatrix,
    regularization: float = LAMBDA,
) -> tuple[FloatMatrix, float]:
    identity = np.eye(3, dtype=np.float64)
    weighted = weights[:, None] * observed
    normal = observed.T @ weighted + regularization * identity
    right_hand_side = observed.T @ (weights[:, None] * target) + regularization * identity
    matrix = np.linalg.solve(normal, right_hand_side)
    eigenvalues = np.linalg.eigvalsh(normal)
    condition = float(np.sqrt(eigenvalues[-1] / eigenvalues[0]))
    return matrix, condition


def warm_cast_golden() -> CalibrationGolden:
    gains = np.asarray([1.18, 0.94, 0.82], dtype=np.float64)
    linear_observed = PATCH_TARGETS / gains
    encoded = np.where(
        linear_observed <= 0.0031308,
        12.92 * linear_observed,
        1.055 * np.power(linear_observed, 1.0 / 2.4) - 0.055,
    )
    quantized = np.round(np.clip(encoded, 0, 1) * 255) / 255
    observed = np.where(
        quantized <= 0.04045,
        quantized / 12.92,
        np.power((quantized + 0.055) / 1.055, 2.4),
    )
    matrix, condition = solve_weighted_matrix(observed, PATCH_TARGETS, np.ones(4, dtype=np.float64))
    corrected = observed @ matrix
    return {
        "matrix_row_major": matrix.reshape(-1).tolist(),
        "condition_number": condition,
        "maximum_linear_residual": float(np.max(np.abs(corrected - PATCH_TARGETS))),
        "tolerance": 0.003,
    }


def main() -> None:
    destination = Path(__file__).parents[1] / "TestFixtures" / "GoldenOutputs" / "ColorCalibration" / "warm_cast.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(warm_cast_golden(), indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
