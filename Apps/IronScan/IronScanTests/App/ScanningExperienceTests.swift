import XCTest
@testable import IronScan

final class ScanningExperienceTests: XCTestCase {
    func testThreeEvaluationsCompleteVisualScan() {
        var tracker = LiveScanProgressTracker()
        let report = makeReport()

        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 1.0 / 3.0))
        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 2.0 / 3.0))
        XCTAssertEqual(tracker.register(report: report), .completed(report: report))
        XCTAssertEqual(tracker.evaluationCount, 3)
    }

    func testResetRequiresThreeFreshEvaluations() {
        var tracker = LiveScanProgressTracker()
        let report = makeReport()

        _ = tracker.register(report: report)
        _ = tracker.register(report: report)
        tracker.reset()

        XCTAssertEqual(tracker.evaluationCount, 0)
        XCTAssertEqual(tracker.register(report: report), .scanning(progress: 1.0 / 3.0))
    }

    func testScanningStatusUsesNonClinicalVisualLanguage() {
        XCTAssertEqual(LiveScanningState.idle.statusText, "Align tongue inside the oval…")
        XCTAssertEqual(LiveScanningState.aligning.statusText, "Locking focus and adjusting lighting…")
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.34).statusText,
            "Analyzing mucosal color profile…"
        )
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.67).statusText,
            "Calculating visual indicators…"
        )
    }

    private func makeReport() -> TongueVisualAttributeReport {
        let score = VisualAttributeScore(probability: 0.25, lockedThreshold: 0.5)
        return TongueVisualAttributeReport(
            pallor: score,
            toothmark: score,
            crack: score,
            tipSideRed: score,
            furThick: score,
            inferenceDurationMs: 12,
            modelVersion: "test",
            isEngineeringFixture: true
        )
    }
}
