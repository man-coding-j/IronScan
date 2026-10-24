@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

private actor CameraFrameRenderer {
    private let ciContext = CIContext()

    func render(_ frame: AnalyzableFrame) -> UIImage? {
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
            guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        }
    }
}

/// Main-actor presentation of the camera actor's throttled video stream.
/// Session configuration and hardware controls remain in CameraSessionActor.
@MainActor
final class MedicalCameraManager: ObservableObject {
    /// The default scan flow retains one controller and its capture session
    /// across SwiftUI view and view-model lifetimes.
    static let shared = MedicalCameraManager()

    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var isUsingFrontCamera = true
    @Published private(set) var isFlashlightOn = false
    private(set) var currentVideoFrame: AnalyzableFrame?

    @Published private(set) var currentPosition: AVCaptureDevice.Position = .front

    private let renderer = CameraFrameRenderer()
    private var isRendering = false
    private var frameGeneration = UUID()
    let camera: any CameraSessionControlling
    private var isSwitchingCamera = false

    /// Explicit controller injection keeps tests isolated from shared hardware.
    init(camera: any CameraSessionControlling = CameraControllerFactory.makeDefault()) {
        self.camera = camera
    }

    /// Start only after camera access is available. The session actor performs
    /// the final authorization check and starts capture off the main thread.
    func start() async {
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
        print("🎥 TOGGLE CAMERA TAPPED. Current position: \(currentPosition)")
        guard !isSwitchingCamera else {
            throw CameraError.configurationFailed("Camera switch is already in progress")
        }
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }
        let targetPosition: CameraLensPosition = isUsingFrontCamera ? .back : .front
        do {
            try await camera.toggleCamera()
            updateLensPosition(targetPosition)
            print("🎥 Camera successfully flipped to: \(currentPosition)")
        } catch {
            print("❌ ERROR switching camera: \(error.localizedDescription)")
            throw error
        }
    }

    func updateLensPosition(_ position: CameraLensPosition) {
        currentPosition = position.avPosition
        isUsingFrontCamera = position == .front
        isFlashlightOn = false
    }

    func toggleFlashlight() async throws {
        guard !isUsingFrontCamera, !isSwitchingCamera else {
            throw CameraError.torchUnavailable
        }
        let enabled = !isFlashlightOn
        try await camera.setTorchEnabled(enabled)
        isFlashlightOn = enabled
    }

    func display(_ frame: AnalyzableFrame) async {
        // Drop frames under load instead of queuing image conversions on UI.
        guard !isRendering else { return }
        isRendering = true
        let generation = frameGeneration
        defer { isRendering = false }
        guard let image = await renderer.render(frame), generation == frameGeneration else { return }
        currentVideoFrame = frame
        currentFrame = image
    }

    func capturePhoto() -> UIImage? {
        currentFrame
    }

    func clear() {
        frameGeneration = UUID()
        currentVideoFrame = nil
        currentFrame = nil
    }
}
