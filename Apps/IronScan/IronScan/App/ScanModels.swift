import Combine
import Foundation
import SwiftUI

enum ScanRiskLevel: String, Codable, CaseIterable, Sendable {
    case normal = "Lower research signal"
    case mild = "Mild research signal"
    case moderate = "Moderate research signal"
    case severe = "Higher research signal"

    var color: Color {
        switch self {
        case .normal: .green
        case .mild: .yellow
        case .moderate: .orange
        case .severe: .red
        }
    }
}

struct ScanRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let hemoglobinG_dL: Double
    let riskLevel: ScanRiskLevel
    let conjunctivaScore: Double
    let nailScore: Double
    let tongueScore: Double
    let calibrationOffsetApplied: Double
    /// Optional for compatibility with records saved before demo seeding.
    let isDemoSample: Bool?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        hemoglobinG_dL: Double,
        riskLevel: ScanRiskLevel,
        conjunctivaScore: Double,
        nailScore: Double,
        tongueScore: Double,
        calibrationOffsetApplied: Double,
        isDemoSample: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hemoglobinG_dL = hemoglobinG_dL
        self.riskLevel = riskLevel
        self.conjunctivaScore = conjunctivaScore
        self.nailScore = nailScore
        self.tongueScore = tongueScore
        self.calibrationOffsetApplied = calibrationOffsetApplied
        self.isDemoSample = isDemoSample
    }
}

struct UserProfile: Codable, Sendable {
    var age: Int
    var biologicalSex: String
    var fitzpatrickSkinType: Int
    var recentLabHemoglobin: Double?
    var baselineThreshold: Double

    static let `default` = UserProfile(
        age: 0,
        biologicalSex: "Unspecified",
        fitzpatrickSkinType: 0,
        recentLabHemoglobin: nil,
        baselineThreshold: 0
    )
}

private actor ScanRecordStorage {
    private let suiteName: String?
    private let recordsKey = "ironscan_saved_scans_v1"
    private let profileKey = "ironscan_saved_profile_v1"
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    init(suiteName: String?) { self.suiteName = suiteName }

    func load() -> ([ScanRecord], UserProfile) {
        let records = defaults.data(forKey: recordsKey)
            .flatMap { try? JSONDecoder().decode([ScanRecord].self, from: $0) } ?? []
        let profile = defaults.data(forKey: profileKey)
            .flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) } ?? .default
        return (records, profile)
    }

    func replaceRecords(_ records: [ScanRecord]) throws {
        if records.isEmpty {
            defaults.removeObject(forKey: recordsKey)
        } else {
            defaults.set(try JSONEncoder().encode(records), forKey: recordsKey)
        }
    }

    func save(records: [ScanRecord], profile: UserProfile?) throws {
        // A record can arrive before launch loading completes. Merge persisted
        // IDs so an early add never replaces older history with an empty snapshot.
        let saved = load().0
        let ids = Set(records.map(\.id))
        let merged = (records + saved.filter { !ids.contains($0.id) })
            .sorted { $0.timestamp > $1.timestamp }
        defaults.set(try JSONEncoder().encode(merged), forKey: recordsKey)
        if let profile {
            defaults.set(try JSONEncoder().encode(profile), forKey: profileKey)
        }
    }
}

@MainActor
final class ScanHistoryManager: ObservableObject {
    static let shared = ScanHistoryManager()

    @Published private(set) var records: [ScanRecord] = []
    @Published private(set) var profile: UserProfile = .default
    @Published private(set) var persistenceError: String?
    @Published private var legacyRecords: [ScanHistoryRecord] = []

    private let storage: ScanRecordStorage
    private var historyGeneration = UUID()
    private var didLoad = false
    private var profileWasEdited = false
    private var persistenceTask: Task<Void, Never>?
    private var syncStore: ScanHistoryStore?
    private var syncObservation: AnyCancellable?

    /// Injectable persistence is used by isolated tests, never by app screens.
    init(suiteName: String? = nil) {
        storage = ScanRecordStorage(suiteName: suiteName)
    }

    /// One presentation of canonical scans plus pre-existing legacy summaries.
    /// Canonical IDs win, so syncing cannot duplicate a completed assessment.
    var displayRecords: [ScanHistoryRecord] {
        DashboardHistoryRecords.merging(records, legacy: legacyRecords)
    }

    /// The legacy store is a migration/cloud transport adapter, not the source
    /// of completed three-tissue assessments shown by Home and History.
    func connectSyncStore(_ store: ScanHistoryStore) {
        guard syncStore !== store else { return }
        syncStore = store
        syncObservation = store.$records.sink { [weak self] records in
            self?.legacyRecords = records
        }
        for record in records { store.upsert(record) }
    }

    func loadData() async {
        guard !didLoad else { return }
        didLoad = true
        let generation = historyGeneration
        // A reset may have updated presentation while its ordered disk write is pending.
        await persistenceTask?.value
        let (savedRecords, savedProfile) = await storage.load()
        guard generation == historyGeneration else { return }
        let ids = Set(records.map(\.id))
        records = (records + savedRecords.filter { !ids.contains($0.id) })
            .sorted { $0.timestamp > $1.timestamp }
        if !profileWasEdited { profile = savedProfile }
        for record in records { syncStore?.upsert(record) }
    }

    func addRecord(_ record: ScanRecord) {
        objectWillChange.send()
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.timestamp > $1.timestamp }
        persist()
        syncStore?.upsert(record)
    }

    /// Clears local scan history only; profile and consent settings are preserved.
    func clearAllRecords() {
        replaceHistory(with: [])
    }

    /// Fictional numerical samples for recording a prototype demonstration.
    func resetToDemoBaseline() {
        let now = Date()
        let samples: [(Int, Double, ScanRiskLevel, Double)] = [
            (4, 10.9, .moderate, 0.62), (2, 11.4, .mild, 0.48),
        ]
        replaceHistory(with: samples.map { days, hemoglobin, risk, score in
            ScanRecord(
                timestamp: Calendar.current.date(byAdding: .day, value: -days, to: now)!,
                hemoglobinG_dL: hemoglobin, riskLevel: risk,
                conjunctivaScore: score, nailScore: score, tongueScore: score,
                calibrationOffsetApplied: 0, isDemoSample: true
            )
        })
    }

    private func replaceHistory(with replacement: [ScanRecord]) {
        historyGeneration = UUID()
        records = replacement.sorted { $0.timestamp > $1.timestamp }
        legacyRecords = []
        syncStore?.clearAllRecords()
        let previous = persistenceTask
        let store = syncStore
        let snapshot = records
        persistenceTask = Task {
            await previous?.value
            await store?.waitForReset()
            do {
                try await storage.replaceRecords(snapshot)
                persistenceError = store?.persistenceError
            } catch {
                persistenceError = "Local scan history could not be reset."
            }
        }
    }

    func saveProfile(_ newProfile: UserProfile) {
        profileWasEdited = true
        profile = newProfile
        persist()
    }

    func waitForPersistence() async {
        await persistenceTask?.value
    }

    private func persist() {
        let records = records
        let profile = profileWasEdited ? profile : nil
        let previous = persistenceTask
        persistenceTask = Task {
            await previous?.value
            do {
                try await storage.save(records: records, profile: profile)
                persistenceError = nil
            } catch {
                persistenceError = "Local scan history could not be saved."
            }
        }
    }
}
