# IronScan

An on-device AI research prototype for the Congressional App Challenge.

## Overview & Mission

IronScan explores non-invasive hemoglobin estimation and anemia screening through images of the conjunctiva, fingernail bed, and tongue. Its mission is to demonstrate an accessible, privacy-conscious mobile research workflow powered by on-device AI.

**IronScan is a non-clinical research prototype.** Its scores, estimates, and demonstrations are not validated measurements, diagnoses, or a basis for care decisions. Hemoglobin and anemia assessment require appropriate laboratory testing and professional evaluation.

## Key Features

- **3-step multimodal scan suite:** A guided Conjunctiva → Fingernail Bed → Tongue workflow, with camera controls and Apple Vision face/hand checks.
- **Photo library import with RAM-only ephemeral handling:** Imported assessment images are decoded in memory without creating app photo files. Session-owned image references are cleared after success, failure, or cancellation. Numerical scan history is stored separately; Photos retains the user's originals. ARC release does not guarantee secure RAM zeroing or removal of framework/OS caches.
- **Longitudinal Hemoglobin Trend graph:** Home and History observe shared numerical records, with local persistence and a consistent display projection. Displayed estimates remain experimental; tutorial records are fictional.
- **Apple Health vitals sync preview:** The current Home and History interactions display fixed sample vitals. These previews do not request HealthKit access or fetch live Apple Health samples.
- **Doctor PDF export preview:** The current button opens a static, dismissible research-report layout with fictional values. Generating and sharing an actual PDF is not implemented in this flow.

## Tech Stack & Architecture

IronScan is built with **Swift, SwiftUI, Core ML, Apple Vision, AVFoundation, and Combine**, using Swift 6 strict concurrency.

The three-step assessment prepares **224 × 224 pixel buffers** for three specialized Core ML models: `ConjunctivaPallor`, `NailHemoglobin`, and `TonguePallor`. Model tensor scores are normalized before multimodal fusion: the nail model's raw logit receives a sigmoid transform, while the eye and tongue heads already produce sigmoid probabilities. This normalization does not establish clinical accuracy or calibrated hemoglobin measurement.

Camera session work, image decoding, Vision checks, model inference, disk persistence, and UI updates remain separated across their designated actors. SwiftUI and Combine publish shared history updates on the main actor while persistence runs separately. Model preprocessing contracts are maintained with manifests and Python/Swift parity fixtures.

Raw tongue images remain local outside explicitly enabled Developer Mode. The optional synthetic engineering dashboard in [`Server/`](Server/README.md) is separate from the app's inference pipeline.

## Getting Started

1. Open `IronScan.xcworkspace` in Xcode and select the `IronScan` scheme.
2. Choose an iPhone simulator and run the app. Simulator camera fixtures support engineering checks without participant images.
3. For a physical iPhone, select a development team under Signing & Capabilities, enable device Developer Mode, and run on the connected device.

The submission intro source and regeneration instructions are in [`Video/IronScanIntro/`](Video/IronScanIntro/README.md).

## Validation & Limitations

The recorded final validation includes a successful clean generic iPhone build with signing disabled, 36 passing standalone Swift package tests, and 26 passing focused camera/history/lifecycle tests. The full simulator suite recorded **167 tests with 17 assertion failures across 8 test cases**, including image-quality, palette, and triangulation expectations. See [`docs/final-workspace-build-validation.md`](docs/final-workspace-build-validation.md) for commands, evidence, and remaining issues.

Physical iPhone camera switching, mirroring, torch behavior, capture alignment, and performance measurements still require hardware validation. Simulator results and unsigned device builds do not verify those behaviors. Engineering fixtures, heuristic quality checks, unvalidated calibration assumptions, and demo previews must not be presented as validated participant results. No clinical validity is claimed.

Additional demo behavior and limitations are documented in [`docs/demo-features.md`](docs/demo-features.md).

## Team Credits

Developed by **Naman Jain** and **Ved Patel** for the **Congressional App Challenge**.
