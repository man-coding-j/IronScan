# IronScan

IronScan is a non-clinical research prototype that estimates possible anemia risk from a standardized tongue image. Results require confirmation with a laboratory test.

## iOS app

The SwiftUI app owns AVFoundation session mutations inside `CameraSessionActor`, analyzes BGRA preview and photo buffers away from the main actor, enables supported video stabilization, and locks focus/exposure plus a fixed 5500 K daylight white-balance target after stabilization. Every 24th preview frame runs actor-isolated tongue segmentation for live alignment feedback; sustained alignment re-stabilizes camera controls. Risk inference remains capture-based and calibration-gated. Camera permission denial produces a Settings guidance screen rather than a failed preview.

Open `IronScan.xcworkspace`, choose the `IronScan` scheme, select an iPhone simulator, and press Run. The simulator automatically uses an animated synthetic camera stream; use **Capture simulated frame** to exercise the camera UI, segmentation, and risk-inference fixture locally. For camera testing, select a connected iPhone or iPad, choose a development team under Signing & Capabilities, enable Developer Mode on the device, and press Run.

Both model packages are validated during app startup. Physical-device builds also provide **Run 100-scan ML benchmark** so p95 timings can be collected without participant images.

## Local engineering dashboard

`Server/` contains an optional FastAPI diagnostics dashboard for anonymous synthetic engineering runs. It is not used by the application inference pipeline. Run `docker compose -f Server/docker-compose.yml up --build`, then open `http://127.0.0.1:8000/dashboard`; migration, synthetic seeding, privacy controls, retention, and physical-device LAN instructions are documented in `Server/README.md`.

Current limitations:

- Physical captures currently return "Unable to assess" because the locked default capture protocol has no validated physical reference-patch locations or targets. The calibration implementation is exercised only with synthetic fixtures, and rejected calibration samples never reach risk inference.
- The bundled Core ML packages are deterministic synthetic engineering fixtures, so their outputs must not be treated as participant results.
- Image quality checks currently estimate luminance, clipping, and coarse contrast. Motion, tongue coverage, and tongue centering are placeholders and must not be treated as validated measurements.
- Live segmentation alignment thresholds are engineering heuristics. The repository does not contain an `IronScanClassifier`, and raw preview frames do not produce risk decisions.
- Camera behavior requires validation on supported physical iPhone hardware; the simulator cannot validate capture, torch, focus, exposure, or white-balance behavior.
- Required p95 measurements on two physical iPhones are still pending; the benchmark procedure and result table are in `docs/architecture/ml-runtime.md`.
- The local TongueDX copy is not used for calibration or risk training because calibration targets, capture metadata, laboratory labels, licensing, and consent documentation were not present.
- No raw-image upload path exists in iOS production code. The optional debug server rejects non-synthetic images unless Developer Mode uploads are explicitly enabled and retained temporarily.
- Docker Compose startup could not be executed on the development Mac because Docker is not installed; the wheel, migration, seed, loopback server, API, and rendered dashboard were validated directly.
