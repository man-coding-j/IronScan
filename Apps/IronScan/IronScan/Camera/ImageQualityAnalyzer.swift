import Accelerate
import CoreVideo
import Foundation

struct ImageQualityAnalyzer: CameraQualityAnalyzing {
    private let minimumLuminance = 0.18
    private let maximumClipping = 0.08
    private let minimumSharpness = 0.012

    func analyzePreview(_ frame: AnalyzableFrame) -> QualityObservation {
        analyze(frame.pixelBuffer)
    }

    func analyzeCapture(_ pixelBuffer: CVPixelBuffer) -> QualityObservation {
        analyze(pixelBuffer)
    }

    private func analyze(_ pixelBuffer: CVPixelBuffer) -> QualityObservation {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return .unavailable
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return .unavailable
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let sampleStep = max(1, min(width, height) / 160)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var luminanceValues = [Float]()
        luminanceValues.reserveCapacity((width / sampleStep) * (height / sampleStep))
        var clippedCount = 0

        for row in stride(from: 0, to: height, by: sampleStep) {
            for column in stride(from: 0, to: width, by: sampleStep) {
                let offset = row * bytesPerRow + column * 4
                let blue = Float(bytes[offset]) / 255
                let green = Float(bytes[offset + 1]) / 255
                let red = Float(bytes[offset + 2]) / 255
                let luminance = 0.0722 * blue + 0.7152 * green + 0.2126 * red
                luminanceValues.append(luminance)
                if luminance > 0.98 { clippedCount += 1 }
            }
        }

        guard !luminanceValues.isEmpty else { return .unavailable }
        var mean: Float = 0
        vDSP_meanv(luminanceValues, 1, &mean, vDSP_Length(luminanceValues.count))
        var meanSquare: Float = 0
        vDSP_measqv(luminanceValues, 1, &meanSquare, vDSP_Length(luminanceValues.count))
        let variance = max(0, meanSquare - mean * mean)
        let clippedFraction = Double(clippedCount) / Double(luminanceValues.count)

        let readiness: CaptureReadiness
        if Double(mean) < minimumLuminance {
            readiness = .increaseLight
        } else if clippedFraction > maximumClipping {
            readiness = .glareDetected
        } else if Double(variance) < minimumSharpness {
            readiness = .holdStill
        } else {
            readiness = .ready
        }

        return QualityObservation(
            readiness: readiness,
            sharpnessScore: Double(variance),
            clippedHighlightFraction: clippedFraction,
            motionScore: 0,
            meanLuminance: Double(mean),
            tongueCoverage: 1,
            tongueCenterOffset: 0
        )
    }
}
