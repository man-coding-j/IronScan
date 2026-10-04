@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class CameraInferenceBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onPreviewFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onDisplayFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onInferenceFrame: (@Sendable (AnalyzableFrame) -> Void)?
    private var displayThrottle = FrameStrideThrottle(maximumRate: 15)
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
            let frame = AnalyzableFrame(
                pixelBuffer: pixelBuffer,
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
