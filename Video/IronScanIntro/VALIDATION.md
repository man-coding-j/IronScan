# 32-second / 60 fps intro verification

## Passed

- `npm run typecheck` and `npm run check-assets`.
- `npm run stills`: 24 representative scene, import-phase, and transition-boundary PNGs rendered. Title credits, acquisition pill, PhotosUI caption, three filled vector thumbnails, laser/HUD, 100% completion/image release, three-point trend, six counters/progress segments, and closing disclaimer inspected.
- `npm run render`: `out/new.mp4` generated locally.
- ffprobe: 1920×1080, 60/1 fps, 1,920 frames, exactly 32.000000 seconds, H.264, no audio stream.
- `scripts/verify-output.py`: decoded all 1,020 carousel frames from the actual encoded MP4. Checked all 972 fully visible phone frames and every internal-transition frame against a blank-interior detector. Deliberate scene-entry and closing fades are excluded.
- Zero blank phone frames. All five transitions (16, 19, 23, 26, 28 seconds) passed for all 18 frames each: 90 transition frames checked. Minimum deep-teal UI coverage in any checked phone interior was 7,922 pixels, above the 300-pixel minimum. A plain warm-sand negative-control image correctly returns zero pixels.
- Full MP4 decode passed separately using bundled ffmpeg.
- `git diff --check`.

Machine-readable results: `out/transition-verification.json`. Verification checks the encoded images, not only the React timeline. It detects a blank warm-sand phone interior; visual review separately covers readability and layout.

## Sources and scope

The 32-second motion update changed the video generator and documentation, not Swift behavior or inference. The subsequent repository organization relocates Swift/model files byte-for-byte; see `../../docs/repository-organization-validation.md`. Home, Learn, and Profile use the retained native simulator screenshots with fictional records. Live scan, the new import workflow, and the requested three-point history chart are original React/SVG UI illustrations. The video explicitly identifies fictional data and an illustrated workflow. No real tissue image, participant record, emoji, external icon pack, or manufacturer logo was added.

The app's current `MultiScanHubViewModel` was inspected: photo import stores selected images separately from assessment, and `purgeSessionImages()` clears session-owned references after analysis. Its comments explicitly do not promise RAM zeroing. The animation therefore qualifies the requested RAM/privacy copy: it concerns imported working copies, library originals remain, and reference release is not guaranteed memory zeroing. The four-second sequence is a demonstration, not an inference benchmark or proof of a privacy/security property.

The WHO statistic remains explicitly dated to its 1993–2005 assessment, with the source attribution shown in the video. References and commands are in README.md.

Physical camera/torch behavior, clinical validity, model accuracy, memory zeroization, and deleting Photos-library originals are not established by this motion video. The new workflow is intentionally mocked as requested.
