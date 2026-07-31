import AVFoundation
import CoreMedia
import Foundation

actor SimulatorCameraActor: CameraSessionControlling {
    nonisolated let previewSource = CameraPreviewSource.simulated

    private let imageProvider: any CameraImageProviding
    private let analyzer: any CameraQualityAnalyzing
    private var eventContinuation: AsyncStream<CameraEvent>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var stateMachine = CameraStateMachine()
    private var captureOrientation = CaptureOrientation.portrait

    init(
        imageProvider: any CameraImageProviding = StaticTestImageProvider(),
        analyzer: any CameraQualityAnalyzing = ImageQualityAnalyzer()
    ) {
        self.imageProvider = imageProvider
        self.analyzer = analyzer
    }

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
        do {
            let frame = try imageProvider.makeFrame()
            eventContinuation?.yield(.quality(analyzer.analyzePreview(frame)))
        } catch {
            transition(.failed(.configurationFailed(error.localizedDescription)))
            return
        }
        transition(.stabilized)
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runPreviewLoop()
        }
    }

    @discardableResult
    func capture() async -> Bool {
        guard stateMachine.state == .ready else { return false }
        transition(.captureRequested)
        do {
            let pixelBuffer = try imageProvider.makeFrame().pixelBuffer
            let frame = CapturedFrame(
                pixelBuffer: pixelBuffer,
                metadata: Self.metadata(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer),
                    orientation: captureOrientation
                ),
                quality: analyzer.analyzeCapture(pixelBuffer)
            )
            transition(.captureCompleted)
            eventContinuation?.yield(.captured(frame))
            transition(.resetAfterCapture)
            transition(.stabilized)
            return true
        } catch let error as CameraError {
            transition(.failed(error))
            return true
        } catch {
            transition(.failed(.captureFailed(error.localizedDescription)))
            return true
        }
    }

    func toggleCamera() async throws {
        throw CameraError.unsupportedDevice
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) async {
        captureOrientation = orientation
    }

    func setOpticsProfile(_ profile: CameraOpticsProfile) async throws {}

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
            do {
                let frame = try imageProvider.makeFrame()
                eventContinuation?.yield(.quality(analyzer.analyzePreview(frame)))
                eventContinuation?.yield(.liveFrame(frame))
            } catch {
                eventContinuation?.yield(.interruption("Static test frame unavailable"))
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
        supportsCameraToggle: false,
        lensPosition: .back,
        supportsFocusPoint: false,
        supportsExposurePoint: false,
        supportsFocusLock: true,
        supportsCustomExposure: true,
        supportsWhiteBalanceLock: true,
        supportsActiveMaxDimensions: false
    )

    private static func metadata(width: Int, height: Int, orientation: CaptureOrientation) -> CaptureMetadata {
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
            orientation: orientation.rawValue,
            focusWasLocked: true,
            exposureWasLocked: true,
            whiteBalanceWasLocked: true,
            sourceColorSpace: "sRGB",
            photoWidth: width,
            photoHeight: height
        )
    }
}
