# IronScan tutorial intro

A 29.2-second silent Remotion animation: 1920×1080, 30 fps, 876 frames. Five React/TypeScript scene components use Fraunces headings, DM Sans body text, original SVG icons, marigold ribbons, glass cards, and actual simulator captures of the app's production SwiftUI views.

## Install, preview, render

Use Node.js 22.18 or newer. From this directory:

```sh
npm ci
npm run check-assets
npx remotion studio
npm run typecheck
npm run stills
npm run render
```

The first render may download Chrome Headless Shell. Google Fonts loading requires network access and blocks rendering until fonts are ready. The output is `out/ironscan-intro.mp4`: H.264, 4:2:0 color, CRF 16, no audio track. All Remotion packages are pinned to matching versions.

## Edit

`src/config.ts` contains editorial text, brand colors, scene durations, asset names, and output paths. The problem placeholder has been replaced with source-backed wording approved in chat. The 1.62 billion estimate is explicitly dated to WHO's 1993–2005 assessment. No claim that blood draws cause millions of missed diagnoses is made.

Sources:

- [WHO: Worldwide prevalence of anaemia 1993–2005](https://www.who.int/publications/i/item/9789241596657)
- [WHO: Anaemia fact sheet](https://www.who.int/news-room/fact-sheets/detail/anaemia)

| Time | Scene |
| --- | --- |
| 0–4 s | IronScan title and updated on-device AI subtitle |
| 4–8 s | Source-backed problem statement and visible WHO attribution |
| 8–14 s | Three tissue cards → on-device AI; tech-stack caption |
| 14–26.2 s | Home, Scan, History, Learn, Profile |
| 26.2–29.2 s | Tutorial handoff and non-clinical disclaimer |

Five 2.2-second screenshot intervals plus four 0.3-second transitions take 12.2 seconds. Only one screenshot is mounted at a time; the old image fades out before the source changes. The phone stays centered at x=960. All captures are measured at load time and contained within the screen, with a gentle zoom that never exceeds 100% scale. Caption cards have a fixed size to avoid layout jumps.

## Re-capture the app screens

The app has an explicitly enabled Debug/simulator-only capture mode. It renders `HomeDashboardView`, `HistoryView`, `MultiScanHubView`, `LearnView`, and `ProfileView` with seven deterministic **fictional** readings ending at 11.8 g/dL / Mild. The history store bypasses disk loading and cloud sync. Profile defaults use a separate suite and the greeting is fictional. Camera startup is disabled; its surface is labeled as a simulator preview. No captured tissue image or participant record is used.

Build on a Mac with Xcode, replacing `DEVICE_ID` with an available, booted simulator UUID:

```sh
# Run from the repository root:
xcodebuild -project Apps/IronScan/IronScan.xcodeproj -scheme IronScan \
  -configuration Debug -destination 'platform=iOS Simulator,id=DEVICE_ID' \
  -derivedDataPath /private/tmp/ironscan-intro-build CODE_SIGNING_ALLOWED=NO build

# Run from Video/IronScanIntro:
python3 scripts/capture-screenshots.py DEVICE_ID \
  /private/tmp/ironscan-intro-build/Build/Products/Debug-iphonesimulator/IronScan.app
npm run stills
npm run render
```

The capture script uses `--tutorial-capture --tutorial-screen=home` (or scan/history/learn/profile). It first saves PNGs in a temporary directory because CoreSimulator cannot write directly to protected Documents folders, then copies them to `public/screenshots/`. Launch the app without these flags to use the ordinary app flow. Capture mode is unavailable in Release or on physical devices.

These five PNGs are the current inputs: `home.png`, `scan.png`, `history.png`, `learn.png`, `profile.png`. `login.png` is not shown. Screenshot files remain local and gitignored; do not replace them with participant data. No screenshot overlays manufacture readings or hide clipping. The image sources themselves are native app captures. Health Vitals remains a static sample preview, as its visible explanatory text states. Camera flip/flash hardware behavior and clinical/model accuracy are not validated by a simulator video.

The optional `public/logo.png` is disabled. Only enable it for your original IronScan mark. The phone frame is drawn with CSS and includes no manufacturer logo.
