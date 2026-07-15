import XCTest
@testable import IronScan

@MainActor
final class InferenceConcurrencyTests: XCTestCase {
    func testRejectedCalibrationDoesNotLoadOrRunRiskModel() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let actor = RiskInferenceActor(registry: registry, metrics: metrics)

        do {
            _ = try await actor.predict(MLTestSupport.riskSample(status: .rejected))
            XCTFail("Rejected calibration must not produce a prediction")
        } catch let error as InferenceError {
            XCTAssertEqual(error, .rejectedCalibration)
        }
        let loadCount = await registry.riskLoadCount
        XCTAssertEqual(loadCount, 0)
    }

    func testCancellationBeforeInferenceBegins() async throws {
        let metrics = InferenceMetricsRecorder()
        let actor = RiskInferenceActor(
            registry: try MLTestSupport.registry(metrics: metrics),
            metrics: metrics
        )
        let sample = try MLTestSupport.riskSample()
        let task = Task { try await actor.predict(sample) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled request must not produce a prediction")
        } catch let error as InferenceError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testConcurrentCallsAreSerializedAndDeterministic() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let actor = RiskInferenceActor(registry: registry, metrics: metrics)
        let sample = try MLTestSupport.riskSample()

        let results = try await withThrowingTaskGroup(of: RiskPrediction.self) { group in
            for _ in 0..<12 {
                group.addTask { try await actor.predict(sample) }
            }
            var predictions = [RiskPrediction]()
            for try await prediction in group {
                predictions.append(prediction)
            }
            return predictions
        }

        guard let first = results.first else {
            XCTFail("Expected predictions")
            return
        }
        XCTAssertTrue(results.allSatisfy {
            abs($0.calibratedProbability - first.calibratedProbability) <= 0.000_001 && $0.decision == first.decision
        })
        let loadCount = await registry.riskLoadCount
        XCTAssertEqual(loadCount, 1)
    }

    func testTemporaryBuffersReleaseAfterOneHundredScans() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let actor = RiskInferenceActor(registry: registry, metrics: metrics)
        let sample = try MLTestSupport.riskSample()

        for _ in 0..<100 {
            _ = try await actor.predict(sample)
        }

        let snapshot = await metrics.snapshot()
        let loadCount = await registry.riskLoadCount
        XCTAssertEqual(snapshot.activeTemporaryBufferCount, 0)
        XCTAssertLessThanOrEqual(snapshot.peakTemporaryBufferCount, 1)
        XCTAssertEqual(loadCount, 1)
    }
}
