import CoreVideo
import Foundation
import ImageIO
import OSLog

struct LiveScanSummary: Equatable, Sendable {
    let tongueAreaRatio: Double
    let meanConfidence: Double
    let alignmentProgress: Double
    let isTongueAligned: Bool
    let inferenceDurationMs: Double
    let modelVersion: String
    let visualAttributeReport: TongueVisualAttributeReport?
}

struct ScanResultSummary: Equatable, Sendable {
    let title: String
    let detail: String
    let decision: RiskDecision
    let riskScore: Double?
    let segmentationAreaRatio: Double
    let inferenceDurationMs: Double
    let visualAttributeReport: TongueVisualAttributeReport?

    static func physicalCapture(segmentation: SegmentationResult) -> ScanResultSummary {
        ScanResultSummary(
            title: "Unable to assess",
            detail: "Color calibration is not yet validated for physical captures.",
            decision: .unableToAssess,
            riskScore: nil,
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs,
            visualAttributeReport: nil
        )
    }

    static func physicalPrediction(segmentation: SegmentationResult, prediction: RiskPrediction) -> ScanResultSummary {
        ScanResultSummary(
            title: prediction.decision.displayTitle,
            detail: "Research prototype result — confirm with a laboratory test.",
            decision: prediction.decision,
            riskScore: prediction.calibratedProbability,
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs + prediction.inferenceDurationMs,
            visualAttributeReport: nil
        )
    }

    static func syntheticDemo(segmentation: SegmentationResult, prediction: RiskPrediction) -> ScanResultSummary {
        ScanResultSummary(
            title: prediction.decision.displayTitle,
            detail: "Synthetic engineering fixture — not a participant result.",
            decision: prediction.decision,
            riskScore: prediction.calibratedProbability,
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs + prediction.inferenceDurationMs,
            visualAttributeReport: nil
        )
    }

    static func prototypeDemoCapture(
        segmentation: SegmentationResult,
        report: TongueVisualAttributeReport
    ) -> ScanResultSummary {
        ScanResultSummary(
            title: "Visual research summary",
            detail: "Image-model output for research demonstration. Confirm with a laboratory test.",
            decision: .unableToAssess,
            riskScore: nil,
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs + report.inferenceDurationMs,
            visualAttributeReport: report
        )
    }
}

extension RiskDecision {
    var displayTitle: String {
        switch self {
        case .lowerObservedRisk: "Lower observed risk"
        case .possibleRisk: "Possible anemia risk"
        case .unableToAssess: "Unable to assess"
        }
    }
}

actor ScanPipelineActor {
    private let logger = Logger(subsystem: "org.ironscan.app", category: "live-scan")
    private let registry: ModelRegistryActor
    private let metrics: InferenceMetricsRecorder
    private let segmentation: SegmentationInferenceActor
    private let risk: RiskInferenceActor
    private let calibration: SmartColorCalibrationActor
    private let multiInference: MultiInferenceEngine
    private let calibrationConfiguration: ColorCalibrationConfiguration

    init(
        registry: ModelRegistryActor = .shared,
        metrics: InferenceMetricsRecorder = InferenceMetricsRecorder(),
        calibration: SmartColorCalibrationActor = SmartColorCalibrationActor(),
        multiInference: MultiInferenceEngine? = nil,
        calibrationConfiguration: ColorCalibrationConfiguration = .lockedV1
    ) {
        self.registry = registry
        self.metrics = metrics
        segmentation = SegmentationInferenceActor(registry: registry, metrics: metrics)
        risk = RiskInferenceActor(registry: registry, metrics: metrics)
        self.calibration = calibration
        self.multiInference = multiInference ?? MultiInferenceEngine(registry: registry, metrics: metrics)
        self.calibrationConfiguration = calibrationConfiguration
    }

    func prepareModels() async throws -> ModelRegistryReadiness {
        try await registry.preloadModels()
    }

    func analyzeLiveFrame(
        _ frame: AnalyzableFrame,
        runVisualInference: Bool = true
    ) async throws -> LiveScanSummary {
        let startedAt = ContinuousClock.now
        do {
            let result = try await segmentation.segment(OrientationNormalizedCapture(
                pixelBuffer: frame.pixelBuffer,
                colorSpace: "sRGB"
            ))
            let statistics = result.confidenceStatistics
            let areaProgress = min(max(statistics.areaRatio / 0.24, 0), 1)
            let confidence = min(max(statistics.meanForegroundProbability, 0), 1)
            let alignmentProgress = areaProgress * confidence
            let minimumConfidence = PrototypeDemoMode.isEnabled
                ? PrototypeDemoMode.minimumSegmentationConfidence
                : 0.55
            let acceptedAreaRatio = PrototypeDemoMode.isEnabled
                ? PrototypeDemoMode.acceptedTongueAreaRatio
                : 0.12 ... 0.62
            let isAligned = acceptedAreaRatio.contains(statistics.areaRatio)
                && confidence >= minimumConfidence
            let visualAttributeReport: TongueVisualAttributeReport? = if isAligned && runVisualInference {
                try await multiInference.predict(frame)
            } else {
                nil
            }
            let elapsedMs = startedAt.duration(to: .now).milliseconds
            logger.debug("Live tongue segmentation completed in \(elapsedMs, format: .fixed(precision: 1)) ms")
            return LiveScanSummary(
                tongueAreaRatio: statistics.areaRatio,
                meanConfidence: confidence,
                alignmentProgress: alignmentProgress,
                isTongueAligned: isAligned,
                inferenceDurationMs: elapsedMs,
                modelVersion: result.modelVersion,
                visualAttributeReport: visualAttributeReport
            )
        } catch {
            logger.error("Live tongue segmentation failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func processPhysicalCapture(_ frame: CapturedFrame) async throws -> ScanResultSummary {
        let segmentationResult = try await segmentation.segment(OrientationNormalizedCapture(
            pixelBuffer: frame.pixelBuffer,
            colorSpace: frame.metadata.sourceColorSpace
        ))
        let statistics = segmentationResult.confidenceStatistics
        let minimumConfidence = PrototypeDemoMode.isEnabled
            ? PrototypeDemoMode.minimumSegmentationConfidence
            : 0.55
        let acceptedAreaRatio = PrototypeDemoMode.isEnabled
            ? PrototypeDemoMode.acceptedTongueAreaRatio
            : 0.12 ... 0.62
        let visualQualityAccepted = frame.quality.readiness == .ready
            && acceptedAreaRatio.contains(statistics.areaRatio)
            && statistics.meanForegroundProbability >= minimumConfidence
        if PrototypeDemoMode.isEnabled, visualQualityAccepted,
           let report = try await multiInference.predict(
               AnalyzableFrame(pixelBuffer: frame.pixelBuffer, timestamp: .zero),
               bypassThrottle: true
           ) {
            return .prototypeDemoCapture(segmentation: segmentationResult, report: report)
        }
        let calibratedSample = try await calibration.calibrate(
            capture: frame.pixelBuffer,
            metadata: CalibrationCaptureMetadata(
                orientation: .up,
                exposureTargetOffset: Double(frame.metadata.exposureTargetOffset),
                focusWasLocked: frame.metadata.focusWasLocked,
                exposureWasLocked: frame.metadata.exposureWasLocked,
                whiteBalanceWasLocked: frame.metadata.whiteBalanceWasLocked,
                sourceColorSpaceName: frame.metadata.sourceColorSpace
            ),
            segmentation: segmentationResult,
            configuration: calibrationConfiguration
        )
        guard calibratedSample.accepted else {
            return .physicalCapture(segmentation: segmentationResult)
        }
        let prediction = try await risk.predict(calibratedSample)
        return .physicalPrediction(segmentation: segmentationResult, prediction: prediction)
    }

    func runSyntheticDemo() async throws -> ScanResultSummary {
        let pixelBuffer = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 96)
        let segmentationResult = try await segmentation.segment(OrientationNormalizedCapture(
            pixelBuffer: pixelBuffer,
            colorSpace: "sRGB"
        ))
        let statistics = segmentationResult.confidenceStatistics
        let prediction = try await risk.predict(CalibratedTongueSample(
            pixelBuffer: pixelBuffer,
            colorSpace: "sRGB",
            calibrationStatus: .accepted,
            calibrationDurationMs: 0,
            qualitySummary: InferenceQualitySummary(
                segmentationAreaRatio: statistics.areaRatio,
                segmentationMeanConfidence: statistics.meanForegroundProbability,
                calibrationResidual: 0,
                captureQualityScore: 1
            )
        ))
        return .syntheticDemo(segmentation: segmentationResult, prediction: prediction)
    }

    func runSyntheticBenchmark(
        iterations: Int,
        deviceModelIdentifier: String,
        operatingSystemVersion: String
    ) async throws -> InferenceBenchmarkSummary {
        guard iterations > 0 else { throw InferenceError.invalidDimensions }
        _ = try await prepareModels()
        await metrics.reset()
        for _ in 0..<iterations {
            try Task.checkCancellation()
            _ = try await runSyntheticDemo()
        }
        let snapshot = await metrics.snapshot()
        guard let segmentationP95 = snapshot.percentile95(for: .segmentation),
              let riskP95 = snapshot.percentile95(for: .riskInference),
              let totalP95 = snapshot.percentile95(for: .totalPipeline) else {
            throw InferenceError.missingOutput("benchmark metrics")
        }
        return InferenceBenchmarkSummary(
            deviceModelIdentifier: deviceModelIdentifier,
            operatingSystemVersion: operatingSystemVersion,
            iterationCount: iterations,
            segmentationP95Ms: segmentationP95,
            riskInferenceP95Ms: riskP95,
            totalPipelineP95Ms: totalP95,
            peakTemporaryBufferCount: snapshot.peakTemporaryBufferCount
        )
    }
}
