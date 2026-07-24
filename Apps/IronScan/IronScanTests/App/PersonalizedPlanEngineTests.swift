import XCTest
@testable import IronScan

final class PersonalizedPlanEngineTests: XCTestCase {
    func testPlantBasedIntakeAndEyeSignalProduceSeparateSafeGuidance() {
        let plan = PersonalizedPlanEngine().makePlan(
            fusedScore: 0.7,
            opticalSummary: .possibleAnemiaRisk,
            outputs: [.eye: makeEyeOutput(signalObserved: true)],
            intake: makeIntake(diet: .plantBased, fatigue: true)
        )

        XCTAssertEqual(plan.tone, .laboratoryConfirmation)
        XCTAssertTrue(plan.summary.localizedCaseInsensitiveContains("eye image"))
        XCTAssertTrue(plan.items.contains(where: { $0.id == "plant-based-pairing" }))
        XCTAssertTrue(plan.items.contains(where: { $0.id == "laboratory-confirmation" }))
        XCTAssertSafe(plan)
    }

    func testLowerOpticalSignalDoesNotClaimNormalIronOrScheduleRescan() {
        let plan = PersonalizedPlanEngine().makePlan(
            fusedScore: 0.2,
            opticalSummary: .lowerObservedRisk,
            outputs: [:],
            intake: makeIntake()
        )
        let copy = combinedCopy(plan)

        XCTAssertEqual(plan.tone, .routine)
        XCTAssertTrue(copy.contains("does not confirm normal iron status"))
        XCTAssertFalse(copy.contains("monthly"))
        XCTAssertFalse(copy.contains("healthy iron"))
        XCTAssertSafe(plan)
    }

    func testReportedMenstrualHistoryCreatesContextItemWithoutChangingModelLanguage() {
        let plan = PersonalizedPlanEngine().makePlan(
            fusedScore: 0.2,
            opticalSummary: .lowerObservedRisk,
            outputs: [:],
            intake: makeIntake(menstrualHistory: .reportsHeavyBleeding)
        )

        XCTAssertEqual(plan.tone, .monitor)
        XCTAssertTrue(plan.items.contains(where: { $0.id == "reported-menstrual-history" }))
        XCTAssertTrue(plan.summary.localizedCaseInsensitiveContains("does not change the model output"))
        XCTAssertSafe(plan)
    }

    func testInvalidFusedScoreReturnsUnableToAssess() {
        let plan = PersonalizedPlanEngine().makePlan(
            fusedScore: .nan,
            opticalSummary: .possibleAnemiaRisk,
            outputs: [:],
            intake: makeIntake()
        )

        XCTAssertEqual(plan.tone, .unableToAssess)
        XCTAssertTrue(plan.summary.localizedCaseInsensitiveContains("no scan-based"))
        XCTAssertSafe(plan)
    }

    func testGeneralGuidanceAvoidsUniversalMultiplierAndBlockingClaims() {
        let copy = [
            HealthGuidanceContent.hemeAndNonHeme,
            HealthGuidanceContent.vitaminC,
            HealthGuidanceContent.inhibitors,
        ].joined(separator: " ").lowercased()

        XCTAssertTrue(copy.contains("can improve"))
        XCTAssertTrue(copy.contains("may reduce"))
        XCTAssertFalse(copy.contains("3x"))
        XCTAssertFalse(copy.contains("three times"))
        XCTAssertFalse(copy.contains("block iron"))
    }

    private func makeIntake(
        diet: DietContext = .includesMeat,
        fatigue: Bool = false,
        coldHands: Bool = false,
        menstrualHistory: MenstrualHistoryContext = .notApplicable
    ) -> ScreeningIntakeSnapshot {
        ScreeningIntakeSnapshot(
            biologicalSex: .preferNotToSay,
            diet: diet,
            reportsFatigue: fatigue,
            reportsColdHands: coldHands,
            menstrualHistory: menstrualHistory
        )
    }

    private func makeEyeOutput(signalObserved: Bool) -> TissueScreeningOutput {
        TissueScreeningOutput(
            tissue: .eye,
            probability: signalObserved ? 0.8 : 0.2,
            lockedThreshold: 0.5,
            qualityAccepted: true,
            rejectionReasons: [],
            modelVersion: "test",
            preprocessingVersion: "test",
            isEngineeringFixture: true
        )
    }

    private func combinedCopy(_ plan: PersonalizedIronPlan) -> String {
        ([plan.title, plan.summary, plan.disclaimer] + plan.items.flatMap { [$0.title, $0.detail] })
            .joined(separator: " ")
            .lowercased()
    }

    private func XCTAssertSafe(
        _ plan: PersonalizedIronPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let copy = combinedCopy(plan)
        for prohibited in [
            "you have anemia",
            "you are iron deficient",
            "supplement",
            "medication",
            "take iron",
        ] {
            XCTAssertFalse(copy.contains(prohibited), "Found prohibited copy: \(prohibited)", file: file, line: line)
        }
    }
}
