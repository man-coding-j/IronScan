import XCTest
@testable import IronScan

final class IDARiskEngineTests: XCTestCase {
    func testLowOpticalScoreAndNoContextFactorsReturnsLowerObservedRisk() {
        let assessment = IDARiskEngine().evaluate(
            triangulation: makeTriangulation(score: 0.2),
            intake: makeIntake()
        )

        XCTAssertEqual(assessment.summary, .lowerObservedRisk)
        XCTAssertEqual(assessment.followUpPriority, .routine)
        XCTAssertEqual(assessment.contextProfile.reportedFactorCount, 0)
    }

    func testModerateOpticalScoreReturnsPossibleRiskMonitor() {
        let assessment = IDARiskEngine().evaluate(
            triangulation: makeTriangulation(score: 0.5),
            intake: makeIntake()
        )

        XCTAssertEqual(assessment.summary, .possibleAnemiaRisk)
        XCTAssertEqual(assessment.followUpPriority, .monitor)
    }

    func testOneReportedFactorChangesFollowUpWithoutChangingOpticalScore() {
        let assessment = IDARiskEngine().evaluate(
            triangulation: makeTriangulation(score: 0.2),
            intake: makeIntake(fatigue: true)
        )

        XCTAssertEqual(assessment.summary, .possibleAnemiaRisk)
        XCTAssertEqual(assessment.followUpPriority, .monitor)
        XCTAssertEqual(assessment.opticalScore, 0.2)
    }

    func testMultipleReportedFactorsRequestLaboratoryConfirmation() {
        let assessment = IDARiskEngine().evaluate(
            triangulation: makeTriangulation(score: 0.2),
            intake: makeIntake(diet: .plantBased, fatigue: true)
        )

        XCTAssertEqual(assessment.summary, .possibleAnemiaRisk)
        XCTAssertEqual(assessment.followUpPriority, .laboratoryConfirmation)
        XCTAssertTrue(assessment.contextProfile.hasMultipleFactors)
    }

    func testUnableOpticalAssessmentRemainsUnableToAssess() {
        let result = TriangulationResult(
            summary: .unableToAssess,
            opticalPallorIndex: nil,
            contributions: [],
            rejectionReasons: ["Insufficient scans"],
            configurationIdentifier: "test",
            configurationVersion: "1",
            mode: .researchValidated,
            calibrationCategory: .defaultCategory,
            calibratedDecisionThreshold: 0.5
        )

        let assessment = IDARiskEngine().evaluate(
            triangulation: result,
            intake: makeIntake(diet: .plantBased, fatigue: true, coldHands: true)
        )

        XCTAssertEqual(assessment.summary, .unableToAssess)
        XCTAssertNil(assessment.opticalScore)
    }

    private func makeTriangulation(score: Double) -> TriangulationResult {
        TriangulationResult(
            summary: score >= 0.5 ? .possibleAnemiaRisk : .lowerObservedRisk,
            opticalPallorIndex: score,
            contributions: [],
            rejectionReasons: [],
            configurationIdentifier: "test",
            configurationVersion: "1",
            mode: .researchValidated,
            calibrationCategory: .defaultCategory,
            calibratedDecisionThreshold: 0.5
        )
    }

    private func makeIntake(
        diet: DietContext = .includesMeat,
        fatigue: Bool = false,
        coldHands: Bool = false
    ) -> ScreeningIntakeSnapshot {
        ScreeningIntakeSnapshot(
            biologicalSex: .preferNotToSay,
            diet: diet,
            reportsFatigue: fatigue,
            reportsColdHands: coldHands
        )
    }
}
