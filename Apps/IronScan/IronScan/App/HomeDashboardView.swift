import Charts
import Foundation
import SwiftUI
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct ScanHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let summary: OpticalRiskSummary
    let opticalPatternIndex: Double?
    let includedTissues: Int
    let tissues: [String]
    let calibrationCategoryRawValue: String

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        summary: OpticalRiskSummary,
        opticalPatternIndex: Double?,
        includedTissues: Int,
        tissues: [String] = [],
        calibrationCategory: DemographicCalibrationCategory = .generalResearchProfile
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.summary = summary
        self.opticalPatternIndex = opticalPatternIndex
        self.includedTissues = includedTissues
        self.tissues = tissues
        calibrationCategoryRawValue = calibrationCategory.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case summary
        case opticalPatternIndex
        case includedTissues
        case tissues
        case calibrationCategoryRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        let summaryValue = try container.decode(String.self, forKey: .summary)
        summary = OpticalRiskSummary(rawValue: summaryValue) ?? .unableToAssess
        opticalPatternIndex = try container.decodeIfPresent(Double.self, forKey: .opticalPatternIndex)
        includedTissues = try container.decode(Int.self, forKey: .includedTissues)
        tissues = try container.decodeIfPresent([String].self, forKey: .tissues) ?? []
        calibrationCategoryRawValue = try container.decodeIfPresent(String.self, forKey: .calibrationCategoryRawValue)
            ?? DemographicCalibrationCategory.generalResearchProfile.rawValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(summary.rawValue, forKey: .summary)
        try container.encodeIfPresent(opticalPatternIndex, forKey: .opticalPatternIndex)
        try container.encode(includedTissues, forKey: .includedTissues)
        try container.encode(tissues, forKey: .tissues)
        try container.encode(calibrationCategoryRawValue, forKey: .calibrationCategoryRawValue)
    }

    var calibrationCategory: DemographicCalibrationCategory {
        DemographicCalibrationCategory(rawValue: calibrationCategoryRawValue) ?? .generalResearchProfile
    }
}

struct ScanUserProfile: Equatable, Sendable {
    let age: String?
    let gender: String?
}

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let storageKey = "ironscan.local.scan-history.v1"
    static let maximumRecordCount = 30

    @Published private(set) var records: [ScanHistoryRecord]
    @Published private(set) var userProfile: ScanUserProfile?
    @Published private(set) var persistenceError: String?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = []
        let profile = DemographicProfileStore.load(defaults: defaults)
        userProfile = ScanUserProfile(
            age: profile.age.map { String($0) },
            gender: profile.biologicalSex.rawValue
        )
        persistenceError = nil
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            records = try decoder.decode([ScanHistoryRecord].self, from: data)
                .sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            persistenceError = "Local scan history could not be read."
        }
    }

    func add(_ result: TriangulationResult, capturedAt: Date = Date()) {
        let record = ScanHistoryRecord(
            capturedAt: capturedAt,
            summary: result.summary,
            opticalPatternIndex: result.opticalPallorIndex,
            includedTissues: result.contributions.filter { $0.status == .included }.count,
            tissues: result.contributions.map { $0.tissue.glassTitle },
            calibrationCategory: result.calibrationCategory
        )
        insert(record)
    }

    func saveScan(_ result: TriangulationResult) async {
        let capturedAt = Date()
        let record = ScanHistoryRecord(
            capturedAt: capturedAt,
            summary: result.summary,
            opticalPatternIndex: result.opticalPallorIndex,
            includedTissues: result.contributions.filter { $0.status == .included }.count,
            tissues: result.contributions.map { $0.tissue.glassTitle },
            calibrationCategory: result.calibrationCategory
        )
        insert(record)

        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let user = Auth.auth().currentUser else { return }

        var payload: [String: Any] = [
            "timestamp": Timestamp(date: capturedAt),
            "anemiaRiskLevel": result.summary.rawValue,
            "tissuesScanned": result.contributions.map(\.tissue.rawValue),
            "calibrationCategory": result.calibrationCategory.rawValue
        ]
        if let confidenceScore = result.opticalPallorIndex {
            payload["confidenceScore"] = confidenceScore
        }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .collection("scans")
                .document(record.id.uuidString)
                .setData(payload)
        } catch {
            persistenceError = error.localizedDescription
        }
        #endif
    }

    func fetchHistory() async {
        syncUserProfileFromLocalDefaults()
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let user = Auth.auth().currentUser else { return }

        do {
            let database = Firestore.firestore()
            let localProfile = DemographicProfileStore.load(defaults: defaults)
            let userSnapshot = try await database
                .collection("users")
                .document(user.uid)
                .getDocument()

            if userSnapshot.exists {
                userProfile = ScanUserProfile(
                    age: localProfile.age.map { String($0) } ?? (userSnapshot.get("age") as? String),
                    gender: localProfile.biologicalSex.rawValue
                )
            }

            let snapshot = try await database
                .collection("users")
                .document(user.uid)
                .collection("scans")
                .order(by: "timestamp", descending: true)
                .limit(to: Self.maximumRecordCount)
                .getDocuments()

            records = snapshot.documents.compactMap { document in
                let timestamp = (document.get("timestamp") as? Timestamp)?.dateValue() ?? Date()
                let summaryRawValue = document.get("anemiaRiskLevel") as? String ?? OpticalRiskSummary.unableToAssess.rawValue
                let tissuesScanned = document.get("tissuesScanned") as? [String] ?? []
                let confidenceScore = document.get("confidenceScore") as? Double
                let calibrationRawValue = document.get("calibrationCategory") as? String
                    ?? DemographicCalibrationCategory.generalResearchProfile.rawValue

                return ScanHistoryRecord(
                    id: UUID(uuidString: document.documentID) ?? UUID(),
                    capturedAt: timestamp,
                    summary: OpticalRiskSummary(rawValue: summaryRawValue) ?? .unableToAssess,
                    opticalPatternIndex: confidenceScore,
                    includedTissues: tissuesScanned.count,
                    tissues: tissuesScanned.map(Self.displayName(for:)),
                    calibrationCategory: DemographicCalibrationCategory(rawValue: calibrationRawValue) ?? .generalResearchProfile
                )
            }
            persist()
        } catch {
            persistenceError = error.localizedDescription
        }
        #endif
    }

    func removeAll() {
        records.removeAll()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        do {
            defaults.set(try encoder.encode(records), forKey: Self.storageKey)
            persistenceError = nil
        } catch {
            persistenceError = "Local scan history could not be saved."
        }
    }

    private func insert(_ record: ScanHistoryRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        if records.count > Self.maximumRecordCount {
            records.removeLast(records.count - Self.maximumRecordCount)
        }
        persist()
        syncUserProfileFromLocalDefaults()
    }

    private func syncUserProfileFromLocalDefaults() {
        let profile = DemographicProfileStore.load(defaults: defaults)
        userProfile = ScanUserProfile(
            age: profile.age.map { String($0) },
            gender: profile.biologicalSex.rawValue
        )
    }

    private static func displayName(for rawTissue: String) -> String {
        switch TissueSite(rawValue: rawTissue) {
        case .eye:
            return TissueSite.eye.glassTitle
        case .nail:
            return TissueSite.nail.glassTitle
        case .tongue:
            return TissueSite.tongue.glassTitle
        case .none:
            return rawTissue.capitalized
        }
    }
}

struct HomeDashboardView: View {
    @ObservedObject var history: ScanHistoryStore
    let startScan: () -> Void
    @Namespace private var dashboardGlassNamespace

    private var latest: ScanHistoryRecord? {
        history.records.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    greeting
                    statusCard
                    trendCard
                    recentScans
                    if let persistenceError = history.persistenceError {
                        Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(IronTheme.warning)
                    }
                    privacyNote
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(IronTheme.mintBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                dashboardFloatingActions
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var greeting: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(IronTheme.tealPrimary.gradient)
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome back")
                    .font(.title2.weight(.bold))
                Text("Your local research dashboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(IronTheme.textDark)
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            Image(systemName: statusSymbol)
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 58, height: 58)
                .background(statusColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Visual screening status")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(statusTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(IronTheme.textDark)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .dashboardContentCard()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Optical patterns over time")
                        .font(.headline)
                    Text("Research index from accepted local scans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(IronTheme.tealPrimary)
            }

            if chartRecords.isEmpty {
                ContentUnavailableView(
                    "No trend yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Complete a three-step scan to begin your local history.")
                )
                .frame(minHeight: 190)
            } else {
                Chart(chartRecords) { record in
                    LineMark(
                        x: .value("Date", record.capturedAt),
                        y: .value("Research index", record.opticalPatternIndex ?? 0)
                    )
                    .foregroundStyle(IronTheme.tealPrimary.gradient)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", record.capturedAt),
                        y: .value("Research index", record.opticalPatternIndex ?? 0)
                    )
                    .foregroundStyle(IronTheme.tealDeep)
                }
                .chartYScale(domain: 0 ... 1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1])
                }
                .frame(height: 220)
                .accessibilityLabel("Optical pattern history chart")
            }
        }
        .padding(18)
        .dashboardContentCard()
    }

    private var recentScans: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent scans")
                    .font(.headline)
                Spacer()
                Button("Start scan", action: startScan)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.tealDeep)
            }

            if history.records.isEmpty {
                Text("No scans are stored yet. Images remain local and are not included in history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dashboardContentCard(cornerRadius: 20)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(history.records.prefix(8)) { record in
                            recentScanCard(record)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func recentScanCard(_ record: ScanHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol(for: record.summary))
                    .foregroundStyle(color(for: record.summary))
                Spacer()
                Text(record.capturedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title(for: record.summary))
                .font(.headline)
                .foregroundStyle(IronTheme.textDark)
            Text("\(record.includedTissues) of 3 tissue checks included")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 210, height: 130, alignment: .topLeading)
        .dashboardContentCard(cornerRadius: 20)
    }

    private var dashboardFloatingActions: some View {
        HStack {
            Spacer()

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        dashboardToggle(title: "History", systemName: "clock.arrow.circlepath", id: "dashboard.history")
                        dashboardToggle(title: "Saved", systemName: "photo.on.rectangle", id: "dashboard.saved")
                        dashboardToggle(title: "Latest", systemName: "waveform.path.ecg", id: "dashboard.latest")
                    }
                }
            } else {
                HStack(spacing: 12) {
                    dashboardToggle(title: "History", systemName: "clock.arrow.circlepath", id: "dashboard.history")
                    dashboardToggle(title: "Saved", systemName: "photo.on.rectangle", id: "dashboard.saved")
                    dashboardToggle(title: "Latest", systemName: "waveform.path.ecg", id: "dashboard.latest")
                }
            }
        }
    }

    private func dashboardToggle(title: String, systemName: String, id: String) -> some View {
        Label(title, systemImage: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .dashboardGlassCapsule(id: id, in: dashboardGlassNamespace)
    }

    private var privacyNote: some View {
        Label(
            "Only categorical summaries and the research index are stored locally. Captured images are not saved here.",
            systemImage: "lock.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private var chartRecords: [ScanHistoryRecord] {
        Array(history.records
            .filter { $0.opticalPatternIndex != nil }
            .suffix(12)
            .reversed())
    }

    private var statusTitle: String {
        guard let latest else { return "Ready for your first scan" }
        return title(for: latest.summary)
    }

    private var statusDetail: String {
        guard latest != nil else {
            return "Run the eye, nail, and tongue sequence when you are ready."
        }
        return "Research prototype result. Confirm concerns with a laboratory test."
    }

    private var statusSymbol: String {
        latest.map { symbol(for: $0.summary) } ?? "sparkles"
    }

    private var statusColor: Color {
        latest.map { color(for: $0.summary) } ?? IronTheme.tealPrimary
    }

    private func title(for summary: OpticalRiskSummary) -> String {
        switch summary {
        case .lowerObservedRisk: "Lower observed risk"
        case .possibleAnemiaRisk: "Possible anemia risk"
        case .unableToAssess: "Unable to assess"
        }
    }

    private func symbol(for summary: OpticalRiskSummary) -> String {
        switch summary {
        case .lowerObservedRisk: "checkmark.circle.fill"
        case .possibleAnemiaRisk: "exclamationmark.triangle.fill"
        case .unableToAssess: "questionmark.circle.fill"
        }
    }

    private func color(for summary: OpticalRiskSummary) -> Color {
        switch summary {
        case .lowerObservedRisk: IronTheme.tealPrimary
        case .possibleAnemiaRisk: IronTheme.warning
        case .unableToAssess: .gray
        }
    }
}

private struct DashboardGlassCapsuleModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID(id, in: namespace)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                }
        }
    }
}

private extension View {
    func dashboardContentCard(cornerRadius: CGFloat = 24) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
            }
    }

    func dashboardGlassCapsule(id: String, in namespace: Namespace.ID) -> some View {
        modifier(DashboardGlassCapsuleModifier(id: id, namespace: namespace))
    }
}
