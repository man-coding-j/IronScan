@preconcurrency import Vision
import CoreVideo
import Foundation

struct AutoCaptureConfiguration: Equatable, Sendable {
    let alignmentHoldSeconds: TimeInterval
    let countdownSeconds: TimeInterval
    let signalFreshnessSeconds: TimeInterval
    let motionThresholdG: Double
    let maximumFeatureDrift: Double

    init(
        alignmentHoldSeconds: TimeInterval = 1,
        countdownSeconds: TimeInterval = 3,
        signalFreshnessSeconds: TimeInterval = 1.25,
        motionThresholdG: Double = 0.10,
        maximumFeatureDrift: Double = 0.055
    ) {
        self.alignmentHoldSeconds = max(alignmentHoldSeconds, 0)
        self.countdownSeconds = max(countdownSeconds, 0.1)
        self.signalFreshnessSeconds = max(signalFreshnessSeconds, 0.1)
        self.motionThresholdG = max(motionThresholdG, 0)
        self.maximumFeatureDrift = max(maximumFeatureDrift, 0)
    }
}

enum AutoCapturePhase: Equatable, Sendable {
    case disabled
    case seeking
    case holding(progress: Double)
    case countdown(secondsRemaining: Int, progress: Double)
    case readyToCapture
    case reset(message: String)
}

struct AutoCaptureEvent: Equatable, Sendable {
    let phase: AutoCapturePhase
    let shouldCapture: Bool
}

struct AutoCaptureStateMachine: Sendable {
    let configuration: AutoCaptureConfiguration
    private(set) var phase: AutoCapturePhase = .seeking
    private var holdStartedAt: TimeInterval?
    private var countdownStartedAt: TimeInterval?
    private var captureFired = false
    private var hadProgress = false
    private var isEnabled = true

    init(configuration: AutoCaptureConfiguration = AutoCaptureConfiguration()) {
        self.configuration = configuration
    }

    mutating func setEnabled(_ enabled: Bool) -> AutoCaptureEvent {
        isEnabled = enabled
        resetProgress()
        phase = enabled ? .seeking : .disabled
        return AutoCaptureEvent(phase: phase, shouldCapture: false)
    }

    mutating func reset() -> AutoCaptureEvent {
        resetProgress()
        phase = isEnabled ? .seeking : .disabled
        return AutoCaptureEvent(phase: phase, shouldCapture: false)
    }

    mutating func update(
        isAligned: Bool,
        isStable: Bool,
        now: TimeInterval
    ) -> AutoCaptureEvent {
        guard isEnabled else {
            phase = .disabled
            return AutoCaptureEvent(phase: phase, shouldCapture: false)
        }
        guard isAligned, isStable else {
            let shouldShowReset = hadProgress
            resetProgress()
            phase = shouldShowReset ? .reset(message: "Hold steady...") : .seeking
            return AutoCaptureEvent(phase: phase, shouldCapture: false)
        }
        guard !captureFired else {
            phase = .readyToCapture
            return AutoCaptureEvent(phase: phase, shouldCapture: false)
        }

        hadProgress = true
        if holdStartedAt == nil {
            holdStartedAt = now
        }
        let holdElapsed = max(0, now - (holdStartedAt ?? now))
        guard holdElapsed >= configuration.alignmentHoldSeconds else {
            let denominator = max(configuration.alignmentHoldSeconds, 0.001)
            phase = .holding(progress: min(holdElapsed / denominator, 1))
            return AutoCaptureEvent(phase: phase, shouldCapture: false)
        }

        if countdownStartedAt == nil {
            countdownStartedAt = now
        }
        let countdownElapsed = max(0, now - (countdownStartedAt ?? now))
        guard countdownElapsed >= configuration.countdownSeconds else {
            let remaining = max(1, Int(ceil(configuration.countdownSeconds - countdownElapsed)))
            phase = .countdown(
                secondsRemaining: remaining,
                progress: min(countdownElapsed / configuration.countdownSeconds, 1)
            )
            return AutoCaptureEvent(phase: phase, shouldCapture: false)
        }

        captureFired = true
        phase = .readyToCapture
        return AutoCaptureEvent(phase: phase, shouldCapture: true)
    }

    private mutating func resetProgress() {
        holdStartedAt = nil
        countdownStartedAt = nil
        captureFired = false
        hadProgress = false
    }
}

struct TissueAlignmentObservation: Equatable, Sendable {
    let normalizedBounds: CGRect
}

protocol TissueAlignmentDetecting: Sendable {
    func observation(
        in pixelBuffer: CVPixelBuffer,
        tissue: TissueSite
    ) throws -> TissueAlignmentObservation?
}

struct VisionTissueAlignmentDetector: TissueAlignmentDetecting {
    func observation(
        in pixelBuffer: CVPixelBuffer,
        tissue: TissueSite
    ) throws -> TissueAlignmentObservation? {
        switch tissue {
        case .eye:
            try faceFeatureObservation(in: pixelBuffer, tissue: .eye)
        case .nail:
            try nailObservation(in: pixelBuffer)
        case .tongue:
            try faceFeatureObservation(in: pixelBuffer, tissue: .tongue)
        }
    }

    private func faceFeatureObservation(
        in pixelBuffer: CVPixelBuffer,
        tissue: TissueSite
    ) throws -> TissueAlignmentObservation? {
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        ).perform([request])
        guard let face = request.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }), let landmarks = face.landmarks else {
            return nil
        }

        let bounds: CGRect?
        switch tissue {
        case .eye:
            bounds = [landmarks.leftEye, landmarks.rightEye]
                .compactMap { region in
                    guard let region else { return nil }
                    return try? ConjunctivaRegionCalculator.lowerQuarter(
                        faceBoundingBox: face.boundingBox,
                        eyePoints: region.normalizedPoints
                    )
                }
                .min(by: { abs($0.midX - 0.5) < abs($1.midX - 0.5) })
        case .tongue:
            bounds = landmarks.outerLips.map {
                imageBounds(faceBoundingBox: face.boundingBox, points: $0.normalizedPoints)
            }
        case .nail:
            bounds = nil
        }
        guard let bounds, targetRect(for: tissue).contains(bounds.center) else {
            return nil
        }
        return TissueAlignmentObservation(normalizedBounds: bounds)
    }

    private func nailObservation(in pixelBuffer: CVPixelBuffer) throws -> TissueAlignmentObservation? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4
        request.minimumSize = 0.08
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1
        request.quadratureTolerance = 25
        try VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        ).perform([request])
        guard let rectangle = request.results?
            .filter({ targetRect(for: .nail).contains($0.boundingBox.center) })
            .max(by: {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }) else {
            return nil
        }
        return TissueAlignmentObservation(normalizedBounds: rectangle.boundingBox)
    }

    private func imageBounds(faceBoundingBox: CGRect, points: [CGPoint]) -> CGRect {
        let imagePoints = points.map {
            CGPoint(
                x: faceBoundingBox.minX + $0.x * faceBoundingBox.width,
                y: faceBoundingBox.minY + $0.y * faceBoundingBox.height
            )
        }
        guard let minimumX = imagePoints.map(\.x).min(),
              let maximumX = imagePoints.map(\.x).max(),
              let minimumY = imagePoints.map(\.y).min(),
              let maximumY = imagePoints.map(\.y).max() else {
            return .zero
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private func targetRect(for tissue: TissueSite) -> CGRect {
        switch tissue {
        case .eye:
            CGRect(x: 0.18, y: 0.20, width: 0.64, height: 0.62)
        case .nail:
            CGRect(x: 0.25, y: 0.31, width: 0.50, height: 0.42)
        case .tongue:
            CGRect(x: 0.27, y: 0.25, width: 0.46, height: 0.50)
        }
    }
}

actor AutoCaptureManager {
    private let configuration: AutoCaptureConfiguration
    private let detector: any TissueAlignmentDetecting
    private var stateMachine: AutoCaptureStateMachine
    private var continuation: AsyncStream<AutoCaptureEvent>.Continuation?
    private var tickerTask: Task<Void, Never>?
    private var currentTissue = TissueSite.eye
    private var lastBounds: CGRect?
    private var latestAligned = false
    private var latestStable = false
    private var lastSignalTime: TimeInterval?

    init(
        configuration: AutoCaptureConfiguration = AutoCaptureConfiguration(),
        detector: any TissueAlignmentDetecting = VisionTissueAlignmentDetector()
    ) {
        self.configuration = configuration
        self.detector = detector
        stateMachine = AutoCaptureStateMachine(configuration: configuration)
    }

    func eventStream() -> AsyncStream<AutoCaptureEvent> {
        let pair = AsyncStream<AutoCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation?.finish()
        continuation = pair.continuation
        pair.continuation.yield(AutoCaptureEvent(phase: stateMachine.phase, shouldCapture: false))
        startTickerIfNeeded()
        return pair.stream
    }

    func setEnabled(_ enabled: Bool) {
        publish(stateMachine.setEnabled(enabled))
    }

    func reset(for tissue: TissueSite) {
        currentTissue = tissue
        lastBounds = nil
        latestAligned = false
        latestStable = false
        lastSignalTime = nil
        publish(stateMachine.reset())
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        tissue: TissueSite,
        motion: MotionStabilityReading,
        acceptsSyntheticAlignment: Bool
    ) throws {
        guard tissue == currentTissue else {
            reset(for: tissue)
            return
        }
        let observation = if acceptsSyntheticAlignment {
            TissueAlignmentObservation(
                normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
            )
        } else {
            try detector.observation(in: pixelBuffer, tissue: tissue)
        }
        let featureIsSteady = observation.map(isFeatureSteady) ?? false
        lastBounds = observation?.normalizedBounds
        latestAligned = observation != nil && featureIsSteady
        latestStable = motion.status == .unavailable
            || (motion.status == .stable
                && motion.accelerationVariationG <= configuration.motionThresholdG)
        lastSignalTime = systemUptime
        publishCurrent(at: systemUptime)
    }

    func stop() {
        tickerTask?.cancel()
        tickerTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func startTickerIfNeeded() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                await self?.tick()
            }
        }
    }

    private func tick() {
        publishCurrent(at: systemUptime)
    }

    private func publishCurrent(at now: TimeInterval) {
        let signalIsFresh = lastSignalTime.map {
            now - $0 <= configuration.signalFreshnessSeconds
        } ?? false
        publish(stateMachine.update(
            isAligned: latestAligned && signalIsFresh,
            isStable: latestStable && signalIsFresh,
            now: now
        ))
    }

    private func publish(_ event: AutoCaptureEvent) {
        continuation?.yield(event)
    }

    private func isFeatureSteady(_ observation: TissueAlignmentObservation) -> Bool {
        guard let lastBounds else { return true }
        let deltaX = observation.normalizedBounds.midX - lastBounds.midX
        let deltaY = observation.normalizedBounds.midY - lastBounds.midY
        return hypot(deltaX, deltaY) <= configuration.maximumFeatureDrift
    }

    private var systemUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
