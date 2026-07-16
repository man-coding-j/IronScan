import CoreGraphics
import Foundation
import ImageIO
import simd

enum CalibrationMode: String, Codable, Equatable, Sendable {
    case multiPatchReference
    case neutralPatchReference
    case teethPseudoReference
    case uncalibratedRejected
}

enum CalibrationRejectionReason: String, Codable, Equatable, Sendable {
    case invalidCaptureMetadata
    case insufficientReferencePatches
    case clippedReferencePatch
    case unstableMatrix
    case excessiveMedianResidual
    case excessiveMaximumResidual
    case tongueMaskTooSmall
    case tongueMaskTouchesBoundary
    case excessiveSpecularFraction
    case excessiveShadowGradient
    case unsupportedPixelFormat
}

struct CalibrationCaptureMetadata: Equatable, Sendable {
    let orientation: CGImagePropertyOrientation
    let exposureTargetOffset: Double
    let focusWasLocked: Bool
    let exposureWasLocked: Bool
    let whiteBalanceWasLocked: Bool
    let sourceColorSpaceName: String
}

struct CalibrationPatch: Equatable, Sendable {
    let normalizedRect: CGRect
    let targetLinearRGB: SIMD3<Double>
    let weight: Double
    let isNeutral: Bool
}

struct ColorCalibrationConfiguration: Equatable, Sendable {
    let patches: [CalibrationPatch]
    let teethPatch: CalibrationPatch?
    let minimumUsablePatchCount: Int
    let patchBorderFraction: Double
    let saturationThreshold: Double
    let shadowThreshold: Double
    let outlierDistanceThreshold: Double
    let regularizationLambda: Double
    let maximumConditionNumber: Double
    let maximumMedianDeltaE: Double
    let maximumDeltaE: Double
    let minimumTongueAreaRatio: Double
    let boundaryMarginPixels: Int
    let maximumSpecularFraction: Double
    let maximumShadowUniformity: Double
    let specularValueThreshold: Double
    let specularChromaThreshold: Double
    let centralROIErosionIterations: Int
    let targetTongueMedianLuminance: Double?
    let exposureScaleRange: ClosedRange<Double>
    let teethGainRange: ClosedRange<Double>
    let preprocessingVersion: String

    static let lockedV1 = ColorCalibrationConfiguration(
        patches: [],
        teethPatch: nil,
        minimumUsablePatchCount: 3,
        patchBorderFraction: 0.12,
        saturationThreshold: 0.98,
        shadowThreshold: 0.025,
        outlierDistanceThreshold: 0.12,
        regularizationLambda: 0.001,
        maximumConditionNumber: 250,
        maximumMedianDeltaE: 8,
        maximumDeltaE: 15,
        minimumTongueAreaRatio: 0.04,
        boundaryMarginPixels: 1,
        maximumSpecularFraction: 0.12,
        maximumShadowUniformity: 0.45,
        specularValueThreshold: 0.92,
        specularChromaThreshold: 0.06,
        centralROIErosionIterations: 2,
        targetTongueMedianLuminance: nil,
        exposureScaleRange: 0.8...1.25,
        teethGainRange: 0.8...1.2,
        preprocessingVersion: "1.0.0"
    )
}

struct CalibrationDiagnosticFeatures: Codable, Equatable, Sendable {
    let meanLabL: Double
    let meanLabA: Double
    let meanLabB: Double
    let medianLinearRed: Double
    let medianLinearGreen: Double
    let medianLinearBlue: Double
    let acceptedPixelCount: Int
}
