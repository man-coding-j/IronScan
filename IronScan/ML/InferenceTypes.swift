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
    let pixelBuffer: CVPixelBuffer
    let colorSpace: String
    let calibrationStatus: CalibrationStatus
    let calibrationDurationMs: Double
    let qualitySummary: InferenceQualitySummary
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
