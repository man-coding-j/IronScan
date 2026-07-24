import SwiftUI

enum HealthGuidanceContent {
    static let hemeAndNonHeme = "Heme iron is found in animal foods such as meat, poultry, and seafood. Non-heme iron is found in plant foods such as lentils, beans, spinach, and fortified grains."
    static let vitaminC = "Vitamin C can improve absorption of non-heme iron from plant foods. Examples include pairing beans or leafy greens with citrus, tomatoes, berries, or bell peppers."
    static let inhibitors = "Calcium and compounds in coffee or tea may reduce iron absorption when consumed with an iron-containing meal. Individual dietary needs vary, so discuss concerns with a licensed clinician or dietitian."
}

struct HealthGuidanceView: View {
    let plan: PersonalizedIronPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            generalWellnessSection
            personalizedPlanSection
        }
    }

    private var generalWellnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("General Iron Wellness", systemImage: "book.closed.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(IronTheme.textDark)
                Text("General education only—not a personalized diet or treatment plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GuidanceDisclosureCard(
                title: "Heme vs. Non-Heme Iron",
                symbol: "leaf.circle.fill",
                detail: HealthGuidanceContent.hemeAndNonHeme
            )
            GuidanceDisclosureCard(
                title: "The Vitamin C Synergy",
                symbol: "sun.max.fill",
                detail: HealthGuidanceContent.vitaminC
            )
            GuidanceDisclosureCard(
                title: "Inhibitors Alert",
                symbol: "cup.and.saucer.fill",
                detail: HealthGuidanceContent.inhibitors
            )

            if let sourceURL = URL(string: "https://ods.od.nih.gov/factsheets/Iron-Consumer/") {
                Link(destination: sourceURL) {
                    Label("NIH iron information", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var personalizedPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Your Personalized Iron Action Plan", systemImage: "list.clipboard.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                Text("Research follow-up guidance based on the displayed optical category and optional local context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(plan.title)
                    .font(.headline)
                    .foregroundStyle(IronTheme.textDark)
                Text(plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(plan.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(IronTheme.textDark)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(plan.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var tint: Color {
        switch plan.tone {
        case .routine: .green
        case .monitor: IronTheme.warning
        case .laboratoryConfirmation: .orange
        case .unableToAssess: .gray
        }
    }
}

private struct GuidanceDisclosureCard: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        DisclosureGroup {
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(IronTheme.textDark)
        }
        .tint(IronTheme.tealPrimary)
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }
}
