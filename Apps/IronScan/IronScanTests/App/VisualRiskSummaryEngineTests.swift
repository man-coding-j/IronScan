import XCTest
@testable import IronScan

final class VisualRiskSummaryEngineTests: XCTestCase {
    func testBelowLockedThresholdMapsToLowerObservedRisk() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: 0.49, threshold: 0.5),
            quality: .accepted
        )

        XCTAssertEqual(summary.category, .lowerObservedRisk)
        XCTAssertEqual(summary.title, "Lower observed risk")
    }

    func testLockedThresholdMapsToPossibleAnemiaRisk() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: 0.5, threshold: 0.5),
            quality: .accepted
        )

        XCTAssertEqual(summary.category, .possibleAnemiaRisk)
        XCTAssertEqual(summary.title, "Possible anemia risk")
    }

    func testRejectedQualityReturnsUnableToAssess() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: 0.8, threshold: 0.5),
            quality: .rejected(reasons: ["blur"])
        )

        XCTAssertEqual(summary.category, .unableToAssess)
    }

    func testEngineeringFixtureProducesClearlyLabeledDemoCategory() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: 0.8, threshold: 0.5, isEngineeringFixture: true),
            quality: .accepted,
            demoModeEnabled: true
        )

        XCTAssertEqual(summary.category, .possibleAnemiaRisk)
        XCTAssertTrue(summary.detail.contains("Prototype demo prediction"))
        XCTAssertTrue(summary.detail.contains("unvalidated engineering model"))
    }

    func testEngineeringFixtureRemainsRejectedOutsideDemoMode() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: 0.8, threshold: 0.5, isEngineeringFixture: true),
            quality: .accepted,
            demoModeEnabled: false
        )

        XCTAssertEqual(summary.category, .unableToAssess)
    }

    func testInvalidProbabilityReturnsUnableToAssess() {
        let summary = VisualRiskSummaryEngine.summarize(
            report: makeReport(probability: .nan, threshold: 0.5),
            quality: .accepted
        )

        XCTAssertEqual(summary.category, .unableToAssess)
    }

    func testIntakeContextDoesNotEnterVisualSummaryAPI() {
        let report = makeReport(probability: 0.2, threshold: 0.5)
        let first = VisualRiskSummaryEngine.summarize(report: report, quality: .accepted)
        _ = ScreeningIntakeSnapshot(
            biologicalSex: .female,
            diet: .plantBased,
            reportsFatigue: true,
            reportsColdHands: true
        )
        let second = VisualRiskSummaryEngine.summarize(report: report, quality: .accepted)

        XCTAssertEqual(first, second)
    }

    func testUserFacingSummaryContainsNoMedicalUnitsOrPercentages() {
        let summaries = [
            VisualRiskSummaryEngine.summarize(
                report: makeReport(probability: 0.2, threshold: 0.5),
                quality: .accepted
            ),
            VisualRiskSummaryEngine.summarize(
                report: makeReport(probability: 0.8, threshold: 0.5),
                quality: .accepted
            ),
        ]

        for summary in summaries {
            let text = "\(summary.title) \(summary.detail)".lowercased()
            XCTAssertFalse(text.contains("g/dl"))
            XCTAssertFalse(text.contains("%"))
            XCTAssertFalse(text.contains("hemoglobin"))
            XCTAssertFalse(text.contains("ferritin"))
        }
    }

    func testSymptomSummaryUsesOnlySelectedContext() {
        let intake = ScreeningIntakeSnapshot(
            biologicalSex: .preferNotToSay,
            diet: .preferNotToSay,
            reportsFatigue: true,
            reportsColdHands: false
        )

        XCTAssertEqual(intake.symptomSummary, "Fatigue")
    }

    private func makeReport(
        probability: Double,
        threshold: Double,
        isEngineeringFixture: Bool = false
    ) -> TongueVisualAttributeReport {
        let quietScore = VisualAttributeScore(probability: 0.1, lockedThreshold: 0.5)
        return TongueVisualAttributeReport(
            pallor: VisualAttributeScore(probability: probability, lockedThreshold: threshold),
            toothmark: quietScore,
            crack: quietScore,
            tipSideRed: quietScore,
            furThick: quietScore,
            inferenceDurationMs: 10,
            modelVersion: "test",
            isEngineeringFixture: isEngineeringFixture
        )
    }
}
