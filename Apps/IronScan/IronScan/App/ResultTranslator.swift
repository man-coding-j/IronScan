import Foundation

enum ResultTheme: Equatable, Sendable {
    case neutral
    case calm
    case attention
}

struct FriendlyResultCard: Equatable, Identifiable, Sendable {
    enum Identifier: String, Sendable {
        case tongueColor
        case tongueEdges
        case surfaceLines
        case localizedColor
        case surfaceCoating
    }

    let id: Identifier
    let title: String
    let status: String
    let detail: String
    let symbol: String
    let theme: ResultTheme
    let isHighlighted: Bool
}

struct FriendlyScanSummary: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let detail: String
    let theme: ResultTheme
    let cards: [FriendlyResultCard]
    let nextSteps: [String]
    let disclaimer: String
}

enum ResultTranslator {
    static func translate(_ report: TongueVisualAttributeReport) -> FriendlyScanSummary {
        let cards = [
            tongueColor(score: report.pallor),
            tongueEdges(score: report.toothmark),
            surfaceLines(score: report.crack),
            localizedColor(score: report.tipSideRed),
            surfaceCoating(score: report.furThick),
        ]
        let highlightedCount = cards.filter(\.isHighlighted).count
        return FriendlyScanSummary(
            eyebrow: report.isEngineeringFixture ? "RESEARCH PREVIEW" : "VISUAL PREVIEW",
            title: overallTitle(highlightedCount: highlightedCount),
            detail: highlightedCount == 0
                ? "This scan did not highlight any of its five appearance labels. This is not a health result."
                : "Review the highlighted appearance cards below. The app cannot assess their health significance.",
            theme: highlightedCount == 0 ? .calm : .attention,
            cards: cards,
            nextSteps: [
                "Retake the scan in even, neutral lighting if the camera view looked unclear.",
                "Use this result only as a visual research preview.",
                "Confirm any health concern with a laboratory test and a qualified professional.",
            ],
            disclaimer: "IronScan is a research prototype. It does not measure hemoglobin, ferritin, or iron status and does not provide clinical conclusions."
        )
    }

    private static func overallTitle(highlightedCount: Int) -> String {
        switch highlightedCount {
        case 0: "No visual patterns highlighted"
        case 1: "One visual pattern highlighted"
        default: "\(highlightedCount) visual patterns highlighted"
        }
    }

    private static func tongueColor(score: VisualAttributeScore) -> FriendlyResultCard {
        card(
            id: .tongueColor,
            title: "Tongue color",
            score: score,
            highlightedStatus: "Paler color pattern noticed",
            quietStatus: "No pale-color pattern highlighted",
            highlightedDetail: "The model highlighted a lighter-color appearance in this image. This is not a laboratory measurement.",
            quietDetail: "The model did not highlight its pale-color appearance label in this image.",
            symbol: "circle.lefthalf.filled"
        )
    }

    private static func tongueEdges(score: VisualAttributeScore) -> FriendlyResultCard {
        card(
            id: .tongueEdges,
            title: "Tongue edges",
            score: score,
            highlightedStatus: "Edge indentations noticed",
            quietStatus: "No edge indentations highlighted",
            highlightedDetail: "The model highlighted a side-indentation pattern along the visible tongue edge.",
            quietDetail: "The model did not highlight its side-indentation appearance label.",
            symbol: "arrow.left.and.right"
        )
    }

    private static func surfaceLines(score: VisualAttributeScore) -> FriendlyResultCard {
        card(
            id: .surfaceLines,
            title: "Surface lines",
            score: score,
            highlightedStatus: "Line pattern noticed",
            quietStatus: "No line pattern highlighted",
            highlightedDetail: "The model highlighted visible line or fissure-like shapes on the tongue surface.",
            quietDetail: "The model did not highlight its surface-line appearance label.",
            symbol: "line.diagonal"
        )
    }

    private static func localizedColor(score: VisualAttributeScore) -> FriendlyResultCard {
        card(
            id: .localizedColor,
            title: "Color near tip and sides",
            score: score,
            highlightedStatus: "Redness pattern noticed",
            quietStatus: "No redness pattern highlighted",
            highlightedDetail: "The model highlighted a stronger red-color pattern near the visible tip or sides.",
            quietDetail: "The model did not highlight its localized red-color appearance label.",
            symbol: "circle.hexagongrid"
        )
    }

    private static func surfaceCoating(score: VisualAttributeScore) -> FriendlyResultCard {
        card(
            id: .surfaceCoating,
            title: "Tongue surface",
            score: score,
            highlightedStatus: "Coating pattern noticed",
            quietStatus: "No coating pattern highlighted",
            highlightedDetail: "The model highlighted a thicker-looking surface-coating pattern in this image.",
            quietDetail: "The model did not highlight its surface-coating appearance label.",
            symbol: "circle.dotted"
        )
    }

    private static func card(
        id: FriendlyResultCard.Identifier,
        title: String,
        score: VisualAttributeScore,
        highlightedStatus: String,
        quietStatus: String,
        highlightedDetail: String,
        quietDetail: String,
        symbol: String
    ) -> FriendlyResultCard {
        let isHighlighted = score.exceedsLockedThreshold
        return FriendlyResultCard(
            id: id,
            title: title,
            status: isHighlighted ? highlightedStatus : quietStatus,
            detail: isHighlighted ? highlightedDetail : quietDetail,
            symbol: symbol,
            theme: isHighlighted ? .attention : .calm,
            isHighlighted: isHighlighted
        )
    }
}
