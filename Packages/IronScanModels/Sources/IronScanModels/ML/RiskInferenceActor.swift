@preconcurrency import CoreML
import CoreVideo
import Foundation

actor RiskInferenceActor {
    private let registry: ModelRegistryActor
    private let metrics: InferenceMetricsRecorder

    init(
        registry: ModelRegistryActor = .shared,
        metrics: InferenceMetricsRecorder
    ) {
        self.registry = registry
        self.metrics = metrics
    }

    func predict(_ sample: CalibratedTongueSample) async throws -> RiskPrediction {
        let totalStart = ContinuousClock.now
        try checkCancellation()
        guard sample.calibrationStatus == .accepted else {
            throw InferenceError.rejectedCalibration
        }
        guard sample.colorSpace == "sRGB" else {
            throw InferenceError.unsupportedPixelFormat("Expected sRGB, received \(sample.colorSpace)")
        }
        let handle = try await registry.riskModel()
        guard sample.preprocessingVersion == handle.manifest.preprocessingVersion else {
            throw ModelContractError.preprocessingVersion(
                expected: handle.manifest.preprocessingVersion,
                actual: sample.preprocessingVersion
            )
        }
        guard handle.manifest.input.dimensions.count == 4 else {
            throw InferenceError.invalidDimensions
        }
        let height = handle.manifest.input.dimensions[1]
        let width = handle.manifest.input.dimensions[2]

        try checkCancellation()
        let preprocessingStart = ContinuousClock.now
        await metrics.temporaryBufferAllocated()
        let inputBuffer: CVPixelBuffer
        do {
            inputBuffer = try PixelBufferFactory.makeBuffer(
                from: sample.pixelBuffer,
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
        await metrics.record(stage: .calibration, durationMs: sample.calibrationDurationMs)

        try checkCancellation()
        let inferenceStart = ContinuousClock.now
        let output: AnemiaRiskOutput
        do {
            output = try handle.model.prediction(image: inputBuffer)
        } catch {
            await metrics.temporaryBufferReleased()
            throw InferenceError.predictionFailed(error.localizedDescription)
        }
        let inferenceDuration = inferenceStart.duration(to: .now).milliseconds
        await metrics.temporaryBufferReleased()
        let rawScore = try scalar(from: output, feature: "raw_score")
        let probability = try scalar(from: output, feature: "calibrated_probability")
        let decision: RiskDecision
        if handle.manifest.deploymentStatus != .validated {
            decision = .unableToAssess
        } else if probability >= handle.manifest.decisionThreshold {
            decision = .possibleRisk
        } else {
            decision = .lowerObservedRisk
        }
        let uncertainty = max(0, min(1, 1 - abs(probability - 0.5) * 2))
        await metrics.record(
            stage: .riskInference,
            durationMs: inferenceDuration,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        await metrics.record(
            stage: .totalPipeline,
            durationMs: totalStart.duration(to: .now).milliseconds + sample.calibrationDurationMs,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        return RiskPrediction(
            rawScore: rawScore,
            calibratedProbability: probability,
            decision: decision,
            uncertainty: uncertainty,
            modelVersion: handle.manifest.semanticVersion,
            preprocessingVersion: handle.manifest.preprocessingVersion,
            inferenceDurationMs: inferenceDuration,
            computeUnits: handle.computeUnits,
            qualitySummary: sample.qualitySummary
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
