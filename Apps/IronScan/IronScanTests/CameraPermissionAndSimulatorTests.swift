import AVFoundation
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
    func testFrameStrideThrottleProcessesEveryTwentyFourthFrame() {
        var throttle = FrameStrideThrottle(stride: 24)
        var processedFrames = [UInt64]()

        for _ in 0..<72 where throttle.shouldProcessNextFrame() {
            processedFrames.append(throttle.frameCount)
        }

        XCTAssertEqual(processedFrames, [24, 48, 72])
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
