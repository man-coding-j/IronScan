import SwiftUI

struct HumanResultsView: View {
    let report: TongueVisualAttributeReport
    let onScanAgain: () -> Void

    private var summary: FriendlyScanSummary {
        ResultTranslator.translate(report)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            overallBanner
            ForEach(summary.cards) { card in
                resultCard(card)
            }
            nextStepsBox
            disclaimer
            Button {
                onScanAgain()
            } label: {
                Label("Run another live scan", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }

    private var overallBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(themeColor(summary.theme))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.theme == .attention ? "eye.trianglebadge.exclamationmark" : "eye.circle.fill")
                    .font(.title)
                    .foregroundStyle(themeColor(summary.theme))
                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.title)
                        .font(.title2.weight(.bold))
                    Text(summary.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeColor(summary.theme).opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
    }

    private func resultCard(_ card: FriendlyResultCard) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(themeColor(card.theme))
                .frame(width: 38, height: 38)
                .background(themeColor(card.theme).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.status)
                    .font(.headline)
                Text(card.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(themeColor(card.theme))
                .frame(width: 4)
        }
    }

    private var nextStepsBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What can I do next?", systemImage: "checklist")
                .font(.headline)
            ForEach(summary.nextSteps, id: \.self) { step in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var disclaimer: some View {
        Label(summary.disclaimer, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func themeColor(_ theme: ResultTheme) -> Color {
        switch theme {
        case .neutral: .gray
        case .calm: .blue
        case .attention: .orange
        }
    }
}
