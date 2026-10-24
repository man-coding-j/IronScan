// Explicit dependency for Xcode’s app-intents metadata extraction phase.
import AppIntents
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

@MainActor
final class IronScanAppDependencies: ObservableObject {
    var history: ScanHistoryStore?
    var nearbyCare: LocationManager?
    var multiTissueInference: MultiTissueInferenceActor?
    var healthKit: HealthKitManager?

    @Published var isReady = false

    func initializeHeavyDependencies() async {
        let store = ScanHistoryStore()
        ScanHistoryManager.shared.connectSyncStore(store)
        await ScanHistoryManager.shared.loadData()
        history = store
        nearbyCare = LocationManager()
        multiTissueInference = MultiTissueInferenceActor()
        healthKit = HealthKitManager()
        isReady = true
    }
}

@main
struct IronScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var dependencies = IronScanAppDependencies()
    @StateObject var authManager = AuthManager()
    @StateObject private var historyManager = ScanHistoryManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if TutorialCapture.isEnabled {
                    TutorialCaptureRoot()
                        .defaultAppStorage(TutorialCapture.defaults)
                } else if dependencies.isReady {
                    if !authManager.isAuthenticated {
                        LoginView()
                            .transition(appRouteTransition)
                    } else if authManager.isCheckingOnboarding {
                        AppLaunchLoadingView()
                            .transition(appRouteTransition)
                    } else if !authManager.hasCompletedOnboarding {
                        OnboardingProfileView {
                            authManager.markOnboardingCompleted()
                        }
                        .transition(appRouteTransition)
                    } else {
                        MainTabView()
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
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authManager.hasCompletedOnboarding)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authManager.isCheckingOnboarding)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dependencies.isReady)
            .environmentObject(authManager)
            .environmentObject(dependencies)
            .environmentObject(historyManager)
            .background(IronTheme.creamBackground.ignoresSafeArea())
            .tint(IronTheme.terracottaPrimary)
            .organicTypography()
            .onOpenURL { url in
                Task {
                    await authManager.handleIncomingURL(url)
                }
            }
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

struct ScanUserProfile: Codable, Sendable {
    var age: String
    var gender: String?
}

struct ScanHistoryRecord: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var capturedAt: Date = Date()
    var summary: String
    var opticalPatternIndex: Double?
    var severity: AnemiaSeverity = .normal
    var estimatedHemoglobin: Double?
    var isSyncedToCloud: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case summary
        case opticalPatternIndex = "optical_pattern_index"
        case severity
        case estimatedHemoglobin = "estimated_hemoglobin"
        case isSyncedToCloud = "is_synced_to_cloud"
    }

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        summary: String,
        opticalPatternIndex: Double?,
        severity: AnemiaSeverity? = nil,
        estimatedHemoglobin: Double? = nil,
        isSyncedToCloud: Bool = false
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.summary = summary
        self.opticalPatternIndex = opticalPatternIndex
        self.severity = severity ?? AnemiaSeverity.from(probability: opticalPatternIndex)
        self.estimatedHemoglobin = estimatedHemoglobin
        self.isSyncedToCloud = isSyncedToCloud
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
        summary = try container.decode(String.self, forKey: .summary)
        opticalPatternIndex = try container.decodeIfPresent(Double.self, forKey: .opticalPatternIndex)
        severity = try container.decodeIfPresent(AnemiaSeverity.self, forKey: .severity)
            ?? AnemiaSeverity.from(probability: opticalPatternIndex)
        estimatedHemoglobin = try container.decodeIfPresent(Double.self, forKey: .estimatedHemoglobin)
        isSyncedToCloud = try container.decodeIfPresent(Bool.self, forKey: .isSyncedToCloud) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(opticalPatternIndex, forKey: .opticalPatternIndex)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(estimatedHemoglobin, forKey: .estimatedHemoglobin)
        try container.encode(isSyncedToCloud, forKey: .isSyncedToCloud)
    }
}
