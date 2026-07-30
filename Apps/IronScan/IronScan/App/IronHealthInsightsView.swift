import Foundation
import SwiftUI

struct IronHealthInsight: Equatable, Identifiable, Sendable {
    enum Identifier: String, Sendable {
        case plantBasedAbsorption
        case laboratoryTesting
        case lowerObservedRiskEducation
    }

    let id: Identifier
    let title: String
    let detail: String
    let symbol: String
    let sourceTitle: String
    let sourceURL: URL?
}

enum IronHealthInsightsBuilder {
    static func insights(
        visualSummary: VisualRiskSummary,
        diet: DietContext
    ) -> [IronHealthInsight] {
        var insights = [IronHealthInsight]()
        if diet == .plantBased {
            insights.append(IronHealthInsight(
                id: .plantBasedAbsorption,
                title: "Plant-based iron absorption",
                detail: "Plant foods contain non-heme iron, which the body generally absorbs less readily than heme iron. Vitamin C can improve non-heme iron absorption; examples include pairing beans or lentils with citrus, tomatoes, or sweet peppers.",
                symbol: "leaf.fill",
                sourceTitle: "NIH Office of Dietary Supplements",
                sourceURL: URL(string: "https://ods.od.nih.gov/factsheets/Iron-Consumer/")
            ))
        }

        switch visualSummary.category {
        case .possibleAnemiaRisk:
            insights.append(IronHealthInsight(
                id: .laboratoryTesting,
                title: "How laboratory testing helps",
                detail: "A tongue image cannot measure iron status. A clinician may use a complete blood count and a ferritin blood test; ferritin is a blood marker related to iron stored in the body and requires clinical interpretation.",
                symbol: "cross.case.fill",
                sourceTitle: "MedlinePlus ferritin blood test",
                sourceURL: URL(string: "https://medlineplus.gov/lab-tests/ferritin-blood-test/")
            ))
        case .lowerObservedRisk:
            insights.append(IronHealthInsight(
                id: .lowerObservedRiskEducation,
                title: "What this visual result means",
                detail: "No visual pallor pattern was highlighted, but this does not confirm normal iron status. General food sources of iron include beans, lentils, leafy greens, fortified grains, lean meat, seafood, and poultry.",
                symbol: "book.closed.fill",
                sourceTitle: "NIH Office of Dietary Supplements",
                sourceURL: URL(string: "https://ods.od.nih.gov/factsheets/Iron-Consumer/")
            ))
        case .unableToAssess:
            break
        }
        return insights
    }
}

struct IronHealthInsightsView: View {
    let visualSummary: VisualRiskSummary
    let diet: DietContext

    private var insights: [IronHealthInsight] {
        IronHealthInsightsBuilder.insights(visualSummary: visualSummary, diet: diet)
    }

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Iron education", systemImage: "lightbulb.fill")
                        .font(.headline)
                    Text("General information only—not a personalized diet or treatment plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }
        }
    }

    private func insightCard(_ insight: IronHealthInsight) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(insight.title, systemImage: insight.symbol)
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let sourceURL = insight.sourceURL {
                Link(destination: sourceURL) {
                    Label(insight.sourceTitle, systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .foregroundColor(.primary)
    }
}
