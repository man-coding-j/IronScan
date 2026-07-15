import CoreGraphics
import CoreVideo
import Foundation

struct ScanResultSummary: Equatable, Sendable {
    let title: String
    let detail: String
    let segmentationAreaRatio: Double
    let inferenceDurationMs: Double

    static func physicalCapture(segmentation: SegmentationResult) -> ScanResultSummary {
        ScanResultSummary(
            title: "Unable to assess",
            detail: "Color calibration is not yet validated for physical captures.",
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs
        )
    }

    static func syntheticDemo(segmentation: SegmentationResult, prediction: RiskPrediction) -> ScanResultSummary {
        ScanResultSummary(
            title: prediction.decision.displayTitle,
            detail: "Synthetic engineering fixture — not a participant result.",
            segmentationAreaRatio: segmentation.confidenceStatistics.areaRatio,
            inferenceDurationMs: segmentation.inferenceDurationMs + prediction.inferenceDurationMs
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
    private let segmentation: SegmentationInferenceActor
    private let risk: RiskInferenceActor

    init(metrics: InferenceMetricsRecorder = InferenceMetricsRecorder()) {
        segmentation = SegmentationInferenceActor(metrics: metrics)
        risk = RiskInferenceActor(metrics: metrics)
    }

    func processPhysicalCapture(_ frame: CapturedFrame) async throws -> ScanResultSummary {
        let segmentationResult = try await segmentation.segment(OrientationNormalizedCapture(
            pixelBuffer: frame.pixelBuffer,
            colorSpace: frame.metadata.sourceColorSpace
        ))
        return .physicalCapture(segmentation: segmentationResult)
    }

    func runSyntheticDemo() async throws -> ScanResultSummary {
        let pixelBuffer = try SyntheticSampleFactory.makePixelBuffer(width: 96, height: 96)
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
}

private enum SyntheticSampleFactory {
    static func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        guard width > 0, height > 0 else { throw InferenceError.invalidDimensions }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw InferenceError.pixelBufferAllocationFailed(status)
        }
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw InferenceError.pixelBufferLockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw InferenceError.invalidDimensions
        }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let centerX = Double(width - 1) / 2
        let centerY = Double(height - 1) / 2
        for row in 0..<height {
            for column in 0..<width {
                let normalizedX = (Double(column) - centerX) / (Double(width) * 0.34)
                let normalizedY = (Double(row) - centerY) / (Double(height) * 0.42)
                let isTongueShape = normalizedX * normalizedX + normalizedY * normalizedY <= 1
                let offset = row * bytesPerRow + column * 4
                bytes[offset] = isTongueShape ? 105 : 48
                bytes[offset + 1] = isTongueShape ? 112 : 58
                bytes[offset + 2] = isTongueShape ? 205 : 68
                bytes[offset + 3] = 255
            }
        }
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        }
        return pixelBuffer
    }
}
