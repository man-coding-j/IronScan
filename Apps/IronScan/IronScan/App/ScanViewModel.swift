import Foundation
import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var statusText = "Preparing camera"
    @Published private(set) var readiness: CaptureReadiness = .stabilizing
    @Published private(set) var result: ScanResultSummary?
    @Published private(set) var benchmark: InferenceBenchmarkSummary?
    @Published private(set) var isBusy = false
    @Published private(set) var permissionStatus: AVAuthorizationStatus
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var liveScanSummary: LiveScanSummary?
    @Published private(set) var liveScanErrorText: String?
    @Published private(set) var liveVisualAttributeReport: TongueVisualAttributeReport?
    @Published private(set) var liveScanningState = LiveScanningState.idle
    @Published private(set) var isLiveTongueSteady = false
    @Published private(set) var supportsCameraToggle = false
    @Published private(set) var lensPosition = CameraLensPosition.front
    @Published private(set) var captureOrientation = CaptureOrientation.portrait
    @Published private(set) var errorAlertMessage: String?
    @Published private(set) var isSimulatorMode: Bool
    @Published private(set) var modelError: String?

    let previewSource: CameraPreviewSource

    private let camera: any CameraSessionControlling
    private let permissionManager: CameraPermissionManager
    private let pipeline: ScanPipelineActor
    private let haptics: ScanHapticsManager
    private var eventTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var liveInferenceTask: Task<Void, Never>?
    private var resultFallbackTask: Task<Void, Never>?
    private var modelsReady = false
    private var alignedLiveFrameCount = 0
    private var didStabilizeForLiveAlignment = false
    private var scanProgressTracker = LiveScanProgressTracker()

    init(
        camera: any CameraSessionControlling = CameraControllerFactory.makeDefault(),
        permissionManager: CameraPermissionManager = CameraPermissionManager(),
        pipeline: ScanPipelineActor = ScanPipelineActor(),
        haptics: ScanHapticsManager = ScanHapticsManager()
    ) {
        self.camera = camera
        self.permissionManager = permissionManager
        self.pipeline = pipeline
        self.haptics = haptics
        previewSource = camera.previewSource
        isSimulatorMode = camera.previewSource.isSimulated
        permissionStatus = permissionManager.authorizationStatus
        haptics.prepare()
    }

    var canCapture: Bool {
        modelsReady && cameraState == .ready && !isBusy
    }

    var isProcessing: Bool {
        isBusy
    }

    var canRunSyntheticWork: Bool {
        modelsReady && !isBusy
    }

    var canStartAnotherScan: Bool {
        result != nil && !isBusy && (cameraState == .ready || isSimulatorMode)
    }

    var showsPermissionInstructions: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }

    func start() {
        guard eventTask == nil else { return }
        modelError = nil
        statusText = "Validating on-device models"
        isBusy = true
        eventTask = Task { [weak self, camera, permissionManager, pipeline] in
            guard await permissionManager.requestIfNeeded() else {
                self?.permissionStatus = permissionManager.authorizationStatus
                self?.statusText = permissionManager.authorizationStatus == .restricted
                    ? "Camera access is restricted on this device"
                    : "Allow camera access in Settings"
                self?.readiness = .unavailable
                self?.isBusy = false
                return
            }
            self?.permissionStatus = permissionManager.authorizationStatus
            do {
                _ = try await pipeline.prepareModels()
                guard !Task.isCancelled else { return }
                self?.modelsReady = true
                self?.isBusy = false
                self?.statusText = "On-device models ready"
            } catch {
                print("AI model initialization failed: \(error)")
                self?.modelError = "AI Model Unavailable"
                if self?.isSimulatorMode == true {
                    self?.modelsReady = true
                    self?.isBusy = false
                    self?.statusText = "Simulator mode ready"
                } else {
                    self?.statusText = "AI Model Unavailable"
                    self?.isBusy = false
                    return
                }
            }
            let stream = await camera.eventStream()
            await camera.start()
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    func refreshPermissionAndRestart() {
        let previousStatus = permissionStatus
        permissionManager.refresh()
        permissionStatus = permissionManager.authorizationStatus
        guard permissionManager.isAuthorized, previousStatus != .authorized else { return }
        eventTask?.cancel()
        eventTask = nil
        start()
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        processingTask?.cancel()
        processingTask = nil
        liveInferenceTask?.cancel()
        liveInferenceTask = nil
        resultFallbackTask?.cancel()
        resultFallbackTask = nil
        resetLiveScanningExperience()
        Task { [camera] in
            await camera.stop()
        }
    }

    func capture() {
        guard canCapture else { return }
        liveInferenceTask?.cancel()
        liveInferenceTask = nil
        resetLiveScanningExperience()
        errorAlertMessage = nil
        isBusy = true
        result = nil
        scheduleResultFallback()
        Task { [camera] in
            await camera.capture()
        }
    }

    func dismissErrorAlert() {
        errorAlertMessage = nil
    }

    func resetForNextScan() {
        guard canStartAnotherScan else { return }
        result = nil
        resultFallbackTask?.cancel()
        resultFallbackTask = nil
        liveScanSummary = nil
        liveScanErrorText = nil
        resetLiveScanningExperience()
        statusText = "Ready for another scan"
    }

    func resetLiveScan() {
        liveScanSummary = nil
        liveScanErrorText = nil
        resetLiveScanningExperience()
        statusText = "Ready for another live scan"
    }

    func toggleCamera() {
        guard supportsCameraToggle, !isBusy else { return }
        liveInferenceTask?.cancel()
        liveInferenceTask = nil
        resetLiveScanningExperience()
        isBusy = true
        statusText = "Switching camera"
        Task { [weak self, camera] in
            do {
                try await camera.toggleCamera()
                self?.statusText = "Camera ready"
                self?.isBusy = false
            } catch {
                self?.statusText = "Camera switch is unavailable"
                self?.isBusy = false
            }
        }
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) {
        guard captureOrientation != orientation else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            captureOrientation = orientation
        }
        Task { [camera] in
            await camera.updateCaptureOrientation(orientation)
        }
    }

    func setTorchEnabled(_ enabled: Bool) {
        guard isTorchAvailable, !isBusy else { return }
        Task { [weak self, camera] in
            do {
                try await camera.setTorchEnabled(enabled)
                self?.isTorchEnabled = enabled
            } catch {
                self?.isTorchEnabled = false
                self?.statusText = "Lighting control is unavailable"
            }
        }
    }

    func runSyntheticDemo() {
        guard canRunSyntheticWork else { return }
        processingTask?.cancel()
        isBusy = true
        result = nil
        statusText = "Running synthetic fixture"
        processingTask = Task { [weak self, pipeline] in
            do {
                let summary = try await pipeline.runSyntheticDemo()
                guard !Task.isCancelled else { return }
                self?.finish(with: summary)
            } catch {
                self?.finish(with: error)
            }
        }
    }

    func runPhysicalDeviceBenchmark() {
        guard canRunSyntheticWork else { return }
        processingTask?.cancel()
        isBusy = true
        benchmark = nil
        statusText = "Running 100 local benchmark scans"
        let deviceModel = Self.deviceModelIdentifier()
        let operatingSystem = UIDevice.current.systemVersion
        processingTask = Task { [weak self, pipeline] in
            do {
                let summary = try await pipeline.runSyntheticBenchmark(
                    iterations: 100,
                    deviceModelIdentifier: deviceModel,
                    operatingSystemVersion: operatingSystem
                )
                guard !Task.isCancelled else { return }
                self?.benchmark = summary
                self?.statusText = "Benchmark complete"
                self?.isBusy = false
            } catch {
                self?.finish(with: error)
            }
        }
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case .displayFrame:
            break
        case let .state(state):
            update(state: state)
        case let .quality(observation):
            readiness = observation.readiness
            if !isBusy, modelError == nil {
                statusText = observation.readiness.message
            }
        case let .interruption(reason):
            statusText = "Camera interrupted: \(reason)"
        case let .liveFrame(frame):
            processLiveFrame(frame)
        case let .captured(frame):
            statusText = "Processing capture locally"
            if isSimulatorMode {
                statusText = "Preparing synthetic Simulator result"
                return
            }
            processingTask?.cancel()
            processingTask = Task { [weak self, pipeline] in
                do {
                    let summary = if self?.previewSource.isSimulated == true {
                        try await pipeline.processSyntheticCapture(frame)
                    } else {
                        try await pipeline.processPhysicalCapture(frame)
                    }
                    guard !Task.isCancelled else { return }
                    self?.finish(with: summary)
                } catch {
                    guard !Task.isCancelled else { return }
                    print("Post-capture image processing failed: \(error)")
                    self?.finishImageProcessingFailure()
                }
            }
        case let .captureIssue(error):
            print("Photo capture was not processed: \(error)")
            statusText = "Camera capture failed. Preparing a synthetic fallback."
            errorAlertMessage = "Could not process image. Please try again"
            haptics.failed()
        case let .capabilities(capabilities):
            isTorchAvailable = capabilities.hasTorch
            isTorchEnabled = capabilities.hasTorch
            supportsCameraToggle = capabilities.supportsCameraToggle
            lensPosition = capabilities.lensPosition
        }
    }

    private func processLiveFrame(_ frame: AnalyzableFrame) {
        guard modelsReady, cameraState == .ready, !isBusy, liveInferenceTask == nil else { return }
        if case .completed = liveScanningState { return }
        let shouldRunVisualInference = isLiveTongueSteady
        liveInferenceTask = Task { @MainActor [weak self, camera, pipeline] in
            defer { self?.liveInferenceTask = nil }
            do {
                let summary = try await pipeline.analyzeLiveFrame(
                    frame,
                    runVisualInference: shouldRunVisualInference
                )
                guard !Task.isCancelled else { return }
                self?.liveScanSummary = summary
                if !summary.isTongueAligned {
                    self?.handleLostAlignment()
                    return
                }
                self?.liveScanErrorText = nil
                if self?.alignedLiveFrameCount == 0 {
                    self?.liveScanningState = .aligning
                    self?.haptics.alignmentDetected()
                }
                self?.alignedLiveFrameCount = (self?.alignedLiveFrameCount ?? 0) + 1
                self?.isLiveTongueSteady = (self?.alignedLiveFrameCount ?? 0) >= 2
                if self?.isLiveTongueSteady == true, self?.didStabilizeForLiveAlignment == false {
                    self?.didStabilizeForLiveAlignment = true
                    await camera.stabilizeForAlignedTongue()
                }
                if let report = summary.visualAttributeReport {
                    self?.registerVisualEvaluation(report)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.liveScanErrorText = "Live alignment temporarily unavailable"
                self?.handleAnalysisFailure("Unable to analyze this frame. Hold steady and try again.")
            }
        }
    }

    private func update(state: CameraState) {
        cameraState = state
        switch state {
        case .idle: statusText = "Camera idle"
        case .requestingPermission: statusText = "Requesting camera permission"
        case .configuring: statusText = "Configuring camera"
        case .stabilizing: statusText = "Stabilizing camera"
        case .ready: statusText = modelError ?? "Ready"
        case .capturing: statusText = "Capturing"
        case .completed: statusText = "Capture complete"
        case .interrupted: statusText = "Camera interrupted"
        case let .failed(error):
            readiness = .unavailable
            permissionManager.refresh()
            permissionStatus = permissionManager.authorizationStatus
            isTorchEnabled = false
            liveInferenceTask?.cancel()
            liveInferenceTask = nil
            liveScanningState = .failed(reason: error.displayMessage)
            haptics.failed()
            let shouldProvideFallback: Bool = switch error {
            case .permissionDenied, .restricted:
                false
            default:
                modelsReady && result == nil
            }
            if shouldProvideFallback {
                statusText = "Camera unavailable. Preparing a synthetic fallback."
                isBusy = true
                if resultFallbackTask == nil {
                    scheduleResultFallback()
                }
            } else {
                statusText = error.displayMessage
                isBusy = false
            }
        }
    }

    private func finish(with summary: ScanResultSummary) {
        resultFallbackTask?.cancel()
        resultFallbackTask = nil
        if let visualAttributeReport = summary.visualAttributeReport {
            result = nil
            liveVisualAttributeReport = visualAttributeReport
            liveScanningState = .completed(report: visualAttributeReport)
        } else {
            result = summary
        }
        statusText = summary.title
        isBusy = false
        haptics.completed()
    }

    private func finish(with error: Error) {
        result = nil
        statusText = "Unable to assess: \(error.localizedDescription)"
        isBusy = false
        haptics.failed()
    }

    private func finishImageProcessingFailure() {
        result = nil
        statusText = "Analysis failed. Preparing a synthetic fallback."
        errorAlertMessage = "Could not process image. Please try again"
        haptics.failed()
    }

    private func scheduleResultFallback() {
        resultFallbackTask?.cancel()
        resultFallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.isBusy,
                  self.result == nil else { return }
            self.processingTask?.cancel()
            self.processingTask = nil
            self.resultFallbackTask = nil
            self.finish(with: .prototypeFallback(isSimulatorMode: self.isSimulatorMode))
        }
    }

    private func registerVisualEvaluation(_ report: TongueVisualAttributeReport) {
        let nextState = scanProgressTracker.register(report: report)
        liveScanningState = nextState
        if case .completed = nextState {
            liveVisualAttributeReport = report
            haptics.completed()
        } else {
            haptics.scanProgress(nextState.progress)
        }
    }

    private func handleLostAlignment() {
        let wasScanning = liveScanningState.isActivelyScanning || scanProgressTracker.evaluationCount > 0
        liveVisualAttributeReport = nil
        alignedLiveFrameCount = 0
        isLiveTongueSteady = false
        didStabilizeForLiveAlignment = false
        scanProgressTracker.reset()
        if wasScanning {
            liveScanningState = .failed(reason: "Tongue moved outside the oval. Realign and hold steady.")
            haptics.failed()
        } else {
            liveScanningState = .idle
        }
    }

    private func handleAnalysisFailure(_ reason: String) {
        liveVisualAttributeReport = nil
        alignedLiveFrameCount = 0
        isLiveTongueSteady = false
        didStabilizeForLiveAlignment = false
        scanProgressTracker.reset()
        liveScanningState = .failed(reason: reason)
        haptics.failed()
    }

    private func resetLiveScanningExperience() {
        liveVisualAttributeReport = nil
        liveScanningState = .idle
        alignedLiveFrameCount = 0
        isLiveTongueSteady = false
        didStabilizeForLiveAlignment = false
        scanProgressTracker.reset()
        haptics.reset()
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
}

private extension CameraError {
    var displayMessage: String {
        switch self {
        case .permissionDenied: "Camera permission is required"
        case .restricted: "Camera access is restricted"
        case .unsupportedDevice: "Camera unavailable — use the synthetic simulator demo"
        case .torchUnavailable: "A supported rear camera and torch are required"
        case .stabilizationTimedOut: "Camera could not stabilize"
        case .exposureOutOfTolerance: "Lighting is outside the capture range"
        case .noAcceptableCapture: "No capture met the quality checks"
        case .missingPixelBuffer: "Camera image was unavailable"
        case .configurationFailed, .captureFailed: "Camera setup could not complete"
        }
    }
}
