@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class CameraInferenceBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onPreviewFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onInferenceFrame: (@Sendable (AnalyzableFrame) -> Void)?
    private var inferenceThrottle = FrameStrideThrottle(stride: 24)

    func configureInferenceStride(_ stride: Int) {
        inferenceThrottle = FrameStrideThrottle(stride: stride)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let frame = AnalyzableFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
        onPreviewFrame?(frame)
        if inferenceThrottle.shouldProcessNextFrame() {
            onInferenceFrame?(frame)
        }
    }
}
