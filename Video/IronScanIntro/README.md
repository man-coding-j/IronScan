# IronScan intro — 32 seconds at 60 fps

A silent 1920×1080 Remotion MP4 with the IronScan warm sand, deep teal, marigold, glacier blue, editorial serif, and glass-card aesthetic. Six phone slides include an animated three-photo import / laser scan / image-release workflow.

## Install, preview, render

Node.js 22.18 or newer:

```sh
npm ci
npm run check-assets
npx remotion studio
npm run typecheck
npm run stills
npm run export-readme
npm run render
```

Output: `out/new.mp4` — H.264, CRF 16, 60 fps, 1920 frames, exactly 32 seconds, no audio stream. The prior `out/ironscan-intro.mp4` is retained separately. First use can download Chrome Headless Shell; Google Fonts require network access and block rendering until loaded.

## Editorial control panel

`src/config.ts` contains copy, colors, timing, per-slide durations, filenames, review times, and video-verification settings. Each scene has a separate component. `src/scenes/PhoneScreens.tsx` contains original code-native phone UI, SVG anatomical illustrations, the laser/HUD, and the three-point chart. No emojis, patient photos, external icon packs, or manufacturer logos are added.

| Time | Scene / phone caption |
| --- | --- |
| 0–4 s | IronScan title, updated subtitle, Naman Jain & Ved Patel credit |
| 4–8 s | WHY IT MATTERS, dated WHO estimate and visible citation |
| 8–13 s | How it works; live-or-library pill; RAM caption; PhotosUI tech stack |
| 13–16 s | 01 / 06 — Your dashboard |
| 16–19 s | 02 / 06 — Guided 3-step live scan |
| 19–23 s | 03 / 06 — Import photos & private AI scan |
| 23–26 s | 04 / 06 — Track trends over time |
| 26–28 s | 05 / 06 — Learn about iron health |
| 28–30 s | 06 / 06 — Your profile |
| 30–32 s | Tutorial handoff and non-clinical disclaimer |

The import slide highlights the Photos pill, fills three synthetic anatomical thumbnails with completion borders/checks, sweeps a 3-pixel glowing laser, pulses telemetry nodes, fills fusion progress to 100%, then clears the image illustrations and shows shields. The right caption and HUD distinguish releasing imported working copies from deleting originals in the Photos library or guaranteeing memory zeroing.

## Phone sources and privacy

Home, Learn, and Profile use the existing native simulator captures in `public/screenshots/demo-*.png`. These three public fixture images are versioned so a fresh checkout can render the intro. Their sample profile and seven scan records are fictional. Live scan, import, and three-point History are deliberately **illustrated React/SVG UI**, not new app recordings or model evaluations. The chart shows 10.9 → 11.4 → 11.8 g/dL and a glacier reference band. The original native scan/history PNGs remain local and are not used in this video.

The app's `purgeSessionImages()` releases session-owned image references; its source explicitly does not promise RAM zeroing. This video adds no raw tissue images and makes no claim that originals are deleted from the Photos library. The four-second animation demonstrates a workflow rather than measuring inference duration. The visible non-clinical disclaimer remains.

Personal/local captures remain gitignored; only the three explicitly named fictional `demo-*.png` fixtures are versioned. Optional `public/logo.png` remains disabled. Do not substitute participant photos for the vector illustrations.

To regenerate the three native screenshot inputs, build the app for a booted simulator and use the existing isolated capture mode:

```sh
# From the repository root (replace DEVICE_ID):
xcodebuild -project Apps/IronScan/IronScan.xcodeproj -scheme IronScan \
  -configuration Debug -destination 'platform=iOS Simulator,id=DEVICE_ID' \
  -derivedDataPath /private/tmp/ironscan-intro-build CODE_SIGNING_ALLOWED=NO build

# From Video/IronScanIntro:
python3 scripts/capture-screenshots.py DEVICE_ID \
  /private/tmp/ironscan-intro-build/Build/Products/Debug-iphonesimulator/IronScan.app
```

## Cross-dissolve and blank-frame verification

At each internal change, the outgoing screen stays fully opaque beneath the incoming one. Only the incoming layer's opacity changes. This produces `previous × (1 − blend) + next × blend` without exposing the sand canvas. A 0.3-second dissolve starts at 16, 19, 23, 26, and 28 seconds. The six progress segments and captions use the same timeline.

Verify the **encoded MP4**, not just the component logic, with Python and NumPy (the repository virtualenv already supplies NumPy):

```sh
../../.venv/bin/python scripts/verify-output.py
```

The verifier checks dimensions, fps, frame count, duration, codec, and absence of audio, then decodes all 1,020 carousel frames. It checks deep-teal UI pixel coverage within the phone interior in every fully visible phone frame and all 90 internal-transition frames. A blank warm-sand image is the detector's negative control. Only the deliberate scene-entry and closing fades are excluded. A second pass decodes the entire video. The report is saved to `out/transition-verification.json`. Representative PNGs, including boundary frames and import phases, are in `out/stills/`.

## Sources

- [WHO: Worldwide prevalence of anaemia 1993–2005](https://www.who.int/publications/i/item/9789241596657)
- [WHO: Anaemia fact sheet](https://www.who.int/news-room/fact-sheets/detail/anaemia)

The historical 1.62 billion estimate remains explicitly dated. No claim about blood draws causing millions of missed diagnoses is introduced.
