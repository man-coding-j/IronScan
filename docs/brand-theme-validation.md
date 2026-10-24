# Brand theme validation

The brand board is used only for palette, serif typography, and looping background curves. Existing screen sections, controls, SF Symbols, component ordering, spacing, frames, and camera target geometry are preserved. The theme contains the exact #145247, #FAA805, #CDE0E4, and #E8D9C9 tokens. The shared background draws two marigold cubic Bézier ribbons on a sand canvas and is hidden from accessibility and hit testing.

The repository currently uses SwiftUI's native TabView. Its existing tab hierarchy and native material behavior are retained, with UITabBarAppearance supplying teal glass, sand inactive items, and a marigold selection indicator. A replacement custom tab bar was not introduced. Existing CTA shapes and dimensions are also retained.

Validation performed:

- Debug iOS Simulator build with code signing disabled passed using Xcode 26.6.
- Isolated theme type checking with strict concurrency set to complete passed.
- Swift syntax parsing and git diff whitespace checks passed.
- Compared the modified screens with their pre-edit working copies: SF Symbol names, text/label literals, padding, frame, aspect ratio, offset, and position modifiers remain unchanged.

Outstanding visual validation:

- No simulator screenshots or physical-device visual review were performed.
- Confirm native tab selection rendering on iOS 18 and iOS 26; the OS controls native tab geometry and Liquid Glass compositing.
- Check ribbon visibility through materials while scrolling, light/dark appearances, Reduce Transparency, and text wrapping at accessibility Dynamic Type sizes. Serif font metrics may change wrapping despite unchanged layout constraints.

This is a presentation-only change to the non-clinical research prototype. Camera capture, inference, preprocessing, persistence, and participant-data handling are unchanged.
