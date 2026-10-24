# Camera flip and demo baseline reset

Date: 2026-10-23. IronScan is a non-clinical research prototype.

The active scan suite puts its flip/torch controls last in the preview ZStack at
zIndex 999. The flip button has an explicit action, circular 48-point target,
and medium impact feedback. The alternate scan toolbar keeps its 44-point target
and now also supplies haptic feedback and a raised stacking order. Decorations
remain noninteractive. Existing colors, typography, Liquid Glass materials, and
CoreML logic are preserved.

MedicalCameraManager already delegates directly through CameraSessionControlling
to CameraSessionActor. The requested sessionQueue code is implemented through
that existing dedicated serial executor rather than adding session/device state
to the MainActor manager. Discovery includes wide-angle, TrueDepth, dual, and
triple devices at the requested position. The actor checks support for `.high`,
removes all video inputs, restores previous inputs if replacement fails, and
publishes capabilities only for the installed lens. Portrait rotation/front-only
mirroring remain applied to output and preview connections. No per-tissue camera
position override was found in the hub view/model; optics changes retain the lens.

Profile's bottom Demo Data card provides the two requested reset buttons. The
baseline is two fictional numerical samples: 10.9 g/dL/moderate four calendar days
ago, then 11.4 g/dL/mild two days ago. They carry an optional Codable demo marker
(backward compatible with existing scans), appear as “Synthetic demo baseline,”
and are excluded from the cloud transport adapter. The next scan follows the
existing inference/save path; its value and curve direction are not forced.

Reset updates shared presentation immediately, clears both canonical and legacy
local history, and orders replacement after pending writes. Replacement bypasses
the normal merge-on-save behavior so deleted records cannot return on relaunch.
An in-progress startup load cannot restore records from before the reset. The
legacy cache reset runs on the utility queue; records added during it are saved
after completion. Reset invalidates pending sync acknowledgements and pre-network
checks. It does not delete previously uploaded cloud rows or retract an upload
already in flight. Profile, consent settings, and raw image handling are unchanged.

Verification:
- iPhone target build, signing disabled: passed.
- Focused simulator regressions: 36 passed, zero failures, including three new
  reset/baseline tests. Covers persistence/relaunch, pending writes, pending
  additions, repeat seeding, legacy cache removal, synthetic sync exclusion,
  preserved profile, and a live third numerical record.
- No Swift compiler warnings; Xcode reports its existing skipped AppIntents
  metadata extraction notice.
- `git diff --check`: passed.
- Final logs: `/tmp/ironscan-demo-reset-device-final.log` and
  `/tmp/ironscan-demo-reset-tests-final.log`.

Physical-device checks still required, using synthetic or authorized demo inputs:
1. Flip repeatedly on each scan step; feel the haptic, confirm the lens remains
   selected after step changes, and confirm upright portrait/front-only mirroring.
2. Enable the rear torch, flip to front and back, and verify it stays off until
   explicitly toggled again. Exercise interruption and failed-swap recovery.
3. Use Profile to seed exactly two chart/list entries; relaunch to verify them.
   Complete a live third scan and verify its actual result appears as point three.
4. Clear scans, relaunch, and confirm all local counts/chart/list start at zero.

Compilation and simulator tests do not establish physical tap delivery, lens
availability, torch operation, preview orientation, or sustained camera behavior.
