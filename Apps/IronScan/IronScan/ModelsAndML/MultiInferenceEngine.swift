@preconcurrency import CoreML
import CoreVideo
import Foundation

struct VisualAttributeScore: Equatable, Sendable {
    let probability: Double
    let lockedThreshold: Double

    var exceedsLockedThreshold: Bool {
        probability >= lockedThreshold
    }
}

struct TongueVisualAttributeReport: Equatable, Sendable {
    let pallor: VisualAttributeScore
    let toothmark: VisualAttributeScore
    let crack: VisualAttributeScore
    let tipSideRed: VisualAttributeScore
    let furThick: VisualAttributeScore
    let inferenceDurationMs: Double
    let modelVersion: String
    let isEngineeringFixture: Bool

    var pallorScore: Double { pallor.probability }
    var toothmarkScore: Double { toothmark.probability }
    var crackScore: Double { crack.probability }
    var tipSideRedScore: Double { tipSideRed.probability }
    var coatingScore: Double { furThick.probability }

    var elevatedVisualAttributeCount: Int {
        [pallor, toothmark, crack, tipSideRed, furThick]
            .filter(\.exceedsLockedThreshold)
            .count
    }
}

actor MultiInferenceEngine {
    private static let outputNames = [
        "tongue_pale_probability",
        "toothmark_probability",
        "crack_probability",
        "tip_side_red_probability",
        "fur_thick_probability",
    ]

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

    func predict(
        _ frame: AnalyzableFrame,
        bypassThrottle: Bool = false
    ) async throws -> TongueVisualAttributeReport? {
        try checkCancellation()
        let now = ContinuousClock.now
        if !bypassThrottle,
           let lastInferenceStart,
           lastInferenceStart.duration(to: now) < minimumInterval {
            return nil
        }
        lastInferenceStart = now

        let handle = try await registry.multiScreenModel()
        guard handle.manifest.input.dimensions.count == 4 else {
            throw InferenceError.invalidDimensions
        }
        guard let thresholds = handle.manifest.decisionThresholds,
              Set(thresholds.keys) == Set(Self.outputNames) else {
            throw ModelContractError.missingModelMetadata("decisionThresholds")
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

        let inferenceStart = ContinuousClock.now
        let output: IronScanMultiScreenOutput
        do {
            try checkCancellation()
            output = try handle.model.prediction(image: inputBuffer)
        } catch let error as InferenceError {
            await metrics.temporaryBufferReleased()
            throw error
        } catch {
            await metrics.temporaryBufferReleased()
            throw InferenceError.predictionFailed(error.localizedDescription)
        }
        let inferenceDurationMs = inferenceStart.duration(to: .now).milliseconds
        await metrics.temporaryBufferReleased()
        let scores = try Self.outputNames.map { outputName in
            guard let threshold = thresholds[outputName] else {
                throw ModelContractError.missingModelMetadata(outputName)
            }
            return VisualAttributeScore(
                probability: try scalar(from: output, feature: outputName),
                lockedThreshold: threshold
            )
        }
        await metrics.record(
            stage: .riskInference,
            durationMs: inferenceDurationMs,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        return TongueVisualAttributeReport(
            pallor: scores[0],
            toothmark: scores[1],
            crack: scores[2],
            tipSideRed: scores[3],
            furThick: scores[4],
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
