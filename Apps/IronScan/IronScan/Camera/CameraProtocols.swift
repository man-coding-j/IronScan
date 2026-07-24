import AVFoundation
import CoreVideo
import Foundation

protocol CameraSessionControlling: Sendable {
    var previewSource: CameraPreviewSource { get }
    func eventStream() async -> AsyncStream<CameraEvent>
    func start() async
    @discardableResult
    func capture() async -> Bool
    func toggleCamera() async throws
    func updateCaptureOrientation(_ orientation: CaptureOrientation) async
    func setOpticsProfile(_ profile: CameraOpticsProfile) async throws
    func setTorchEnabled(_ enabled: Bool) async throws
    func stabilizeForAlignedTongue() async
    func stop() async
    func handleInterruptionEnded() async
}

struct AnalyzableFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
}

protocol CameraQualityAnalyzing: Sendable {
    func analyzePreview(_ frame: AnalyzableFrame) -> QualityObservation
    func analyzeCapture(_ pixelBuffer: CVPixelBuffer) -> QualityObservation
}
