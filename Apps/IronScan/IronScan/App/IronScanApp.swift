// MARK: - Application Entry Point (Triggering fresh CI Build)
import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// 1. The Official Firebase Setup
// This guarantees Firebase wakes up at the exact right moment, and keeps the Swizzler perfectly happy.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        #if canImport(FirebaseCore)
        let isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isUnitTesting {
            FirebaseApp.configure()
        }
        #endif
        
        return true
    }
}

@MainActor
final class IronScanAppDependencies: ObservableObject {
    var history: ScanHistoryStore?
    var nearbyCare: LocationManager?
    var multiTissueInference: MultiTissueInferenceActor?

    @Published var isReady = false

    func initializeHeavyDependencies() async {
        history = ScanHistoryStore()
        nearbyCare = LocationManager()
        multiTissueInference = MultiTissueInferenceActor()
        isReady = true
    }
}

@main
struct IronScanApp: App {
    // 2. Attach the AppDelegate to iOS
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // 3. SwiftUI is smart enough to wait until AFTER the AppDelegate runs to load these!
    @StateObject private var dependencies = IronScanAppDependencies()
    @StateObject var authManager = AuthManager()
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage(OnboardingConsent.storageKey) private var acceptedResearchConsent = false

    var body: some Scene {
        WindowGroup {
            Group {
                if dependencies.isReady {
                    if authManager.isAuthenticated {
                        if hasSeenOnboarding {
                            MainTabView()
                                .transition(appRouteTransition)
                        } else {
                            OnboardingFlowView {
                                acceptedResearchConsent = true
                                hasSeenOnboarding = true
                            }
                            .transition(appRouteTransition)
                        }
                    } else {
                        LoginView()
                            .transition(appRouteTransition)
                    }
                } else {
                    AppLaunchLoadingView()
                        .transition(appRouteTransition)
                        .task {
                            await dependencies.initializeHeavyDependencies()
                        }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authManager.isAuthenticated)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasSeenOnboarding)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dependencies.isReady)
            .environmentObject(authManager)
            .environmentObject(dependencies)
            .background(IronTheme.creamBackground.ignoresSafeArea())
            .tint(IronTheme.terracottaPrimary)
            .organicTypography()
        }
    }
}

private var appRouteTransition: AnyTransition {
    AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .scale.combined(with: .opacity)
    )
}

private struct AppLaunchLoadingView: View {
    var body: some View {
        ZStack {
            IronTheme.creamBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(IronTheme.terracottaPrimary)

                Text("Preparing IronScan")
                    .font(IronTheme.roundedFont(.title3, weight: .semibold))
                    .foregroundStyle(IronTheme.textSlate)

                Text("Loading on-device screening and nearby care services.")
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }
}
