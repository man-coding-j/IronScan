import AVFoundation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class MultiScanHubViewModel: ObservableObject {
    @Published private(set) var currentTissue: TissueSite = .eye
    @Published private(set) var completedOutputs: [TissueSite: TissueScreeningOutput] = [:]
    @Published private(set) var triangulationResult: TriangulationResult?
    @Published private(set) var statusText = "Preparing image models"
    @Published private(set) var isBusy = true
    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var permissionStatus: AVAuthorizationStatus
    @Published private(set) var lensPosition = CameraLensPosition.back
    @Published private(set) var captureOrientation = CaptureOrientation.portrait
    @Published private(set) var supportsCameraToggle = false
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var isSwitchingCamera = false
    @Published private(set) var isAnalyzingTongueCapture = false
    @Published private(set) var lastError: String?
    @Published private(set) var eyeGuidanceText: String?
    @Published private(set) var eyePredictiveUncertainty: Double?
    @Published private(set) var motionReading = MotionStabilityReading.unavailable
    @Published private(set) var autoCapturePhase = AutoCapturePhase.seeking
    @Published private(set) var isAutoCaptureEnabled = true
    @Published private(set) var imageQualityAssessment = ImageQualityGatekeeper.Assessment.optimal
    @Published private(set) var latestTongueImage: CGImage?

    let previewSource: CameraPreviewSource

    private let camera: any CameraSessionControlling
    private let permissionManager: CameraPermissionManager
    private let inference: MultiTissueInferenceActor
    private let motionMonitor: any MotionStabilityMonitoring
    private let autoCaptureManager: AutoCaptureManager
    private let coreMLInferenceManager = CoreMLInferenceManager()
    private let triangulation = TriangulationEngine()
    private let haptics = ScanHapticsManager()
    private let liveInferenceMaximumRate: Double = 4
    private var readiness: MultiTissueReadiness?
    private var latestQuality = QualityObservation.unavailable
    private var capturedFrames: [TissueSite: CapturedFrame] = [:]
    private var eventTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var liveEyeTask: Task<Void, Never>?
    private var motionTask: Task<Void, Never>?
    private var autoCaptureTask: Task<Void, Never>?
    private var lastLiveInferenceStartedAt: ContinuousClock.Instant?

    init(
        camera: any CameraSessionControlling = CameraControllerFactory.makeDefault(),
        permissionManager: CameraPermissionManager = CameraPermissionManager(),
        inference: MultiTissueInferenceActor = MultiTissueInferenceActor(),
        motionMonitor: any MotionStabilityMonitoring = MotionStabilityMonitor(),
        autoCaptureManager: AutoCaptureManager = AutoCaptureManager()
    ) {
        self.camera = camera
        self.permissionManager = permissionManager
        self.inference = inference
        self.motionMonitor = motionMonitor
        self.autoCaptureManager = autoCaptureManager
        previewSource = camera.previewSource
        permissionStatus = permissionManager.authorizationStatus
    }

    var canCapture: Bool {
        readiness != nil
            && cameraState == .ready
            && !isBusy
            && triangulationResult == nil
            && motionReading.allowsInference
    }

    var showsMotionWarning: Bool {
        motionReading.status == .unstable
    }

    var showsPermissionInstructions: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }

    func start() {
        guard eventTask == nil else { return }
        isBusy = true
        statusText = "Validating eye, nail, and tongue models"
        haptics.prepare()
        startAutoCaptureMonitoring()
        eventTask = Task { [weak self, camera, permissionManager, inference] in
            guard await permissionManager.requestIfNeeded() else {
                self?.permissionStatus = permissionManager.authorizationStatus
                self?.statusText = "Allow camera access in Settings"
                self?.isBusy = false
                return
            }
            self?.permissionStatus = permissionManager.authorizationStatus
            self?.startMotionMonitoring()
            do {
                self?.readiness = try await inference.preloadModels()
                self?.isBusy = false
                self?.statusText = "Ready to capture the eye image"
            } catch {
                self?.fail("Image models could not be loaded: \(error.localizedDescription)")
                return
            }
            let stream = await camera.eventStream()
            try? await camera.setOpticsProfile(.eye)
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
        liveEyeTask?.cancel()
        liveEyeTask = nil
        motionTask?.cancel()
        motionTask = nil
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
        Task { [camera] in await camera.stop() }
        Task { [motionMonitor] in await motionMonitor.stop() }
        Task { [autoCaptureManager] in await autoCaptureManager.stop() }
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

    func captureCurrentTissue() {
        guard motionReading.allowsInference else {
            statusText = "Hold phone steady..."
            return
        }
        guard canCapture else { return }
        performCapture(overrideChecks: false)
    }

    func forceManualCapture() {
        guard readiness != nil,
              cameraState == .ready,
              !isBusy,
              triangulationResult == nil else { return }
        performCapture(overrideChecks: true)
    }

    private func performCapture(overrideChecks: Bool) {
        isBusy = true
        lastError = nil
        eyeGuidanceText = nil
        eyePredictiveUncertainty = nil
        statusText = "Capturing \(currentTissue.displayName.lowercased()) image"
        Task { [weak self, camera, autoCaptureManager] in
            if overrideChecks {
                await autoCaptureManager.cancelCountdown(message: "Manual capture")
            } else {
                await autoCaptureManager.reset(for: self?.currentTissue ?? .eye)
            }
            let accepted = await camera.capture()
            guard !accepted else { return }
            self?.fail("The camera was not ready. Hold steady and capture again.")
        }
    }

    func setAutoCaptureEnabled(_ enabled: Bool) {
        isAutoCaptureEnabled = enabled
        autoCapturePhase = enabled ? .seeking : .disabled
        Task { [autoCaptureManager] in
            await autoCaptureManager.setEnabled(enabled)
        }
    }

    func resetDemo() {
        processingTask?.cancel()
        processingTask = nil
        liveEyeTask?.cancel()
        liveEyeTask = nil
        completedOutputs = [:]
        triangulationResult = nil
        currentTissue = .eye
        lastError = nil
        latestTongueImage = nil
        isAnalyzingTongueCapture = false
        isSwitchingCamera = false
        eyeGuidanceText = nil
        eyePredictiveUncertainty = nil
        autoCapturePhase = isAutoCaptureEnabled ? .seeking : .disabled
        imageQualityAssessment = .optimal
        capturedFrames = [:]
        Task { [autoCaptureManager] in
            await autoCaptureManager.reset(for: .eye)
        }
        applyOpticsProfile(.eye, readyText: "Ready to capture the eye image")
    }

    func toggleCamera() {
        guard supportsCameraToggle, !isBusy, !isSwitchingCamera else { return }
        isSwitchingCamera = true
        eyeGuidanceText = nil
        statusText = "Switching camera"
        Task { [weak self, camera, autoCaptureManager] in
            await autoCaptureManager.cancelCountdown(message: "Camera switch in progress")
            do {
                try await camera.toggleCamera()
                guard let self else { return }
                self.isSwitchingCamera = false
                self.statusText = "Ready to capture the \(self.currentTissue.displayName.lowercased()) image"
                self.resetAutoCapture(for: self.currentTissue)
            } catch {
                self?.isSwitchingCamera = false
                self?.fail("Camera switch is unavailable")
            }
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
                self?.lastError = "Lighting control is unavailable"
            }
        }
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) {
        captureOrientation = orientation
        Task { [camera] in await camera.updateCaptureOrientation(orientation) }
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case let .state(state):
            cameraState = state
            if state == .ready, !isBusy, !isSwitchingCamera {
                statusText = "Ready to capture the \(currentTissue.displayName.lowercased()) image"
            }
        case let .captured(frame):
            process(frame)
        case let .captureIssue(error):
            fail("Capture was not processed: \(error.localizedDescription)")
        case let .capabilities(capabilities):
            supportsCameraToggle = capabilities.supportsCameraToggle
            lensPosition = capabilities.lensPosition
            isTorchAvailable = capabilities.hasTorch
            isTorchEnabled = capabilities.hasTorch && currentTissue == .nail
        case let .interruption(reason):
            fail("Camera interrupted: \(reason)")
        case let .liveFrame(frame):
            processLiveFrame(frame)
        case let .quality(observation):
            latestQuality = observation
        }
    }

    private func processLiveFrame(_ frame: AnalyzableFrame) {
        imageQualityAssessment = ImageQualityGatekeeper.assess(frame.pixelBuffer)
        guard motionReading.allowsInference,
              cameraState == .ready,
              !isBusy,
              !isSwitchingCamera,
              liveEyeTask == nil,
              shouldStartLiveInference() else {
            return
        }
        let tissue = currentTissue
        let motion = motionReading
        let isAutoCaptureEnabled = isAutoCaptureEnabled
        let usesSyntheticAlignment = previewSource.isSimulated && latestQuality.readiness == .ready
        liveEyeTask = Task { [weak self, inference, autoCaptureManager] in
            defer {
                Task { @MainActor [weak self] in
                    self?.liveEyeTask = nil
                }
            }
            if isAutoCaptureEnabled {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try await autoCaptureManager.analyze(
                            pixelBuffer: frame.pixelBuffer,
                            tissue: tissue,
                            motion: motion,
                            acceptsSyntheticAlignment: usesSyntheticAlignment
                        )
                    }.value
                } catch {
                    await MainActor.run {
                        self?.statusText = "Automatic alignment is unavailable. Use manual capture."
                    }
                    await autoCaptureManager.reset(for: tissue)
                }
            }
            guard tissue == .eye, !usesSyntheticAlignment else { return }
            do {
                let assessment = try await Task.detached(priority: .userInitiated) {
                    try await inference.assessEyePreview(pixelBuffer: frame.pixelBuffer)
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.eyePredictiveUncertainty = assessment.predictiveUncertainty
                    self?.eyeGuidanceText = assessment.uncertaintyAccepted
                        ? "Conjunctiva located — hold still"
                        : "High image uncertainty: move to better lighting and lower your eyelid to expose the conjunctiva."
                }
            } catch let error as ConjunctivaCropError {
                await MainActor.run {
                    self?.eyePredictiveUncertainty = nil
                    self?.eyeGuidanceText = switch error {
                    case .faceNotDetected:
                        "Center your face and eye inside the guide."
                    case .eyeLandmarksNotDetected, .regionTooSmall:
                        "Lower your eyelid so the conjunctiva is clearly visible."
                    }
                }
            } catch {
                await MainActor.run {
                    self?.eyePredictiveUncertainty = nil
                    self?.eyeGuidanceText = "Hold still while the eye region is checked."
                }
            }
        }
    }

    private func process(_ frame: CapturedFrame) {
        guard motionReading.allowsInference else {
            fail("Hold phone steady...")
            return
        }
        isBusy = true
        lastError = nil
        let tissue = currentTissue
        let lensPosition = lensPosition
        let captureOrientation = captureOrientation
        processingTask?.cancel()
        processingTask = Task { [weak self, inference, coreMLInferenceManager] in
            do {
                let preparedFrame: CapturedFrame
                if tissue == .tongue {
                    await MainActor.run {
                        self?.isAnalyzingTongueCapture = true
                    }
                    let payload = try await Task.detached(priority: .userInitiated) {
                        try coreMLInferenceManager.prepareCapturedFrame(
                            frame,
                            tissue: tissue,
                            lensPosition: lensPosition,
                            captureOrientation: captureOrientation
                        )
                    }.value
                    guard let previewImage = payload.previewImage else {
                        await MainActor.run {
                            self?.fail("Scan incomplete. Please retake the tongue photo.")
                        }
                        return
                    }
                    await MainActor.run {
                        self?.latestTongueImage = previewImage
                    }
                    preparedFrame = payload.frame
                } else {
                    preparedFrame = frame
                }

                let output = try await Task.detached(priority: .userInitiated) {
                    try await inference.predict(frame: preparedFrame, tissue: tissue)
                }.value
                guard !Task.isCancelled else { return }
                guard output.qualityAccepted else {
                    await MainActor.run {
                        self?.fail(output.rejectionReasons.first ?? "Capture quality was not accepted")
                    }
                    return
                }
                await MainActor.run {
                    self?.completedOutputs[tissue] = output
                    self?.capturedFrames[tissue] = preparedFrame
                    self?.advance(after: tissue)
                }
            } catch let error as ConjunctivaCropError {
                await MainActor.run {
                    self?.fail(self?.conjunctivaMessage(for: error) ?? "Unable to locate the conjunctiva")
                }
            } catch {
                await MainActor.run {
                    self?.fail("Unable to process the \(tissue.displayName.lowercased()) image: \(error.localizedDescription)")
                }
            }
        }
    }

    private func shouldStartLiveInference() -> Bool {
        let now = ContinuousClock.now
        let minimumInterval = Duration.seconds(1 / max(liveInferenceMaximumRate, 0.1))
        if let lastLiveInferenceStartedAt,
           lastLiveInferenceStartedAt.duration(to: now) < minimumInterval {
            return false
        }
        lastLiveInferenceStartedAt = now
        return true
    }

    private func advance(after tissue: TissueSite) {
        switch tissue {
        case .eye:
            liveEyeTask?.cancel()
            liveEyeTask = nil
            eyeGuidanceText = nil
            currentTissue = .nail
            resetAutoCapture(for: .nail)
            applyOpticsProfile(
                .nail,
                readyText: "Eye step complete — capture the fingernail image"
            )
        case .nail:
            currentTissue = .tongue
            resetAutoCapture(for: .tongue)
            applyOpticsProfile(
                .tongue,
                readyText: "Nail step complete — capture the tongue image"
            )
        case .tongue:
            finishTriangulation()
        }
    }

    private func finishTriangulation() {
        let hasAllFrames = TissueSite.allCases.allSatisfy { capturedFrames[$0] != nil }
        guard hasAllFrames, latestTongueImage != nil, completedOutputs[.tongue] != nil else {
            fail("Scan incomplete. Please retake the tongue photo.")
            return
        }
        guard let readiness else {
            fail("Model versions are unavailable")
            return
        }
        do {
            let demographicCalibration = DemographicProfileStore.calibration()
            let configuration = try TriangulationConfiguration(
                identifier: "org.ironscan.prototype-demo.triangulation",
                semanticVersion: "0.2.0-engineering.1",
                mode: .prototypeDemo,
                decisionThreshold: demographicCalibration.decisionThreshold,
                calibrationCategory: demographicCalibration.category,
                modelVersions: readiness.modelVersions,
                preprocessingVersions: readiness.preprocessingVersions
            )
            triangulationResult = triangulation.evaluate(
                outputs: completedOutputs,
                configuration: configuration,
                allowEngineeringFixtures: PrototypeDemoMode.isEnabled
            )
            statusText = "Three-step scan complete"
            isAnalyzingTongueCapture = false
            isBusy = false
        } catch {
            fail("Scan configuration is invalid")
        }
    }

    private func fail(_ message: String) {
        lastError = message
        statusText = message
        isBusy = false
        isAnalyzingTongueCapture = false
        resetAutoCapture(for: currentTissue)
    }

    private func startMotionMonitoring() {
        guard motionTask == nil else { return }
        motionTask = Task { [weak self, motionMonitor] in
            let stream = await motionMonitor.eventStream()
            await motionMonitor.start()
            for await reading in stream {
                guard !Task.isCancelled else { return }
                self?.motionReading = reading
                if reading.status == .unstable {
                    self?.liveEyeTask?.cancel()
                    self?.liveEyeTask = nil
                    if self?.isBusy == false {
                        self?.statusText = "Hold phone steady..."
                    }
                } else if self?.cameraState == .ready, self?.isBusy == false,
                          self?.isSwitchingCamera == false,
                          let tissue = self?.currentTissue {
                    self?.statusText = "Ready to capture the \(tissue.displayName.lowercased()) image"
                }
            }
        }
    }

    private func startAutoCaptureMonitoring() {
        guard autoCaptureTask == nil else { return }
        autoCaptureTask = Task { [weak self, autoCaptureManager] in
            let stream = await autoCaptureManager.eventStream()
            await autoCaptureManager.setEnabled(self?.isAutoCaptureEnabled == true)
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.handleAutoCapture(event)
            }
        }
    }

    private func handleAutoCapture(_ event: AutoCaptureEvent) {
        let previousPhase = autoCapturePhase
        autoCapturePhase = event.phase
        switch event.phase {
        case .disabled, .seeking:
            break
        case .holding:
            if case .seeking = previousPhase {
                haptics.alignmentDetected()
            }
            statusText = "Alignment detected — hold steady"
        case let .countdown(_, progress):
            statusText = "Auto-capture ready"
            haptics.scanProgress(progress)
        case .readyToCapture:
            break
        case let .reset(message):
            statusText = message
        }
        guard event.shouldCapture, isAutoCaptureEnabled, canCapture else { return }
        haptics.completed()
        captureCurrentTissue()
    }

    private func resetAutoCapture(for tissue: TissueSite) {
        autoCapturePhase = isAutoCaptureEnabled ? .seeking : .disabled
        Task { [autoCaptureManager] in
            await autoCaptureManager.reset(for: tissue)
        }
    }

    private func applyOpticsProfile(
        _ profile: CameraOpticsProfile,
        readyText: String
    ) {
        isBusy = true
        statusText = "Adjusting camera optics"
        Task { [weak self, camera] in
            do {
                try await camera.setOpticsProfile(profile)
                self?.isTorchEnabled = profile.automaticTorchLevel != nil
                    && self?.isTorchAvailable == true
                self?.statusText = readyText
                self?.isBusy = false
                self?.resetAutoCapture(for: profile.tissueSite)
            } catch {
                self?.fail("Camera optics could not be adjusted")
            }
        }
    }

    private func conjunctivaMessage(for error: ConjunctivaCropError) -> String {
        switch error {
        case .faceNotDetected:
            "Unable to locate a face. Center your face and eye inside the guide."
        case .eyeLandmarksNotDetected:
            "Unable to locate the eyelid. Look upward and gently lower one eyelid."
        case .regionTooSmall:
            "The conjunctiva region is too small. Move closer while keeping the eye in focus."
        }
    }
}

private extension CameraOpticsProfile {
    var tissueSite: TissueSite {
        switch self {
        case .eye: .eye
        case .nail: .nail
        case .tongue: .tongue
        }
    }
}
