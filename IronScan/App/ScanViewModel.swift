import Foundation

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var statusText = "Preparing camera"
    @Published private(set) var readiness: CaptureReadiness = .stabilizing
    @Published private(set) var result: ScanResultSummary?
    @Published private(set) var isBusy = false

    let previewSource: CameraPreviewSource

    private let camera: CameraSessionActor
    private let pipeline: ScanPipelineActor
    private var eventTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    init(
        camera: CameraSessionActor = CameraSessionActor(),
        pipeline: ScanPipelineActor = ScanPipelineActor()
    ) {
        self.camera = camera
        self.pipeline = pipeline
        previewSource = camera.previewSource
    }

    var canCapture: Bool {
        readiness == .ready && !isBusy
    }

    func start() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, camera] in
            let stream = await camera.eventStream()
            await camera.start()
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        processingTask?.cancel()
        processingTask = nil
        Task { [camera] in
            await camera.stop()
        }
    }

    func capture() {
        guard canCapture else { return }
        isBusy = true
        result = nil
        Task { [camera] in
            await camera.capture()
        }
    }

    func runSyntheticDemo() {
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
        case let .captured(frame):
            statusText = "Processing capture locally"
            processingTask?.cancel()
            processingTask = Task { [weak self, pipeline] in
                do {
                    let summary = try await pipeline.processPhysicalCapture(frame)
                    guard !Task.isCancelled else { return }
                    self?.finish(with: summary)
                } catch {
                    self?.finish(with: error)
                }
            }
        case .capabilities:
            break
        }
    }

    private func update(state: CameraState) {
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
