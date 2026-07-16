import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import simd
@testable import IronScan

enum CalibrationTestSupport {
    static let width = 64
    static let height = 64
    static let targets = [
        SIMD3<Double>(0.62, 0.12, 0.08),
        SIMD3<Double>(0.08, 0.55, 0.10),
        SIMD3<Double>(0.07, 0.13, 0.58),
        SIMD3<Double>(0.48, 0.48, 0.48)
    ]
    static let patchRects = [
        CGRect(x: 0.04, y: 0.04, width: 0.18, height: 0.16),
        CGRect(x: 0.28, y: 0.04, width: 0.18, height: 0.16),
        CGRect(x: 0.52, y: 0.04, width: 0.18, height: 0.16),
        CGRect(x: 0.76, y: 0.04, width: 0.18, height: 0.16)
    ]
    static let tongueLinearRGB = SIMD3<Double>(0.42, 0.16, 0.18)

    struct Scenario {
        var gains = SIMD3<Double>(repeating: 1)
        var tongueExposure = 1.0
        var saturatedPatchIndex: Int?
        var missingPatchIndices = Set<Int>()
        var noisyPatchIndex: Int?
        var specularFraction = 0.0
        var shadowGradient = false
        var unstablePatches = false
        var smallMask = false
        var boundaryMask = false
    }

    static func configuration(
        includeCardPatches: Bool = true,
        teethPatch: CalibrationPatch? = nil,
        targetTongueLuminance: Double? = nil,
        maximumConditionNumber: Double = 250,
        maximumShadowUniformity: Double = 0.45,
        maximumSpecularFraction: Double = 0.12
    ) -> ColorCalibrationConfiguration {
        let patches = includeCardPatches ? zip(patchRects, targets).enumerated().map { index, pair in
            CalibrationPatch(
                normalizedRect: pair.0,
                targetLinearRGB: pair.1,
                weight: 1,
                isNeutral: index == 3
            )
        } : []
        return ColorCalibrationConfiguration(
            patches: patches,
            teethPatch: teethPatch,
            minimumUsablePatchCount: 3,
            patchBorderFraction: 0.12,
            saturationThreshold: 0.98,
            shadowThreshold: 0.025,
            outlierDistanceThreshold: 0.12,
            regularizationLambda: 0.001,
            maximumConditionNumber: maximumConditionNumber,
            maximumMedianDeltaE: 8,
            maximumDeltaE: 15,
            minimumTongueAreaRatio: 0.04,
            boundaryMarginPixels: 1,
            maximumSpecularFraction: maximumSpecularFraction,
            maximumShadowUniformity: maximumShadowUniformity,
            specularValueThreshold: 0.92,
            specularChromaThreshold: 0.06,
            centralROIErosionIterations: 2,
            targetTongueMedianLuminance: targetTongueLuminance,
            exposureScaleRange: 0.8...1.25,
            teethGainRange: 0.8...1.2,
            preprocessingVersion: "1.0.0"
        )
    }

    static func metadata(stable: Bool = true) -> CalibrationCaptureMetadata {
        CalibrationCaptureMetadata(
            orientation: .up,
            exposureTargetOffset: stable ? 0 : 0.8,
            focusWasLocked: stable,
            exposureWasLocked: stable,
            whiteBalanceWasLocked: stable,
            sourceColorSpaceName: "sRGB"
        )
    }

    static func segmentation(scenario: Scenario = Scenario()) -> SegmentationResult {
        var mask = [UInt8](repeating: 0, count: width * height)
        if scenario.smallMask {
            for row in 30..<34 { for column in 30..<34 { mask[row * width + column] = 1 } }
        } else {
            for row in 22..<60 {
                for column in 10..<54 {
                    let x = (Double(column) - 31.5) / 22
                    let y = (Double(row) - 40.5) / 19
                    if x * x + y * y <= 1 { mask[row * width + column] = 1 }
                }
            }
        }
        if scenario.boundaryMask {
            for row in 20..<44 { mask[row * width] = 1 }
        }
        let count = mask.reduce(0) { $0 + Int($1) }
        return SegmentationResult(
            probabilityMask: mask.map { $0 == 0 ? 0.05 : 0.95 },
            binaryMask: mask,
            width: width,
            height: height,
            confidenceStatistics: SegmentationConfidenceStatistics(
                meanForegroundProbability: 0.95,
                minimumForegroundProbability: 0.95,
                maximumForegroundProbability: 0.95,
                foregroundPixelCount: count,
                areaRatio: Double(count) / Double(mask.count)
            ),
            inferenceDurationMs: 1,
            modelVersion: "synthetic"
        )
    }

    static func pixelBuffer(scenario: Scenario = Scenario()) throws -> CVPixelBuffer {
        var colors = [SIMD3<Double>](repeating: SIMD3(0.08, 0.08, 0.08), count: width * height)
        let mask = segmentation(scenario: scenario).binaryMask
        let tongue = tongueLinearRGB * scenario.tongueExposure / scenario.gains
        for index in colors.indices where mask[index] != 0 {
            colors[index] = tongue
        }
        if scenario.shadowGradient {
            for row in 0..<height {
                for column in 0..<width where mask[row * width + column] != 0 {
                    colors[row * width + column] *= 0.35 + 1.1 * Double(column) / Double(width - 1)
                }
            }
        }
        var specularRemaining = Int(Double(mask.reduce(0) { $0 + Int($1) }) * scenario.specularFraction)
        for index in colors.indices where mask[index] != 0 && specularRemaining > 0 {
            colors[index] = SIMD3(repeating: 0.96)
            specularRemaining -= 1
        }
        for patchIndex in patchRects.indices {
            let rect = pixelRect(patchRects[patchIndex])
            let base: SIMD3<Double>
            if scenario.missingPatchIndices.contains(patchIndex) {
                base = .zero
            } else if scenario.saturatedPatchIndex == patchIndex {
                base = SIMD3(repeating: 1)
            } else if scenario.unstablePatches {
                base = SIMD3(repeating: 0.3)
            } else {
                base = targets[patchIndex] / scenario.gains
            }
            for row in rect.minY..<rect.maxY {
                for column in rect.minX..<rect.maxX {
                    var value = base
                    if scenario.noisyPatchIndex == patchIndex, (row + column).isMultiple(of: 7) {
                        value = SIMD3(0.9, 0.05, 0.7)
                    }
                    colors[row * width + column] = value
                }
            }
        }
        return try makeBuffer(colors)
    }

    static func uncalibratedMedianDeltaE(gains: SIMD3<Double>) -> Double {
        let values = zip(targets, targets.map { $0 / gains }).map { CalibrationMath.deltaE($0.1, $0.0) }.sorted()
        return (values[1] + values[2]) / 2
    }

    private static func makeBuffer(_ colors: [SIMD3<Double>]) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw InferenceError.pixelBufferAllocationFailed(status) }
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess, let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw InferenceError.pixelBufferLockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            for column in 0..<width {
                let color = colors[row * width + column]
                let offset = row * bytesPerRow + column * 4
                bytes[offset] = encode(color.z)
                bytes[offset + 1] = encode(color.y)
                bytes[offset + 2] = encode(color.x)
                bytes[offset + 3] = 255
            }
        }
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        }
        return buffer
    }

    private static func encode(_ linear: Double) -> UInt8 {
        let value = min(max(linear, 0), 1)
        let encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, Int((encoded * 255).rounded()))))
    }

    private static func pixelRect(_ normalized: CGRect) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        (
            Int((normalized.minX * CGFloat(width)).rounded(.down)),
            Int((normalized.minY * CGFloat(height)).rounded(.down)),
            Int((normalized.maxX * CGFloat(width)).rounded(.up)),
            Int((normalized.maxY * CGFloat(height)).rounded(.up))
        )
    }
}
