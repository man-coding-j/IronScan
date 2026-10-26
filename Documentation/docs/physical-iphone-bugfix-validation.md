# Physical iPhone regression fixes

Date: 2026-10-23. IronScan remains a non-clinical research prototype.

## Shared history and graph

The scan suite wrote numerical `ScanRecord`s into `ScanHistoryManager`, but Home
and History displayed only `ScanHistoryStore.records`. The assessment path did
not produce the legacy triangulation callback that fed that second store.

The app now injects `ScanHistoryManager.shared` and loads it before showing the
main tabs. Home and History observe its shared presentation of canonical records.
The old store remains a migration/cloud transport adapter, preserving its existing
numeric-summary sync payload and old records that lack per-tissue scores. New
canonical records are adapted using their original UUID, so cloud acknowledgements
and reloads cannot duplicate their chart/list entries. The redundant triangulation
callback that created a second UUID was removed. Tutorial capture keeps its
explicit synthetic fixture store; isolated tests use separate UserDefaults suites.

Canonical persistence stays on its storage actor. Writes are ordered and merge
saved records by ID; loading also merges pending additions. This prevents an add
before startup loading finishes from dropping either the new scan or old history.
Only numerical/date/identifier/profile values are encoded, with no image storage.

The trend renders for one numerical measurement. Its date domain has padding even
when all timestamps are identical, and the reference band spans that domain.
Connecting Marigold lines appear only for two or more measurements. Recent History
shows every available record rather than only the first six. Palette, typography,
and existing card/tab styling were not changed.

## Camera

Session/device mutations remain on the camera actor's dedicated serial queue.
Configuration uses `.high` and discovers wide-angle/TrueDepth cameras by requested
position. A swap removes all video device inputs before checking the replacement,
restores the previous inputs if needed, and reapplies portrait/front-only mirroring.
A frame-rate preference cannot fail startup or an otherwise successful flip. Lens changes
can run during stabilization; focus settling happens in a cancellable task after
the swap, with a generation check preventing older start/flip work from changing
newer camera state. UI controls have explicit actions and z-index 10; decorative
guides, status pills, and scan animation remain noninteractive.

The preview layer reapplies its own supported 90-degree rotation and mirroring in
layout, UIView updates, and after session-start notification. The video delegate
normalizes landscape buffers to portrait before delivering them to quality checks,
capture, and image rendering. Front-camera horizontal mirroring is applied only
if the output connection has not already mirrored the pixels. Already portrait,
correctly mirrored buffers pass through without an extra transform. Rendered
UIImages retain `.up` orientation. For landscape buffers already mirrored in sensor
coordinates, normalization rotates left instead of right. An asymmetric four-corner
pixel regression confirms this matches rotating the unmirrored buffer right and
then applying the portrait selfie mirror, avoiding an upside-down selfie.

## Verification

- Physical iOS target build with signing disabled: passed.
- Focused simulator regression suite: 33 passed, zero failures.
- Added coverage: persistence/reload, addition before loading, deduplication by
  canonical UUID, single-point chart rendering and date domain, portrait buffer
  dimensions, mirror round trip, avoiding double mirroring, and lens-change
  recovery from stabilization failure.
- No Swift compiler warnings in those builds. Xcode emits its tooling notice
  that AppIntents metadata extraction was skipped because no framework is used.
- `git diff --check`: passed.
- Latest verification logs: `/tmp/ironscan-bugfix-recheck-device.log`,
  `/tmp/ironscan-bugfix-recheck-tests.log`.

## Still requires the physical iPhone

Using only synthetic or authorized demonstration inputs, confirm top-of-head-up
portrait and native selfie mirroring on both lenses after startup, rotation, and
repeated flips on every scan step. Check rear torch reset and failed-swap recovery.
Complete one scan, check Home/date/count and the single-point chart/list, relaunch
and verify persistence, then complete another scan and verify the connected curve
and absence of duplicate entries. Exercise both live capture and manual assessment
after photo import. Actual hardware orientation, sustained frame rate, and network
sync success are not established by a simulator run or device-target compilation.
