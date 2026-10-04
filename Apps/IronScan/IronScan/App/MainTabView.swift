import Charts
import PhotosUI
import SwiftUI
import UIKit

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
    @EnvironmentObject private var historyManager: ScanHistoryManager
    @State private var selection = MainTab.home

    var body: some View {
        Group {
            if let history = dependencies.history,
               let inference = dependencies.multiTissueInference,
               let healthKit = dependencies.healthKit {
                TabView(selection: $selection) {
                    HomeDashboardView(history: history, healthKit: healthKit) {
                        selection = .scan
                    }
                    .tag(MainTab.home)
                    .tabItem { Label(MainTab.home.title, systemImage: MainTab.home.symbol) }

                    HistoryView(history: history) {
                        selection = .scan
                    }
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
            await historyManager.loadData()
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
    @EnvironmentObject var historyManager: ScanHistoryManager
    @ObservedObject var history: ScanHistoryStore
    let startScan: () -> Void
    @State private var shareDocument: ShareablePDFDocument?
    @State private var exportError: String?

    private var recentHistoryRecords: [ScanHistoryRecord] {
        DashboardHistoryRecords.from(historyManager.records)
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

                syncStatusBanner

                VStack(alignment: .leading, spacing: 14) {
                    Text("Hemoglobin Trend")
                        .font(IronTheme.roundedFont(.title3, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    HistoricalHemoglobinTrendCard(
                        records: recentHistoryRecords,
                        height: 260,
                        emptyMessage: "Complete at least two scans to reveal your longitudinal recovery curve."
                    )
                }

                Button(action: exportPDF) {
                    IronCTAButtonLabel(title: "Export PDF for Doctor")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())

                recentHistorySection
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
        .background(IronTheme.beigeBackground.ignoresSafeArea())
    }

    private var syncStatusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(history.pendingSyncCount == 0 ? IronTheme.sageAccent : IronTheme.warning)
                .frame(width: 8, height: 8)

            Text(history.syncStatusText)
                .font(IronTheme.roundedFont(.caption, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent History")
                    .font(IronTheme.roundedFont(.title3, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)
                Spacer()
                Button("Start Scan", action: startScan)
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.terracottaPrimary)
            }

            if recentHistoryRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(IronTheme.textSecondary)

                    Text("No scans yet")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text("Take your first scan to see your trends!")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .liquidGlassCard(cornerRadius: 26)
            } else {
                VStack(spacing: 12) {
                    ForEach(recentHistoryRecords.prefix(6)) { record in
                        historyRow(record)
                    }
                }
            }
        }
    }

    private func historyRow(_ record: ScanHistoryRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color(for: record.summary).opacity(0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: symbol(for: record.summary))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color(for: record.summary))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: record.summary))
                    .font(IronTheme.roundedFont(.headline, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)

                Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(IronTheme.roundedFont(.caption))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(record.opticalPatternIndex?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 22)
    }

    private func title(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "Lower observed risk"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "Possible anemia risk"
        default:
            return summary
        }
    }

    private func symbol(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "checkmark.circle.fill"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "exclamationmark.triangle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private func color(for summary: String) -> Color {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return IronTheme.sageAccent
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return IronTheme.warning
        default:
            return IronTheme.textSecondary
        }
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func exportPDF() {
        if let url = PDFReportGenerator.generateReport(for: recentHistoryRecords.first, history: recentHistoryRecords) {
            shareDocument = ShareablePDFDocument(url: url)
        } else {
            exportError = "The PDF could not be created."
        }
    }
}

struct LearnView: View {
    @ObservedObject var history: ScanHistoryStore
    @AppStorage("userGender") private var userGender: String = ""

    private var latestScan: ScanHistoryRecord? {
        history.records.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Learn More")
                    .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    .padding(.top, 16)

                featuredRecommendationCard

                VStack(spacing: 14) {
                    LearnDisclosureCard(
                        title: "What is Anemia?",
                        summary: "A quick overview of what anemia is and why hemoglobin matters.",
                        source: "Source: World Health Organization, Anaemia fact sheet.",
                        url: Self.safeURL("https://www.who.int/news-room/fact-sheets/detail/anaemia"),
                        content: "Anemia happens when the body does not have enough healthy red blood cells or hemoglobin to carry oxygen efficiently. That can leave people feeling tired, weak, short of breath, or lightheaded."
                    )

                    LearnDisclosureCard(
                        title: "Symptoms of Iron Deficiency",
                        summary: "Common signs that can be associated with low iron or iron-deficiency anemia.",
                        source: "Source: Mayo Clinic, Iron deficiency anemia overview.",
                        url: Self.safeURL("https://www.mayoclinic.org/diseases-conditions/iron-deficiency-anemia/symptoms-causes/syc-20355034"),
                        content: "Symptoms can include fatigue, weakness, pale skin, headaches, dizziness, brittle nails, or reduced exercise tolerance. These symptoms are not specific to iron deficiency, but they can be useful prompts for follow-up."
                    )

                    LearnDisclosureCard(
                        title: "Iron-Rich Foods",
                        summary: "Food choices that can help support healthy iron intake.",
                        source: "Source: World Health Organization, Healthy diet guidance.",
                        url: Self.safeURL("https://www.who.int/news-room/fact-sheets/detail/healthy-diet"),
                        content: "Iron-rich options include lean meats, beans, lentils, tofu, spinach, fortified cereals, and pumpkin seeds. Pairing plant-based iron sources with vitamin C-rich foods can improve absorption."
                    )

                    if userGender == "Female" {
                        LearnDisclosureCard(
                            title: "Menstruation and Iron Loss",
                            summary: "Why menstrual bleeding can affect iron balance over time.",
                            source: "Source: Office on Women’s Health, Iron-deficiency anemia.",
                            url: Self.safeURL("https://womenshealth.gov/a-z-topics/iron-deficiency-anemia"),
                            content: "Menstrual blood loss is a common reason iron stores can drop, especially when periods are heavy or prolonged. Recurrent monthly loss can make it harder to keep up with iron needs through diet alone."
                        )
                    }
                }
            }
            .padding(.bottom, 128)
        }
        .background(IronTheme.beigeBackground.ignoresSafeArea())
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

    private static func safeURL(_ value: String) -> URL {
        URL(string: value) ?? URL(fileURLWithPath: "/unavailable-resource")
    }

    private var featuredRecommendationDetail: String {
        if latestScan?.summary == OpticalRiskSummary.possibleAnemiaRisk.rawValue {
            return "Your recent result suggests reviewing symptom guidance, iron-rich foods, and follow-up education first."
        }
        if userGender == "Female" {
            return "Your feed includes core anemia basics plus additional education about menstruation-related iron loss."
        }
        return "Your feed starts with the most useful anemia education and next-step guidance for new scan data."
    }
}

@MainActor
struct ProfileView: View {
    @ObservedObject var history: ScanHistoryStore
    @AppStorage("userAge") private var userAge = 0
    @AppStorage("userBiologicalSex") private var userBiologicalSex = ""
    @AppStorage("fitzpatrickSkinPhototype") private var fitzpatrickSkinPhototype = FitzpatrickSkinPhototype.notProvided.rawValue
    @AppStorage("lightingEnvironment") private var lightingEnvironment = LightingEnvironment.notProvided.rawValue
    @AppStorage("isPregnant") private var isPregnant = false
    @AppStorage("recentLabHemoglobin") private var recentLabHemoglobin = 0.0
    @AppStorage("profileImageData") private var profileImageData = Data()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var recentLabHemoglobinInput = ""
    @State private var exportedResearchBundle: ShareablePDFDocument?
    @State private var researchExportError: String?
    @State private var showSettings = false

    var body: some View {
        let displayedProfileImage = profileImage
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Profile")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(IronTheme.textSlate)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.68), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open settings")
                }
                .padding(.top, 16)

                VStack(spacing: 18) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let displayedProfileImage {
                                    displayedProfileImage
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.42)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .overlay {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 78))
                                            .foregroundStyle(IronTheme.sageAccent)
                                    }
                                }
                            }
                            .frame(width: 118, height: 118)
                            .clipShape(Circle())

                            Circle()
                                .fill(Color.white.opacity(0.88))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(IronTheme.textSlate)
                                }
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personal Info")
                            .font(IronTheme.roundedFont(.headline, weight: .bold))
                        profileRow("Age", userAge > 0 ? "\(userAge)" : "Not provided")
                        Divider()
                        profileRow("Biological Sex", userBiologicalSex.isEmpty ? "Not provided" : userBiologicalSex)
                        if userBiologicalSex == UserBiologicalSex.female.rawValue {
                            Divider()
                            profileRow("Pregnancy Status", isPregnant ? "Currently Pregnant" : "Not Pregnant")
                        }
                        Divider()
                        profileRow("Skin Phototype", fitzpatrickSkinPhototype)
                        Divider()
                        profileRow("Lighting Context", lightingEnvironment)
                        Divider()
                        profileRow(
                            "Recent Lab Hemoglobin",
                            recentLabHemoglobin > 0
                                ? "\(recentLabHemoglobin.formatted(.number.precision(.fractionLength(1)))) g/dL"
                                : "Not provided"
                        )
                        Divider()
                        profileRow("Saved Scans", "\(history.records.count)")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .liquidGlassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Demographic Calibration")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))

                    Text("Optional fairness context helps the research prototype normalize optical colorimetry across skin phototypes and everyday lighting conditions.")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textMuted)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fitzpatrick Skin Phototype")
                            .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                            .foregroundStyle(IronTheme.textSecondary)

                        Picker("Fitzpatrick Skin Phototype", selection: $fitzpatrickSkinPhototype) {
                            ForEach(FitzpatrickSkinPhototype.allCases) { phototype in
                                Text(phototype.rawValue).tag(phototype.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lighting Environment")
                            .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                            .foregroundStyle(IronTheme.textSecondary)

                        Picker("Lighting Environment", selection: $lightingEnvironment) {
                            ForEach(LightingEnvironment.allCases) { lighting in
                                Text(lighting.rawValue).tag(lighting.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text("These values stay local unless you explicitly share a research report.")
                        .font(IronTheme.roundedFont(.caption))
                        .foregroundStyle(IronTheme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Lab Calibration")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))

                    Text("Add a recent hemoglobin lab value to anchor the prototype estimate more closely to your own baseline.")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textMuted)

                    HStack(spacing: 12) {
                        TextField("e.g. 13.4", text: $recentLabHemoglobinInput)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(IronTheme.roundedFont(.body, weight: .medium))
                            .foregroundStyle(IronTheme.textSlate)

                        Text("g/dL")
                            .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                            .foregroundStyle(IronTheme.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("Leave blank to use the prototype’s generic adult baseline.")
                        .font(IronTheme.roundedFont(.caption))
                        .foregroundStyle(IronTheme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Research & Open Science")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))

                    Text("Export a sanitized JSON record without names, email addresses, or direct identifiers for research donation or personal backup.")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textMuted)

                    Button("Export Anonymized Research Record (JSON)") {
                        exportResearchBundle()
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 128)
        }
        .background(IronTheme.beigeBackground.ignoresSafeArea())
        .sheet(item: $exportedResearchBundle) { document in
            ActivityShareSheet(activityItems: [document.url])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Research Export Unavailable", isPresented: researchExportAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(researchExportError ?? "The anonymized research bundle could not be created.")
        }
        .onAppear {
            recentLabHemoglobinInput = recentLabHemoglobin > 0
                ? recentLabHemoglobin.formatted(.number.precision(.fractionLength(1)))
                : ""
            Task { @MainActor in
                updateProfileImage()
            }
        }
        .onChange(of: profileImageData) { _, _ in
            Task { @MainActor in
                updateProfileImage()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        profileImageData = data
                        updateProfileImage()
                    }
                }
            }
        }
        .onChange(of: recentLabHemoglobinInput) { _, newValue in
            let normalized = newValue
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty else {
                recentLabHemoglobin = 0
                return
            }

            if let parsed = Double(normalized), parsed.isFinite, parsed > 0 {
                recentLabHemoglobin = parsed
            }
        }
    }

    @MainActor
    private func updateProfileImage() {
        guard !profileImageData.isEmpty,
              let uiImage = UIImage(data: profileImageData) else {
            profileImage = nil
            return
        }
        profileImage = Image(uiImage: uiImage)
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

    private var researchExportAlertBinding: Binding<Bool> {
        Binding(
            get: { researchExportError != nil },
            set: { if !$0 { researchExportError = nil } }
        )
    }

    private func exportResearchBundle() {
        let demographics = DemographicProfileStore.load()
        guard let outputURL = ResearchDataExporter.exportAnonymizedResearchBundle(
            history: history.records,
            demographics: demographics
        ) else {
            researchExportError = "The anonymized research bundle could not be created."
            return
        }
        exportedResearchBundle = ShareablePDFDocument(url: outputURL)
    }
}

@MainActor
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("profile.notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("profile.remindersEnabled") private var remindersEnabled = true

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard("Account Details") {
                        LabeledContent("Name", value: userFirstName.isEmpty ? "Not provided" : userFirstName)
                        Divider()
                        LabeledContent("Account", value: authManager.currentUserId ?? "Signed in")
                    }

                    settingsCard("Notifications") {
                        Toggle("Notifications", isOn: $notificationsEnabled)
                            .tint(IronTheme.terracottaPrimary)
                        Divider()
                        Toggle("Scan Reminders", isOn: $remindersEnabled)
                            .tint(IronTheme.terracottaPrimary)
                    }

                    settingsCard("About") {
                        LabeledContent("App Version", value: appVersion)
                        Text("IronScan is a non-clinical research prototype and does not replace laboratory testing.")
                            .font(.caption)
                            .foregroundStyle(IronTheme.textMuted)
                    }

                    Button("Log Out", role: .destructive) {
                        dismiss()
                        authManager.signOut()
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(IronTheme.beigeBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(IronTheme.roundedFont(.headline, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }
}

private struct LearnDisclosureCard: View {
    let title: String
    let summary: String
    let source: String
    let url: URL
    let content: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(content)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)

                Text(source)
                    .font(IronTheme.roundedFont(.caption, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)

                Link("Learn More", destination: url)
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.terracottaPrimary)
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                Text(summary)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)
            }
        }
        .padding(18)
        .liquidGlassCard()
    }
}
