import AVFoundation
import CoreVideo
import Foundation

protocol CameraSessionControlling: Sendable {
    var previewSource: CameraPreviewSource { get }
    func eventStream() async -> AsyncStream<CameraEvent>
    func start() async
    func capture() async
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
