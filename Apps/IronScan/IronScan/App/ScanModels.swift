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

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        hemoglobinG_dL: Double,
        riskLevel: ScanRiskLevel,
        conjunctivaScore: Double,
        nailScore: Double,
        tongueScore: Double,
        calibrationOffsetApplied: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hemoglobinG_dL = hemoglobinG_dL
        self.riskLevel = riskLevel
        self.conjunctivaScore = conjunctivaScore
        self.nailScore = nailScore
        self.tongueScore = tongueScore
        self.calibrationOffsetApplied = calibrationOffsetApplied
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
    private let recordsKey = "ironscan_saved_scans_v1"
    private let profileKey = "ironscan_saved_profile_v1"

    func load() -> ([ScanRecord], UserProfile) {
        let records = UserDefaults.standard.data(forKey: recordsKey)
            .flatMap { try? JSONDecoder().decode([ScanRecord].self, from: $0) } ?? []
        let profile = UserDefaults.standard.data(forKey: profileKey)
            .flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) } ?? .default
        return (records, profile)
    }

    func save(records: [ScanRecord], profile: UserProfile) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(records), forKey: recordsKey)
        UserDefaults.standard.set(try JSONEncoder().encode(profile), forKey: profileKey)
    }
}

@MainActor
final class ScanHistoryManager: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []
    @Published private(set) var profile: UserProfile = .default
    @Published private(set) var persistenceError: String?

    private let storage = ScanRecordStorage()
    private var didLoad = false

    func loadData() async {
        guard !didLoad else { return }
        let (savedRecords, savedProfile) = await storage.load()
        records = savedRecords
        profile = savedProfile
        didLoad = true
    }

    func addRecord(_ record: ScanRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func saveProfile(_ newProfile: UserProfile) {
        profile = newProfile
        persist()
    }

    private func persist() {
        let records = records
        let profile = profile
        Task {
            do {
                try await storage.save(records: records, profile: profile)
                persistenceError = nil
            } catch {
                persistenceError = "Local scan history could not be saved."
            }
        }
    }
}
