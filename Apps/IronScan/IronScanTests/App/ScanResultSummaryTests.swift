import CoreMedia
import XCTest
@testable import IronScan

final class ScanResultSummaryTests: XCTestCase {
    func testLiveFrameRunsSegmentationWithoutRiskPrediction() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let pipeline = ScanPipelineActor(registry: registry, metrics: metrics)
        let pixelBuffer = try SyntheticTongueFrameFactory.makePixelBuffer()

        let summary = try await pipeline.analyzeLiveFrame(
            AnalyzableFrame(pixelBuffer: pixelBuffer, timestamp: .zero),
            runVisualInference: false
        )
        let segmentationLoadCount = await registry.segmentationLoadCount
        let riskLoadCount = await registry.riskLoadCount
        let multiScreenLoadCount = await registry.multiScreenLoadCount

        XCTAssertGreaterThan(summary.tongueAreaRatio, 0)
        XCTAssertGreaterThanOrEqual(summary.alignmentProgress, 0)
        XCTAssertLessThanOrEqual(summary.alignmentProgress, 1)
        XCTAssertGreaterThanOrEqual(summary.inferenceDurationMs, 0)
        XCTAssertEqual(segmentationLoadCount, 1)
        XCTAssertEqual(riskLoadCount, 0)
        XCTAssertEqual(multiScreenLoadCount, 0)
    }

    func testSyntheticSimulatorFlowRunsOnDeviceModels() async throws {
        let summary = try await ScanPipelineActor().runSyntheticDemo()

        XCTAssertEqual(summary.title, "Unable to assess")
        XCTAssertEqual(summary.detail, "Synthetic engineering fixture — not a participant result.")
        XCTAssertGreaterThan(summary.segmentationAreaRatio, 0)
        XCTAssertGreaterThanOrEqual(summary.inferenceDurationMs, 0)
    }

    func testManualDemoCaptureProducesVisualAttributeReport() async throws {
        let camera = SimulatorCameraActor()
        let stream = await camera.eventStream()
        var iterator = stream.makeAsyncIterator()
        await camera.start()
        await camera.capture()

        var capturedFrame: CapturedFrame?
        for _ in 0 ..< 16 {
            guard let event = await iterator.next() else { break }
            if case let .captured(frame) = event {
                capturedFrame = frame
                break
            }
        }
        await camera.stop()

        let frame = try XCTUnwrap(capturedFrame)
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let pipeline = ScanPipelineActor(registry: registry, metrics: metrics)
        let liveSummary = try await pipeline.analyzeLiveFrame(
            AnalyzableFrame(pixelBuffer: frame.pixelBuffer, timestamp: .zero),
            runVisualInference: false
        )
        XCTAssertTrue(
            liveSummary.isTongueAligned,
            "area=\(liveSummary.tongueAreaRatio), confidence=\(liveSummary.meanConfidence)"
        )
        let summary = try await pipeline.processPhysicalCapture(frame)

        XCTAssertEqual(summary.title, "Visual research summary")
        XCTAssertNotNil(summary.visualAttributeReport)
    }

    func testSyntheticBenchmarkReportsP95Metrics() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)
        let pipeline = ScanPipelineActor(registry: registry, metrics: metrics)

        let summary = try await pipeline.runSyntheticBenchmark(
            iterations: 3,
            deviceModelIdentifier: "synthetic-test-device",
            operatingSystemVersion: "test-os"
        )
        let segmentationLoadCount = await registry.segmentationLoadCount
        let riskLoadCount = await registry.riskLoadCount

        XCTAssertEqual(summary.iterationCount, 3)
        XCTAssertEqual(summary.deviceModelIdentifier, "synthetic-test-device")
        XCTAssertGreaterThanOrEqual(summary.segmentationP95Ms, 0)
        XCTAssertGreaterThanOrEqual(summary.riskInferenceP95Ms, 0)
        XCTAssertGreaterThanOrEqual(summary.totalPipelineP95Ms, 0)
        XCTAssertLessThanOrEqual(summary.peakTemporaryBufferCount, 1)
        XCTAssertEqual(segmentationLoadCount, 1)
        XCTAssertEqual(riskLoadCount, 1)
    }

    func testAllowedDecisionTitles() {
        XCTAssertEqual(RiskDecision.lowerObservedRisk.displayTitle, "Lower observed risk")
        XCTAssertEqual(RiskDecision.possibleRisk.displayTitle, "Possible anemia risk")
        XCTAssertEqual(RiskDecision.unableToAssess.displayTitle, "Unable to assess")
    }

    func testPrototypeFallbackIsClearlySyntheticAndNonDiagnostic() {
        let summary = ScanResultSummary.prototypeFallback(isSimulatorMode: true)

        XCTAssertEqual(summary.title, "Demo estimate: 12.4 g/dL")
        XCTAssertEqual(summary.decision, .unableToAssess)
        XCTAssertNil(summary.riskScore)
        XCTAssertTrue(summary.detail.contains("Synthetic Simulator fallback"))
        XCTAssertTrue(summary.detail.contains("not a participant result"))
    }

    func testPhysicalCaptureRemainsUnableWithoutValidatedCalibration() {
        let segmentation = SegmentationResult(
            probabilityMask: [0.9],
            binaryMask: [1],
            width: 1,
            height: 1,
            confidenceStatistics: SegmentationConfidenceStatistics(
                meanForegroundProbability: 0.9,
                minimumForegroundProbability: 0.9,
                maximumForegroundProbability: 0.9,
                foregroundPixelCount: 1,
                areaRatio: 1
            ),
            inferenceDurationMs: 2,
            modelVersion: "test"
        )

        let summary = ScanResultSummary.physicalCapture(segmentation: segmentation)

        XCTAssertEqual(summary.title, "Unable to assess")
        XCTAssertEqual(summary.segmentationAreaRatio, 1)
    }
}
