@preconcurrency import CoreML
import CoreVideo
import Foundation

enum InferenceComputeUnits: String, Codable, Equatable, Sendable {
    case all
    case cpuAndGPU
    case cpuOnly

    var coreMLValue: MLComputeUnits {
        switch self {
        case .all: .all
        case .cpuAndGPU: .cpuAndGPU
        case .cpuOnly: .cpuOnly
        }
    }
}

struct OrientationNormalizedCapture: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let colorSpace: String
}

enum CalibrationStatus: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
}

struct InferenceQualitySummary: Codable, Equatable, Sendable {
    let segmentationAreaRatio: Double
    let segmentationMeanConfidence: Double
    let calibrationResidual: Double
    let captureQualityScore: Double
}

struct CalibratedTongueSample: @unchecked Sendable {
    let calibratedPixelBuffer: CVPixelBuffer
    let tongueMask: [UInt8]
    let centralROIMask: [UInt8]
    let maskWidth: Int
    let maskHeight: Int
    let calibrationMode: CalibrationMode
    let calibrationMatrix: [Double]
    let exposureScale: Double
    let usablePatchCount: Int
    let medianReferenceDeltaE: Double
    let maximumReferenceDeltaE: Double
    let matrixConditionNumber: Double
    let specularFraction: Double
    let shadowUniformity: Double
    let segmentationConfidence: Double
    let calibrationConfidence: Double
    let accepted: Bool
    let rejectionReasons: [CalibrationRejectionReason]
    let preprocessingVersion: String
    let calibrationDurationMs: Double
    let qualitySummary: InferenceQualitySummary
    let diagnosticFeatures: CalibrationDiagnosticFeatures

    var pixelBuffer: CVPixelBuffer { calibratedPixelBuffer }
    var colorSpace: String { "sRGB" }
    var calibrationStatus: CalibrationStatus { accepted ? .accepted : .rejected }

    init(
        calibratedPixelBuffer: CVPixelBuffer,
        tongueMask: [UInt8],
        centralROIMask: [UInt8],
        maskWidth: Int,
        maskHeight: Int,
        calibrationMode: CalibrationMode,
        calibrationMatrix: [Double],
        exposureScale: Double,
        usablePatchCount: Int,
        medianReferenceDeltaE: Double,
        maximumReferenceDeltaE: Double,
        matrixConditionNumber: Double,
        specularFraction: Double,
        shadowUniformity: Double,
        segmentationConfidence: Double,
        calibrationConfidence: Double,
        accepted: Bool,
        rejectionReasons: [CalibrationRejectionReason],
        preprocessingVersion: String,
        calibrationDurationMs: Double,
        qualitySummary: InferenceQualitySummary,
        diagnosticFeatures: CalibrationDiagnosticFeatures
    ) {
        self.calibratedPixelBuffer = calibratedPixelBuffer
        self.tongueMask = tongueMask
        self.centralROIMask = centralROIMask
        self.maskWidth = maskWidth
        self.maskHeight = maskHeight
        self.calibrationMode = calibrationMode
        self.calibrationMatrix = calibrationMatrix
        self.exposureScale = exposureScale
        self.usablePatchCount = usablePatchCount
        self.medianReferenceDeltaE = medianReferenceDeltaE
        self.maximumReferenceDeltaE = maximumReferenceDeltaE
        self.matrixConditionNumber = matrixConditionNumber
        self.specularFraction = specularFraction
        self.shadowUniformity = shadowUniformity
        self.segmentationConfidence = segmentationConfidence
        self.calibrationConfidence = calibrationConfidence
        self.accepted = accepted
        self.rejectionReasons = rejectionReasons
        self.preprocessingVersion = preprocessingVersion
        self.calibrationDurationMs = calibrationDurationMs
        self.qualitySummary = qualitySummary
        self.diagnosticFeatures = diagnosticFeatures
    }

    init(
        pixelBuffer: CVPixelBuffer,
        colorSpace: String,
        calibrationStatus: CalibrationStatus,
        calibrationDurationMs: Double,
        qualitySummary: InferenceQualitySummary
    ) {
        calibratedPixelBuffer = pixelBuffer
        tongueMask = []
        centralROIMask = []
        maskWidth = 0
        maskHeight = 0
        calibrationMode = calibrationStatus == .accepted ? .multiPatchReference : .uncalibratedRejected
        calibrationMatrix = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        exposureScale = 1
        usablePatchCount = 0
        medianReferenceDeltaE = 0
        maximumReferenceDeltaE = 0
        matrixConditionNumber = 1
        specularFraction = 0
        shadowUniformity = 0
        segmentationConfidence = qualitySummary.segmentationMeanConfidence
        accepted = calibrationStatus == .accepted
        calibrationConfidence = accepted ? 1 : 0
        rejectionReasons = accepted ? [] : [.invalidCaptureMetadata]
        preprocessingVersion = "1.0.0"
        self.calibrationDurationMs = calibrationDurationMs
        self.qualitySummary = qualitySummary
        diagnosticFeatures = CalibrationDiagnosticFeatures(
            meanLabL: 0,
            meanLabA: 0,
            meanLabB: 0,
            medianLinearRed: 0,
            medianLinearGreen: 0,
            medianLinearBlue: 0,
            acceptedPixelCount: 0
        )
        _ = colorSpace
    }
}

struct SegmentationConfidenceStatistics: Codable, Equatable, Sendable {
    let meanForegroundProbability: Double
    let minimumForegroundProbability: Double
    let maximumForegroundProbability: Double
    let foregroundPixelCount: Int
    let areaRatio: Double
}

struct SegmentationResult: Sendable {
    let probabilityMask: [Float]
    let binaryMask: [UInt8]
    let width: Int
    let height: Int
    let confidenceStatistics: SegmentationConfidenceStatistics
    let inferenceDurationMs: Double
    let modelVersion: String
}

enum RiskDecision: String, Codable, Equatable, Sendable {
    case lowerObservedRisk
    case possibleRisk
    case unableToAssess
}

struct RiskPrediction: Codable, Equatable, Sendable {
    let rawScore: Double
    let calibratedProbability: Double
    let decision: RiskDecision
    let uncertainty: Double
    let modelVersion: String
    let preprocessingVersion: String
    let inferenceDurationMs: Double
    let computeUnits: InferenceComputeUnits
    let qualitySummary: InferenceQualitySummary
}
