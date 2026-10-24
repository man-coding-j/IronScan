# Presentation-only demo features

The Home forecast banner appears after two seconds. Home and History each have
an independent, local Watch sync preview: tap Sync Apple Health, wait 1.5 seconds,
then view fixed sample vitals. No HealthKit permission prompt or sample fetch is
triggered by either preview.

History's Explore Nutrition Plan opens a static sheet. Logging a sample
supplement changes its button to green and requests a medium impact haptic once.
The state is not persisted. No supplement dose is recommended.

History's existing Export PDF for Doctor button now opens a dismissible white
report preview. It does not generate or share a PDF. All report values are fixed
fixtures, independent of scan history or model output.

The UI labels these interactions as simulated and non-clinical. Nutrition and
report headings use research-preview language to follow AGENTS.md. The meal's
sample iron number is not presented as an estimate of absorbed iron.

Validation: the new views and existing IronTheme pass an iOS Simulator SDK
typecheck with Swift 6 and complete strict concurrency. The modified Home and
History sources pass Swift parsing, and the Xcode project passes plist lint.
The full Debug app build also passes for the generic iOS Simulator destination
with code signing disabled. Visual layout,
VoiceOver, navigation timing, and physical-device haptic behavior still require
interactive review; no physical-device validation is claimed.
