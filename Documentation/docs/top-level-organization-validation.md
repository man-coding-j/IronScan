# Repository-level two-folder organization — 2026-10-25

The earlier PR organized only `Apps/IronScan/IronScan`. That did not simplify the repository landing page. This follow-up organizes the repository itself into two main visible folders:

- `IronScan/`: the complete technical workspace, including app, packages, trained models, reference code, training tools, server, test fixtures, scripts, and Remotion generator. Their relative locations are preserved under one parent.
- `Documentation/`: existing `docs/` and `compliance/`, including all five submission PNGs.

GitHub metadata (`.github`), README, license, security, contributor instructions, ownership, ignore rules, and third-party notices remain at the repository root so GitHub can discover them. Generated local caches and private local configuration stay ignored and are not submission content.

## Preservation and path updates

The [relocation map](top-level-relocation-map.json) records all 363 relocated tracked files with before/after checksums; 353 retain identical bytes. Content edits are limited to workspace configuration, workflow/script paths, documentation, the audit metadata, and the Remotion README-asset output path. App Swift source, Python implementation/tests, model packages, model manifests, parity fixtures, and screenshot/PNG content are unchanged.

CI shell steps now run from `IronScan/`. Provenance checks point to `../Documentation/compliance`. Shell entry points resolve their own technical workspace, making invocation from the repository root safe. README links and clone/build/media instructions reflect the new locations. `Package.swift` and `pyproject.toml` move with their sources; create the technical workspace environment with `cd IronScan && uv sync --all-groups` rather than depending on an old root virtualenv.

Open `IronScan/IronScan.xcworkspace` after checkout. An already-open workspace at the former path must be reopened from the new location.

## Verification

- `python3 IronScan/scripts/check_repository_layout.py --verify-relocation-hashes`: repository folder structure checked, all 77 main-target Xcode references resolve, all 90 earlier app-relocation hashes match.
- Generic simulator build at the relocated project: **BUILD SUCCEEDED, 0 build errors, 0 warnings**. Log: `/private/tmp/ironscan-root-layout-build.log`.
- Configured Python/reference/server suites from `IronScan/`: **25 passed**.
- `python3 scripts/verify_model_hashes.py` from `IronScan/`: model package checksums match manifests.
- Remotion `npm run typecheck` and `npm run check-assets`: passed.
- All 20 local root README links resolve. All five relocated images remain 1920×1080 and match their recorded SHA-256 checksums. The configured Remotion export destination resolves to `Documentation/docs/readme_assets`.
- Shell syntax checks, Xcode project plist validation, and whitespace checks pass.

Build command from repository root:

```sh
xcodebuild -project IronScan/Apps/IronScan/IronScan.xcodeproj -scheme IronScan \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/ironscan-intro-build \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build
```

## Limits

An additional run including `MLTraining/tests` stopped during collection because the existing local environment lacks Pillow (`PIL`). The configured reference/server suites were run separately and passed. This folder-only change does not install or change training dependencies. Swift tests were not rerun for this repository-level move; the previous focused-test and full-suite results remain in [the earlier validation](repository-organization-validation.md). Existing full-suite assertion failures, physical-device assumptions, and non-clinical research limitations remain unresolved.
