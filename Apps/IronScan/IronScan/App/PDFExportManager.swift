import SwiftUI
import UIKit

@MainActor
final class PDFExportManager {
    static let shared = PDFExportManager()

    private init() {}

    func exportClinicalPDF(
        timestamp: Date,
        result: TriangulationResult,
        outputs: [TissueSite: TissueScreeningOutput]
    ) throws -> URL {
        let pageSize = CGSize(width: 595.2, height: 841.8)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "IronScan-Clinical-\(stamp).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let content = ClinicalPDFPage(
            timestamp: timestamp,
            result: result,
            outputs: outputs
        )
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(pageSize)
        renderer.scale = 1

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try pdfRenderer.writePDF(to: url) { context in
            context.beginPage()
            renderer.render { _, renderInContext in
                renderInContext(context.cgContext)
            }
        }

        return url
    }
}

private struct ClinicalPDFPage: View {
    let timestamp: Date
    let result: TriangulationResult
    let outputs: [TissueSite: TissueScreeningOutput]

    private var score: Double {
        min(max(result.opticalPallorIndex ?? 0, 0), 1)
    }

    private var tier: ClinicalRiskTier {
        ClinicalRiskTier(score: score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("IronScan Clinical Export")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                Text("Generated \(timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Risk Score")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.65))
                    Text(score.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black)
                    Text(tier.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tier.uiColor.swiftUIColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(tier.uiColor.swiftUIColor.opacity(0.12), in: Capsule())
                }

                Spacer()

                ScoreScaleBlock(score: score, tier: tier)
                    .frame(width: 190, height: 120)
            }
            .padding(20)
            .background(Color(red: 0.98, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("WHO Risk Tier Guide")
                    .font(.system(size: 18, weight: .bold))
                tierRow(color: ClinicalRiskTier.low.uiColor, title: ClinicalRiskTier.low.title, range: ClinicalRiskTier.low.rangeLabel, detail: ClinicalRiskTier.low.explanation)
                tierRow(color: ClinicalRiskTier.moderate.uiColor, title: ClinicalRiskTier.moderate.title, range: ClinicalRiskTier.moderate.rangeLabel, detail: ClinicalRiskTier.moderate.explanation)
                tierRow(color: ClinicalRiskTier.high.uiColor, title: ClinicalRiskTier.high.title, range: ClinicalRiskTier.high.rangeLabel, detail: ClinicalRiskTier.high.explanation)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Tissue Breakdown")
                    .font(.system(size: 18, weight: .bold))

                ForEach(TissueSite.allCases, id: \.self) { tissue in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tissue.displayName)
                                .font(.system(size: 15, weight: .bold))
                            Text(statusText(for: tissue))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.66))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(probabilityText(for: tissue))
                                .font(.system(size: 15, weight: .bold))
                            Text(weightText(for: tissue))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.66))
                        }
                    }
                    .padding(.vertical, 10)

                    if tissue != TissueSite.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }

            Spacer()

            Text("Research prototype only. This PDF summarizes the app’s fused optical risk output and does not establish a medical diagnosis.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func tierRow(color: UIColor, title: String, range: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.swiftUIColor)
                .frame(width: 10, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(range)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.68))
            }
        }
        .padding(14)
        .background(color.swiftUIColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func probabilityText(for tissue: TissueSite) -> String {
        if let output = outputs[tissue] {
            return output.probability.formatted(.number.precision(.fractionLength(2)))
        }
        if let contribution = result.contribution(for: tissue) {
            return contribution.probability.formatted(.number.precision(.fractionLength(2)))
        }
        return "--"
    }

    private func weightText(for tissue: TissueSite) -> String {
        guard let contribution = result.contribution(for: tissue) else { return "Weight unavailable" }
        return "Weight \(contribution.weight.formatted(.percent.precision(.fractionLength(0))))"
    }

    private func statusText(for tissue: TissueSite) -> String {
        guard let contribution = result.contribution(for: tissue) else {
            return "Contribution unavailable."
        }
        switch contribution.status {
        case .included:
            return contribution.proxySignalObserved
                ? "Included with elevated visual proxy signal."
                : "Included with lower visual proxy signal."
        case .uncertainRescanRecommended:
            return "Uncertain contribution; re-scan recommended."
        case .qualityRejected:
            return "Quality rejected for final fusion."
        }
    }
}

private struct ScoreScaleBlock: View {
    let score: Double
    let tier: ClinicalRiskTier

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scale")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.6))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ClinicalRiskTier.low.uiColor.swiftUIColor,
                                    ClinicalRiskTier.moderate.uiColor.swiftUIColor,
                                    ClinicalRiskTier.high.uiColor.swiftUIColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(tier.uiColor.swiftUIColor, lineWidth: 3)
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                        .offset(x: max(0, (geometry.size.width - 18) * score))
                }
            }
            .frame(height: 18)

            HStack {
                Text("0.00")
                Spacer()
                Text("1.00")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.55))
        }
    }
}

private enum ClinicalRiskTier {
    case low
    case moderate
    case high

    init(score: Double) {
        if score <= 0.30 {
            self = .low
        } else if score < 0.70 {
            self = .moderate
        } else {
            self = .high
        }
    }

    var title: String {
        switch self {
        case .low: "Low Risk"
        case .moderate: "Moderate Risk"
        case .high: "High Risk"
        }
    }

    var rangeLabel: String {
        switch self {
        case .low: "0.00 - 0.30"
        case .moderate: "0.30 - 0.70"
        case .high: "0.70 - 1.00"
        }
    }

    var explanation: String {
        switch self {
        case .low:
            "Lower fused visual signal across the three tissue sites."
        case .moderate:
            "Intermediate fused signal that benefits from follow-up context and repeat review."
        case .high:
            "Higher fused visual signal that should be clinically confirmed with lab testing."
        }
    }

    var uiColor: UIColor {
        switch self {
        case .low:
            UIColor(red: 141 / 255, green: 170 / 255, blue: 130 / 255, alpha: 1)
        case .moderate:
            UIColor(red: 242 / 255, green: 199 / 255, blue: 71 / 255, alpha: 1)
        case .high:
            UIColor(red: 1, green: 107 / 255, blue: 53 / 255, alpha: 1)
        }
    }
}

private extension UIColor {
    var swiftUIColor: Color {
        Color(uiColor: self)
    }
}
