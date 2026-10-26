import Foundation
import SwiftUI
@preconcurrency import HealthKit

private let appleHealthUnavailableMessage = "Apple Health is unavailable on this build"

enum HealthSyncStatus: Equatable, Sendable {
    case idle
    case authorizing
    case syncing
    case synced
    case failed(String)

    var isWorking: Bool {
        self == .authorizing || self == .syncing
    }
}

private enum HealthSyncError: LocalizedError {
    case unavailable
    case authorizationDenied(String?)
    case queryFailed(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            appleHealthUnavailableMessage
        case let .authorizationDenied(detail), let .queryFailed(detail):
            detail?.isEmpty == false ? detail : appleHealthUnavailableMessage
        }
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var spO2: Double?
    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationError: String?
    @Published private(set) var healthSyncStatus: HealthSyncStatus = .idle

    private var healthStore: HKHealthStore?

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }

    func requestAuthorization() {
        guard let healthStore = availableHealthStore() else {
            fail(with: Self.unavailableMessage)
            return
        }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            fail(with: Self.unavailableMessage)
            return
        }

        healthSyncStatus = .authorizing
        authorizationError = nil
        let readTypes: Set<HKObjectType> = [heartRateType, oxygenType]
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.authorize(healthStore: healthStore, readTypes: readTypes)
                guard HKHealthStore.isHealthDataAvailable() else {
                    throw HealthSyncError.unavailable
                }
                self.isAuthorized = true
                self.fetchLatestVitals()
            } catch {
                print("Apple Health authorization failed: \(error)")
                self.fail(with: Self.unavailableMessage)
            }
        }
    }

    func fetchLatestVitals() {
        guard isAuthorized, let healthStore = availableHealthStore() else { return }
        healthSyncStatus = .syncing
        authorizationError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let latestHeartRate = try await self.mostRecentSample(
                    healthStore: healthStore,
                    identifier: .heartRate,
                    unit: HKUnit(from: "count/min")
                )
                let latestOxygenSaturation = try await self.mostRecentSample(
                    healthStore: healthStore,
                    identifier: .oxygenSaturation,
                    unit: HKUnit.percent()
                )
                guard HKHealthStore.isHealthDataAvailable() else {
                    throw HealthSyncError.unavailable
                }
                self.heartRate = latestHeartRate
                self.spO2 = latestOxygenSaturation.map { $0 * 100 }
                self.healthSyncStatus = .synced
            } catch {
                print("Apple Health query failed: \(error)")
                self.fail(with: Self.unavailableMessage)
            }
        }
    }

    func dismissError() {
        authorizationError = nil
    }

    private func availableHealthStore() -> HKHealthStore? {
        guard HKHealthStore.isHealthDataAvailable(), let healthStore else {
            fail(with: Self.unavailableMessage)
            return nil
        }
        return healthStore
    }

    private func authorize(
        healthStore: HKHealthStore,
        readTypes: Set<HKObjectType>
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthSyncError.unavailable
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.authorizationDenied(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthSyncError.authorizationDenied(nil))
                }
            }
        }
    }

    private func mostRecentSample(
        healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthSyncError.unavailable
        }
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthSyncError.queryFailed(nil)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate,
                ascending: false
            )
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.queryFailed(error.localizedDescription))
                    return
                }
                let quantity = (results?.first as? HKQuantitySample)?.quantity
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }

            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: HealthSyncError.unavailable)
                return
            }
            healthStore.execute(query)
        }
    }

    private func fail(with message: String) {
        isAuthorized = false
        healthSyncStatus = .failed(message)
        authorizationError = message
    }

    nonisolated static let unavailableMessage = appleHealthUnavailableMessage
}
