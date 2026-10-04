import Foundation

enum LiveScanningState: Equatable, Sendable {
    case idle
    case aligning
    case scanning(progress: Double)
    case completed(report: TongueVisualAttributeReport)
    case failed(reason: String)

    var progress: Double {
        switch self {
        case .idle: 0
        case .aligning: 0.12
        case let .scanning(progress): min(max(progress, 0), 1)
        case .completed: 1
        case .failed: 0
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            "Align tongue inside the oval…"
        case .aligning:
            "Adjusting focus and lighting…"
        case let .scanning(progress) where progress < 0.67:
            "Analyzing mucosal color profile…"
        case .scanning:
            "Calculating visual indicators…"
        case .completed:
            "Visual report ready"
        case let .failed(reason):
            reason
        }
    }

    var isActivelyScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

struct LiveScanProgressTracker: Sendable {
    static let requiredEvaluations = 3

    private(set) var evaluationCount = 0

    mutating func register(report: TongueVisualAttributeReport) -> LiveScanningState {
        evaluationCount += 1
        let progress = min(Double(evaluationCount) / Double(Self.requiredEvaluations), 1)
        return evaluationCount >= Self.requiredEvaluations
            ? .completed(report: report)
            : .scanning(progress: progress)
    }

    mutating func reset() {
        evaluationCount = 0
    }
}
