# Camera pipeline

AVFoundation session mutations execute on `CameraSessionActor`. Preview analysis and capture conversion run away from `MainActor`; UI state updates run on `MainActor`. Captures are 32BGRA pixel buffers, remain in memory for local processing, and temporary captures are released after processing.

`CameraPermissionManager` checks and requests video authorization before camera startup. Denied access presents an iOS Settings action; restricted access presents device-management guidance without repeatedly requesting permission. The generated application plist uses:

```text
NSCameraUsageDescription = IronScan requires access to your camera to analyze tongue color and screen for anemia risk.
```

On physical devices, `CameraSessionActor` configures the rear wide camera, streams 32BGRA frames, stabilizes focus and exposure, locks both controls, then locks white balance to a clamped 5500 K daylight target. The torch defaults to a bounded constant level and remains user-controllable from SwiftUI. Camera errors are converted into safe UI states rather than escaping onto `MainActor`.

The video-data connection uses standard hardware stabilization when supported. `SampleBufferReceiver.captureOutput(_:didOutput:from:)` extracts the `CVPixelBuffer` from each sample buffer. `FrameStrideThrottle` forwards every 24th frame for live model work; overlapping live requests are dropped while the prior actor-isolated prediction is running. Two consecutive aligned observations trigger a second autofocus, exposure, and fixed-daylight white-balance stabilization cycle before capture remains ready.

On the simulator, `SimulatorCameraActor` emits a bounded mock preview-event loop and procedurally generated synthetic tongue frames. The capture button routes those frames through the same local synthetic segmentation and risk-inference fixture flow. The animated preview and synthetic frame generator contain no participant images.

The centered oval overlay is alignment guidance only. Result colors correspond only to the allowed decisions `lowerObservedRisk`, `possibleRisk`, and `unableToAssess`; they are not severity categories.

Live preview frames run only `TongueSegmentation` through `SegmentationInferenceActor`. The UI displays alignment progress, a pulsing **Scanning…** state, and the measured local inference duration. Timing is also emitted through unified logging with subsystem `org.ironscan.app` and category `live-scan`; logs contain duration and errors only, never image data or participant identifiers.

There is no `IronScanClassifier` model artifact or generated class in this repository. Raw preview frames must not invoke `AnemiaRisk`: that model accepts only an accepted `CalibratedTongueSample`, and the bundled package is an engineering fixture. Live severity categories are therefore intentionally not produced.

The simulator path validates orchestration, UI states, throttling, segmentation execution, cancellation, and temporary-buffer release. Alignment thresholds are engineering heuristics and are not validated tongue-detection measurements. Torch, focus, exposure, stabilization, fixed-daylight white balance, motion, real-tongue alignment, and physical framing still require supported-device validation.
