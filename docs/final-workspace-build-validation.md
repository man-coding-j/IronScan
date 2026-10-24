# Final workspace build validation — 2026-10-23

IronScan remains a non-clinical research prototype. All regression inputs were synthetic.

## Changes in this check

- Assessment score extraction now clears all session-owned image references on success, error, and cancellation, before the presentation delay. This covers session images, captured-frame aliases, thumbnails, the pending capture, the tongue image, and the camera manager’s current image/frame. The cleanup regression checks that a weak reference to an imported synthetic image becomes nil after validation fails.
- Added a regression for synchronous history publication, the shared display-record projection, and subsequent JSON persistence to UserDefaults.
- Seeded the root workspace Package.resolved from the existing project lockfile, keeping all dependency versions unchanged and preventing workspace resolution from selecting newer versions.
- Corrected Swift package exclusions for video/node dependencies, Python packaging metadata, configuration plists, and iOS app-only tests. Those app tests remain enabled in the Xcode test target; the standalone package does not contain their engines.
- Added explicit AppIntents imports to the app and test targets so Xcode’s automatic metadata extraction phase has its required framework dependency. Compiler warnings are not suppressed.

## Verified behavior

- The default MultiScanHubViewModel retains MedicalCameraManager.shared and its controller. Both camera flip buttons call the view model, which awaits that manager’s toggleCamera(). Injected camera controllers remain isolated for tests.
- Camera forwarding, duplicate-tap suppression, failed-flip state preservation, and shared manager identity are covered by simulator regressions.
- ScanHistoryManager publishes numerical records on MainActor before its storage actor finishes writing JSON to UserDefaults. HomeDashboardView (the Home screen) and HistoryView both observe the injected shared manager and read displayRecords. Persistence, reload, deduplication, reset ordering, and publication tests pass. This verifies the observation/data path; interactive on-device UI latency was not measured.
- The assessed photo flow does not write raw images to app files, UserDefaults, or cloud history. Numerical history persistence is intentional. Photo library originals remain managed by Photos; importing does not delete those originals.
- ARC reference release is verified for failed assessment. Secure zeroing of physical RAM, framework-internal caches, and OS-owned camera/photo-library buffers is not guaranteed. Live preview can produce new frames after assessment; those are separate from the released captures.

## Commands and evidence

Clean generic iPhone build (signing disabled):

```sh
xcodebuild -workspace IronScan.xcworkspace -scheme IronScan -destination 'generic/platform=iOS' -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO clean build
```

Result: BUILD SUCCEEDED, **0 errors and 0 warnings** in `/tmp/ironscan-final-device-build.log`.

Clean standalone package verification:

```sh
swift package clean
swift test
```

Result: **36 tests passed, 0 failures, 0 errors, 0 warnings**, recorded in `/tmp/ironscan-final-swift-test.log`.

Focused simulator verification: ScanningExperienceTests and DesignSystemAndHistoryTests passed all **26 tests**, including the two new regressions. Log: `/tmp/ironscan-final-focused-tests.log`.

The full simulator suite is also run with:

```sh
xcodebuild -workspace IronScan.xcworkspace -scheme IronScan -destination 'platform=iOS Simulator,id=4E8A5F7C-0A89-4EA3-8459-F04FB90F1126' -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO test
```

Final full-suite result: **167 tests executed, 17 assertion failures across 8 test cases, 0 build warnings**. The 26 camera/history/lifecycle tests passed again in this final run.

## Remaining validation limits

Physical iPhone lens switching, preview mirroring, and flashlight behavior still require hardware validation. A simulator controller test and a generic device build do not establish hardware behavior.

Full-suite runtime failures remain in image-quality synthetic-frame expectations, older palette expectations, and triangulation weighting/usable-scan expectations. These are outside the warning and scan-history/image-lifecycle changes. Their algorithmic and design assumptions were not changed to make the suite pass. See `/tmp/ironscan-final-simulator-tests.log` for the final run; this workspace must not be described as having an entirely passing test suite.
