# Submission intro verification

## Passed

- Xcode Debug simulator build with the app target's existing Swift 6 / complete strict-concurrency settings.
- Focused XCTest: `IronScanMLTests/DesignSystemAndHistoryTests/testTutorialCaptureFixtureIsConsistentAndFictional` (one test, zero failures). Checks seven unique fictional records, descending dates, latest 11.8 g/dL / Mild, a consistent sync state, and capture mode disabled without its explicit argument.
- Five native screenshots captured from production SwiftUI views on iPhone 17 Pro / iOS 26.5, using the isolated capture fixture. Source PNGs are 1206×2622; the generator reads their dimensions rather than assuming them.
- Visual review: Home's populated estimate and Vitals card; Scan's full header, three steps, oval guide, alignment pill and flip/flash controls; History's populated chart, synced state, PDF button and recent rows; symmetric Learn/Profile margins; all five tab labels visible.
- `npm run typecheck`, `npm run check-assets`, `npm run stills`, and `npm run render`.
- Nine rendered scene/carousel review frames inspected. Only one screenshot is mounted at a time. Phone center is x=960; source images use contain fitting and at most 100% scale.
- ffprobe: H.264, 1920×1080, 30/1 fps, 876 frames, 29.200000 seconds, full-range yuvj420p, no audio stream.
- Full video decoded successfully with bundled ffmpeg (`-c:v libx264 -preset ultrafast -f null -`).
- `git diff --check`.

## Evidence and limits

The WHO problem wording is historical where appropriate and follows the user's approval to remove the unsupported missed-diagnosis causal claim. Sources and regeneration commands are in README.md. The sigmoid caption corresponds to the existing logit-to-probability normalization in `MultiScanHubViewModel.swift`; this work did not change preprocessing, model manifests, fixtures, or inference algorithms.

The capture data is fictional and explicitly identified in the video. Capture mode is Debug/simulator-only, bypasses normal authentication/session lookup, uses a separate profile-defaults suite, does not load saved scan records, does not sync sample records, and does not start camera capture or inference. No real tissue image is used. Vitals remains the app's static sample preview; the visible explanatory copy is retained after removing the DEMO pill.

A separate build attempt forcing `SWIFT_STRICT_CONCURRENCY=complete` onto every third-party dependency caused a Swift compiler crash in FirebaseAuth sources. The normal app-target Swift 6/complete build and focused test pass; third-party build settings were not changed.

Verification was on the simulator. Physical-device camera rotation, torch availability, preview-to-capture alignment with the new 3:4 viewport, orientation changes, and live tissue capture still require a physical-device check. No clinical validity or model-accuracy claim is established by these screenshots. The PDF button's existing preview behavior was not changed or represented as a newly implemented export feature. Other existing repository edits have been preserved.
