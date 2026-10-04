@preconcurrency import AVFoundation
import CoreMedia
import CoreImage
import CoreVideo
import Foundation
import UIKit

#if !targetEnvironment(simulator)
actor CameraSessionActor: CameraSessionControlling {
    nonisolated let previewSource: CameraPreviewSource

    private let session: AVCaptureSession
    private var deviceInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var latestVideoFrame: AnalyzableFrame?
    private var device: AVCaptureDevice?

    private let configuration: CameraConfiguration
    private let analyzer: any CameraQualityAnalyzing
    private let videoQueue = DispatchQueue(label: "com.ironscan.videoQueue", qos: .userInitiated)
    private let inferenceBridge = CameraInferenceBridge()
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
    private var torchOverride = false
    private var opticsProfile = CameraOpticsProfile.tongue
    private var lensPosition = CameraLensPosition.front
    private var captureOrientation = CaptureOrientation.portrait
    private var isSwitchingCamera = false

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
            // Permission prompts are owned by CameraPermissionManager on MainActor.
            // Never start or configure a capture session while authorization is unresolved.
            fail(.permissionDenied)
            return
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
            await startSessionIfNeeded()
            if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
                try applyTorch(enabled: true, level: torchLevel)
            }
            try beginStabilization()
            transition(.configured)
            try await settleAutomaticControls()
            try await waitForStableFrames()
            transition(.stabilized)
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.configurationFailed(error.localizedDescription))
        }
    }

    @discardableResult
    func capture() async -> Bool {
        guard let latestVideoFrame else { return false }
        return await capture(from: latestVideoFrame)
    }

    @discardableResult
    func capture(from frame: AnalyzableFrame) async -> Bool {
        guard stateMachine.state == .ready, !isSwitchingCamera else { return false }
        transition(.captureRequested)

        do {
            // The video frame is retained for capture and copied before inference.
            let pixelBuffer = try PixelBufferFactory.makeCrop(
                from: frame.pixelBuffer,
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            let quality = analyzer.analyzeCapture(pixelBuffer)
            let metadata = try makeMetadata(
                pixelBuffer: pixelBuffer,
                photoWidth: CVPixelBufferGetWidth(pixelBuffer),
                photoHeight: CVPixelBufferGetHeight(pixelBuffer)
            )
            let selected = CapturedFrame(
                pixelBuffer: pixelBuffer,
                metadata: metadata,
                quality: quality
            )

            try finishCaptureLifecycle()
            transition(.captureCompleted)
            eventContinuation?.yield(.captured(selected))
            try await prepareForNextCapture()
            return true
        } catch let error as CameraError {
            if stateMachine.state == .capturing {
                await recoverFromCaptureIssue(error)
            } else {
                fail(error)
            }
            return true
        } catch {
            let cameraError = CameraError.captureFailed(error.localizedDescription)
            if stateMachine.state == .capturing {
                await recoverFromCaptureIssue(cameraError)
            } else {
                fail(cameraError)
            }
            return true
        }
    }

    func toggleCamera() async throws {
        guard stateMachine.state == .ready,
              !isSwitchingCamera,
              isConfigured,
              let previousInput = deviceInput else {
            throw CameraError.configurationFailed("Camera session is not configured")
        }
        isSwitchingCamera = true
        latestVideoFrame = nil
        defer { isSwitchingCamera = false }

        let requestedPosition: CameraLensPosition = lensPosition == .back ? .front : .back
        guard let selectedDevice = cameraDevice(at: requestedPosition) else {
            throw CameraError.unsupportedDevice
        }

        let replacementInput: AVCaptureDeviceInput
        do {
            replacementInput = try AVCaptureDeviceInput(device: selectedDevice)
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }

        if currentTorchLevel > 0 {
            try applyTorch(enabled: false)
        }

        session.beginConfiguration()
        session.removeInput(previousInput)
        guard session.canAddInput(replacementInput) else {
            if session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            session.commitConfiguration()
            throw CameraError.configurationFailed("Requested camera input cannot be added")
        }
        session.addInput(replacementInput)
        device = selectedDevice
        deviceInput = replacementInput
        lensPosition = requestedPosition
        // Switching lenses requires a new explicit flashlight toggle.
        torchOverride = false
        focusWasLocked = false
        exposureWasLocked = false
        whiteBalanceWasLocked = false
        captureOrientation = .portrait
        configureOutputConnections()
        session.commitConfiguration()

        if let torchLevel = desiredTorchLevel, selectedDevice.hasTorch {
            try applyTorch(enabled: true, level: torchLevel)
        }
        eventContinuation?.yield(.capabilities(capabilities(for: selectedDevice)))
        try beginStabilization()
        try await settleAutomaticControls()
        try await waitForStableFrames()
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) async {
        let appliedOrientation = lensPosition == .front ? .portrait : orientation
        guard captureOrientation != appliedOrientation else { return }
        captureOrientation = appliedOrientation
        configureOutputConnections()
    }

    func setOpticsProfile(_ profile: CameraOpticsProfile) async throws {
        opticsProfile = profile
        guard isConfigured else { return }

        if currentTorchLevel > 0 {
            try applyTorch(enabled: false)
        }
        if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
            try applyTorch(enabled: true, level: torchLevel)
        }
        try beginStabilization()
        try await settleAutomaticControls()
        try await waitForStableFrames()
    }

    func setTorchEnabled(_ enabled: Bool) async throws {
        guard stateMachine.state != .idle else { return }
        if enabled {
            try applyTorch(
                enabled: true,
                level: opticsProfile.automaticTorchLevel ?? configuration.torchLevel
            )
        } else {
            try applyTorch(enabled: false)
        }
        torchOverride = enabled
        try beginStabilization()
        try await settleAutomaticControls()
        try await waitForStableFrames()
    }

    func stabilizeForAlignedTongue() async {
        guard stateMachine.state == .ready else { return }
        transition(.alignmentConfirmed)
        do {
            try beginStabilization()
            try await settleAutomaticControls()
            try await waitForStableFrames()
            transition(.stabilized)
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.configurationFailed(error.localizedDescription))
        }
    }

    func stop() async {
        latestVideoFrame = nil
        var cleanupError: CameraError?
        do {
            try finishCaptureLifecycle()
        } catch let error as CameraError {
            cleanupError = error
        } catch {
            cleanupError = .configurationFailed(error.localizedDescription)
        }
        await stopSessionIfNeeded()
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

    private func startSessionIfNeeded() async {
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    private func stopSessionIfNeeded() async {
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureSession() throws {
        // IronScan intentionally configures video only. No microphone/audio
        // device is discovered or added to the capture session.
        guard let selectedDevice = cameraDevice(at: .back) else {
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
        session.sessionPreset = .hd1920x1080

        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("Rear camera input cannot be added")
        }
        session.addInput(input)

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(inferenceBridge, queue: videoQueue)
        guard session.canAddOutput(videoDataOutput) else {
            throw CameraError.configurationFailed("Video-data output cannot be added")
        }
        session.addOutput(videoDataOutput)

        lensPosition = .back
        configureOutputConnections()

        let processor = LatestFrameProcessor<AnalyzableFrame>(maximumRate: configuration.maximumAnalysisRate) { [weak self] frame in
            await self?.processPreview(frame)
        }
        frameProcessor = processor
        inferenceBridge.onPreviewFrame = { frame in
            Task { await processor.submit(frame) }
        }
        inferenceBridge.onDisplayFrame = { [weak self] frame in
            Task { await self?.publishDisplayFrame(frame) }
        }
        inferenceBridge.configureMaximumInferenceRate(configuration.maximumLiveInferenceRate)
        inferenceBridge.onInferenceFrame = { [weak self] frame in
            Task { await self?.publishLiveFrame(frame) }
        }

        device = selectedDevice
        deviceInput = input
        lensPosition = .back
        isConfigured = true
        installInterruptionObserver()
        eventContinuation?.yield(.capabilities(capabilities(for: selectedDevice)))
    }

    private func cameraDevice(at position: CameraLensPosition) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            )
        }
        let preferredTypes = CameraDeviceDiscovery.preferredDeviceTypes(for: position)
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position.avPosition
        ).devices
        return preferredTypes.lazy.compactMap { preferredType in
            devices.first(where: { $0.deviceType == preferredType })
        }.first
    }

    private func configureOutputConnections() {
        configure(
            connection: videoDataOutput.connection(with: .video),
            orientation: captureOrientation,
            enablesStabilization: true
        )
    }

    private func configure(
        connection: AVCaptureConnection?,
        orientation: CaptureOrientation,
        enablesStabilization: Bool
    ) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            let angle = orientation.videoRotationAngle
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation.legacyVideoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = lensPosition == .front
        }
        if enablesStabilization, connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .standard
        }
    }

    private func beginStabilization() throws {
        guard let device else { throw CameraError.unsupportedDevice }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        } catch let error as CameraError {
            throw error
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
        focusWasLocked = false
        exposureWasLocked = false
        whiteBalanceWasLocked = false
    }

    private func prepareForNextCapture() async throws {
        transition(.resetAfterCapture)
        if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
            try applyTorch(enabled: true, level: torchLevel)
        }
        try beginStabilization()
        try await settleAutomaticControls()
        try await waitForStableFrames()
        transition(.stabilized)
    }

    /// Waits for the standard automatic controls without switching any control
    /// into a hardware-specific locked or custom mode.
    private func settleAutomaticControls() async throws {
        guard let device else { throw CameraError.unsupportedDevice }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.stabilizationTimeout)

        while device.isAdjustingFocus || device.isAdjustingExposure || device.isAdjustingWhiteBalance {
            guard clock.now < deadline else { throw CameraError.stabilizationTimedOut }
            try await clock.sleep(for: .milliseconds(50))
        }

        focusWasLocked = false
        exposureWasLocked = false
        whiteBalanceWasLocked = false
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
        stableFrameCount = observation.readiness == .unavailable ? 0 : stableFrameCount + 1
        eventContinuation?.yield(.quality(observation))
    }

    private func publishDisplayFrame(_ frame: AnalyzableFrame) {
        guard stateMachine.state == .stabilizing || stateMachine.state == .ready else { return }
        latestVideoFrame = frame
        eventContinuation?.yield(.displayFrame(frame))
    }

    private func publishLiveFrame(_ frame: AnalyzableFrame) {
        guard stateMachine.state == .stabilizing || stateMachine.state == .ready else { return }
        eventContinuation?.yield(.liveFrame(frame))
    }


    private func recoverFromCaptureIssue(_ issue: CameraError) async {
        transition(.captureAborted)
        do {
            if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
                try applyTorch(enabled: true, level: torchLevel)
            }
            try beginStabilization()
            try await settleAutomaticControls()
            try await waitForStableFrames()
            transition(.stabilized)
            eventContinuation?.yield(.captureIssue(issue))
        } catch let error as CameraError {
            fail(error)
        } catch {
            fail(.configurationFailed(error.localizedDescription))
        }
    }

    private func applyTorch(enabled: Bool, level: Float? = nil) throws {
        guard let device else { throw CameraError.unsupportedDevice }
        guard device.hasTorch, device.isTorchAvailable else {
            currentTorchLevel = 0
            if enabled { throw CameraError.torchUnavailable }
            return
        }
        if enabled, !device.isTorchModeSupported(.on) {
            throw CameraError.torchUnavailable
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled {
                let clampedLevel = min(max(level ?? configuration.torchLevel, 0.01), 1)
                try device.setTorchModeOn(level: clampedLevel)
                currentTorchLevel = clampedLevel
            } else if device.hasTorch, device.isTorchModeSupported(.off) {
                device.torchMode = .off
                currentTorchLevel = 0
            }
        } catch {
            print("Torch configuration failed: \(error)")
            throw CameraError.configurationFailed(error.localizedDescription)
        }
    }

    private var desiredTorchLevel: Float? {
        torchOverride ? (opticsProfile.automaticTorchLevel ?? configuration.torchLevel) : nil
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
            orientation: captureOrientation.rawValue,
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
            supportsCameraToggle: cameraDevice(at: lensPosition == .back ? .front : .back) != nil,
            lensPosition: lensPosition,
            supportsFocusPoint: device.isFocusPointOfInterestSupported,
            supportsExposurePoint: device.isExposurePointOfInterestSupported,
            supportsFocusLock: false,
            supportsCustomExposure: false,
            supportsWhiteBalanceLock: false,
            supportsActiveMaxDimensions: false
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
        latestVideoFrame = nil
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
#endif
