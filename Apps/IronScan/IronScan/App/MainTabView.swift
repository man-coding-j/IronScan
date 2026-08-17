import Charts
import SwiftUI

enum UserBiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    var id: String { rawValue }
}

enum MainTab: String, CaseIterable, Identifiable {
    case home
    case history
    case scan
    case learn
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .scan: "Scan"
        case .learn: "Learn"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .scan: "camera.fill"
        case .learn: "book.closed"
        case .profile: "person"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var dependencies: IronScanAppDependencies
    @State private var selection = MainTab.home

    var body: some View {
        Group {
            if let history = dependencies.history,
               let inference = dependencies.multiTissueInference {
                TabView(selection: $selection) {
                    HomeDashboardView(history: history) {
                        selection = .scan
                    }
                    .tag(MainTab.home)
                    .tabItem { Label(MainTab.home.title, systemImage: MainTab.home.symbol) }

                    HistoryView(history: history)
                        .tag(MainTab.history)
                        .tabItem { Label(MainTab.history.title, systemImage: MainTab.history.symbol) }

                    MultiScanHubView(inference: inference) { result in
                        Task {
                            await history.saveScan(result)
                        }
                    }
                    .tag(MainTab.scan)
                    .tabItem { Label(MainTab.scan.title, systemImage: MainTab.scan.symbol) }

                    LearnView(history: history)
                        .tag(MainTab.learn)
                        .tabItem { Label(MainTab.learn.title, systemImage: MainTab.learn.symbol) }

                    ProfileView(history: history)
                        .tag(MainTab.profile)
                        .tabItem { Label(MainTab.profile.title, systemImage: MainTab.profile.symbol) }
                }
            } else {
                ProgressView("Loading history")
            }
        }
        .tint(IronTheme.terracottaPrimary)
        .organicTypography()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selection)
        .task {
            await dependencies.history?.fetchHistory()
        }
    }
}

private struct HeroDashboardView: View {
    let onStartScan: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(IronTheme.terracottaPrimary)
                    Text("IronScan")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Text("Smart. Simple. Non-Invasive.\nAnemia Screening for Everyone.")
                        .font(IronTheme.roundedFont(.title3))
                        .foregroundStyle(IronTheme.textMuted)
                }
                .padding(.top, 16)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.54))
                        .frame(width: 256, height: 256)
                        .liquidGlassPanel(in: Circle(), interactive: false)

                    GlossyTerracottaDrop()
                        .frame(width: 126, height: 166)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Check your iron levels in under 2 minutes.")
                        .font(IronTheme.roundedFont(.title3, weight: .medium))
                        .foregroundStyle(IronTheme.textSlate)

                    Button(action: onStartScan) {
                        IronCTAButtonLabel(title: "Get Started")
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())
                }
                .padding(20)
                .liquidGlassCard(cornerRadius: 28)
            }
            .padding(.bottom, 128)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var history: ScanHistoryStore
    @State private var shareDocument: ShareablePDFDocument?
    @State private var exportError: String?

    private var points: [HistoryPoint] {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return history.records
            .prefix(5)
            .reversed()
            .map {
                HistoryPoint(
                    label: formatter.string(from: $0.capturedAt),
                    score: $0.opticalPatternIndex ?? 0,
                    color: color(for: tier(for: $0.opticalPatternIndex ?? 0))
                )
            }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Your History")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(IronTheme.textSlate)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.68), in: Circle())
                }
                .padding(.top, 16)

                Group {
                    if points.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(IronTheme.textMuted)
                            Text("No scans yet")
                                .font(IronTheme.roundedFont(.headline, weight: .bold))
                                .foregroundStyle(IronTheme.textSlate)
                            Text("Take your first scan to see your trends!")
                                .font(IronTheme.roundedFont(.subheadline))
                                .foregroundStyle(IronTheme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                                LineMark(
                                    x: .value("Date", point.label),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(IronTheme.sageAccent)
                                .interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Date", point.label),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(point.color)
                                .symbolSize(90)
                            }
                            .chartYScale(domain: 0 ... 1)
                            .chartYAxis(.hidden)
                            .frame(height: 180)

                            VStack(spacing: 0) {
                                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                                    HStack {
                                        Text(point.label)
                                            .foregroundStyle(IronTheme.textMuted)
                                        Spacer()
                                        Text(point.score.formatted(.number.precision(.fractionLength(2))))
                                            .fontWeight(.bold)
                                        Text(tier(for: point.score).title)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(color(for: tier(for: point.score)))
                                        Circle()
                                            .fill(color(for: tier(for: point.score)))
                                            .frame(width: 8, height: 8)
                                    }
                                    .font(IronTheme.roundedFont(.subheadline))
                                    .padding(.vertical, 14)

                                    if index < points.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .liquidGlassCard()

                Button(action: exportPDF) {
                    IronCTAButtonLabel(title: "Export PDF for Doctor")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
            }
            .padding(.bottom, 128)
        }
        .sheet(item: $shareDocument) { document in
            ActivityShareSheet(activityItems: [document.url])
        }
        .alert("PDF Export Unavailable", isPresented: exportAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "The PDF could not be created.")
        }
    }

    private func tier(for score: Double) -> RiskBand {
        switch score {
        case ..<0.30:
            RiskBand(title: "Low Risk", color: .green)
        case ..<0.70:
            RiskBand(title: "Moderate", color: .yellow)
        default:
            RiskBand(title: "High Risk", color: IronTheme.terracottaPrimary)
        }
    }

    private func color(for band: RiskBand) -> Color {
        band.color
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func exportPDF() {
        if let url = PDFReportGenerator.generateReport(for: history.records.first, history: history.records) {
            shareDocument = ShareablePDFDocument(url: url)
        } else {
            exportError = "The PDF could not be created."
        }
    }
}

struct LearnView: View {
    @ObservedObject var history: ScanHistoryStore

    private let allArticles: [LearnArticle] = [
        LearnArticle(
            icon: "fork.knife",
            tint: IronTheme.terracottaPrimary,
            title: "Iron-Rich Diet Essentials",
            subtitle: "Foods and meal pairings that can support healthy iron intake.",
            tags: [.highRisk, .diet]
        ),
        LearnArticle(
            icon: "cross.case.fill",
            tint: IronTheme.terracottaPrimary,
            title: "When to Consult a Physician",
            subtitle: "Signs that lab work and a clinician conversation are worth prioritizing.",
            tags: [.highRisk, .physician]
        ),
        LearnArticle(
            icon: "drop.fill",
            tint: IronTheme.sageAccent,
            title: "Ferritin and Iron Stores",
            subtitle: "Understand how ferritin relates to iron deficiency and follow-up testing.",
            tags: [.femaleFocus, .ferritin]
        ),
        LearnArticle(
            icon: "person.2.fill",
            tint: IronTheme.sageAccent,
            title: "Women’s Iron Health",
            subtitle: "Why menstruation, pregnancy, and recovery needs can affect iron balance.",
            tags: [.femaleFocus]
        ),
        LearnArticle(
            icon: "book.closed.fill",
            tint: IronTheme.sageAccent,
            title: "What Is Anemia?",
            subtitle: "A practical primer on symptoms, causes, and common next steps.",
            tags: [.general]
        )
    ]

    private var latestScan: ScanHistoryRecord? {
        history.records.first
    }

    private var personalizedArticles: [LearnArticle] {
        let isHighRisk = latestScan?.summary == OpticalRiskSummary.possibleAnemiaRisk.rawValue
        let isFemale = history.userProfile?.gender?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() == "female"

        return allArticles
            .map { article in
                var priority = 0
                if isHighRisk, article.tags.contains(.highRisk) || article.tags.contains(.diet) || article.tags.contains(.physician) {
                    priority += 3
                }
                if isFemale, article.tags.contains(.femaleFocus) || article.tags.contains(.ferritin) {
                    priority += 2
                }
                if article.tags.contains(.general) {
                    priority += 1
                }
                return (article, priority)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title < rhs.0.title
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Learn More")
                    .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    .padding(.top, 16)

                featuredRecommendationCard

                VStack(spacing: 14) {
                    ForEach(personalizedArticles) { article in
                        LearnCard(article: article)
                    }
                }
            }
            .padding(.bottom, 128)
        }
    }

    private var featuredRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended based on your latest scan.")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Text(featuredRecommendationDetail)
                .font(IronTheme.roundedFont(.subheadline))
                .foregroundStyle(IronTheme.textMuted)
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 26, interactive: true)
    }

    private var featuredRecommendationDetail: String {
        if latestScan?.summary == OpticalRiskSummary.possibleAnemiaRisk.rawValue {
            return "Your recent result suggests prioritizing nutrition guidance and follow-up care articles first."
        }
        if history.userProfile?.gender?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() == "female" {
            return "Your feed highlights ferritin and women’s health topics alongside the core anemia basics."
        }
        return "Your feed starts with the most useful anemia education and next-step guidance for new scan data."
    }
}

struct ProfileView: View {
    @ObservedObject var history: ScanHistoryStore
    @AppStorage("userAge") private var userAge = 18
    @AppStorage("userBiologicalSex") private var userBiologicalSex = "Other"
    @AppStorage("isPregnant") private var isPregnant = false
    @State private var remindersEnabled = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Profile")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Spacer()
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(IronTheme.textSlate)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.68), in: Circle())
                }
                .padding(.top, 16)

                VStack(spacing: 18) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.92), Color.white.opacity(0.42)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 118, height: 118)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 78))
                                    .foregroundStyle(IronTheme.sageAccent)
                            }

                        Circle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(IronTheme.textSlate)
                            }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personal Info")
                            .font(IronTheme.roundedFont(.headline, weight: .bold))
                        profileRow("Age", "\(userAge)")
                        Divider()
                        profileRow("Biological Sex", userBiologicalSex)
                        if userBiologicalSex == UserBiologicalSex.female.rawValue {
                            Divider()
                            profileRow("Pregnancy Status", isPregnant ? "Currently Pregnant" : "Not Pregnant")
                        }
                        Divider()
                        profileRow("Saved Scans", "\(history.records.count)")
                    }
                }
                .padding(20)
                .liquidGlassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Reminders")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))

                    Toggle(isOn: $remindersEnabled) {
                        Text("Scan Reminder")
                            .font(IronTheme.roundedFont(.body, weight: .medium))
                    }
                    .tint(IronTheme.terracottaPrimary)
                }
                .padding(20)
                .liquidGlassCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 128)
        }
        .background(IronScreenBackground())
    }

    private func profileRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(IronTheme.textMuted)
            Spacer()
            Text(value)
                .foregroundStyle(IronTheme.textSlate)
        }
        .font(IronTheme.roundedFont(.subheadline))
    }
}

private struct LearnArticle: Identifiable {
    enum Tag: Hashable {
        case highRisk
        case diet
        case physician
        case femaleFocus
        case ferritin
        case general
    }

    var id: String { title }
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let tags: Set<Tag>
}

private struct LearnCard: View {
    let article: LearnArticle

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 60, height: 60)
                Image(systemName: article.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(article.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                Text(article.subtitle)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IronTheme.textMuted)
        }
        .padding(18)
        .liquidGlassCard()
    }
}

private struct HistoryPoint {
    let label: String
    let score: Double
    let color: Color
}

private struct RiskBand {
    let title: String
    let color: Color
}
