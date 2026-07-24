@preconcurrency import AVFoundation
import Foundation

protocol CameraAuthorizationProviding: Sendable {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess() async -> Bool
}

struct SystemCameraAuthorizationProvider: CameraAuthorizationProviding {
    func authorizationStatus() -> AVAuthorizationStatus {
        #if targetEnvironment(simulator)
        .authorized
        #else
        AVCaptureDevice.authorizationStatus(for: .video)
        #endif
    }

    func requestAccess() async -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        await AVCaptureDevice.requestAccess(for: .video)
        #endif
    }
}

@MainActor
final class CameraPermissionManager: ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus

    private let provider: any CameraAuthorizationProviding

    init(provider: any CameraAuthorizationProviding = SystemCameraAuthorizationProvider()) {
        self.provider = provider
        authorizationStatus = provider.authorizationStatus()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var shouldShowSettingsInstructions: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refresh() {
        authorizationStatus = provider.authorizationStatus()
    }

    func requestIfNeeded() async -> Bool {
        refresh()
        switch authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await provider.requestAccess()
            authorizationStatus = granted ? .authorized : .denied
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
