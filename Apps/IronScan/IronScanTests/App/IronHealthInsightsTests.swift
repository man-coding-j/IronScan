import XCTest
@testable import IronScan

final class IronHealthInsightsTests: XCTestCase {
    func testPlantBasedDietAddsAbsorptionEducation() throws {
        let insights = IronHealthInsightsBuilder.insights(
            visualSummary: summary(category: .unableToAssess),
            diet: .plantBased
        )

        let insight = try XCTUnwrap(insights.first)
        XCTAssertEqual(insights.map(\.id), [.plantBasedAbsorption])
        XCTAssertTrue(insight.detail.contains("non-heme iron"))
        XCTAssertTrue(insight.detail.contains("Vitamin C"))
    }

    func testPossibleRiskAddsLaboratoryEducationWithoutClaimingLowIron() throws {
        let insights = IronHealthInsightsBuilder.insights(
            visualSummary: summary(category: .possibleAnemiaRisk),
            diet: .preferNotToSay
        )
        let insight = try XCTUnwrap(insights.first)

        XCTAssertEqual(insight.id, .laboratoryTesting)
        XCTAssertTrue(insight.detail.contains("cannot measure iron status"))
        XCTAssertFalse(insight.detail.lowercased().contains("your iron is low"))
        XCTAssertFalse(insight.detail.lowercased().contains("exact amount"))
    }

    func testLowerObservedRiskDoesNotClaimNormalIronStatus() throws {
        let insights = IronHealthInsightsBuilder.insights(
            visualSummary: summary(category: .lowerObservedRisk),
            diet: .includesMeat
        )
        let insight = try XCTUnwrap(insights.first)

        XCTAssertEqual(insight.id, .lowerObservedRiskEducation)
        XCTAssertTrue(insight.detail.contains("does not confirm normal iron status"))
    }

    func testContextAndVisualCardsComposeWithoutScoreFusion() {
        let insights = IronHealthInsightsBuilder.insights(
            visualSummary: summary(category: .possibleAnemiaRisk),
            diet: .plantBased
        )

        XCTAssertEqual(insights.map(\.id), [.plantBasedAbsorption, .laboratoryTesting])
    }

    private func summary(category: VisualRiskCategory) -> VisualRiskSummary {
        VisualRiskSummary(
            category: category,
            title: "Test",
            detail: "Test",
            symbol: "circle"
        )
    }
}
