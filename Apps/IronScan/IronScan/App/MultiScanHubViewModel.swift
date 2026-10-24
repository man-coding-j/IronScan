import AVFoundation
import CoreImage
import Foundation
import CoreML
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum ScanValidationError: LocalizedError {
    case noFace(ScanStep)
    case noHand(ScanStep)
    case invalidImage
    case invalidModelOutput

    var step: ScanStep? {
        switch self {
        case let .noFace(step), let .noHand(step): step
        case .invalidImage, .invalidModelOutput: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .noFace:
            "Invalid Image: No face detected. Please ensure your face is in the frame."
        case .noHand:
            "Invalid Image: No hand detected. Please ensure your fingers are visible."
        case .invalidImage:
            "The captured image could not be prepared. Please retake it."
        case .invalidModelOutput:
            "The image model returned an invalid research score. Please try again."
        }
    }
}

private extension UIImage.Orientation {
    var visionOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

private actor VisionScanGatekeeper {
    func validateImage(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        for step: ScanStep
    ) throws -> Bool {
        try Task.checkCancellation()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        switch step {
        case .conjunctiva, .tongue:
            let request = VNDetectFaceRectanglesRequest()
            try handler.perform([request])
            guard let results = request.results, !results.isEmpty else {
                throw ScanValidationError.noFace(step)
            }
        case .fingernail:
            let request = VNDetectHumanHandPoseRequest()
            try handler.perform([request])
            guard let results = request.results, !results.isEmpty else {
                throw ScanValidationError.noHand(step)
            }
        }
        try Task.checkCancellation()
        return true
    }
}

private actor PallorInferenceActor {
    private var eyeModel: ConjunctivaPallor?
    private var nailModel: NailHemoglobin?
    private var tongueModel: TonguePallor?

    func predict(_ image: CGImage, for step: ScanStep) throws -> Double {
        try Task.checkCancellation()
        guard let buffer = try MLFeatureValue(
            cgImage: image,
            pixelsWide: 224,
            pixelsHigh: 224,
            pixelFormatType: kCVPixelFormatType_32ARGB,
            options: nil
        ).imageBufferValue else {
            throw ScanValidationError.invalidImage
        }
        let array: MLMultiArray
        switch step {
        case .conjunctiva:
            if eyeModel == nil { eyeModel = try ConjunctivaPallor() }
            array = try eyeModel!.prediction(image: buffer).pallor_score
        case .fingernail:
            if nailModel == nil { nailModel = try NailHemoglobin() }
            array = try nailModel!.prediction(input_1: buffer).Identity
        case .tongue:
            if tongueModel == nil { tongueModel = try TonguePallor() }
            array = try tongueModel!.prediction(image: buffer).tongue_score
        }
        guard array.count == 1 else { throw ScanValidationError.invalidModelOutput }
        let rawValue = array[0].doubleValue
        guard rawValue.isFinite else { throw ScanValidationError.invalidModelOutput }
        // NailHemoglobin exposes a raw logit. The eye and tongue model heads
        // already apply sigmoid, so their outputs are probabilities.
        let normalizedScore = step == .fingernail
            ? 1.0 / (1.0 + exp(-rawValue))
            : rawValue
        guard normalizedScore.isFinite, (0...1).contains(normalizedScore) else {
            throw ScanValidationError.invalidModelOutput
        }
        return normalizedScore
    }
}

/// Decoding and orientation normalization stay off the UI actor. The picker
/// supplies bytes in memory; no application photo files are created.
private actor ScanPhotoLoader {

    func load(_ items: [PhotosPickerItem]) async throws -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            try Task.checkCancellation()
            guard let data = try await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else {
                throw ScanValidationError.invalidImage
            }
            images.append(UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        }
        return images
    }
}

private enum SessionCapture {
    case camera(CapturedFrame)
    case imported(UIImage)
}

enum ScanStep: Int, CaseIterable, Identifiable, Sendable {
    case conjunctiva = 1
    case fingernail = 2
    case tongue = 3

    var id: Int { rawValue }

    var tissue: TissueSite {
        switch self {
        case .conjunctiva: .eye
        case .fingernail: .nail
        case .tongue: .tongue
        }
    }

    var progressTitle: String {
        switch self {
        case .conjunctiva: "Conjunctiva"
        case .fingernail: "Fingernail Bed"
        case .tongue: "Tongue"
        }
    }

    var guideTitle: String {
        switch self {
        case .conjunctiva: "Conjunctiva"
        case .fingernail: "Fingernail Bed"
        case .tongue: "Tongue"
        }
    }

    var guideInstruction: String {
        "Align \(guideTitle) within the guide"
    }

    var stepLabel: String {
        "Step \(rawValue) of \(Self.allCases.count)"
    }

    var referenceAssetName: String {
        switch self {
        case .conjunctiva: "ScanReferenceEye"
        case .fingernail: "ScanReferenceFingernail"
        case .tongue: "ScanReferenceInnerLip"
        }
    }

    var referenceAccessibilityLabel: String {
        switch self {
        case .conjunctiva: "Example of a gently pulled-down lower eyelid"
        case .fingernail: "Example of a bare fingernail"
        case .tongue: "Example of an exposed tongue"
        }
    }
}

@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var capturedImages: [ScanStep: UIImage] = [:]

    var isComplete: Bool {
        ScanStep.allCases.allSatisfy { capturedImages[$0] != nil }
    }

    func store(_ image: UIImage, for step: ScanStep) {
        capturedImages[step] = image
    }

    func reset() {
        capturedImages.removeAll(keepingCapacity: true)
    }
}

struct ScanAssessmentSummary: Equatable, Sendable {
    let estimatedHemoglobin: Double
    let pallorIndices: [ScanStep: Double]
    let warningText: String
    let usesDemoFallback: Bool

    static let demoFallback = ScanAssessmentSummary(
        estimatedHemoglobin: 9.8,
        pallorIndices: [
            .conjunctiva: 0.720000,
            .fingernail: 0.810000,
            .tongue: 0.700000,
        ],
        warningText: "Severe Anemia Risk",
        usesDemoFallback: true
    )
}

@MainActor
final class MultiScanHubViewModel: ObservableObject {
    let cameraManager: MedicalCameraManager
    private let historyManager: ScanHistoryManager
    @Published private(set) var currentStep: ScanStep = .conjunctiva
    @Published private(set) var completedOutputs: [TissueSite: TissueScreeningOutput] = [:]
    @Published private(set) var skippedTissues: Set<TissueSite> = []
    @Published private(set) var triangulationResult: TriangulationResult?
    @Published private(set) var statusText = "Preparing image models"
    @Published private(set) var isBusy = true
    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var permissionStatus: AVAuthorizationStatus
    @Published private(set) var lensPosition = CameraLensPosition.front
    @Published private(set) var captureOrientation = CaptureOrientation.portrait
    @Published private(set) var supportsCameraToggle = false
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchEnabled = false
    @Published private(set) var isSwitchingCamera = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isRunningAssessment = false
    @Published private(set) var assessmentImagesCleared = false
    @Published private(set) var isImportingPhotos = false
    @Published private(set) var importPulseID = 0
    @Published private(set) var errorToast: String?
    @Published private(set) var lastError: String?
    @Published private(set) var eyeGuidanceText: String?
    @Published private(set) var eyePredictiveUncertainty: Double?
    @Published private(set) var motionReading = MotionStabilityReading.unavailable
    @Published private(set) var autoCapturePhase = AutoCapturePhase.seeking
    @Published private(set) var isAutoCaptureEnabled = true
    @Published private(set) var imageQualityAssessment = ImageQualityAssessment.unavailable
    @Published private(set) var captureQualityAssessment: ImageQualityAssessment?
    @Published private(set) var latestTongueImage: CGImage?
    @Published private(set) var tissuePreviewImages: [TissueSite: UIImage] = [:]
    @Published private(set) var isCheckingFraming = false
    @Published private(set) var isSimulatorMode: Bool
    @Published private(set) var modelError: String?
    @Published private(set) var assessmentSummary: ScanAssessmentSummary?
    @Published private(set) var scanRecord: ScanRecord?
    @Published var showSummary = false
    @Published var validationAlert: String?
    /// Raw captures stay in memory until assessment finishes or the session
    /// resets. They are never written to the history store or cloud database.
    @Published private(set) var sessionImages: [ScanStep: UIImage] = [:]

    let previewSource: CameraPreviewSource

    private let camera: any CameraSessionControlling
    private let permissionManager: CameraPermissionManager
    private let inference: MultiTissueInferenceActor
    private let visionGatekeeper = VisionScanGatekeeper()
    private let pallorInference = PallorInferenceActor()
    private let motionMonitor: any MotionStabilityMonitoring
    private let autoCaptureManager: AutoCaptureManager
    private let coreMLInferenceManager = CoreMLInferenceManager()
    private let triangulation = TriangulationEngine()
    private let imageQualityAnalyzer = ImageQualityAnalyzer()
    private let haptics = ScanHapticsManager()
    private let liveInferenceMaximumRate: Double = 4
    private var readiness: MultiTissueReadiness?
    private var latestQuality = QualityObservation.unavailable
    private var capturedFrames: [TissueSite: SessionCapture] = [:]
    private let photoLoader = ScanPhotoLoader()
    private var importTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var liveEyeTask: Task<Void, Never>?
    private var motionTask: Task<Void, Never>?
    private var autoCaptureTask: Task<Void, Never>?
    private var analysisTimeoutTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var framingCheckTimeoutTask: Task<Void, Never>?
    private var lastLiveInferenceStartedAt: ContinuousClock.Instant?
    private var activeCaptureID: UUID?
    private var activeFramingCheckID: UUID?
    private var pendingCaptureImage: UIImage?

    var currentTissue: TissueSite { currentStep.tissue }

    init(
        historyManager: ScanHistoryManager = .shared,
        camera: (any CameraSessionControlling)? = nil,
        permissionManager: CameraPermissionManager = CameraPermissionManager(),
        inference: MultiTissueInferenceActor = MultiTissueInferenceActor(),
        motionMonitor: any MotionStabilityMonitoring = MotionStabilityMonitor(),
        autoCaptureManager: AutoCaptureManager = AutoCaptureManager()
    ) {
        self.historyManager = historyManager
        let manager = camera.map { MedicalCameraManager(camera: $0) } ?? .shared
        cameraManager = manager
        self.camera = manager.camera
        self.permissionManager = permissionManager
        self.inference = inference
        self.motionMonitor = motionMonitor
        self.autoCaptureManager = autoCaptureManager
        previewSource = manager.camera.previewSource
        isSimulatorMode = manager.camera.previewSource.isSimulated
        lensPosition = manager.isUsingFrontCamera ? .front : .back
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

    var isSessionComplete: Bool {
        ScanStep.allCases.allSatisfy { sessionImages[$0] != nil }
    }

    var canToggleCamera: Bool {
        supportsCameraToggle && cameraState == .ready && !isBusy && !isSwitchingCamera
    }

    func start() {
        guard eventTask == nil else { return }
        modelError = nil
        isBusy = true
        statusText = "Preparing camera"
        haptics.prepare()
        startAutoCaptureMonitoring()
        eventTask = Task { [weak self, camera, permissionManager] in
            await self?.historyManager.loadData()
            guard await permissionManager.requestIfNeeded() else {
                self?.permissionStatus = permissionManager.authorizationStatus
                self?.statusText = "Allow camera access in Settings"
                self?.isBusy = false
                return
            }
            self?.permissionStatus = permissionManager.authorizationStatus
            self?.startMotionMonitoring()
            // Do not initialize CoreML while entering the camera screen. Model
            // loading happens only after all three images have been captured.
            self?.readiness = Self.simulatorReadiness
            self?.isBusy = false
            self?.statusText = "Ready to capture the conjunctiva image"
            let stream = await camera.eventStream()
            guard !Task.isCancelled, let manager = self?.cameraManager else { return }
            // Consume events while startup stabilizes. Otherwise display frames
            // can evict the capabilities event from the bounded stream buffer,
            // leaving supportsCameraToggle false even on a two-camera device.
            async let startup: Void = {
                try? await camera.setOpticsProfile(.eye)
                guard !Task.isCancelled else { return }
                await manager.start()
            }()
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.handle(event)
            }
            _ = await startup
        }
    }

    func stop() {
        importTask?.cancel()
        importTask = nil
        isImportingPhotos = false
        isRunningAssessment = false
        purgeSessionImages()
        cameraManager.clear()
        pendingCaptureImage = nil
        eventTask?.cancel()
        eventTask = nil
        processingTask?.cancel()
        processingTask = nil
        analysisTimeoutTask?.cancel()
        analysisTimeoutTask = nil
        toastTask?.cancel()
        toastTask = nil
        framingCheckTimeoutTask?.cancel()
        framingCheckTimeoutTask = nil
        errorToast = nil
        activeCaptureID = nil
        activeFramingCheckID = nil
        isAnalyzing = false
        isCheckingFraming = false
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
        guard let image = cameraManager.currentFrame,
              let videoFrame = cameraManager.currentVideoFrame else {
            fail("Wait for the camera preview, then try again.")
            return
        }
        finishFramingCheck()
        let captureID = UUID()
        activeCaptureID = captureID
        pendingCaptureImage = image
        sessionImages[currentStep] = image
        isBusy = true
        isAnalyzing = true
        lastError = nil
        errorToast = nil
        toastTask?.cancel()
        toastTask = nil
        captureQualityAssessment = nil
        eyeGuidanceText = nil
        eyePredictiveUncertainty = nil
        statusText = "Capturing \(currentTissue.displayName.lowercased()) image"
        startAnalysisTimeout(for: captureID)
        Task { [weak self, camera, autoCaptureManager, videoFrame] in
            if overrideChecks {
                await autoCaptureManager.cancelCountdown(message: "Manual capture")
            } else {
                await autoCaptureManager.reset(for: self?.currentTissue ?? .eye)
            }
            let accepted = await camera.capture(from: videoFrame)
            guard !accepted else { return }
            self?.fail("The camera was not ready. Hold steady and capture again.", captureID: captureID)
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
        importTask?.cancel()
        importTask = nil
        isImportingPhotos = false
        isRunningAssessment = false
        purgeSessionImages()
        pendingCaptureImage = nil
        processingTask?.cancel()
        processingTask = nil
        liveEyeTask?.cancel()
        liveEyeTask = nil
        completedOutputs = [:]
        skippedTissues = []
        triangulationResult = nil
        assessmentSummary = nil
        scanRecord = nil
        showSummary = false
        validationAlert = nil
        currentStep = .conjunctiva
        sessionImages.removeAll(keepingCapacity: true)
        lastError = nil
        latestTongueImage = nil
        tissuePreviewImages = [:]
        isAnalyzing = false
        errorToast = nil
        analysisTimeoutTask?.cancel()
        analysisTimeoutTask = nil
        activeCaptureID = nil
        isSwitchingCamera = false
        eyeGuidanceText = nil
        eyePredictiveUncertainty = nil
        autoCapturePhase = isAutoCaptureEnabled ? .seeking : .disabled
        imageQualityAssessment = .unavailable
        captureQualityAssessment = nil
        capturedFrames = [:]
        finishFramingCheck()
        Task { [autoCaptureManager] in
            await autoCaptureManager.reset(for: .eye)
        }
        applyOpticsProfile(.eye, readyText: "Ready to capture the eye image")
    }

    func toggleCamera() {
        guard canToggleCamera else { return }
        cameraManager.clear()
        isSwitchingCamera = true
        eyeGuidanceText = nil
        statusText = "Switching camera"
        Task { [weak self, cameraManager, autoCaptureManager] in
            await autoCaptureManager.cancelCountdown(message: "Camera switch in progress")
            do {
                try await cameraManager.toggleCamera()
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
        guard isTorchAvailable, !isBusy, enabled != cameraManager.isFlashlightOn else { return }
        Task { [weak self, cameraManager] in
            do {
                try await cameraManager.toggleFlashlight()
                self?.isTorchEnabled = cameraManager.isFlashlightOn
            } catch {
                self?.lastError = "Lighting control is unavailable"
            }
        }
    }

    func toggleFlashlight() {
        setTorchEnabled(!cameraManager.isFlashlightOn)
    }

    func updateCaptureOrientation(_ orientation: CaptureOrientation) {
        guard captureOrientation != .portrait else { return }
        captureOrientation = .portrait
        Task { [camera] in await camera.updateCaptureOrientation(.portrait) }
    }

    func dismissCaptureQualityFeedback() {
        captureQualityAssessment = nil
        guard cameraState == .ready, !isBusy else { return }
        statusText = "Ready to capture the \(currentTissue.displayName.lowercased()) image"
    }

    func skipCurrentTissue() {
        guard triangulationResult == nil, !isBusy else { return }
        lastError = nil
        captureQualityAssessment = nil
        skippedTissues.insert(currentTissue)
        statusText = "Skipping \(currentTissue.displayName.lowercased()) capture"
        advance(after: currentTissue)
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case let .displayFrame(frame):
            if !isRunningAssessment, !isSwitchingCamera {
                Task { [weak self] in
                    guard let self, self.eventTask != nil,
                          !self.isRunningAssessment, !self.isSwitchingCamera else { return }
                    await self.cameraManager.display(frame)
                }
            }
        case let .state(state):
            cameraState = state
            if state == .ready, !isBusy, !isSwitchingCamera {
                statusText = modelError
                    ?? "Ready to capture the \(currentTissue.displayName.lowercased()) image"
            }
        case let .captured(frame):
            process(frame)
        case let .captureIssue(error):
            print("Video-frame capture was not processed: \(error)")
            awaitPrototypeFallback(captureID: activeCaptureID)
        case let .capabilities(capabilities):
            supportsCameraToggle = capabilities.supportsCameraToggle
            lensPosition = capabilities.lensPosition
            cameraManager.updateLensPosition(capabilities.lensPosition)
            isTorchAvailable = capabilities.hasTorch
            isTorchEnabled = cameraManager.isFlashlightOn
        case let .interruption(reason):
            cameraManager.clear()
            fail("Camera interrupted: \(reason)")
        case let .liveFrame(frame):
            if isSimulatorMode, !isRunningAssessment, !isSwitchingCamera {
                Task { [weak self] in
                    guard let self, self.eventTask != nil,
                          !self.isRunningAssessment, !self.isSwitchingCamera else { return }
                    await self.cameraManager.display(frame)
                }
            }
            processLiveFrame(frame)
        case let .quality(observation):
            latestQuality = observation
        }
    }

    private func processLiveFrame(_ frame: AnalyzableFrame) {
        imageQualityAssessment = imageQualityAnalyzer.previewAssessment(for: frame.pixelBuffer)
    }

    private func process(_ frame: CapturedFrame) {
        guard let captureID = activeCaptureID else { return }
        let step = currentStep
        let tissue = currentTissue
        guard let previewImage = pendingCaptureImage ?? frame.capturedImage ?? Self.makePreviewImage(from: frame.pixelBuffer) else {
            fail("The captured image could not be prepared. Please try again.", captureID: captureID)
            return
        }
        pendingCaptureImage = nil

        analysisTimeoutTask?.cancel()
        analysisTimeoutTask = nil
        statusText = "Checking \(step.progressTitle.lowercased()) image"
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.validateImage(previewImage, for: step)
                guard !Task.isCancelled, self.activeCaptureID == captureID else { return }
                self.capturedFrames[tissue] = .camera(frame)
                self.tissuePreviewImages[tissue] = previewImage
                self.sessionImages[step] = previewImage
                self.captureQualityAssessment = self.imageQualityAnalyzer.captureAssessment(for: frame.pixelBuffer)
                self.lastError = nil
                self.finishAnalysis(for: captureID)
                self.isBusy = false
                self.advance(after: tissue)
            } catch {
                guard !Task.isCancelled, self.activeCaptureID == captureID else { return }
                self.rejectImage(for: step, message: error.localizedDescription, captureID: captureID)
            }
        }
    }

    func validateImage(_ image: UIImage, for step: ScanStep) async throws -> Bool {
        guard let cgImage = image.cgImage else { throw ScanValidationError.invalidImage }
        return try await visionGatekeeper.validateImage(
            cgImage,
            orientation: image.imageOrientation.visionOrientation,
            for: step
        )
    }

    private func rejectImage(for step: ScanStep, message: String, captureID: UUID? = nil) {
        sessionImages[step] = nil
        capturedFrames[step.tissue] = nil
        tissuePreviewImages[step.tissue] = nil
        completedOutputs[step.tissue] = nil
        assessmentSummary = nil
        scanRecord = nil
        showSummary = false
        currentStep = step
        if let captureID { finishAnalysis(for: captureID) }
        isBusy = false
        isAnalyzing = false
        lastError = message
        statusText = message
        validationAlert = message
        resetAutoCapture(for: step.tissue)
        let profile: CameraOpticsProfile = switch step {
        case .conjunctiva: .eye
        case .fingernail: .nail
        case .tongue: .tongue
        }
        applyOpticsProfile(profile, readyText: "Retake the \(step.progressTitle.lowercased()) image")
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
        captureQualityAssessment = nil
        switch tissue {
        case .eye:
            liveEyeTask?.cancel()
            liveEyeTask = nil
            eyeGuidanceText = nil
            currentStep = .fingernail
            resetAutoCapture(for: .nail)
            applyOpticsProfile(
                .nail,
                readyText: "Eye step complete — capture the fingernail image"
            )
        case .nail:
            currentStep = .tongue
            resetAutoCapture(for: .tongue)
            applyOpticsProfile(
                .tongue,
                readyText: "Nail step complete — capture the tongue image"
            )
        case .tongue:
            statusText = "All three images captured — ready to assess"
            isBusy = false
            isAnalyzing = false
        }
    }

    /// Import is deliberately separate from assessment. A partial selection
    /// wraps from the active slot so every selected photo has a destination.
    func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !isBusy, !isImportingPhotos else { return }
        let startingStep = currentStep
        isImportingPhotos = true
        isBusy = true
        statusText = "Loading selected photos"
        importTask = Task { [weak self, photoLoader] in
            do {
                let images = try await photoLoader.load(Array(items.prefix(3)))
                try Task.checkCancellation()
                guard let self else { return }
                self.storeImportedImages(images, startingAt: startingStep)
                self.isImportingPhotos = false
                self.isBusy = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isImportingPhotos = false
                self.isBusy = false
                self.validationAlert = "The selected photos could not be loaded. Please try again."
            }
        }
    }

    func storeImportedImages(_ images: [UIImage], startingAt step: ScanStep) {
        guard !images.isEmpty, !isRunningAssessment else { return }
        let steps = ScanStep.allCases
        let start = images.count == 3 ? 0 : step.rawValue - 1
        for (offset, image) in images.prefix(3).enumerated() {
            let target = steps[(start + offset) % steps.count]
            sessionImages[target] = image
            capturedFrames[target.tissue] = .imported(image)
            tissuePreviewImages[target.tissue] = image
        }
        currentStep = isSessionComplete ? .tongue : steps[(start + min(images.count, 3)) % steps.count]
        validationAlert = nil
        lastError = nil
        statusText = isSessionComplete ? "All three images ready — tap Run Anemia Assessment" : "Photo imported — capture or import the next image"
        importPulseID += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Clears every session-owned reference, including thumbnail and pending
    /// capture aliases. ARC releases images; this does not promise RAM zeroing.
    private func purgeSessionImages() {
        sessionImages.removeAll()
        capturedFrames.removeAll()
        tissuePreviewImages.removeAll()
        latestTongueImage = nil
        pendingCaptureImage = nil
        cameraManager.clear()
    }

    func resetSession() {
        resetDemo()
    }

    /// Image locals live only in this helper and are released before the
    /// minimum-duration animation wait in runMLAssessment.
    private func extractAssessmentScores() async throws -> [ScanStep: Double] {
        defer {
            purgeSessionImages()
            assessmentImagesCleared = true
        }
        let images = sessionImages
        var scores: [ScanStep: Double] = [:]
        for step in ScanStep.allCases {
            try Task.checkCancellation()
            guard let image = images[step], let cgImage = image.cgImage else {
                throw ScanValidationError.invalidImage
            }
            _ = try await validateImage(image, for: step)
            scores[step] = try await pallorInference.predict(cgImage, for: step)
        }
        return scores
    }

    func runMLAssessment() {
        guard !isBusy, !isRunningAssessment, isSessionComplete,
              capturedFrames.count == ScanStep.allCases.count else { return }
        processingTask?.cancel()
        isBusy = true
        isAnalyzing = true
        isRunningAssessment = true
        assessmentImagesCleared = false
        lastError = nil
        statusText = "Running research assessment"
        processingTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .milliseconds(2150))
            defer { self.isRunningAssessment = false }
            do {
                let scores = try await self.extractAssessmentScores()
                try Task.checkCancellation()
                guard let eyeScore = scores[.conjunctiva],
                      let nailScore = scores[.fingernail],
                      let tongueScore = scores[.tongue] else {
                    throw ScanValidationError.invalidModelOutput
                }
                try await clock.sleep(until: deadline)
                try Task.checkCancellation()
                let estimatedHb = min(16.0, max(7.0, 15.5 - ((eyeScore + nailScore + tongueScore) * 2.2)))
                let riskLevel: ScanRiskLevel = if estimatedHb > 12.0 {
                    .normal
                } else if estimatedHb >= 11.0 {
                    .mild
                } else if estimatedHb >= 9.5 {
                    .moderate
                } else {
                    .severe
                }
                let newRecord = ScanRecord(
                    hemoglobinG_dL: estimatedHb,
                    riskLevel: riskLevel,
                    conjunctivaScore: eyeScore,
                    nailScore: nailScore,
                    tongueScore: tongueScore,
                    calibrationOffsetApplied: 0
                )
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.historyManager.addRecord(newRecord)
                    self.scanRecord = newRecord
                    self.showSummary = true
                    self.statusText = "Research assessment complete"
                    self.isAnalyzing = false
                    self.isBusy = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let validation = error as? ScanValidationError, let step = validation.step {
                        self.rejectImage(for: step, message: validation.localizedDescription)
                    } else {
                        self.lastError = error.localizedDescription
                        self.statusText = error.localizedDescription
                        self.validationAlert = error.localizedDescription
                        self.isBusy = false
                        self.isAnalyzing = false
                    }
                }
            }
        }
    }

    private func finishTriangulation() {
        guard !completedOutputs.isEmpty else {
            fail("Capture at least one tissue site before finishing the session.")
            return
        }
        guard let readiness else {
            fail("Model versions are unavailable")
            return
        }
        do {
            let demographicProfile = DemographicProfileStore.load()
            let calibration = demographicProfile.calibration

            let configuration = try TriangulationConfiguration(
                identifier: "org.ironscan.prototype-demo.triangulation",
                semanticVersion: "0.2.0-engineering.1",
                mode: .prototypeDemo,
                decisionThreshold: calibration.decisionThreshold,
                calibrationCategory: calibration.category,
                modelVersions: readiness.modelVersions,
                preprocessingVersions: readiness.preprocessingVersions
            )
            triangulationResult = triangulation.evaluate(
                outputs: completedOutputs,
                configuration: configuration,
                allowEngineeringFixtures: PrototypeDemoMode.isEnabled,
                biologicalSexRawValue: demographicProfile.biologicalSex.rawValue,
                recentLabHemoglobin: demographicProfile.recentLabHemoglobin,
                demographicProfile: demographicProfile
            )
            guard let result = triangulationResult,
                  let estimatedHemoglobin = result.estimatedHemoglobin else {
                presentDemoAssessmentFallback()
                return
            }
            assessmentSummary = ScanAssessmentSummary(
                estimatedHemoglobin: estimatedHemoglobin,
                pallorIndices: Dictionary(uniqueKeysWithValues: ScanStep.allCases.map { step in
                    (step, completedOutputs[step.tissue]?.probability ?? 0)
                }),
                warningText: result.severity == .severe ? "Severe Anemia Risk" : "Research Pallor Assessment",
                usesDemoFallback: false
            )
            let riskLevel: ScanRiskLevel = switch result.severity {
            case .normal: .normal
            case .mild: .mild
            case .moderate: .moderate
            case .severe: .severe
            }
            historyManager.addRecord(ScanRecord(
                hemoglobinG_dL: estimatedHemoglobin,
                riskLevel: riskLevel,
                conjunctivaScore: completedOutputs[.eye]?.probability ?? 0,
                nailScore: completedOutputs[.nail]?.probability ?? 0,
                tongueScore: completedOutputs[.tongue]?.probability ?? 0,
                calibrationOffsetApplied: 0
            ))
            statusText = "Multi-site scan complete"
            isAnalyzing = false
            isBusy = false
        } catch {
            print("Triangulation failed; presenting demo fallback: \(error)")
            presentDemoAssessmentFallback()
        }
    }

    private func presentDemoAssessmentFallback() {
        assessmentSummary = .demoFallback
        statusText = "Demo assessment ready"
        isAnalyzing = false
        isBusy = false
        showErrorToast("Demo fallback shown — not a participant result.")
    }

    private func fail(_ message: String, captureID: UUID? = nil) {
        if let captureID, activeCaptureID != captureID { return }
        if pendingCaptureImage != nil { sessionImages[currentStep] = nil }
        pendingCaptureImage = nil
        finishFramingCheck()
        captureQualityAssessment = nil
        lastError = message
        statusText = message
        isBusy = false
        if let captureID {
            finishAnalysis(for: captureID)
        } else {
            isAnalyzing = false
            activeCaptureID = nil
            analysisTimeoutTask?.cancel()
            analysisTimeoutTask = nil
        }
        resetAutoCapture(for: currentTissue)
    }

    private func awaitPrototypeFallback(captureID: UUID?) {
        guard let captureID, activeCaptureID == captureID else { return }
        sessionImages[currentStep] = nil
        pendingCaptureImage = nil
        finishAnalysis(for: captureID)
        isBusy = false
        statusText = "Capture failed — please try again"
        showErrorToast("Could not capture image. Please try again.")
    }

    private func beginFramingCheck() {
        let checkID = UUID()
        activeFramingCheckID = checkID
        isCheckingFraming = true
        framingCheckTimeoutTask?.cancel()
        framingCheckTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  self?.activeFramingCheckID == checkID else { return }
            self?.isCheckingFraming = false
            self?.activeFramingCheckID = nil
            self?.framingCheckTimeoutTask = nil
            if self?.isBusy == false {
                self?.statusText = "Automatic framing is taking longer. You can capture manually."
            }
        }
    }

    private func finishFramingCheck() {
        framingCheckTimeoutTask?.cancel()
        framingCheckTimeoutTask = nil
        activeFramingCheckID = nil
        isCheckingFraming = false
    }

    private func startAnalysisTimeout(for captureID: UUID) {
        analysisTimeoutTask?.cancel()
        analysisTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled, self?.activeCaptureID == captureID else { return }
            self?.processingTask?.cancel()
            self?.processingTask = nil
            self?.completeWithPrototypeFallback(captureID: captureID)
        }
    }

    private func completeWithPrototypeFallback(captureID: UUID) {
        guard activeCaptureID == captureID else { return }
        sessionImages[currentStep] = nil
        pendingCaptureImage = nil
        finishFramingCheck()
        finishAnalysis(for: captureID)
        statusText = "Capture timed out — please try again"
        isBusy = false
        showErrorToast("Camera capture timed out. Please try again.")
    }

    private func finishAnalysis(for captureID: UUID) {
        guard activeCaptureID == captureID else { return }
        analysisTimeoutTask?.cancel()
        analysisTimeoutTask = nil
        activeCaptureID = nil
        isAnalyzing = false
    }

    private func showErrorToast(_ message: String) {
        toastTask?.cancel()
        errorToast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.errorToast = nil
        }
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
        cameraManager.clear()
        isBusy = true
        statusText = "Adjusting camera optics"
        Task { [weak self, camera] in
            do {
                try await camera.setOpticsProfile(profile)
                self?.isTorchEnabled = self?.cameraManager.isFlashlightOn == true
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

    private static func makePreviewImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static let simulatorReadiness = MultiTissueReadiness(
        modelVersions: Dictionary(uniqueKeysWithValues: TissueSite.allCases.map { ($0, "simulator-fallback") }),
        preprocessingVersions: Dictionary(uniqueKeysWithValues: TissueSite.allCases.map { ($0, "simulator-fallback") })
    )
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
