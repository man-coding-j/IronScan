import Foundation

actor LatestFrameProcessor<Frame: Sendable> {
    typealias Handler = @Sendable (Frame) async -> Void

    private let minimumInterval: Duration
    private let clock = ContinuousClock()
    private var latestFrame: Frame?
    private var isProcessing = false
    private var lastAnalysisInstant: ContinuousClock.Instant?
    private let handler: Handler

    init(maximumRate: Double, handler: @escaping Handler) {
        minimumInterval = .seconds(1 / max(maximumRate, 0.1))
        self.handler = handler
    }

    func submit(_ frame: Frame) async {
        latestFrame = frame
        guard !isProcessing else { return }
        isProcessing = true

        while let pendingFrame = latestFrame {
            latestFrame = nil
            if let lastAnalysisInstant {
                let nextInstant = lastAnalysisInstant.advanced(by: minimumInterval)
                if nextInstant > clock.now {
                    do {
                        try await clock.sleep(until: nextInstant)
                    } catch {
                        latestFrame = nil
                        isProcessing = false
                        return
                    }
                }
            }
            lastAnalysisInstant = clock.now
            await handler(pendingFrame)
        }

        isProcessing = false
    }
}
