import XCTest
@testable import IronScan

final class ScanResultSummaryTests: XCTestCase {
    func testSyntheticSimulatorFlowRunsOnDeviceModels() async throws {
        let summary = try await ScanPipelineActor().runSyntheticDemo()

        XCTAssertEqual(summary.title, "Unable to assess")
        XCTAssertEqual(summary.detail, "Synthetic engineering fixture — not a participant result.")
        XCTAssertGreaterThan(summary.segmentationAreaRatio, 0)
        XCTAssertGreaterThanOrEqual(summary.inferenceDurationMs, 0)
    }

    func testAllowedDecisionTitles() {
        XCTAssertEqual(RiskDecision.lowerObservedRisk.displayTitle, "Lower observed risk")
        XCTAssertEqual(RiskDecision.possibleRisk.displayTitle, "Possible anemia risk")
        XCTAssertEqual(RiskDecision.unableToAssess.displayTitle, "Unable to assess")
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
