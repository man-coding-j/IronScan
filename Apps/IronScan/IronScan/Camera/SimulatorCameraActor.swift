import AVFoundation
import CoreMedia
import Foundation

actor SimulatorCameraActor: CameraSessionControlling {
    nonisolated let previewSource = CameraPreviewSource.simulated

    private var eventContinuation: AsyncStream<CameraEvent>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var stateMachine = CameraStateMachine()
    private var phase = 0

    func eventStream() -> AsyncStream<CameraEvent> {
        let streamPair = AsyncStream<CameraEvent>.makeStream(bufferingPolicy: .bufferingNewest(12))
        eventContinuation?.finish()
        eventContinuation = streamPair.continuation
        streamPair.continuation.yield(.state(stateMachine.state))
        return streamPair.stream
    }

    func start() async {
        guard stateMachine.state == .idle else { return }
        transition(.requestPermission)
        transition(.permissionGranted)
        transition(.configured)
        eventContinuation?.yield(.capabilities(Self.capabilities))
        eventContinuation?.yield(.quality(Self.readyObservation))
        transition(.stabilized)
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runPreviewLoop()
        }
    }

    func capture() async {
        guard stateMachine.state == .ready else { return }
        transition(.captureRequested)
        do {
            let pixelBuffer = try SyntheticTongueFrameFactory.makePixelBuffer(phase: phase)
            let frame = CapturedFrame(
                pixelBuffer: pixelBuffer,
                metadata: Self.metadata(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
                quality: Self.readyObservation
            )
            transition(.captureCompleted)
            eventContinuation?.yield(.captured(frame))
            transition(.resetAfterCapture)
        } catch let error as CameraError {
            transition(.failed(error))
        } catch {
            transition(.failed(.captureFailed(error.localizedDescription)))
        }
    }

    func setTorchEnabled(_ enabled: Bool) async throws {
        if enabled {
            throw CameraError.torchUnavailable
        }
    }

    func stabilizeForAlignedTongue() async {}

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        transition(.stopped)
        eventContinuation?.finish()
        eventContinuation = nil
    }

    func handleInterruptionEnded() async {}

    private func runPreviewLoop() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            phase += 1
            let readiness: CaptureReadiness = switch phase % 8 {
            case 1: .centerTongue
            case 2: .holdStill
            default: .ready
            }
            eventContinuation?.yield(.quality(QualityObservation(
                readiness: readiness,
                sharpnessScore: readiness == .ready ? 0.92 : 0.72,
                clippedHighlightFraction: 0.01,
                motionScore: readiness == .holdStill ? 0.2 : 0.02,
                meanLuminance: 0.52,
                tongueCoverage: 0.34,
                tongueCenterOffset: readiness == .centerTongue ? 0.12 : 0.02
            )))
            if phase.isMultiple(of: 2) {
                do {
                    let pixelBuffer = try SyntheticTongueFrameFactory.makePixelBuffer(phase: phase)
                    eventContinuation?.yield(.liveFrame(AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero)))
                } catch {
                    eventContinuation?.yield(.interruption("Synthetic preview frame unavailable"))
                }
            }
            do {
                try await clock.sleep(for: .milliseconds(450))
            } catch {
                return
            }
        }
    }

    private func transition(_ event: CameraStateMachine.Event) {
        stateMachine.handle(event)
        eventContinuation?.yield(.state(stateMachine.state))
    }

    private static let capabilities = CameraCapabilities(
        hasTorch: false,
        supportsFocusPoint: false,
        supportsExposurePoint: false,
        supportsFocusLock: true,
        supportsCustomExposure: true,
        supportsWhiteBalanceLock: true,
        supportsActiveMaxDimensions: false
    )

    private static let readyObservation = QualityObservation(
        readiness: .ready,
        sharpnessScore: 0.92,
        clippedHighlightFraction: 0.01,
        motionScore: 0.02,
        meanLuminance: 0.52,
        tongueCoverage: 0.34,
        tongueCenterOffset: 0.02
    )

    private static func metadata(width: Int, height: Int) -> CaptureMetadata {
        CaptureMetadata(
            captureTimestamp: Date(timeIntervalSince1970: 0),
            deviceModelIdentifier: "Simulator",
            cameraDeviceType: "synthetic",
            activeFormatWidth: Int32(width),
            activeFormatHeight: Int32(height),
            pixelFormat: "BGRA",
            exposureDurationSeconds: 1 / 60,
            iso: 100,
            lensPosition: 0.5,
            whiteBalanceGains: WhiteBalanceMetadata(redGain: 1, greenGain: 1, blueGain: 1),
            exposureTargetOffset: 0,
            torchLevel: 0,
            focusMode: "locked",
            exposureMode: "custom",
            whiteBalanceMode: "locked-daylight-5500K",
            orientation: "portrait",
            focusWasLocked: true,
            exposureWasLocked: true,
            whiteBalanceWasLocked: true,
            sourceColorSpace: "sRGB",
            photoWidth: width,
            photoHeight: height
        )
    }
}
