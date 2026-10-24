@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

/// Runs only on the serial video delegate queue. Normalize buffers once so
/// preview snapshots, quality checks, and captures agree on upright pixels.
final class CameraPortraitNormalizer {
    private let ciContext = CIContext()

    func normalize(_ pixelBuffer: CVPixelBuffer, position: AVCaptureDevice.Position,
                   isAlreadyMirrored: Bool) -> CVPixelBuffer? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let isLandscape = image.extent.width > image.extent.height
        let needsMirror = position == .front && !isAlreadyMirrored
        guard isLandscape || needsMirror else { return pixelBuffer }
        if isLandscape {
            // Mirroring a landscape buffer happens in sensor coordinates.
            // Rotate in the opposite direction when it is already mirrored so
            // the final portrait has the same upright selfie orientation as
            // rotating first and then mirroring horizontally.
            image = image.oriented(isAlreadyMirrored ? .left : .right)
        }
        if needsMirror { image = image.oriented(.upMirrored) }
        image = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX, y: -image.extent.minY
        ))
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
            Int(image.extent.width), Int(image.extent.height),
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
        guard status == kCVReturnSuccess, let result else { return nil }
        ciContext.render(image, to: result)
        return result
    }
}

final class CameraInferenceBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onPreviewFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onDisplayFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onInferenceFrame: (@Sendable (AnalyzableFrame) -> Void)?
    private let portraitNormalizer = CameraPortraitNormalizer()
    private var displayThrottle = FrameStrideThrottle(maximumRate: 60)
    private var inferenceThrottle = FrameStrideThrottle(maximumRate: 4)

    func configureMaximumInferenceRate(_ maximumRate: Double) {
        inferenceThrottle = FrameStrideThrottle(maximumRate: maximumRate)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        autoreleasepool {
            guard CMSampleBufferDataIsReady(sampleBuffer),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            let position = connection.inputPorts.first(where: { $0.mediaType == .video })?.sourceDevicePosition ?? .back
            guard let uprightBuffer = portraitNormalizer.normalize(pixelBuffer, position: position,
                isAlreadyMirrored: connection.isVideoMirrored) else { return }
            let frame = AnalyzableFrame(
                pixelBuffer: uprightBuffer,
                timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            )
            onPreviewFrame?(frame)
            if displayThrottle.shouldProcessNextFrame(timestamp: frame.timestamp) {
                onDisplayFrame?(frame)
            }
            if inferenceThrottle.shouldProcessNextFrame(timestamp: frame.timestamp) {
                onInferenceFrame?(frame)
            }
        }
    }
}
