# IronScan

IronScan is a non-clinical research prototype that estimates possible anemia risk from a standardized tongue image. Results require confirmation with a laboratory test.

## iOS app

The SwiftUI app owns AVFoundation session mutations inside `CameraSessionActor`, analyzes BGRA preview and photo buffers away from the main actor, locks focus/exposure/white balance after stabilization, and keeps captured pixel buffers in memory for local processing. The ML runtime validates and loads deterministic engineering fixture models for segmentation and risk-pipeline parity testing. The simulator offers a clearly labeled synthetic fixture because it cannot validate a physical camera.

Open `IronScan.xcworkspace`, choose the `IronScan` scheme, select an iPhone simulator, and press Run. Use **Run synthetic simulator demo** to exercise segmentation and risk inference locally. For camera testing, select a connected iPhone or iPad, choose a development team under Signing & Capabilities, enable Developer Mode on the device, and press Run.

Current limitations:

- Physical captures intentionally return "Unable to assess" after segmentation because validated color calibration has not been integrated. Risk inference is not run for these captures.
- The bundled Core ML packages are deterministic synthetic engineering fixtures, so their outputs must not be treated as participant results.
- Image quality checks currently estimate luminance, clipping, and coarse contrast. Motion, tongue coverage, and tongue centering are placeholders and must not be treated as validated measurements.
- Camera behavior requires validation on supported physical iPhone hardware; the simulator cannot validate capture, torch, focus, exposure, or white-balance behavior.
- No raw-image upload path is implemented. Production code must continue to keep raw tongue images local.
