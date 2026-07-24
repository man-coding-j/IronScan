from __future__ import annotations

import json
from pathlib import Path

import pytest

from PythonReference.conjunctiva_crop import lower_quarter

ROOT = Path(__file__).resolve().parents[2]


def test_conjunctiva_crop_matches_golden_geometry() -> None:
    fixture = json.loads(
        (ROOT / "TestFixtures/GoldenOutputs/ML/conjunctiva_crop_output.json").read_text()
    )

    actual = lower_quarter(fixture["faceBoundingBox"], fixture["eyePoints"])

    assert actual == pytest.approx(fixture["expectedLowerQuarter"], abs=1e-12)


def test_conjunctiva_crop_rejects_missing_landmarks() -> None:
    with pytest.raises(ValueError, match="required"):
        lower_quarter([0.2, 0.1, 0.6, 0.8], [])
