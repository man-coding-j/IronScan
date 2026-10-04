@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

/// Main-actor presentation of the camera actor's throttled video stream.
/// Session configuration and hardware controls remain in CameraSessionActor.
@MainActor
final class MedicalCameraManager: ObservableObject {
    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var isUsingFrontCamera = false
    @Published private(set) var isFlashlightOn = false
    private(set) var currentVideoFrame: AnalyzableFrame?

    private let context = CIContext()
    private let camera: (any CameraSessionControlling)?

    init(camera: (any CameraSessionControlling)? = nil) {
        self.camera = camera
    }

    /// Start only after camera access is available. The session actor performs
    /// the final authorization check and starts capture off the main thread.
    func start() async {
        guard let camera else { return }
        if !camera.previewSource.isSimulated {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .video) else { return }
            case .denied, .restricted:
                return
            @unknown default:
                return
            }
        }
        await camera.start()
    }

    /// The camera actor owns the AVCaptureSession and performs the input swap.
    func toggleCamera() async throws {
        guard let camera else {
            throw CameraError.configurationFailed("Camera session is unavailable")
        }
        try await camera.toggleCamera()
    }

    func updateLensPosition(_ position: CameraLensPosition) {
        isUsingFrontCamera = position == .front
        isFlashlightOn = false
    }

    func toggleFlashlight() async throws {
        guard !isUsingFrontCamera, let camera else {
            throw CameraError.torchUnavailable
        }
        let enabled = !isFlashlightOn
        try await camera.setTorchEnabled(enabled)
        isFlashlightOn = enabled
    }

    func display(_ frame: AnalyzableFrame) {
        let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        currentVideoFrame = frame
        currentFrame = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    func capturePhoto() -> UIImage? {
        currentFrame
    }

    func clear() {
        currentVideoFrame = nil
        currentFrame = nil
    }
}
