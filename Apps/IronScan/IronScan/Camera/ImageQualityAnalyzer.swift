import Accelerate
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import UIKit

enum ImageQualityIssue: LocalizedError, Equatable, Sendable {
    case tooDark
    case overexposed
    case tooBlurry

    var errorDescription: String? {
        switch self {
        case .tooDark:
            return "Increase ambient lighting"
        case .overexposed:
            return "Reduce glare and avoid harsh lighting"
        case .tooBlurry:
            return "Hold steady: blur detected"
        }
    }
}

struct ImageQualityAnalyzer: CameraQualityAnalyzing {
    /// Luminance is normalized from the 0...255 L8 guide-region sample.
    /// Real-world sunlight often leaves the surrounding frame in deep shadow,
    /// so only values below 40/255 are treated as genuinely underexposed.
    static let minimumBrightness = 40.0 / 255.0
    private static let maximumBrightness = 0.92
    private static let maximumHighlightFraction = 0.12
    private static let minimumBlurScore = 60.0
    private static let edgeAnalysisDimension = 192
    private static let centralCropFraction = 0.72

    func analyzePreview(_ frame: AnalyzableFrame) -> QualityObservation {
        Self.makeObservation(from: frame.pixelBuffer)
    }

    func analyzeCapture(_ pixelBuffer: CVPixelBuffer) -> QualityObservation {
        Self.makeObservation(from: pixelBuffer)
    }

    func captureIssue(for image: UIImage) -> ImageQualityIssue? {
        if let cgImage = image.cgImage {
            return Self.captureIssue(for: Self.imageQualityMetrics(for: CIImage(cgImage: cgImage)))
        }
        guard let ciImage = image.ciImage else {
            return nil
        }
        return Self.captureIssue(for: Self.imageQualityMetrics(for: ciImage))
    }

    func captureIssue(for cgImage: CGImage) -> ImageQualityIssue? {
        Self.captureIssue(for: Self.imageQualityMetrics(for: CIImage(cgImage: cgImage)))
    }

    func captureIssue(for pixelBuffer: CVPixelBuffer) -> ImageQualityIssue? {
        Self.captureIssue(for: Self.imageQualityMetrics(for: CIImage(cvPixelBuffer: pixelBuffer)))
    }

    func previewAssessment(for pixelBuffer: CVPixelBuffer) -> ImageQualityAssessment {
        Self.evaluateImageQuality(pixelBuffer: pixelBuffer)
    }

    func captureAssessment(for pixelBuffer: CVPixelBuffer) -> ImageQualityAssessment {
        Self.evaluateImageQuality(pixelBuffer: pixelBuffer)
    }

    static func evaluateImageQuality(image: UIImage) -> ImageQualityAssessment {
        if let cgImage = image.cgImage {
            return evaluateImageQuality(cgImage: cgImage)
        }

        guard let ciImage = image.ciImage else {
            return .unavailable
        }

        return evaluateImageQuality(ciImage: ciImage)
    }

    static func evaluateImageQuality(pixelBuffer: CVPixelBuffer) -> ImageQualityAssessment {
        evaluateImageQuality(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
    }

    private static func evaluateImageQuality(cgImage: CGImage) -> ImageQualityAssessment {
        evaluateImageQuality(ciImage: CIImage(cgImage: cgImage))
    }

    private static func evaluateImageQuality(ciImage: CIImage) -> ImageQualityAssessment {
        makeAssessment(from: imageQualityMetrics(for: ciImage))
    }

    private static func makeObservation(from pixelBuffer: CVPixelBuffer) -> QualityObservation {
        let metrics = imageQualityMetrics(for: CIImage(cvPixelBuffer: pixelBuffer))
        let readiness: CaptureReadiness
        if metrics.brightnessScore < minimumBrightness {
            readiness = .increaseLight
        } else if metrics.highlightFraction > maximumHighlightFraction
            || metrics.brightnessScore > maximumBrightness {
            readiness = .glareDetected
        } else if metrics.blurScore < minimumBlurScore {
            readiness = .holdStill
        } else {
            readiness = .ready
        }

        return QualityObservation(
            readiness: readiness,
            sharpnessScore: metrics.blurScore,
            clippedHighlightFraction: metrics.highlightFraction,
            motionScore: 0,
            meanLuminance: metrics.brightnessScore,
            tongueCoverage: 1,
            tongueCenterOffset: 0
        )
    }

    private static func makeLuminanceBuffer(from ciImage: CIImage) -> LuminanceBuffer? {
        let grayscaleFilter = CIFilter.colorControls()
        grayscaleFilter.inputImage = ciImage
        grayscaleFilter.saturation = 0

        guard let grayscaleImage = grayscaleFilter.outputImage else {
            return nil
        }

        let croppedImage = cropToCenter(of: grayscaleImage)
        let normalizedImage = croppedImage.transformed(
            by: CGAffineTransform(
                translationX: -croppedImage.extent.minX,
                y: -croppedImage.extent.minY
            )
        )
        let maximumDimension = max(normalizedImage.extent.width, normalizedImage.extent.height)
        guard maximumDimension > 0 else { return nil }

        let scale = min(1, CGFloat(edgeAnalysisDimension) / maximumDimension)
        let width = max(64, Int((normalizedImage.extent.width * scale).rounded()))
        let height = max(64, Int((normalizedImage.extent.height * scale).rounded()))
        let resizedImage = normalizedImage.transformed(by: .init(scaleX: scale, y: scale))
        let renderBounds = CGRect(x: 0, y: 0, width: width, height: height)

        var bytes = [UInt8](repeating: 0, count: width * height)
        let context = CIContext(options: nil)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            context.render(
                resizedImage,
                toBitmap: baseAddress,
                rowBytes: width,
                bounds: renderBounds,
                format: .L8,
                colorSpace: CGColorSpaceCreateDeviceGray()
            )
        }

        return LuminanceBuffer(
            pixels: bytes,
            width: width,
            height: height
        )
    }

    private static func imageQualityMetrics(for ciImage: CIImage) -> ImageQualityMetrics {
        guard let luminanceBuffer = makeLuminanceBuffer(from: ciImage) else {
            return .unavailable
        }
        return calculateMetrics(from: luminanceBuffer)
    }

    private static func cropToCenter(of image: CIImage) -> CIImage {
        let extent = image.extent.integral
        let cropWidth = extent.width * centralCropFraction
        let cropHeight = extent.height * centralCropFraction
        let cropRect = CGRect(
            x: extent.midX - (cropWidth / 2),
            y: extent.midY - (cropHeight / 2),
            width: cropWidth,
            height: cropHeight
        ).integral
        return image.cropped(to: cropRect)
    }

    private static func calculateMetrics(from buffer: LuminanceBuffer) -> ImageQualityMetrics {
        let floatPixels = buffer.pixels.map { Float($0) / 255 }
        var brightness: Float = 0
        vDSP_meanv(floatPixels, 1, &brightness, vDSP_Length(floatPixels.count))

        let highlightCount = buffer.pixels.reduce(into: 0) { count, pixel in
            if pixel >= 245 {
                count += 1
            }
        }

        let blurScore = laplacianVariance(in: buffer)

        return ImageQualityMetrics(
            brightnessScore: Double(brightness),
            blurScore: blurScore,
            highlightFraction: Double(highlightCount) / Double(max(buffer.pixels.count, 1))
        )
    }

    private static func laplacianVariance(in buffer: LuminanceBuffer) -> Double {
        guard buffer.width > 2, buffer.height > 2 else { return 0 }

        var laplacianValues = [Float]()
        laplacianValues.reserveCapacity((buffer.width - 2) * (buffer.height - 2))

        for y in 1..<(buffer.height - 1) {
            let rowStart = y * buffer.width
            let previousRowStart = (y - 1) * buffer.width
            let nextRowStart = (y + 1) * buffer.width

            for x in 1..<(buffer.width - 1) {
                let centerIndex = rowStart + x
                let center = Float(buffer.pixels[centerIndex])
                let left = Float(buffer.pixels[centerIndex - 1])
                let right = Float(buffer.pixels[centerIndex + 1])
                let top = Float(buffer.pixels[previousRowStart + x])
                let bottom = Float(buffer.pixels[nextRowStart + x])
                laplacianValues.append((4 * center) - left - right - top - bottom)
            }
        }

        guard !laplacianValues.isEmpty else { return 0 }
        var mean: Float = 0
        var standardDeviation: Float = 0
        vDSP_normalize(
            laplacianValues,
            1,
            nil,
            1,
            &mean,
            &standardDeviation,
            vDSP_Length(laplacianValues.count)
        )
        return Double(standardDeviation * standardDeviation)
    }

    private static func makeAssessment(from metrics: ImageQualityMetrics) -> ImageQualityAssessment {
        let isTooDark = metrics.brightnessScore < minimumBrightness
        let isOverexposed = metrics.brightnessScore > maximumBrightness
            || metrics.highlightFraction > maximumHighlightFraction
        let isTooBlurry = metrics.blurScore < minimumBlurScore

        let feedbackMessage: String
        if isTooDark && isTooBlurry {
            feedbackMessage = "Increase ambient lighting and hold steady"
        } else if isOverexposed && isTooBlurry {
            feedbackMessage = "Reduce glare and hold steady"
        } else if isTooDark {
            feedbackMessage = "Increase ambient lighting"
        } else if isOverexposed {
            feedbackMessage = "Reduce glare and avoid harsh lighting"
        } else if isTooBlurry {
            feedbackMessage = "Hold steady: blur detected"
        } else {
            feedbackMessage = "Image is sharp and well-lit"
        }

        return ImageQualityAssessment(
            isAcceptable: !(isTooDark || isOverexposed || isTooBlurry),
            blurScore: metrics.blurScore,
            brightnessScore: metrics.brightnessScore,
            feedbackMessage: feedbackMessage
        )
    }

    private static func captureIssue(for metrics: ImageQualityMetrics) -> ImageQualityIssue? {
        if metrics.brightnessScore < minimumBrightness {
            return .tooDark
        }
        if metrics.brightnessScore > maximumBrightness
            || metrics.highlightFraction > maximumHighlightFraction {
            return .overexposed
        }
        if metrics.blurScore < minimumBlurScore {
            return .tooBlurry
        }
        return nil
    }
}

private struct LuminanceBuffer {
    let pixels: [UInt8]
    let width: Int
    let height: Int
}

private struct ImageQualityMetrics {
    let brightnessScore: Double
    let blurScore: Double
    let highlightFraction: Double

    static let unavailable = ImageQualityMetrics(
        brightnessScore: 0,
        blurScore: 0,
        highlightFraction: 0
    )
}
