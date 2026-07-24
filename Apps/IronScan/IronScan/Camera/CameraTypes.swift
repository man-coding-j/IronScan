import AVFoundation
import CoreVideo
import Foundation
import UIKit

enum CameraLensPosition: String, Codable, Equatable, Sendable {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: .front
        case .back: .back
        }
    }
}

enum CameraOpticsProfile: String, Codable, Equatable, Sendable {
    case eye
    case nail
    case tongue

    var exposureBias: Float {
        switch self {
        case .eye: -0.5
        case .nail, .tongue: 0
        }
    }

    var usesNearFocusRange: Bool {
        self == .eye || self == .nail
    }

    var locksFocusAfterStabilization: Bool {
        self != .eye
    }

    var locksExposureAfterStabilization: Bool {
        self != .eye
    }

    var automaticTorchLevel: Float? {
        self == .nail ? 0.2 : nil
    }
}

enum CaptureOrientation: String, Codable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    var isPortrait: Bool {
        self == .portrait || self == .portraitUpsideDown
    }

    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 0
        case .landscapeRight: 180
        }
    }

    @available(iOS, deprecated: 17.0)
    var legacyVideoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        }
    }
}

enum CameraError: Error, Equatable, Sendable {
    case permissionDenied
    case restricted
    case unsupportedDevice
    case configurationFailed(String)
    case torchUnavailable
    case stabilizationTimedOut
    case exposureOutOfTolerance
    case captureFailed(String)
    case missingPixelBuffer
    case noAcceptableCapture
}

enum CameraState: Equatable, Sendable {
    case idle
    case requestingPermission
    case configuring
    case stabilizing
    case ready
    case capturing
    case completed
    case interrupted
    case failed(CameraError)
}

enum CaptureReadiness: String, Codable, Equatable, Sendable {
    case unavailable
    case stabilizing
    case moveCloser
    case moveFarther
    case centerTongue
    case holdStill
    case increaseLight
    case glareDetected
    case ready

    var message: String {
        switch self {
        case .unavailable: "Unable to assess"
        case .stabilizing: "Stabilizing camera"
        case .moveCloser: "Move closer"
        case .moveFarther: "Move farther"
        case .centerTongue: "Align your tongue"
        case .holdStill: "Hold still"
        case .increaseLight: "Increase light"
        case .glareDetected: "Glare detected"
        case .ready: "Ready"
        }
    }
}

struct CameraCapabilities: Codable, Equatable, Sendable {
    let hasTorch: Bool
    let supportsCameraToggle: Bool
    let lensPosition: CameraLensPosition
    let supportsFocusPoint: Bool
    let supportsExposurePoint: Bool
    let supportsFocusLock: Bool
    let supportsCustomExposure: Bool
    let supportsWhiteBalanceLock: Bool
    let supportsActiveMaxDimensions: Bool
}

struct WhiteBalanceMetadata: Codable, Equatable, Sendable {
    let redGain: Float
    let greenGain: Float
    let blueGain: Float
}

struct CaptureMetadata: Codable, Equatable, Sendable {
    let captureTimestamp: Date
    let deviceModelIdentifier: String
    let cameraDeviceType: String
    let activeFormatWidth: Int32
    let activeFormatHeight: Int32
    let pixelFormat: String
    let exposureDurationSeconds: Double
    let iso: Float
    let lensPosition: Float
    let whiteBalanceGains: WhiteBalanceMetadata
    let exposureTargetOffset: Float
    let torchLevel: Float
    let focusMode: String
    let exposureMode: String
    let whiteBalanceMode: String
    let orientation: String
    let focusWasLocked: Bool
    let exposureWasLocked: Bool
    let whiteBalanceWasLocked: Bool
    let sourceColorSpace: String
    let photoWidth: Int
    let photoHeight: Int
}

struct QualityObservation: Codable, Equatable, Sendable {
    let readiness: CaptureReadiness
    let sharpnessScore: Double
    let clippedHighlightFraction: Double
    let motionScore: Double
    let meanLuminance: Double
    let tongueCoverage: Double
    let tongueCenterOffset: Double

    static let unavailable = QualityObservation(
        readiness: .unavailable,
        sharpnessScore: 0,
        clippedHighlightFraction: 0,
        motionScore: 0,
        meanLuminance: 0,
        tongueCoverage: 0,
        tongueCenterOffset: 1
    )
}

struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let metadata: CaptureMetadata
    let quality: QualityObservation
}

struct CameraPreviewSource: @unchecked Sendable {
    let session: AVCaptureSession?
    let isSimulated: Bool

    static func physical(session: AVCaptureSession) -> CameraPreviewSource {
        CameraPreviewSource(session: session, isSimulated: false)
    }

    static let simulated = CameraPreviewSource(session: nil, isSimulated: true)
}

enum CameraEvent: @unchecked Sendable {
    case state(CameraState)
    case capabilities(CameraCapabilities)
    case quality(QualityObservation)
    case interruption(String)
    case liveFrame(AnalyzableFrame)
    case captured(CapturedFrame)
    case captureIssue(CameraError)
}

enum PhotoPixelFormatSelector {
    static func select(from availableFormats: [OSType]) -> OSType? {
        let preferredFormats = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        return preferredFormats.first(where: availableFormats.contains) ?? availableFormats.first
    }
}

struct CameraConfiguration: Equatable, Sendable {
    var torchLevel: Float = 0.35
    var whiteBalanceTemperatureKelvin: Float = 5_500
    var stabilizationTimeout: Duration = .seconds(5)
    var exposureTargetTolerance: Float = 0.35
    var maximumAnalysisRate: Double = 5
    var liveInferenceFrameStride = 24
    var requiredStableFrames = 2
    var burstCount = 3
    var clippingThreshold = 0.08
    var motionThreshold = 0.15
}

enum CameraDeviceDiscovery {
    static func preferredDeviceTypes(for position: CameraLensPosition) -> [AVCaptureDevice.DeviceType] {
        switch position {
        case .back:
            [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
            ]
        case .front:
            [.builtInWideAngleCamera]
        }
    }
}
