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
    private var torchOverride: Bool? = true
    private var opticsProfile = CameraOpticsProfile.tongue
    private var lensPosition = CameraLensPosition.back
    private var captureOrientation = CaptureOrientation.portrait

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
            if let torchLevel = desiredTorchLevel {
                try applyTorch(enabled: true, level: torchLevel)
            }
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

    @discardableResult
    func capture() async -> Bool {
        guard stateMachine.state == .ready else { return false }
        guard configuration.burstCount > 0 else {
            fail(.configurationFailed("Burst count must be greater than zero"))
            return false
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
                .filter({ $0.quality.readiness != .unavailable })
                .max(by: { captureCandidateScore($0) < captureCandidateScore($1) }) else {
                throw CameraError.noAcceptableCapture
            }

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
        guard isConfigured, let previousInput = deviceInput else {
            throw CameraError.configurationFailed("Camera session is not configured")
        }

        let requestedPosition: CameraLensPosition = lensPosition == .back ? .front : .back
        guard let selectedDevice = discoverCamera(at: requestedPosition) else {
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
        session.commitConfiguration()

        device = selectedDevice
        deviceInput = replacementInput
        lensPosition = requestedPosition
        focusWasLocked = false
        exposureWasLocked = false
        whiteBalanceWasLocked = false
        configureOutputConnections()
        configureMaximumPhotoDimensions(for: selectedDevice)

        if let torchLevel = desiredTorchLevel, selectedDevice.hasTorch {
            try applyTorch(enabled: true, level: torchLevel)
        }
        eventContinuation?.yield(.capabilities(capabilities(for: selectedDevice)))
        try beginStabilization()
        try await settleAndLockControls()
        try await waitForStableFrames()
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) async {
        guard captureOrientation != orientation else { return }
        captureOrientation = orientation
        configureOutputConnections()
    }

    func setOpticsProfile(_ profile: CameraOpticsProfile) async throws {
        opticsProfile = profile
        torchOverride = nil
        guard isConfigured else { return }

        if currentTorchLevel > 0 {
            try applyTorch(enabled: false)
        }
        if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
            try applyTorch(enabled: true, level: torchLevel)
        }
        try beginStabilization()
        try await settleAndLockControls()
        try await waitForStableFrames()
    }

    func setTorchEnabled(_ enabled: Bool) async throws {
        guard stateMachine.state != .idle else { return }
        torchOverride = enabled
        if enabled {
            try applyTorch(
                enabled: true,
                level: opticsProfile.automaticTorchLevel ?? configuration.torchLevel
            )
        } else {
            try applyTorch(enabled: false)
        }
        try beginStabilization()
        try await settleAndLockControls()
        try await waitForStableFrames()
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
        guard let selectedDevice = discoverCamera(at: .back) else {
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
        videoDataOutput.setSampleBufferDelegate(inferenceBridge, queue: videoQueue)
        guard session.canAddOutput(videoDataOutput) else {
            throw CameraError.configurationFailed("Video-data output cannot be added")
        }
        session.addOutput(videoDataOutput)

        guard session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed("Photo output cannot be added")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        configureOutputConnections()
        configureMaximumPhotoDimensions(for: selectedDevice)

        let processor = LatestFrameProcessor<AnalyzableFrame>(maximumRate: configuration.maximumAnalysisRate) { [weak self] frame in
            await self?.processPreview(frame)
        }
        frameProcessor = processor
        inferenceBridge.onPreviewFrame = { frame in
            Task { await processor.submit(frame) }
        }
        inferenceBridge.configureInferenceStride(configuration.liveInferenceFrameStride)
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

    private func discoverCamera(at position: CameraLensPosition) -> AVCaptureDevice? {
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
        configure(connection: videoDataOutput.connection(with: .video), enablesStabilization: true)
        configure(connection: photoOutput.connection(with: .video), enablesStabilization: false)
    }

    private func configure(connection: AVCaptureConnection?, enablesStabilization: Bool) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            let angle = captureOrientation.videoRotationAngle
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = captureOrientation.legacyVideoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if enablesStabilization, connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .standard
        }
    }

    private func configureMaximumPhotoDimensions(for device: AVCaptureDevice) {
        if #available(iOS 16.0, *),
           let maximumDimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
               Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
           }) {
            photoOutput.maxPhotoDimensions = maximumDimensions
        }
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
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = opticsProfile.usesNearFocusRange ? .near : .none
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.minAvailableVideoZoomFactor <= 1,
               device.maxAvailableVideoZoomFactor >= 1 {
                device.videoZoomFactor = 1
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = centerPoint
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            let exposureBias = min(
                max(opticsProfile.exposureBias, device.minExposureTargetBias),
                device.maxExposureTargetBias
            )
            device.setExposureTargetBias(exposureBias, completionHandler: nil)
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
        try await settleAndLockControls()
        try await waitForStableFrames()
        transition(.stabilized)
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
            if opticsProfile.locksFocusAfterStabilization,
               device.isFocusModeSupported(.locked) {
                let lockedLensPosition: Float = isMacroActive(device) ? 0 : device.lensPosition
                device.setFocusModeLocked(lensPosition: lockedLensPosition, completionHandler: nil)
                focusWasLocked = true
            }
            if opticsProfile.locksExposureAfterStabilization,
               device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO, completionHandler: nil)
                exposureWasLocked = true
            } else if opticsProfile.locksExposureAfterStabilization,
                      device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                exposureWasLocked = true
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                device.setWhiteBalanceModeLocked(
                    with: clampedWhiteBalanceGains(device.deviceWhiteBalanceGains, for: device),
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
        stableFrameCount = observation.readiness == .unavailable ? 0 : stableFrameCount + 1
        eventContinuation?.yield(.quality(observation))
    }

    private func publishLiveFrame(_ frame: AnalyzableFrame) {
        guard stateMachine.state == .stabilizing || stateMachine.state == .ready else { return }
        eventContinuation?.yield(.liveFrame(frame))
    }

    private func capturePhoto() async throws -> PhotoPayload {
        guard let selectedPixelFormat = PhotoPixelFormatSelector.select(
            from: photoOutput.availablePhotoPixelFormatTypes
        ) else {
            throw CameraError.configurationFailed("Photo pixel-buffer capture is unavailable")
        }
        let settings = AVCapturePhotoSettings(format: [
            kCVPixelBufferPixelFormatTypeKey as String: selectedPixelFormat
        ])
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        if #available(iOS 16.0, *), photoOutput.maxPhotoDimensions.width > 0 {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        let rawPayload = try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureReceiver(continuation: continuation)
            delegate.retainUntilCompletion()
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        do {
            let normalizedPixelBuffer = try PixelBufferFactory.makeBGRA(from: rawPayload.pixelBuffer)
            return PhotoPayload(
                pixelBuffer: normalizedPixelBuffer,
                width: CVPixelBufferGetWidth(normalizedPixelBuffer),
                height: CVPixelBufferGetHeight(normalizedPixelBuffer)
            )
        } catch {
            throw CameraError.captureFailed(error.localizedDescription)
        }
    }

    private func captureCandidateScore(_ frame: CapturedFrame) -> Double {
        frame.quality.sharpnessScore
            - frame.quality.clippedHighlightFraction * 2
            - frame.quality.motionScore * 2
    }

    private func recoverFromCaptureIssue(_ issue: CameraError) async {
        transition(.captureAborted)
        do {
            if let torchLevel = desiredTorchLevel, device?.hasTorch == true {
                try applyTorch(enabled: true, level: torchLevel)
            }
            try beginStabilization()
            try await settleAndLockControls()
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
        if enabled {
            guard device.hasTorch, device.isTorchAvailable, device.isTorchModeSupported(.on) else {
                throw CameraError.torchUnavailable
            }
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
            throw CameraError.configurationFailed(error.localizedDescription)
        }
    }

    private var desiredTorchLevel: Float? {
        switch torchOverride {
        case .some(true):
            opticsProfile.automaticTorchLevel ?? configuration.torchLevel
        case .some(false):
            nil
        case .none:
            opticsProfile.automaticTorchLevel
        }
    }

    private func isMacroActive(_ device: AVCaptureDevice) -> Bool {
        if device.deviceType == .builtInUltraWideCamera {
            return true
        }
        return device.activePrimaryConstituent?.deviceType == .builtInUltraWideCamera
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
            supportsCameraToggle: discoverCamera(at: lensPosition == .back ? .front : .back) != nil,
            lensPosition: lensPosition,
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
