import UIKit

@MainActor
final class ScanHapticsManager {
    private let alignmentGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let scanGenerator = UIImpactFeedbackGenerator(style: .light)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private var lastProgressStage = 0

    func prepare() {
        alignmentGenerator.prepare()
        scanGenerator.prepare()
        notificationGenerator.prepare()
    }

    func alignmentDetected() {
        alignmentGenerator.impactOccurred(intensity: 0.55)
        scanGenerator.prepare()
    }

    func scanProgress(_ progress: Double) {
        let stage = min(max(Int(ceil(progress * 3)), 1), 3)
        guard stage > lastProgressStage else { return }
        lastProgressStage = stage
        scanGenerator.impactOccurred(intensity: stage == 3 ? 0.7 : 0.42)
        scanGenerator.prepare()
    }

    func completed() {
        notificationGenerator.notificationOccurred(.success)
        reset()
    }

    func failed() {
        notificationGenerator.notificationOccurred(.warning)
        reset()
    }

    func reset() {
        lastProgressStage = 0
        prepare()
    }
}
