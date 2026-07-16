import Foundation
import AVFoundation
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
    @Published private(set) var isLiveTongueSteady = false

    let previewSource: CameraPreviewSource

    private let camera: any CameraSessionControlling
    private let permissionManager: CameraPermissionManager
    private let pipeline: ScanPipelineActor
    private var eventTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var liveInferenceTask: Task<Void, Never>?
    private var modelsReady = false
    private var alignedLiveFrameCount = 0
    private var didStabilizeForLiveAlignment = false

    init(
        camera: any CameraSessionControlling = CameraControllerFactory.makeDefault(),
        permissionManager: CameraPermissionManager = CameraPermissionManager(),
        pipeline: ScanPipelineActor = ScanPipelineActor()
    ) {
        self.camera = camera
        self.permissionManager = permissionManager
        self.pipeline = pipeline
        previewSource = camera.previewSource
        permissionStatus = permissionManager.authorizationStatus
    }

    var canCapture: Bool {
        modelsReady && cameraState == .ready && readiness == .ready && !isBusy
    }

    var canRunSyntheticWork: Bool {
        modelsReady && !isBusy
    }

    var showsPermissionInstructions: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }

    func start() {
        guard eventTask == nil else { return }
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
                self?.finish(with: error)
                return
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
        alignedLiveFrameCount = 0
        isLiveTongueSteady = false
        didStabilizeForLiveAlignment = false
        Task { [camera] in
            await camera.stop()
        }
    }

    func capture() {
        guard canCapture else { return }
        liveInferenceTask?.cancel()
        liveInferenceTask = nil
        isBusy = true
        result = nil
        Task { [camera] in
            await camera.capture()
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
        case let .state(state):
            update(state: state)
        case let .quality(observation):
            readiness = observation.readiness
            if !isBusy {
                statusText = observation.readiness.message
            }
        case let .interruption(reason):
            statusText = "Camera interrupted: \(reason)"
        case let .liveFrame(frame):
            processLiveFrame(frame)
        case let .captured(frame):
            statusText = "Processing capture locally"
            processingTask?.cancel()
            processingTask = Task { [weak self, pipeline] in
                do {
                    let summary = if self?.previewSource.isSimulated == true {
                        try await pipeline.runSyntheticDemo()
                    } else {
                        try await pipeline.processPhysicalCapture(frame)
                    }
                    guard !Task.isCancelled else { return }
                    self?.finish(with: summary)
                } catch {
                    self?.finish(with: error)
                }
            }
        case let .capabilities(capabilities):
            isTorchAvailable = capabilities.hasTorch
            isTorchEnabled = capabilities.hasTorch
        }
    }

    private func processLiveFrame(_ frame: AnalyzableFrame) {
        guard modelsReady, cameraState == .ready, !isBusy, liveInferenceTask == nil else { return }
        liveInferenceTask = Task { @MainActor [weak self, camera, pipeline] in
            defer { self?.liveInferenceTask = nil }
            do {
                let summary = try await pipeline.analyzeLiveFrame(frame)
                guard !Task.isCancelled else { return }
                self?.liveScanSummary = summary
                self?.liveScanErrorText = nil
                self?.alignedLiveFrameCount = summary.isTongueAligned ? (self?.alignedLiveFrameCount ?? 0) + 1 : 0
                self?.isLiveTongueSteady = (self?.alignedLiveFrameCount ?? 0) >= 2
                if self?.isLiveTongueSteady == true, self?.didStabilizeForLiveAlignment == false {
                    self?.didStabilizeForLiveAlignment = true
                    await camera.stabilizeForAlignedTongue()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.liveScanErrorText = "Live alignment temporarily unavailable"
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
        case .ready: statusText = "Ready"
        case .capturing: statusText = "Capturing"
        case .completed: statusText = "Capture complete"
        case .interrupted: statusText = "Camera interrupted"
        case let .failed(error):
            readiness = .unavailable
            statusText = error.displayMessage
            permissionManager.refresh()
            permissionStatus = permissionManager.authorizationStatus
            isTorchEnabled = false
            liveInferenceTask?.cancel()
            liveInferenceTask = nil
            isBusy = false
        }
    }

    private func finish(with summary: ScanResultSummary) {
        result = summary
        statusText = summary.title
        isBusy = false
    }

    private func finish(with error: Error) {
        result = nil
        statusText = "Unable to assess: \(error.localizedDescription)"
        isBusy = false
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
