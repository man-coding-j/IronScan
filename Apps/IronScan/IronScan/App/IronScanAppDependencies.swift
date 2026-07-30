import SwiftUI

@MainActor
final class IronScanAppDependencies: ObservableObject {
    @Published var isReady = false
    @Published private var nearbyCareStorage: LocationManager?
    @Published private var multiTissueInferenceStorage: MultiTissueInferenceActor?

    lazy var history = ScanHistoryStore()

    private var initializationTask: Task<Void, Never>?

    var nearbyCare: LocationManager {
        guard let nearbyCareStorage else {
            preconditionFailure("LocationManager accessed before dependencies finished loading.")
        }
        return nearbyCareStorage
    }

    var multiTissueInference: MultiTissueInferenceActor {
        guard let multiTissueInferenceStorage else {
            preconditionFailure("MultiTissueInferenceActor accessed before dependencies finished loading.")
        }
        return multiTissueInferenceStorage
    }

    func initializeHeavyDependencies() async {
        if isReady {
            return
        }

        if let initializationTask {
            await initializationTask.value
            return
        }

        let task = Task { @MainActor in
            let inference = await Self.makeInferenceActor()
            let nearbyCare = LocationManager()

            multiTissueInferenceStorage = inference
            nearbyCareStorage = nearbyCare
            isReady = true
            initializationTask = nil
        }

        initializationTask = task
        await task.value
    }

    nonisolated private static func makeInferenceActor() async -> MultiTissueInferenceActor {
        await Task.detached(priority: .userInitiated) {
            let inference = MultiTissueInferenceActor()
            _ = try? await inference.preloadModels()
            return inference
        }.value
    }
}
