import XCTest
@testable import IronScan

final class ResultTranslatorTests: XCTestCase {
    func testBelowThresholdReportUsesPlainVisualLanguage() {
        let summary = ResultTranslator.translate(makeReport(highlighted: []))

        XCTAssertEqual(summary.title, "No visual patterns highlighted")
        XCTAssertEqual(summary.cards.count, 5)
        XCTAssertTrue(summary.cards.allSatisfy { !$0.isHighlighted })
        XCTAssertTrue(summary.cards.allSatisfy { !$0.status.contains("0.") })
    }

    func testHighlightedCardsFollowLockedThresholds() {
        let summary = ResultTranslator.translate(makeReport(highlighted: [.tongueColor, .surfaceCoating]))
        let highlighted = summary.cards.filter(\.isHighlighted)

        XCTAssertEqual(summary.title, "2 visual patterns highlighted")
        XCTAssertEqual(highlighted.map(\.id), [.tongueColor, .surfaceCoating])
        XCTAssertEqual(highlighted.map(\.theme), [.attention, .attention])
    }

    func testTranslationExcludesUnsupportedHealthAndTreatmentClaims() {
        let summary = ResultTranslator.translate(makeReport(highlighted: Set(FriendlyResultCard.Identifier.allCases)))
        let text = ([summary.title, summary.detail, summary.disclaimer]
            + summary.nextSteps
            + summary.cards.flatMap { [$0.title, $0.status, $0.detail] })
            .joined(separator: " ")
            .lowercased()
        let unsupportedPhrases = [
            "healthy iron",
            "low iron indicator",
            "vitamin deficiency",
            "fluid retention",
            "needs brushing",
            "take supplements",
        ]

        for phrase in unsupportedPhrases {
            XCTAssertFalse(text.contains(phrase), "Unexpected claim: \(phrase)")
        }
    }

    private func makeReport(
        highlighted: Set<FriendlyResultCard.Identifier>
    ) -> TongueVisualAttributeReport {
        TongueVisualAttributeReport(
            pallor: score(isHighlighted: highlighted.contains(.tongueColor)),
            toothmark: score(isHighlighted: highlighted.contains(.tongueEdges)),
            crack: score(isHighlighted: highlighted.contains(.surfaceLines)),
            tipSideRed: score(isHighlighted: highlighted.contains(.localizedColor)),
            furThick: score(isHighlighted: highlighted.contains(.surfaceCoating)),
            inferenceDurationMs: 10,
            modelVersion: "test",
            isEngineeringFixture: true
        )
    }

    private func score(isHighlighted: Bool) -> VisualAttributeScore {
        VisualAttributeScore(
            probability: isHighlighted ? 0.8 : 0.2,
            lockedThreshold: 0.5
        )
    }
}

private extension FriendlyResultCard.Identifier {
    static var allCases: [FriendlyResultCard.Identifier] {
        [.tongueColor, .tongueEdges, .surfaceLines, .localizedColor, .surfaceCoating]
    }
}
