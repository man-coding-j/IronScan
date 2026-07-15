import Foundation

enum ModelContractError: Error, Equatable, Sendable {
    case unreadableManifest(String)
    case unsupportedSchemaVersion(Int)
    case modelIdentifier(expected: String, actual: String)
    case invalidSemanticVersion(String)
    case checksum(expected: String, actual: String)
    case inputFeatureName(expected: String, actual: String?)
    case inputDimensions(expected: [Int], actual: [Int])
    case pixelFormat(expected: String, actual: String)
    case colorSpace(expected: String, actual: String)
    case normalization
    case outputFeatureNames(expected: [String], actual: [String])
    case outputDimensions(feature: String, expected: [Int], actual: [Int])
    case outputDataType(feature: String, expected: String, actual: String)
    case decisionThreshold(expected: Double, actual: Double?)
    case preprocessingVersion(expected: String, actual: String?)
    case missingModelMetadata(String)
}

enum InferenceError: Error, Equatable, Sendable {
    case cancelled
    case rejectedCalibration
    case unsupportedPixelFormat(String)
    case invalidDimensions
    case unsupportedResizeMethod(String)
    case pixelBufferAllocationFailed(Int32)
    case pixelBufferLockFailed(Int32)
    case resizeFailed(Int)
    case missingOutput(String)
    case invalidOutputShape(String)
    case modelLoadingFailed(String)
    case predictionFailed(String)
}
