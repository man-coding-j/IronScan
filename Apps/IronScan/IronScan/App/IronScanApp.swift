import SwiftUI

@MainActor
final class IronScanAppDependencies: ObservableObject {
    let history: ScanHistoryStore
    let nearbyCare: LocationManager
    let multiTissueInference: MultiTissueInferenceActor

    init(
        history: ScanHistoryStore = ScanHistoryStore(),
        nearbyCare: LocationManager = LocationManager(),
        multiTissueInference: MultiTissueInferenceActor = MultiTissueInferenceActor()
    ) {
        self.history = history
        self.nearbyCare = nearbyCare
        self.multiTissueInference = multiTissueInference
    }
}

@main
struct IronScanApp: App {
    @StateObject private var dependencies = IronScanAppDependencies()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage(OnboardingConsent.storageKey) private var acceptedResearchConsent = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding, acceptedResearchConsent {
                    MainTabView()
                } else {
                    OnboardingFlowView {
                        acceptedResearchConsent = true
                        hasSeenOnboarding = true
                    }
                }
            }
            .environmentObject(dependencies)
            .background(IronTheme.creamBackground.ignoresSafeArea())
            .tint(IronTheme.terracottaPrimary)
            .organicTypography()
        }
    }
}
