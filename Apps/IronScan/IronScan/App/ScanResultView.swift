import SwiftUI

struct ScanResultView: View {
    let result: TriangulationResult
    let outputs: [TissueSite: TissueScreeningOutput]
    var onScanAgain: (() -> Void)? = nil

    private var score: Double {
        min(max(result.opticalPallorIndex ?? 0.32, 0), 1)
    }

    private var riskBand: ResultRiskBand {
        ResultRiskBand(score: score)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let horizontalPadding = min(max(geometry.size.width * 0.06, 18), 42)
                let contentWidth = min(geometry.size.width - (horizontalPadding * 2), 620)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Your Result")
                                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                                .foregroundStyle(IronTheme.textSlate)

                            gaugeCard
                            summaryCard

                            NavigationLink {
                                MedicalTiersView()
                            } label: {
                                IronCTAButtonLabel(title: "View Details")
                            }
                            .buttonStyle(OrganicPrimaryButtonStyle())

                            if let onScanAgain {
                                Button("Scan Again", action: onScanAgain)
                                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                                    .foregroundStyle(IronTheme.textMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                }
                .background(IronScreenBackground())
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var gaugeCard: some View {
        VStack(spacing: 18) {
            SemiCircularResultGauge(score: score)
                .frame(height: 240)

            VStack(spacing: 8) {
                Text(riskBand.title)
                    .font(IronTheme.roundedFont(.title2, weight: .bold))
                    .foregroundStyle(riskBand.color)

                Text("of Iron Deficiency")
                    .font(IronTheme.roundedFont(.title3))
                    .foregroundStyle(IronTheme.textMuted)
            }
        }
        .padding(22)
        .liquidGlassCard()
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: riskBand.iconName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(riskBand.color)
                .frame(width: 38, height: 38)
                .background(riskBand.color.opacity(0.14), in: Circle())

            Text(summaryText)
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .foregroundStyle(IronTheme.textSlate)

            Spacer(minLength: 0)
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 22)
    }

    private var summaryText: String {
        switch result.summary {
        case .lowerObservedRisk:
            "Your tongue shows healthy coloration and patterns."
        case .possibleAnemiaRisk:
            "Your scan shows possible pallor patterns. Consider follow-up."
        case .unableToAssess:
            "We could not confidently assess this scan. A rescan may help."
        }
    }
}

struct MedicalTiersView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("What Does This Mean?")
                    .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)
                    .padding(.top, 16)

                TierInfoCard(
                    icon: "face.smiling.fill",
                    tint: .green,
                    range: "0.00 – 0.30",
                    title: "Low Risk",
                    description: "Normal tongue coloration pattern."
                )
                TierInfoCard(
                    icon: "face.neutral.fill",
                    tint: .yellow,
                    range: "0.30 – 0.70",
                    title: "Moderate Risk",
                    description: "Possible pallor. Consider follow-up."
                )
                TierInfoCard(
                    icon: "exclamationmark.triangle.fill",
                    tint: IronTheme.terracottaPrimary,
                    range: "0.70 – 1.00",
                    title: "High Risk",
                    description: "Increased likelihood of anemia. Consult a healthcare provider."
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(IronScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SemiCircularResultGauge: View {
    let score: Double

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(
                    LinearGradient(
                        colors: [.green, .yellow, IronTheme.terracottaPrimary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(180))
                .padding(12)

            Circle()
                .trim(from: 0.5, to: 0.5 + (score * 0.5))
                .stroke(
                    Color.white.opacity(0.78),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(180))
                .padding(24)

            VStack(spacing: 8) {
                Text(score.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(ResultRiskBand(score: score).shortTitle)
                    .font(IronTheme.roundedFont(.title2, weight: .bold))
                    .foregroundStyle(ResultRiskBand(score: score).color)
            }
            .offset(y: 24)
        }
    }
}

private struct TierInfoCard: View {
    let icon: String
    let tint: Color
    let range: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(range)
                    .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)
                Text(description)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .liquidGlassCard()
    }
}

private struct ResultRiskBand {
    let title: String
    let shortTitle: String
    let color: Color
    let iconName: String

    init(score: Double) {
        switch score {
        case ..<0.30:
            title = "Low Risk"
            shortTitle = "Low Risk"
            color = .green
            iconName = "checkmark.circle.fill"
        case ..<0.70:
            title = "Moderate Risk"
            shortTitle = "Moderate"
            color = .yellow
            iconName = "exclamationmark.circle.fill"
        default:
            title = "High Risk"
            shortTitle = "High Risk"
            color = IronTheme.terracottaPrimary
            iconName = "exclamationmark.triangle.fill"
        }
    }
}
