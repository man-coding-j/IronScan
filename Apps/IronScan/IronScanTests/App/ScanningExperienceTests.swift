import XCTest
import UIKit
import CoreMedia
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
        XCTAssertEqual(LiveScanningState.aligning.statusText, "Adjusting focus and lighting…")
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.34).statusText,
            "Analyzing mucosal color profile…"
        )
        XCTAssertEqual(
            LiveScanningState.scanning(progress: 0.67).statusText,
            "Calculating visual indicators…"
        )
    }

    func testScanStepsKeepProgressGuideAndInferenceTissueSynchronized() {
        XCTAssertEqual(ScanStep.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(ScanStep.allCases.map(\.progressTitle), ["Conjunctiva", "Fingernail Bed", "Tongue"])
        XCTAssertEqual(ScanStep.allCases.map(\.tissue.rawValue), ["eye", "nail", "tongue"])
        XCTAssertEqual(ScanStep.conjunctiva.guideInstruction, "Align Conjunctiva within the guide")
        XCTAssertEqual(ScanStep.fingernail.guideInstruction, "Align Fingernail Bed within the guide")
        XCTAssertEqual(ScanStep.tongue.guideInstruction, "Align Tongue within the guide")
    }

    @MainActor
    func testScanSessionRequiresExactlyAllThreeStepImages() {
        let session = ScanSession()
        let image = UIImage()

        session.store(image, for: .conjunctiva)
        session.store(image, for: .fingernail)
        XCTAssertFalse(session.isComplete)

        session.store(image, for: .tongue)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.capturedImages.count, 3)

        session.reset()
        XCTAssertFalse(session.isComplete)
        XCTAssertTrue(session.capturedImages.isEmpty)
    }

    @MainActor
    func testMedicalCameraManagerCapturesTheDisplayedFrameAndClearsIt() throws {
        let manager = MedicalCameraManager()
        let buffer = try SyntheticTongueFrameFactory.makePixelBuffer(width: 96, height: 96)
        manager.display(AnalyzableFrame(pixelBuffer: buffer, timestamp: .zero))

        let displayed = try XCTUnwrap(manager.currentFrame)
        XCTAssertEqual(displayed.imageOrientation, .up)
        XCTAssertTrue(manager.capturePhoto() === displayed)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(manager.currentVideoFrame).pixelBuffer), 96)

        manager.clear()
        XCTAssertNil(manager.capturePhoto())
        XCTAssertNil(manager.currentVideoFrame)
    }

    func testAssessmentFallbackUsesSpecifiedDemoValues() {
        let summary = ScanAssessmentSummary.demoFallback
        XCTAssertEqual(summary.estimatedHemoglobin, 9.8)
        XCTAssertEqual(summary.pallorIndices[.conjunctiva], 0.72)
        XCTAssertEqual(summary.pallorIndices[.fingernail], 0.81)
        XCTAssertEqual(summary.pallorIndices[.tongue], 0.70)
        XCTAssertEqual(summary.warningText, "Severe Anemia Risk")
        XCTAssertTrue(summary.usesDemoFallback)
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
