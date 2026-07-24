import XCTest
@testable import IronScan

@MainActor
final class InferenceConcurrencyTests: XCTestCase {
    func testStartupPreloadValidatesAndLoadsAllModelsOnce() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)

        let first = try await registry.preloadModels()
        let second = try await registry.preloadModels()
        let segmentationLoadCount = await registry.segmentationLoadCount
        let riskLoadCount = await registry.riskLoadCount
        let pallorLoadCount = await registry.pallorLoadCount
        let multiScreenLoadCount = await registry.multiScreenLoadCount

        XCTAssertEqual(first, second)
        XCTAssertEqual(segmentationLoadCount, 1)
        XCTAssertEqual(riskLoadCount, 1)
        XCTAssertEqual(pallorLoadCount, 1)
        XCTAssertEqual(multiScreenLoadCount, 1)
    }

    func testConcurrentStartupPreloadStillLoadsEachModelOnce() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)

        let readiness = try await withThrowingTaskGroup(of: ModelRegistryReadiness.self) { group in
            for _ in 0..<8 {
                group.addTask { try await registry.preloadModels() }
            }
            var values = [ModelRegistryReadiness]()
            for try await value in group {
                values.append(value)
            }
            return values
        }
        let segmentationLoadCount = await registry.segmentationLoadCount
        let riskLoadCount = await registry.riskLoadCount
        let pallorLoadCount = await registry.pallorLoadCount
        let multiScreenLoadCount = await registry.multiScreenLoadCount

        XCTAssertEqual(Set(readiness.map(\.segmentationModelVersion)).count, 1)
        XCTAssertEqual(Set(readiness.map(\.riskModelVersion)).count, 1)
        XCTAssertEqual(Set(readiness.map(\.multiScreenModelVersion)).count, 1)
        XCTAssertEqual(segmentationLoadCount, 1)
        XCTAssertEqual(riskLoadCount, 1)
        XCTAssertEqual(pallorLoadCount, 1)
        XCTAssertEqual(multiScreenLoadCount, 1)
    }

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

    func testRiskRejectsCalibrationPreprocessingVersionMismatch() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let actor = RiskInferenceActor(registry: registry, metrics: metrics)
        let valid = try MLTestSupport.riskSample()
        let mismatched = CalibratedTongueSample(
            calibratedPixelBuffer: valid.calibratedPixelBuffer,
            tongueMask: valid.tongueMask,
            centralROIMask: valid.centralROIMask,
            maskWidth: valid.maskWidth,
            maskHeight: valid.maskHeight,
            calibrationMode: valid.calibrationMode,
            calibrationMatrix: valid.calibrationMatrix,
            exposureScale: valid.exposureScale,
            usablePatchCount: valid.usablePatchCount,
            medianReferenceDeltaE: valid.medianReferenceDeltaE,
            maximumReferenceDeltaE: valid.maximumReferenceDeltaE,
            matrixConditionNumber: valid.matrixConditionNumber,
            specularFraction: valid.specularFraction,
            shadowUniformity: valid.shadowUniformity,
            segmentationConfidence: valid.segmentationConfidence,
            calibrationConfidence: valid.calibrationConfidence,
            accepted: true,
            rejectionReasons: [],
            preprocessingVersion: "mismatched",
            calibrationDurationMs: valid.calibrationDurationMs,
            qualitySummary: valid.qualitySummary,
            diagnosticFeatures: valid.diagnosticFeatures
        )

        do {
            _ = try await actor.predict(mismatched)
            XCTFail("Mismatched calibration preprocessing must not reach prediction")
        } catch let error as ModelContractError {
            XCTAssertEqual(error, .preprocessingVersion(expected: "1.0.0", actual: "mismatched"))
        }
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
