import AVFoundation
import CoreVideo
import XCTest
@testable import IronScan

@MainActor
final class CameraPermissionManagerTests: XCTestCase {
    func testNotDeterminedPermissionUpdatesAfterGrant() async {
        let manager = CameraPermissionManager(provider: MockAuthorizationProvider(status: .notDetermined, requestResult: true))

        let granted = await manager.requestIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
        XCTAssertFalse(manager.shouldShowSettingsInstructions)
    }

    func testDeniedPermissionShowsSettingsInstructions() async {
        let manager = CameraPermissionManager(provider: MockAuthorizationProvider(status: .denied, requestResult: false))

        let granted = await manager.requestIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(manager.authorizationStatus, .denied)
        XCTAssertTrue(manager.shouldShowSettingsInstructions)
    }

    func testRestrictedPermissionDoesNotRequestAccess() async {
        let manager = CameraPermissionManager(provider: MockAuthorizationProvider(status: .restricted, requestResult: true))

        let granted = await manager.requestIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(manager.authorizationStatus, .restricted)
    }
}

final class SimulatorCameraActorTests: XCTestCase {
    func testOrientationAdapterMapsEverySupportedInterfaceOrientation() {
        XCTAssertEqual(CaptureOrientation(interfaceOrientation: .portrait), .portrait)
        XCTAssertEqual(CaptureOrientation(interfaceOrientation: .portraitUpsideDown), .portraitUpsideDown)
        XCTAssertEqual(CaptureOrientation(interfaceOrientation: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(CaptureOrientation(interfaceOrientation: .landscapeRight), .landscapeRight)
        XCTAssertNil(CaptureOrientation(interfaceOrientation: .unknown))
        XCTAssertEqual(CaptureOrientation.portrait.videoRotationAngle, 90)
        XCTAssertEqual(CaptureOrientation.landscapeLeft.videoRotationAngle, 0)
        XCTAssertEqual(CaptureOrientation.landscapeRight.videoRotationAngle, 180)
        XCTAssertEqual(CaptureOrientation.portraitUpsideDown.videoRotationAngle, 270)
    }

    func testSimulatorRejectsCameraToggleWithoutChangingCapture() async throws {
        let camera = SimulatorCameraActor()
        await XCTAssertThrowsErrorAsync(try await camera.toggleCamera()) { error in
            XCTAssertEqual(error as? CameraError, .unsupportedDevice)
        }
    }

    func testSimulatorAcceptsEveryOpticsProfile() async throws {
        let camera = SimulatorCameraActor()

        for profile in [CameraOpticsProfile.eye, .nail, .tongue] {
            try await camera.setOpticsProfile(profile)
        }
    }

    func testFrameStrideThrottleLimitsProcessingRate() {
        var throttle = FrameStrideThrottle(maximumRate: 4)
        let timestamps = [0.0, 0.10, 0.24, 0.25, 0.40, 0.50]
        let processed = timestamps.filter { seconds in
            throttle.shouldProcessNextFrame(timestamp: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        XCTAssertEqual(processed, [0.0, 0.25, 0.50])
    }

    func testSimulatorStreamReachesReadyAndCapturesSyntheticFrame() async throws {
        let camera = SimulatorCameraActor()
        let stream = await camera.eventStream()
        var iterator = stream.makeAsyncIterator()

        await camera.start()
        await camera.capture()

        var receivedReady = false
        var receivedCapture = false
        for _ in 0..<16 {
            guard let event = await iterator.next() else { break }
            switch event {
            case .state(.ready):
                receivedReady = true
            case let .captured(frame):
                receivedCapture = true
                XCTAssertEqual(CVPixelBufferGetWidth(frame.pixelBuffer), 96)
                XCTAssertEqual(CVPixelBufferGetHeight(frame.pixelBuffer), 96)
                XCTAssertEqual(frame.metadata.sourceColorSpace, "sRGB")
            default:
                break
            }
            if receivedReady, receivedCapture { break }
        }

        await camera.stop()
        XCTAssertTrue(receivedReady)
        XCTAssertTrue(receivedCapture)
    }

    func testOneHundredSimulatedCapturesCompleteWithBoundedStreamStorage() async {
        let camera = SimulatorCameraActor()
        let stream = await camera.eventStream()
        var iterator = stream.makeAsyncIterator()
        await camera.start()

        var captureCount = 0
        for _ in 0..<100 {
            await camera.capture()
            while let event = await iterator.next() {
                if case .captured = event {
                    captureCount += 1
                    break
                }
            }
        }

        await camera.stop()
        XCTAssertEqual(captureCount, 100)
    }

    func testSimulatorPreviewEmitsLiveInferenceFrame() async {
        let camera = SimulatorCameraActor()
        let stream = await camera.eventStream()
        var iterator = stream.makeAsyncIterator()
        await camera.start()

        var receivedLiveFrame = false
        for _ in 0..<16 {
            guard let event = await iterator.next() else { break }
            if case let .liveFrame(frame) = event {
                receivedLiveFrame = true
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(frame.pixelBuffer), kCVPixelFormatType_32BGRA)
                break
            }
        }

        await camera.stop()
        XCTAssertTrue(receivedLiveFrame)
    }

    func testInjectedStaticImageFeedsQualityAndCapturedFrame() async throws {
        let camera = SimulatorCameraActor(
            imageProvider: SolidCameraImageProvider(channelValue: 20)
        )
        let stream = await camera.eventStream()
        var iterator = stream.makeAsyncIterator()

        await camera.start()
        await camera.capture()

        var quality: QualityObservation?
        var capturedFrame: CapturedFrame?
        for _ in 0..<20 {
            guard let event = await iterator.next() else { break }
            switch event {
            case let .quality(observation):
                quality = observation
            case let .captured(frame):
                capturedFrame = frame
            default:
                break
            }
            if quality != nil, capturedFrame != nil { break }
        }

        await camera.stop()
        XCTAssertEqual(quality?.readiness, .increaseLight)
        XCTAssertEqual(capturedFrame?.quality.readiness, .increaseLight)
        XCTAssertEqual(capturedFrame.map { CVPixelBufferGetWidth($0.pixelBuffer) }, 32)
        XCTAssertEqual(capturedFrame.map { CVPixelBufferGetHeight($0.pixelBuffer) }, 32)
        XCTAssertNotNil(capturedFrame?.capturedImage)
    }

    func testSyntheticFramesReleaseAfterStressLoop() throws {
        weak var finalFrame: CVPixelBuffer?

        for phase in 0..<100 {
            autoreleasepool {
                do {
                    let frame = try SyntheticTongueFrameFactory.makePixelBuffer(phase: phase)
                    finalFrame = frame
                } catch {
                    XCTFail("Synthetic frame generation failed: \(error)")
                }
            }
        }

        XCTAssertNil(finalFrame)
    }
}

final class ImageQualityAnalyzerTests: XCTestCase {
    func testWellLitLowContrastFrameAllowsCapture() throws {
        let pixelBuffer = try makeSolidPixelBuffer(channelValue: 128)

        let observation = ImageQualityAnalyzer().analyzePreview(AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero))

        XCTAssertEqual(observation.readiness, .ready)
        XCTAssertEqual(observation.sharpnessScore, 0, accuracy: 0.000_001)
    }

    func testDarkFrameRequestsMoreLight() throws {
        let pixelBuffer = try makeSolidPixelBuffer(channelValue: 20)

        let observation = ImageQualityAnalyzer().analyzePreview(AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero))

        XCTAssertEqual(observation.readiness, .increaseLight)
    }

    func testFortyLumaFrameDoesNotReportLowExposure() throws {
        let pixelBuffer = try makeSolidPixelBuffer(channelValue: 40)

        let observation = ImageQualityAnalyzer().analyzePreview(AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero))

        XCTAssertNotEqual(observation.readiness, .increaseLight)
    }

    func testClippedFrameReportsGlare() throws {
        let pixelBuffer = try makeSolidPixelBuffer(channelValue: 255)

        let observation = ImageQualityAnalyzer().analyzePreview(AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero))

        XCTAssertEqual(observation.readiness, .glareDetected)
    }
}

final class CameraDeviceDiscoveryTests: XCTestCase {
    func testBackCameraPrefersUltraWideThenWideAngle() {
        XCTAssertEqual(
            CameraDeviceDiscovery.preferredDeviceTypes(for: .back),
            [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
            ]
        )
    }

    func testFrontCameraUsesWideAngleCamera() {
        XCTAssertEqual(
            CameraDeviceDiscovery.preferredDeviceTypes(for: .front),
            [.builtInWideAngleCamera]
        )
    }
}

final class CameraOpticsProfileTests: XCTestCase {
    func testProfilesUseConsistentLowPowerTorch() throws {
        for profile in [CameraOpticsProfile.eye, .nail, .tongue] {
            XCTAssertEqual(try XCTUnwrap(profile.automaticTorchLevel), 0.15)
        }
    }
}

final class MotionStabilityCalculatorTests: XCTestCase {
    func testStationarySamplesRemainStable() {
        var calculator = MotionStabilityCalculator()
        var reading = MotionStabilityReading.unavailable

        for _ in 0..<12 {
            reading = calculator.add(userAccelerationX: 0.01, y: 0.01, z: 0.01)
        }

        XCTAssertEqual(reading.status, .stable)
        XCTAssertEqual(reading.accelerationVariationG, 0, accuracy: 0.000_001)
        XCTAssertTrue(reading.allowsInference)
    }

    func testShakySamplesExceedThresholdAndBlockInference() {
        var calculator = MotionStabilityCalculator()
        var reading = MotionStabilityReading.unavailable

        for index in 0..<12 {
            let acceleration = index.isMultiple(of: 2) ? 0.25 : -0.25
            reading = calculator.add(userAccelerationX: acceleration, y: 0, z: 0)
        }

        XCTAssertEqual(reading.status, .unstable)
        XCTAssertGreaterThan(reading.accelerationVariationG, 0.15)
        XCTAssertFalse(reading.allowsInference)
    }

    func testUnavailableMotionHardwareDoesNotBlockCapture() {
        XCTAssertTrue(MotionStabilityReading.unavailable.allowsInference)
    }
}

private func makeSolidPixelBuffer(channelValue: UInt8) throws -> CVPixelBuffer {
    let width = 32
    let height = 32
    var optionalPixelBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
        &optionalPixelBuffer
    )
    guard createStatus == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
        throw CameraError.configurationFailed("Test pixel-buffer allocation failed: \(createStatus)")
    }
    let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
    guard lockStatus == kCVReturnSuccess else {
        throw CameraError.configurationFailed("Test pixel-buffer lock failed: \(lockStatus)")
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw CameraError.missingPixelBuffer
    }

    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for row in 0..<height {
        for column in 0..<width {
            let offset = row * bytesPerRow + column * 4
            bytes[offset] = channelValue
            bytes[offset + 1] = channelValue
            bytes[offset + 2] = channelValue
            bytes[offset + 3] = 255
        }
    }
    return pixelBuffer
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private struct MockAuthorizationProvider: CameraAuthorizationProviding {
    let status: AVAuthorizationStatus
    let requestResult: Bool

    func authorizationStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess() async -> Bool {
        requestResult
    }
}

private struct SolidCameraImageProvider: CameraImageProviding {
    let channelValue: UInt8

    func makeFrame() throws -> AnalyzableFrame {
        AnalyzableFrame(
            pixelBuffer: try makeSolidPixelBuffer(channelValue: channelValue),
            timestamp: .zero
        )
    }
}
