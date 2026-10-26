# Repository organization and submission assets — 2026-10-25

## Scope and preservation

The main iOS target now has exactly two source folders: `AppAndUI` and `CoreAndML`. Info.plist and entitlements remain at the target root. Shared Swift packages, runtime model contracts, Python training/reference tools, tests, and documentation remain outside the application target.

Moved 78 top-level source files/model packages. The relocation map records 90 individual moved files and SHA-256 hashes; every moved file, model, weight, and manifest is byte-for-byte unchanged. Removed two zero-byte Untitled placeholders. No inference algorithm, camera actor behavior, preprocessing, parity fixture, or trained artifact content was changed.

Consolidated the explicit PBXGroup memberships into two groups and updated paths without recreating the project or changing target dependency versions. All 77 main-target Xcode file references resolve. The unused ignored GoogleService-Info.plist resource membership was removed so a fresh checkout does not need a private local plist to build. Local configuration remains ignored.

Bootstrap and iOS build CI now resolve/build the checked-in project instead of overwriting it with the supplemental XcodeGen structure. CI execution on GitHub is separate from the local results below.

## Two-folder follow-up

Consolidated models and services into `CoreAndML`, leaving `AppAndUI` as the other main source folder. The original relocation map now points to the final paths; all 90 preservation hashes still match and all 77 Xcode references resolve. Source and trained artifact content remain unchanged. Repeated the generic iOS Simulator build after consolidation: **BUILD SUCCEEDED**, with no build errors or warnings (`/private/tmp/ironscan-two-folder-build.log`). All 19 local README links resolve. The 26 focused tests below were run before this path-only follow-up; they were not rerun.

## Verified build

```sh
cd Apps/IronScan
xcodebuild -project IronScan.xcodeproj -scheme IronScan \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/ironscan-intro-build \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build
```

Result: **BUILD SUCCEEDED; 0 missing-file errors, 0 build errors, 0 warnings**. Local log: `/private/tmp/ironscan-reorganization-build.log`.

## Focused regression tests

```sh
xcodebuild -project Apps/IronScan/IronScan.xcodeproj -scheme IronScan \
  -destination 'platform=iOS Simulator,id=4E8A5F7C-0A89-4EA3-8459-F04FB90F1126' \
  -derivedDataPath /private/tmp/ironscan-intro-build \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -only-testing:IronScanMLTests/ScanningExperienceTests \
  -only-testing:IronScanMLTests/DesignSystemAndHistoryTests \
  CODE_SIGNING_ALLOWED=NO test
```

Result: **26 tests passed, 0 failures** (22 scanning tests and 4 design/history tests). Local log: `/private/tmp/ironscan-reorganization-tests.log`.

The prior full-suite result remains 167 tests with 17 assertion failures across 8 cases, as documented in `final-workspace-build-validation.md`. This reorganization did not modify tests or algorithms to hide those failures; the full suite was not rerun here.

## Media and README

- Direct Remotion PNG renders at 1920×1080: title 2.5 s/frame 150; WHO 6.5 s/frame 390; architecture 12 s/frame 720; import/HUD 21.5 s/frame 1290; history 24.5 s/frame 1470, at 60 fps.
- All five images visually inspected. Export dimensions/checksums are in `readme_assets/manifest.json`.
- `npm run typecheck`, `npm run check-assets`, and `npm run export-readme` passed.
- The three known-fictional native demo inputs are explicitly versioned under `demo-*.png` names so the video generator works after a fresh checkout. Other personal/local captures and rendered video/dependency caches remain ignored.
- Root README embeds all five images and links to actual source locations. Platform/Swift badges match iOS 18+ and Swift 6. Privacy, offline-execution, HealthKit/PDF-preview, and historical WHO claims were reconciled with the implementation and sources.
- `python3 scripts/check_repository_layout.py --verify-relocation-hashes`, bootstrap shell syntax, README local-link/image checks, and `git diff --check` passed.

## Remaining assumptions

No clinical validity, calibrated diagnostic accuracy, physical-device camera/torch validation, secure RAM zeroing, or deletion of Photos-library originals is established by this organization or these illustrations. The import and three-point-history video screens are synthetic React/SVG demonstrations. No real participant images or data were added.
