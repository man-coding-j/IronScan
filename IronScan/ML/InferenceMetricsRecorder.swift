import Foundation

enum InferenceMetricStage: String, Codable, Sendable {
    case modelLoading
    case preprocessing
    case segmentation
    case calibration
    case riskInference
    case totalPipeline
}

struct InferenceMetricSample: Codable, Equatable, Sendable {
    let stage: InferenceMetricStage
    let durationMs: Double
    let modelIdentifier: String?
    let computeUnits: InferenceComputeUnits?
}

struct InferenceMetricsSnapshot: Codable, Equatable, Sendable {
    let samples: [InferenceMetricSample]
    let activeTemporaryBufferCount: Int
    let peakTemporaryBufferCount: Int

    func percentile95(for stage: InferenceMetricStage) -> Double? {
        let values = samples.filter { $0.stage == stage }.map(\.durationMs).sorted()
        guard !values.isEmpty else { return nil }
        let index = Int(ceil(Double(values.count) * 0.95)) - 1
        return values[max(0, min(index, values.count - 1))]
    }
}

actor InferenceMetricsRecorder {
    private var samples = [InferenceMetricSample]()
    private var activeTemporaryBufferCount = 0
    private var peakTemporaryBufferCount = 0

    func record(
        stage: InferenceMetricStage,
        durationMs: Double,
        modelIdentifier: String? = nil,
        computeUnits: InferenceComputeUnits? = nil
    ) {
        samples.append(InferenceMetricSample(
            stage: stage,
            durationMs: durationMs,
            modelIdentifier: modelIdentifier,
            computeUnits: computeUnits
        ))
    }

    func temporaryBufferAllocated() {
        activeTemporaryBufferCount += 1
        peakTemporaryBufferCount = max(peakTemporaryBufferCount, activeTemporaryBufferCount)
    }

    func temporaryBufferReleased() {
        activeTemporaryBufferCount = max(0, activeTemporaryBufferCount - 1)
    }

    func snapshot() -> InferenceMetricsSnapshot {
        InferenceMetricsSnapshot(
            samples: samples,
            activeTemporaryBufferCount: activeTemporaryBufferCount,
            peakTemporaryBufferCount: peakTemporaryBufferCount
        )
    }
}
