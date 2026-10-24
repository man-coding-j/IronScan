# Camera and photo import validation

Validation date: 2026-10-23.

The scan suite is a non-clinical research prototype. This update leaves model
preprocessing, normalization, fusion calculations, numeric history records, and
history syncing unchanged.

## Implementation boundaries

- `CameraSessionActor` remains the sole session owner. Its custom serial executor
  uses `com.ironscan.cameraQueue` for session configuration, running state, lens
  changes, and torch controls. `MedicalCameraManager` publishes UI state on
  MainActor. The input swap removes existing video inputs before testing the new
  input and restores the existing input and connection settings on rejection.
- Both camera outputs stay portrait; only the front camera is mirrored. The
  session starts on the front camera. Display conversion uses one
  reusable CIContext on a separate actor and creates `.up` images. Rendering
  drops frames under load. Capture requests 60 fps when the active device format
  supports it; inference and quality analysis retain their existing throttles.
- The ordered PhotosPicker loads at most three images in memory. ImageIO applies
  source orientation and caps the imported preview's longest edge at 2048 pixels
  to bound memory use. Three selections replace all slots in tissue order. One
  or two selections start at the active step and wrap to the first slot when
  necessary. Import never invokes assessment or adds a history record.
- The scan animation lasts at least 2.15 seconds on success. Its sweep and node
  sequence are presentation effects, not measured inference progress. The bar
  stays below completion until scores have been extracted and session image
  references cleared. Reduced Motion disables sweep and node scaling.
- Session image dictionaries, captured frames, thumbnail aliases, pending
  captures, and manager image references are cleared after score extraction,
  on reset, and on disappearance. Image locals are scoped to the scoring helper
  so they do not survive the animation's remaining wait. Import and inference
  tasks are cancelled on exit. No photo persistence was added. Existing images
  in the user's Photos library are unaffected. ARC reference release does not
  guarantee immediate byte zeroing or control OS/library caches.

## Checks

- Simulator build: passed.
- Physical iOS target build (code signing disabled): passed, including camera
  code excluded from simulator builds.
- No Swift compiler warnings in the physical-device build. Xcode emits its
  tooling notice: “Metadata extraction skipped. No AppIntents.framework
  dependency found.”
- Final focused simulator tests: 27 passed, zero failures. These cover
  `ScanningExperienceTests`, `CameraStateMachineTests`,
  `CameraPermissionManagerTests`, and `SimulatorCameraActorTests`.
- Final simulator test build and device build contain no Swift compiler warnings.
- `git diff --check`: passed.

Build/test logs for this session are in `/tmp/ironscan-targeted-final-tests.log`
and `/tmp/ironscan-targeted-final-device.log`.

## Physical-device checks still required

Use only synthetic or expressly authorized non-participant demonstration inputs.
Verify rapid repeated front/back switches, front-only mirroring, portrait after
rotation, restored feed when an input cannot be added, torch reset after a lens
switch, and hardware-supported frame rate. Measure sustained preview smoothness,
thermal behavior, and peak memory for large HEIC/library selections on an iPhone.
Exercise picker cancellation, import without camera permission, partial imports
from each step, failed tissue validation, manual assessment after import, and
exit/reset during loading or inference. Simulator/build checks do not establish
these hardware or visual results, or clinical validity.

Subsequent physical-iPhone regression fixes and current verification are recorded
in [physical-iphone-bugfix-validation.md](physical-iphone-bugfix-validation.md).
