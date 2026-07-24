# System overview

IronScan is a non-clinical research prototype. The SwiftUI iOS application captures a standardized image, performs segmentation and deterministic color calibration, and runs Core ML risk inference locally. The optional FastAPI server stores anonymous engineering metrics only and is not required for inference.

Raw images remain local unless Developer Mode and debug image uploads are both explicitly enabled. Rejected calibration produces `Unable to assess` and does not invoke risk inference.

## iOS navigation and local state

`IronScanApp` owns first-launch routing through the local `hasSeenOnboarding` flag and the versioned research-consent flag. First launch presents a three-page organic onboarding flow over a cream, terracotta, slate, and sage design system. The flow introduces the optical research purpose, provides a non-persistent account-layout preview, and requires explicit research-limitations consent before opening the optional local context intake. Password fields are cleared before leaving their page, no account is created, and no credential is submitted or persisted. `MainTabView` owns only the three-tab application shell and does not duplicate onboarding state.

After one-time research consent and the optional context handoff, `MainTabView` presents three custom SwiftUI destinations:

- **Home** displays categorical research summaries, a Swift Charts trend of accepted optical-pattern indices, and recent scan dates.
- **Scan** owns the existing actor-isolated eye, nail, and tongue capture flow. Completion presents `IntegratedResearchReportView` as a liquid-glass sheet.
- **Care & Labs** provides general educational content and an optional MapKit search across diagnostic laboratories, Quest Diagnostics, Labcorp, urgent-care centers, and hospitals. Tappable results expose Apple Maps phone, website, address, distance, and driving-direction actions when that metadata is available.

On iOS 26 and later, floating cards, controls, onboarding actions, and the custom tab bar use SwiftUI Liquid Glass through `glassEffect` and `GlassEffectContainer`. The iOS 18 deployment path uses an equivalent material-and-stroke fallback. Shared legacy color aliases resolve to the organic palette so existing screens adopt the new theme without duplicating color constants.

`ScanHistoryStore` persists at most 30 compact result summaries in `UserDefaults`. It stores date, allowed categorical summary, research optical-pattern index, and number of included tissue checks. It never stores captured images, participant identifiers, questionnaire responses, or location.

Location permission is requested only after the user selects **Find nearby care**. Core Location supplies a transient current coordinate to MapKit local search; IronScan does not persist or log the coordinate. Search results are informational and users must contact each location to confirm CBC laboratory services. MapKit does not expose dependable operating hours through `MKMapItem`, so the detail sheet labels category-based schedules as prototype estimates and never presents them as live open/closed status. Call, website, and Apple Maps actions leave IronScan and follow the selected system service’s privacy behavior.

## Health guidance

`IntegratedResearchReportView` separates general iron education from scan-based follow-up guidance. `HealthGuidanceView` presents expandable food-source, vitamin C, and meal-timing information using cautious educational language. `PersonalizedPlanEngine` combines only the displayed categorical optical summary with optional locally stored diet, symptom, and menstrual-history context to choose follow-up copy.

Questionnaire context never changes a Core ML probability, tissue result, uncertainty value, or fused optical score. The plan does not estimate iron or hemoglobin, recommend supplements or medication, establish a diagnosis, or prescribe a re-scan interval. Visual concerns and persistent reported concerns direct the user to confirm with a laboratory test and a licensed clinician.
