import XCTest
@testable import IronScan

final class MultiInferenceEngineTests: XCTestCase {
    private static let expectedThresholds = [
        "tongue_pale_probability": 0.1380755681397391,
        "toothmark_probability": 0.6022805929600064,
        "crack_probability": 0.8280629716568514,
        "tip_side_red_probability": 0.4477408973984361,
        "fur_thick_probability": 0.9835036734263566,
    ]

    func testMultiScreenModelInitializesWithAllComputeUnits() async throws {
        let registry = ModelRegistryActor(
            resources: .runtimeBundle(),
            computeUnits: .all,
            metrics: InferenceMetricsRecorder()
        )

        let handle = try await registry.multiScreenModel()

        XCTAssertEqual(handle.computeUnits, .all)
        XCTAssertEqual(handle.manifest.input.dimensions, [1, 224, 224, 3])
        XCTAssertEqual(handle.manifest.decisionThresholds, Self.expectedThresholds)
        XCTAssertEqual(handle.manifest.outputs.count, 5)
    }

    func testPredictionReturnsFiveVisualAttributeScores() async throws {
        let engine = makeEngine(minimumInterval: .zero)

        let result = try await engine.predict(makeFrame())
        let report = try XCTUnwrap(result)
        let scores = [report.pallor, report.toothmark, report.crack, report.tipSideRed, report.furThick]

        XCTAssertEqual(scores.count, 5)
        XCTAssertTrue(scores.allSatisfy { (0...1).contains($0.probability) })
        XCTAssertEqual(report.pallor.lockedThreshold, Self.expectedThresholds["tongue_pale_probability"])
        XCTAssertEqual(report.toothmark.lockedThreshold, Self.expectedThresholds["toothmark_probability"])
        XCTAssertEqual(report.crack.lockedThreshold, Self.expectedThresholds["crack_probability"])
        XCTAssertEqual(report.tipSideRed.lockedThreshold, Self.expectedThresholds["tip_side_red_probability"])
        XCTAssertEqual(report.furThick.lockedThreshold, Self.expectedThresholds["fur_thick_probability"])
        XCTAssertTrue(report.isEngineeringFixture)
    }

    func testRepeatedPredictionIsDeterministic() async throws {
        let engine = makeEngine(minimumInterval: .zero)
        let frame = try makeFrame()

        let firstResult = try await engine.predict(frame)
        let secondResult = try await engine.predict(frame)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)

        XCTAssertEqual(first.pallorScore, second.pallorScore, accuracy: 1e-6)
        XCTAssertEqual(first.toothmarkScore, second.toothmarkScore, accuracy: 1e-6)
        XCTAssertEqual(first.crackScore, second.crackScore, accuracy: 1e-6)
        XCTAssertEqual(first.tipSideRedScore, second.tipSideRedScore, accuracy: 1e-6)
        XCTAssertEqual(first.coatingScore, second.coatingScore, accuracy: 1e-6)
    }

    func testThirtyRapidFramesProduceOnePrediction() async throws {
        let engine = makeEngine(minimumInterval: .seconds(1))
        let frame = try makeFrame()
        var predictionCount = 0

        for _ in 0..<30 {
            if try await engine.predict(frame) != nil {
                predictionCount += 1
            }
        }

        XCTAssertEqual(predictionCount, 1)
    }

    func testManualCaptureBypassesThrottleWithoutDisablingFutureThrottling() async throws {
        let engine = makeEngine(minimumInterval: .seconds(1))
        let frame = try makeFrame()

        let first = try await engine.predict(frame)
        let manualCapture = try await engine.predict(frame, bypassThrottle: true)
        let throttled = try await engine.predict(frame)

        XCTAssertNotNil(first)
        XCTAssertNotNil(manualCapture)
        XCTAssertNil(throttled)
    }

    func testCancellationBeforePredictionBegins() async throws {
        let engine = makeEngine(minimumInterval: .zero)
        let frame = try makeFrame()
        let task = Task { try await engine.predict(frame) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled request must not produce visual-attribute scores")
        } catch let error as InferenceError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testTemporaryBuffersReleaseAfterRepeatedPredictions() async throws {
        let metrics = InferenceMetricsRecorder()
        let engine = makeEngine(minimumInterval: .zero, metrics: metrics)
        let frame = try makeFrame()

        for _ in 0..<20 {
            _ = try await engine.predict(frame)
        }

        let snapshot = await metrics.snapshot()
        XCTAssertEqual(snapshot.activeTemporaryBufferCount, 0)
        XCTAssertLessThanOrEqual(snapshot.peakTemporaryBufferCount, 1)
    }

    private func makeFrame() throws -> AnalyzableFrame {
        AnalyzableFrame(
            pixelBuffer: try SyntheticTongueFrameFactory.makePixelBuffer(width: 224, height: 224),
            timestamp: .zero
        )
    }

    private func makeEngine(
        minimumInterval: Duration,
        metrics: InferenceMetricsRecorder = InferenceMetricsRecorder()
    ) -> MultiInferenceEngine {
        let registry = ModelRegistryActor(
            resources: .runtimeBundle(),
            computeUnits: .cpuOnly,
            metrics: metrics
        )
        return MultiInferenceEngine(
            registry: registry,
            metrics: metrics,
            minimumInterval: minimumInterval
        )
    }
}
