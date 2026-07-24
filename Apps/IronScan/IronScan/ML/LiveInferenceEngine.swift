@preconcurrency import CoreML
import CoreVideo
import Foundation

struct LivePallorPrediction: Equatable, Sendable {
    let calibratedProbability: Double
    let exceedsLockedThreshold: Bool
    let lockedThreshold: Double
    let inferenceDurationMs: Double
    let modelVersion: String
    let isEngineeringFixture: Bool
}

actor LiveInferenceEngine {
    private let registry: ModelRegistryActor
    private let metrics: InferenceMetricsRecorder
    private let minimumInterval: Duration
    private var lastInferenceStart: ContinuousClock.Instant?

    init(
        registry: ModelRegistryActor = .shared,
        metrics: InferenceMetricsRecorder = InferenceMetricsRecorder(),
        minimumInterval: Duration = .seconds(1)
    ) {
        self.registry = registry
        self.metrics = metrics
        self.minimumInterval = minimumInterval
    }

    func predict(_ frame: AnalyzableFrame) async throws -> LivePallorPrediction? {
        try checkCancellation()
        let now = ContinuousClock.now
        if let lastInferenceStart,
           lastInferenceStart.duration(to: now) < minimumInterval {
            return nil
        }
        lastInferenceStart = now

        let handle = try await registry.pallorModel()
        guard handle.manifest.input.dimensions.count == 4 else {
            throw InferenceError.invalidDimensions
        }
        let height = handle.manifest.input.dimensions[1]
        let width = handle.manifest.input.dimensions[2]

        try checkCancellation()
        let preprocessingStart = ContinuousClock.now
        let bgraBuffer = try PixelBufferFactory.makeBGRA(from: frame.pixelBuffer)
        await metrics.temporaryBufferAllocated()
        let inputBuffer: CVPixelBuffer
        do {
            inputBuffer = try PixelBufferFactory.makeBuffer(
                from: bgraBuffer,
                width: width,
                height: height,
                resize: handle.manifest.resize
            )
        } catch {
            await metrics.temporaryBufferReleased()
            throw error
        }
        await metrics.record(
            stage: .preprocessing,
            durationMs: preprocessingStart.duration(to: .now).milliseconds,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )

        try checkCancellation()
        let inferenceStart = ContinuousClock.now
        let output: IronScanPallorClassifierOutput
        do {
            output = try handle.model.prediction(image: inputBuffer)
        } catch {
            await metrics.temporaryBufferReleased()
            throw InferenceError.predictionFailed(error.localizedDescription)
        }
        let inferenceDurationMs = inferenceStart.duration(to: .now).milliseconds
        await metrics.temporaryBufferReleased()
        let probability = try scalar(from: output, feature: "calibrated_pallor_probability")
        guard let decisionThreshold = handle.manifest.decisionThreshold else {
            throw ModelContractError.missingModelMetadata("decisionThreshold")
        }
        await metrics.record(
            stage: .riskInference,
            durationMs: inferenceDurationMs,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        return LivePallorPrediction(
            calibratedProbability: probability,
            exceedsLockedThreshold: probability >= decisionThreshold,
            lockedThreshold: decisionThreshold,
            inferenceDurationMs: inferenceDurationMs,
            modelVersion: handle.manifest.semanticVersion,
            isEngineeringFixture: handle.manifest.deploymentStatus == .engineeringFixture
        )
    }

    private func scalar(from output: any MLFeatureProvider, feature: String) throws -> Double {
        guard let array = output.featureValue(for: feature)?.multiArrayValue else {
            throw InferenceError.missingOutput(feature)
        }
        guard array.count == 1, array.dataType == .float32 else {
            throw InferenceError.invalidOutputShape(feature)
        }
        return Double(array.dataPointer.bindMemory(to: Float.self, capacity: 1).pointee)
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw InferenceError.cancelled }
    }
}
