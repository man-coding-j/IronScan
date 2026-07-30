import Charts
import SwiftUI

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
        GeometryReader { geometry in
            let outerPadding = min(max(geometry.size.width * 0.05, 18), 42)
            let contentWidth = min(geometry.size.width - (outerPadding * 2), 700)

            ZStack(alignment: .bottom) {
                IronScreenBackground()

                Group {
                    switch selection {
                    case .home:
                        HeroDashboardView {
                            selection = .scan
                        }
                    case .history:
                        HistoryView(history: dependencies.history!)
                    case .scan:
                        MultiScanHubView(inference: dependencies.multiTissueInference!) { result in
                            Task {
                                await dependencies.history?.saveScan(result)
                            }
                        }
                    case .learn:
                        LearnView(history: dependencies.history!)
                    case .profile:
                        ProfileView(history: dependencies.history!)
                    }
                }
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, outerPadding)

                tabBar
                    .frame(maxWidth: min(contentWidth, 560))
                    .padding(.horizontal, outerPadding)
                    .padding(.bottom, 12)
            }
            .tint(IronTheme.terracottaPrimary)
            .organicTypography()
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selection)
            .task {
                await dependencies.history?.fetchHistory()
            }
        }
    }

    private var tabBar: some View {
        ZStack {
            HStack(spacing: 0) {
                tabButton(for: .home)
                tabButton(for: .history)
                Spacer(minLength: 90)
                tabButton(for: .learn)
                tabButton(for: .profile)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidGlassCard(cornerRadius: 28)

            Button {
                selection = .scan
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    IronTheme.terracottaPrimary,
                                    Color(red: 1, green: 126 / 255, blue: 76 / 255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: MainTab.scan.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: IronTheme.terracottaPrimary.opacity(0.26), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .offset(y: -26)
        }
    }

    private func tabButton(for tab: MainTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(selection == tab ? IronTheme.terracottaPrimary : IronTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
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
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.84), lineWidth: 1)
                        }

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

    private var points: [HistoryPoint] {
        if history.records.isEmpty {
            return [
                HistoryPoint(label: "May 1", score: 0.38, color: .yellow),
                HistoryPoint(label: "May 15", score: 0.28, color: .green),
                HistoryPoint(label: "May 30", score: 0.45, color: .yellow),
                HistoryPoint(label: "Jun 14", score: 0.32, color: .green),
                HistoryPoint(label: "Today", score: 0.58, color: IronTheme.terracottaPrimary)
            ]
        }

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
                .padding(20)
                .liquidGlassCard()
            }
            .padding(.bottom, 128)
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
        let isHighRisk = latestScan?.summary == .possibleAnemiaRisk
        let isFemale = history.userProfile?.gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "female"

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        }
        .shadow(color: IronTheme.terracottaPrimary.opacity(0.12), radius: 18, y: 10)
    }

    private var featuredRecommendationDetail: String {
        if latestScan?.summary == .possibleAnemiaRisk {
            return "Your recent result suggests prioritizing nutrition guidance and follow-up care articles first."
        }
        if history.userProfile?.gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "female" {
            return "Your feed highlights ferritin and women’s health topics alongside the core anemia basics."
        }
        return "Your feed starts with the most useful anemia education and next-step guidance for new scan data."
    }
}

struct ProfileView: View {
    @ObservedObject var history: ScanHistoryStore
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
                        profileRow("Age Group", "18 – 25")
                        Divider()
                        profileRow("Gender", "Female")
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
            .padding(.bottom, 128)
        }
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
