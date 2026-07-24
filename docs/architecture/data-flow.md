# Data flow

1. `CameraSessionActor` produces an orientation-normalized local capture and stable metadata.
2. `SegmentationInferenceActor` returns a probability mask, postprocessed mask, confidence, and timing.
3. `SmartColorCalibrationActor` validates metadata and references, calibrates linear RGB, and produces a central tongue ROI.
4. `RiskInferenceActor` accepts only an approved, preprocessing-version-matched sample.
5. `MainActor` presents allowed research language.
6. Developer Mode may send anonymous metrics to the optional local server; production code does not upload raw images.
