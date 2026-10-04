import Foundation
import Network
import Supabase

struct ScanHistoryCloudRecord: Encodable {
    let id: String
    let capturedAt: Date
    let summary: String
    let opticalPatternIndex: Double?
    let severity: String
    let estimatedHemoglobin: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case summary
        case opticalPatternIndex = "optical_pattern_index"
        case severity
        case estimatedHemoglobin = "estimated_hemoglobin"
    }
}

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let storageKey = "ironscan.local.scan-history.v1"
    static let maximumRecordCount = 30
    static let cacheFilename = "local_scan_cache.json"

    @Published private(set) var records: [ScanHistoryRecord] = []
    @Published private(set) var userProfile: ScanUserProfile?
    @Published private(set) var persistenceError: String?
    @Published private(set) var isSyncing = false

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cloudSyncQueue = DispatchQueue(label: "org.ironscan.scan-history.sync", qos: .utility)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let savedAge = defaults.integer(forKey: "userAge")
        let savedGender = defaults.string(forKey: "userBiologicalSex") ?? "Unknown"
        userProfile = ScanUserProfile(
            age: savedAge > 0 ? String(savedAge) : "Unknown",
            gender: savedGender
        )

        loadLocalRecords()
        Task {
            await syncPendingRecordsToSupabase()
        }
    }

    var pendingSyncCount: Int {
        records.filter { !$0.isSyncedToCloud }.count
    }

    var syncStatusText: String {
        let pending = pendingSyncCount
        if pending == 0 {
            return "All Scans Synced"
        }
        let noun = pending == 1 ? "Scan" : "Scans"
        return "\(pending) \(noun) Stored Locally - Pending Sync"
    }

    func fetchHistory() async {
        loadLocalRecords()
        await syncPendingRecordsToSupabase()
    }

    func saveScan(_ result: Any, capturedAt: Date = Date()) async {
        guard let triangulationResult = result as? TriangulationResult else { return }

        let record = ScanHistoryRecord(
            capturedAt: capturedAt,
            summary: triangulationResult.summary.rawValue,
            opticalPatternIndex: triangulationResult.opticalPallorIndex,
            severity: triangulationResult.severity,
            estimatedHemoglobin: triangulationResult.estimatedHemoglobin,
            isSyncedToCloud: false
        )

        appendLocalRecord(record)
        await syncPendingRecordsToSupabase()
    }

    func add(_ result: TriangulationResult, capturedAt: Date = Date()) {
        let record = ScanHistoryRecord(
            capturedAt: capturedAt,
            summary: result.summary.rawValue,
            opticalPatternIndex: result.opticalPallorIndex,
            severity: result.severity,
            estimatedHemoglobin: result.estimatedHemoglobin,
            isSyncedToCloud: false
        )
        appendLocalRecord(record)
        Task {
            await syncPendingRecordsToSupabase()
        }
    }

    func syncPendingRecordsToSupabase() async {
        guard !isSyncing else { return }
        guard pendingSyncCount > 0 else { return }
        guard await isNetworkAvailable() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let pendingRecords = records.filter { !$0.isSyncedToCloud }
        guard !pendingRecords.isEmpty else { return }

        do {
            let payload = pendingRecords.map {
                ScanHistoryCloudRecord(
                    id: $0.id.uuidString,
                    capturedAt: $0.capturedAt,
                    summary: $0.summary,
                    opticalPatternIndex: $0.opticalPatternIndex,
                    severity: $0.severity.rawValue,
                    estimatedHemoglobin: $0.estimatedHemoglobin
                )
            }

            try await SupabaseManager.client
                .from("scans")
                // ...
                .insert(payload)
                .execute()

            let syncedIDs = Set(pendingRecords.map(\.id))
            records = records.map { record in
                guard syncedIDs.contains(record.id) else { return record }
                var updatedRecord = record
                updatedRecord.isSyncedToCloud = true
                return updatedRecord
            }
            persist()
        } catch {
            // Offline-first flow: keep records safely on-device and retry later.
        }
    }

    private func appendLocalRecord(_ record: ScanHistoryRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maximumRecordCount {
            records.removeLast(records.count - Self.maximumRecordCount)
        }
        persist()
    }

    private func loadLocalRecords() {
        if let data = try? Data(contentsOf: localCacheURL),
           let decoded = try? decoder.decode([ScanHistoryRecord].self, from: data) {
            records = decoded.sorted { $0.capturedAt > $1.capturedAt }
            persistenceError = nil
            return
        }

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ScanHistoryRecord].self, from: data) {
            records = decoded
                .map { legacyRecord in
                    var mutableRecord = legacyRecord
                    mutableRecord.isSyncedToCloud = false
                    return mutableRecord
                }
                .sorted { $0.capturedAt > $1.capturedAt }
            persist()
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(records)
            try data.write(to: localCacheURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Local scan history could not be saved."
        }
    }

    private var localCacheURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent(Self.cacheFilename)
    }

    private func isNetworkAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let didResume = ManagedAtomicFlag()
            monitor.pathUpdateHandler = { path in
                if didResume.trySet() {
                    continuation.resume(returning: path.status == .satisfied)
                    monitor.cancel()
                }
            }
            monitor.start(queue: cloudSyncQueue)
            cloudSyncQueue.asyncAfter(deadline: .now() + 1.5) {
                if didResume.trySet() {
                    continuation.resume(returning: false)
                    monitor.cancel()
                }
            }
        }
    }
}

private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
