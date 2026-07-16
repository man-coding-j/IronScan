@preconcurrency import CoreML
import CoreVideo
import Foundation

actor SegmentationInferenceActor {
    private let registry: ModelRegistryActor
    private let metrics: InferenceMetricsRecorder
    private let postprocessor: SegmentationPostprocessor

    init(
        registry: ModelRegistryActor = .shared,
        metrics: InferenceMetricsRecorder,
        postprocessor: SegmentationPostprocessor = SegmentationPostprocessor()
    ) {
        self.registry = registry
        self.metrics = metrics
        self.postprocessor = postprocessor
    }

    func segment(_ capture: OrientationNormalizedCapture) async throws -> SegmentationResult {
        let totalStart = ContinuousClock.now
        try checkCancellation()
        guard capture.colorSpace == "sRGB" else {
            throw InferenceError.unsupportedPixelFormat("Expected sRGB, received \(capture.colorSpace)")
        }
        let handle = try await registry.segmentationModel()
        guard let postprocessing = handle.manifest.postprocessing,
              handle.manifest.input.dimensions.count == 4 else {
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
                from: capture.pixelBuffer,
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
            modelIdentifier: handle.manifest.modelIdentifier
        )

        try checkCancellation()
        let inferenceStart = ContinuousClock.now
        let output: TongueSegmentationOutput
        do {
            output = try handle.model.prediction(image: inputBuffer)
        } catch {
            await metrics.temporaryBufferReleased()
            throw InferenceError.predictionFailed(error.localizedDescription)
        }
        let inferenceDuration = inferenceStart.duration(to: .now).milliseconds
        await metrics.temporaryBufferReleased()
        guard let array = output.featureValue(for: "probability_mask")?.multiArrayValue else {
            throw InferenceError.missingOutput("probability_mask")
        }
        let probabilities = try floatValues(from: array, expectedCount: width * height, feature: "probability_mask")
        let processed = try postprocessor.process(
            probabilities: probabilities,
            width: width,
            height: height,
            threshold: handle.manifest.decisionThreshold,
            configuration: postprocessing
        )
        await metrics.record(
            stage: .segmentation,
            durationMs: inferenceDuration,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        await metrics.record(
            stage: .totalPipeline,
            durationMs: totalStart.duration(to: .now).milliseconds,
            modelIdentifier: handle.manifest.modelIdentifier,
            computeUnits: handle.computeUnits
        )
        return SegmentationResult(
            probabilityMask: probabilities,
            binaryMask: processed.mask,
            width: width,
            height: height,
            confidenceStatistics: processed.statistics,
            inferenceDurationMs: inferenceDuration,
            modelVersion: handle.manifest.semanticVersion
        )
    }

    private func floatValues(from array: MLMultiArray, expectedCount: Int, feature: String) throws -> [Float] {
        guard array.count == expectedCount, array.dataType == .float32 else {
            throw InferenceError.invalidOutputShape(feature)
        }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        return Array(UnsafeBufferPointer(start: pointer, count: array.count))
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw InferenceError.cancelled }
    }
}
