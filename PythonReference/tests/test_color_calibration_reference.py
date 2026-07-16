import json
from pathlib import Path

import numpy as np

from PythonReference.color_calibration import warm_cast_golden


def test_warm_cast_golden_matches_reference() -> None:
    golden_path = Path("TestFixtures/GoldenOutputs/ColorCalibration/warm_cast.json")
    golden = json.loads(golden_path.read_text(encoding="utf-8"))
    computed = warm_cast_golden()

    assert np.allclose(computed["matrix_row_major"], golden["matrix_row_major"], atol=1e-12)
    assert abs(float(computed["condition_number"]) - float(golden["condition_number"])) <= 1e-12
    assert abs(float(computed["maximum_linear_residual"]) - float(golden["maximum_linear_residual"])) <= 1e-12
