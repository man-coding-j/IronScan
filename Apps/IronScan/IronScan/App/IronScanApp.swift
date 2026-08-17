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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var dependencies = IronScanAppDependencies()
    @StateObject var authManager = AuthManager()
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(OnboardingConsent.storageKey) private var acceptedResearchConsent = false

    var body: some Scene {
        WindowGroup {
            Group {
                if dependencies.isReady {
                    if authManager.isAuthenticated {
                        if hasCompletedOnboarding {
                            MainTabView()
                                .transition(appRouteTransition)
                        } else {
                            OnboardingProfileView()
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
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasCompletedOnboarding)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dependencies.isReady)
            .environmentObject(authManager)
            .environmentObject(dependencies)
            .background(IronTheme.creamBackground.ignoresSafeArea())
            .tint(IronTheme.terracottaPrimary)
            .organicTypography()
            .task {
                hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
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

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case summary
        case opticalPatternIndex = "optical_pattern_index"
    }
}

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let storageKey = "ironscan.local.scan-history.v1"
    static let maximumRecordCount = 30

    @Published private(set) var records: [ScanHistoryRecord] = []
    @Published private(set) var userProfile: ScanUserProfile?
    @Published private(set) var persistenceError: String?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedAge = defaults.integer(forKey: "userAge")
        let savedGender = defaults.string(forKey: "userBiologicalSex") ?? "Unknown"
        userProfile = ScanUserProfile(
            age: savedAge > 0 ? String(savedAge) : "Unknown",
            gender: savedGender
        )

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? decoder.decode([ScanHistoryRecord].self, from: data) {
            records = decoded.sorted { $0.capturedAt > $1.capturedAt }
        }
    }

    func fetchHistory() async {
        // Supabase fetch logic will go here
    }

    func saveScan(_ result: Any, capturedAt: Date = Date()) async {
        // Supabase save logic will go here
    }

    func add(_ result: TriangulationResult, capturedAt: Date = Date()) {
        let record = ScanHistoryRecord(
            capturedAt: capturedAt,
            summary: result.summary.rawValue,
            opticalPatternIndex: result.opticalPallorIndex
        )
        records.insert(record, at: 0)
        if records.count > Self.maximumRecordCount {
            records.removeLast(records.count - Self.maximumRecordCount)
        }
        persist()
    }

    private func persist() {
        do {
            defaults.set(try encoder.encode(records), forKey: Self.storageKey)
            persistenceError = nil
        } catch {
            persistenceError = "Local scan history could not be saved."
        }
    }
}

class DemographicProfileStore: ObservableObject {
    @AppStorage("userAge") var age: Int = 25
    @AppStorage("userBiologicalSex") var biologicalSex: String = "Male"
    @AppStorage("isPregnant") var isPregnant: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
}

struct OnboardingProfileView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        ZStack {
            IronScreenBackground()

            VStack {
                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 24) {
                    Text("Welcome to IronScan")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text("IronScan is an educational screening tool and does not provide medical diagnoses. Always consult a licensed physician.")
                        .font(IronTheme.roundedFont(.body))
                        .foregroundStyle(IronTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Prototype Access")
                            .font(IronTheme.roundedFont(.headline, weight: .bold))
                            .foregroundStyle(IronTheme.textPrimary)

                        Text("Continue into the warm beige Liquid Glass experience and begin your first research scan.")
                            .font(IronTheme.roundedFont(.subheadline))
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                    .padding(20)
                    .modifier(LiquidGlassCardStyle(cornerRadius: 24, fill: IronTheme.cardFill))

                    Button("I Agree & Continue") {
                        hasCompletedOnboarding = true
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())
                }
                .padding(28)
                .frame(maxWidth: 560)
                .modifier(LiquidGlassCardStyle(cornerRadius: 32))
                .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
        }
        .padding()
        .background(IronTheme.beigeBackground.ignoresSafeArea())
        .organicTypography()
    }
}
