@preconcurrency import AVFoundation
import CoreMedia
import CoreImage
import CoreVideo
import Foundation
import UIKit

actor CameraSessionActor: CameraSessionControlling {
    nonisolated let previewSource: CameraPreviewSource

    private let session: AVCaptureSession
    private var deviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?

    private let configuration: CameraConfiguration
    private let analyzer: any CameraQualityAnalyzing
    private let sampleBufferQueue = DispatchQueue(label: "org.ironscan.camera.sample-buffer", qos: .userInitiated)
    private let sampleReceiver = SampleBufferReceiver()
    private var frameProcessor: LatestFrameProcessor<AnalyzableFrame>?
    private var eventContinuation: AsyncStream<CameraEvent>.Continuation?
    private var stateMachine = CameraStateMachine()
    private var stableFrameCount = 0
    private var interruptionObserver: CameraInterruptionObserver?
    private var isConfigured = false
    private var focusWasLocked = false
    private var exposureWasLocked = false
    private var whiteBalanceWasLocked = false
    private var currentTorchLevel: Float = 0

    init(
        configuration: CameraConfiguration = CameraConfiguration(),
        analyzer: any CameraQualityAnalyzing = ImageQualityAnalyzer()
    ) {
        let captureSession = AVCaptureSession()
        session = captureSession
        previewSource = .physical(session: captureSession)
        self.configuration = configuration
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

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                fail(.permissionDenied)
                return
            }
        case .denied:
            fail(.permissionDenied)
            return
        case .restricted:
            fail(.restricted)
            return
        @unknown default:
            fail(.configurationFailed("Unknown camera authorization state"))
            return
        }

        transition(.permissionGranted)

        do {
            if !isConfigured {
                try configureSession()
            }
            if !session.isRunning {
                session.startRunning()
            }
            try applyTorch(enabled: true)
            try beginStabilization()
            transition(.configured)
            try await settleAndLockControls()
            try await waitForStableFrames()
            transition(.stabilized)
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.configurationFailed(error.localizedDescription))
        }
    }

    func capture() async {
        guard stateMachine.state == .ready else { return }
        guard configuration.burstCount > 0 else {
            fail(.configurationFailed("Burst count must be greater than zero"))
            return
        }
        transition(.captureRequested)

        do {
            var candidates = [CapturedFrame]()
            for _ in 0..<configuration.burstCount {
                let payload = try await capturePhoto()
                let quality = analyzer.analyzeCapture(payload.pixelBuffer)
                let metadata = try makeMetadata(
                    pixelBuffer: payload.pixelBuffer,
                    photoWidth: payload.width,
                    photoHeight: payload.height
                )
                candidates.append(CapturedFrame(pixelBuffer: payload.pixelBuffer, metadata: metadata, quality: quality))
            }

            guard let selected = candidates
                .filter({
                    $0.quality.readiness != .unavailable
                        && $0.quality.clippedHighlightFraction <= configuration.clippingThreshold
                        && $0.quality.motionScore <= configuration.motionThreshold
                })
                .max(by: { $0.quality.sharpnessScore < $1.quality.sharpnessScore }) else {
                throw CameraError.noAcceptableCapture
            }

            try finishCaptureLifecycle()
            transition(.captureCompleted)
            eventContinuation?.yield(.captured(selected))
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.captureFailed(error.localizedDescription))
        }
    }

    func setTorchEnabled(_ enabled: Bool) async throws {
        guard stateMachine.state != .idle else { return }
        try applyTorch(enabled: enabled)
    }

    func stabilizeForAlignedTongue() async {
        guard stateMachine.state == .ready else { return }
        transition(.alignmentConfirmed)
        do {
            try beginStabilization()
            try await settleAndLockControls()
            try await waitForStableFrames()
            transition(.stabilized)
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.configurationFailed(error.localizedDescription))
        }
    }

    func stop() {
        var cleanupError: CameraError?
        do {
            try finishCaptureLifecycle()
        } catch let error as CameraError {
            cleanupError = error
        } catch {
            cleanupError = .configurationFailed(error.localizedDescription)
        }
        if session.isRunning {
            session.stopRunning()
        }
        if let cleanupError {
            transition(.failed(cleanupError))
        } else {
            transition(.stopped)
        }
    }

    func handleInterruptionEnded() async {
        guard stateMachine.state == .interrupted else { return }
        transition(.interruptionEnded)
        await start()
    }

    private func configureSession() throws {
        guard let selectedDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unsupportedDevice
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: selectedDevice)
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("Rear wide-camera input cannot be added")
        }
        session.addInput(input)

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(sampleReceiver, queue: sampleBufferQueue)
        guard session.canAddOutput(videoDataOutput) else {
            throw CameraError.configurationFailed("Video-data output cannot be added")
        }
        session.addOutput(videoDataOutput)

        guard session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed("Photo output cannot be added")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        let portraitRotation: CGFloat = 90
        if let videoConnection = videoDataOutput.connection(with: .video),
           videoConnection.isVideoRotationAngleSupported(portraitRotation) {
            videoConnection.videoRotationAngle = portraitRotation
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .standard
            }
        }
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(portraitRotation) {
            photoConnection.videoRotationAngle = portraitRotation
        }

        if #available(iOS 16.0, *),
           let maximumDimensions = selectedDevice.activeFormat.supportedMaxPhotoDimensions.max(by: {
               Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
           }) {
            photoOutput.maxPhotoDimensions = maximumDimensions
        }

        let processor = LatestFrameProcessor<AnalyzableFrame>(maximumRate: configuration.maximumAnalysisRate) { [weak self] frame in
            await self?.processPreview(frame)
        }
        frameProcessor = processor
        sampleReceiver.onFrame = { frame in
            Task { await processor.submit(frame) }
        }
        sampleReceiver.configureLiveInference(stride: configuration.liveInferenceFrameStride)
        sampleReceiver.onLiveFrame = { [weak self] frame in
            Task { await self?.publishLiveFrame(frame) }
        }

        device = selectedDevice
        deviceInput = input
        isConfigured = true
        installInterruptionObserver()
        eventContinuation?.yield(.capabilities(capabilities(for: selectedDevice)))
    }

    private func beginStabilization() throws {
        guard let device else { throw CameraError.unsupportedDevice }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let centerPoint = CGPoint(x: 0.5, y: 0.5)

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = centerPoint
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = centerPoint
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.activeFormat.supportedColorSpaces.contains(.sRGB) {
                device.activeColorSpace = .sRGB
            }
        } catch let error as CameraError {
            throw error
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
    }

    private func settleAndLockControls() async throws {
        guard let device else { throw CameraError.unsupportedDevice }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.stabilizationTimeout)

        while device.isAdjustingFocus || device.isAdjustingExposure || device.isAdjustingWhiteBalance {
            guard clock.now < deadline else { throw CameraError.stabilizationTimedOut }
            try await clock.sleep(for: .milliseconds(50))
        }

        guard abs(device.exposureTargetOffset) <= configuration.exposureTargetTolerance else {
            throw CameraError.exposureOutOfTolerance
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: device.lensPosition, completionHandler: nil)
                focusWasLocked = true
            }
            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(duration: device.exposureDuration, iso: device.iso, completionHandler: nil)
                exposureWasLocked = true
            } else if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                exposureWasLocked = true
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                let daylightValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: configuration.whiteBalanceTemperatureKelvin,
                    tint: 0
                )
                device.setWhiteBalanceModeLocked(
                    with: clampedWhiteBalanceGains(device.deviceWhiteBalanceGains(for: daylightValues), for: device),
                    completionHandler: nil
                )
                whiteBalanceWasLocked = true
            }
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
    }

    private func waitForStableFrames() async throws {
        stableFrameCount = 0
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.stabilizationTimeout)
        while stableFrameCount < configuration.requiredStableFrames {
            guard clock.now < deadline else { throw CameraError.stabilizationTimedOut }
            try await clock.sleep(for: .milliseconds(25))
        }
    }

    private func processPreview(_ frame: AnalyzableFrame) {
        let observation = analyzer.analyzePreview(frame)
        stableFrameCount = observation.readiness == .ready ? stableFrameCount + 1 : 0
        eventContinuation?.yield(.quality(observation))
    }

    private func publishLiveFrame(_ frame: AnalyzableFrame) {
        guard stateMachine.state == .stabilizing || stateMachine.state == .ready else { return }
        eventContinuation?.yield(.liveFrame(frame))
    }

    private func capturePhoto() async throws -> PhotoPayload {
        guard photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
            throw CameraError.configurationFailed("BGRA photo capture is unavailable")
        }
        let settings = AVCapturePhotoSettings(format: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        if #available(iOS 16.0, *), photoOutput.maxPhotoDimensions.width > 0 {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureReceiver(continuation: continuation)
            delegate.retainUntilCompletion()
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func applyTorch(enabled: Bool) throws {
        guard let device else { throw CameraError.unsupportedDevice }
        if enabled {
            guard device.hasTorch, device.isTorchAvailable, device.isTorchModeSupported(.on) else {
                throw CameraError.torchUnavailable
            }
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled {
                let level = min(max(configuration.torchLevel, 0.01), 1)
                try device.setTorchModeOn(level: level)
                currentTorchLevel = level
            } else if device.hasTorch, device.isTorchModeSupported(.off) {
                device.torchMode = .off
                currentTorchLevel = 0
            }
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
    }

    private func finishCaptureLifecycle() throws {
        if let device {
            try applyTorch(enabled: false)
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } catch {
                throw CameraError.configurationFailed(error.localizedDescription)
            }
        }
        focusWasLocked = false
        exposureWasLocked = false
        whiteBalanceWasLocked = false
    }

    private func makeMetadata(pixelBuffer: CVPixelBuffer, photoWidth: Int, photoHeight: Int) throws -> CaptureMetadata {
        guard let device else { throw CameraError.unsupportedDevice }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let gains = device.deviceWhiteBalanceGains
        let colorSpaceName: String
        if let name = CIImage(cvPixelBuffer: pixelBuffer).colorSpace?.name {
            colorSpaceName = name == CGColorSpace.sRGB ? "sRGB" : name as String
        } else {
            colorSpaceName = "unknown"
        }

        return CaptureMetadata(
            captureTimestamp: Date(),
            deviceModelIdentifier: Self.deviceModelIdentifier(),
            cameraDeviceType: device.deviceType.rawValue,
            activeFormatWidth: dimensions.width,
            activeFormatHeight: dimensions.height,
            pixelFormat: Self.fourCharacterCode(CVPixelBufferGetPixelFormatType(pixelBuffer)),
            exposureDurationSeconds: CMTimeGetSeconds(device.exposureDuration),
            iso: device.iso,
            lensPosition: device.lensPosition,
            whiteBalanceGains: WhiteBalanceMetadata(redGain: gains.redGain, greenGain: gains.greenGain, blueGain: gains.blueGain),
            exposureTargetOffset: device.exposureTargetOffset,
            torchLevel: currentTorchLevel,
            focusMode: String(describing: device.focusMode),
            exposureMode: String(describing: device.exposureMode),
            whiteBalanceMode: String(describing: device.whiteBalanceMode),
            orientation: "portrait",
            focusWasLocked: focusWasLocked,
            exposureWasLocked: exposureWasLocked,
            whiteBalanceWasLocked: whiteBalanceWasLocked,
            sourceColorSpace: colorSpaceName,
            photoWidth: photoWidth,
            photoHeight: photoHeight
        )
    }

    private func capabilities(for device: AVCaptureDevice) -> CameraCapabilities {
        CameraCapabilities(
            hasTorch: device.hasTorch && device.isTorchAvailable,
            supportsFocusPoint: device.isFocusPointOfInterestSupported,
            supportsExposurePoint: device.isExposurePointOfInterestSupported,
            supportsFocusLock: device.isFocusModeSupported(.locked),
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsWhiteBalanceLock: device.isWhiteBalanceModeSupported(.locked),
            supportsActiveMaxDimensions: !device.activeFormat.supportedMaxPhotoDimensions.isEmpty
        )
    }

    private func clampedWhiteBalanceGains(_ gains: AVCaptureDevice.WhiteBalanceGains, for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let range: ClosedRange<Float> = 1...device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, range.lowerBound), range.upperBound),
            greenGain: min(max(gains.greenGain, range.lowerBound), range.upperBound),
            blueGain: min(max(gains.blueGain, range.lowerBound), range.upperBound)
        )
    }

    private func installInterruptionObserver() {
        interruptionObserver = CameraInterruptionObserver(
            session: session,
            onInterrupted: { [weak self] reason in
                Task { await self?.handleInterruption(reason) }
            },
            onInterruptionEnded: { [weak self] in
                Task { await self?.handleInterruptionEnded() }
            }
        )
    }

    private func handleInterruption(_ reason: String) {
        do {
            try applyTorch(enabled: false)
        } catch let error as CameraError {
            transition(.failed(error))
            return
        } catch {
            transition(.failed(.configurationFailed(error.localizedDescription)))
            return
        }
        transition(.interruptionBegan)
        eventContinuation?.yield(.interruption(reason))
    }

    private func transition(_ event: CameraStateMachine.Event) {
        stateMachine.handle(event)
        eventContinuation?.yield(.state(stateMachine.state))
    }

    private func fail(_ error: CameraError) {
        do {
            try finishCaptureLifecycle()
            transition(.failed(error))
        } catch let cleanupError as CameraError {
            transition(.failed(cleanupError))
        } catch {
            transition(.failed(.configurationFailed(error.localizedDescription)))
        }
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    private static func fourCharacterCode(_ code: OSType) -> String {
        let scalars = [24, 16, 8, 0].compactMap { shift -> UnicodeScalar? in
            UnicodeScalar(UInt8((code >> OSType(shift)) & 0xff))
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private final class SampleBufferReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrame: (@Sendable (AnalyzableFrame) -> Void)?
    var onLiveFrame: (@Sendable (AnalyzableFrame) -> Void)?
    private var inferenceThrottle = FrameStrideThrottle(stride: 24)

    func configureLiveInference(stride: Int) {
        inferenceThrottle = FrameStrideThrottle(stride: stride)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        onFrame?(frame)
        if inferenceThrottle.shouldProcessNextFrame() {
            onLiveFrame?(frame)
        }
    }
}

private struct PhotoPayload: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let width: Int
    let height: Int
}

private final class PhotoCaptureReceiver: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var retainedDelegates = [ObjectIdentifier: PhotoCaptureReceiver]()
    private var continuation: CheckedContinuation<PhotoPayload, Error>?

    init(continuation: CheckedContinuation<PhotoPayload, Error>) {
        self.continuation = continuation
    }

    func retainUntilCompletion() {
        Self.lock.lock()
        Self.retainedDelegates[ObjectIdentifier(self)] = self
        Self.lock.unlock()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finish(with: .failure(error))
            return
        }
        guard let pixelBuffer = photo.pixelBuffer else {
            finish(with: .failure(CameraError.missingPixelBuffer))
            return
        }
        let dimensions = photo.resolvedSettings.photoDimensions
        finish(with: .success(PhotoPayload(pixelBuffer: pixelBuffer, width: Int(dimensions.width), height: Int(dimensions.height))))
    }

    private func finish(with result: Result<PhotoPayload, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        Self.lock.lock()
        Self.retainedDelegates.removeValue(forKey: ObjectIdentifier(self))
        Self.lock.unlock()
    }
}

private final class CameraInterruptionObserver: @unchecked Sendable {
    private var tokens = [NSObjectProtocol]()

    init(session: AVCaptureSession, onInterrupted: @escaping @Sendable (String) -> Void, onInterruptionEnded: @escaping @Sendable () -> Void) {
        tokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { notification in
            let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey].map(String.init(describing:)) ?? "unknown"
            onInterrupted(reason)
        })
        tokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { _ in
            onInterruptionEnded()
        })
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}
