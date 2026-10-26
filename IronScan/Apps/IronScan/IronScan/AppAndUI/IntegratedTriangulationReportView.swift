import SwiftUI

struct IntegratedTriangulationReportView: View {
    let result: TriangulationResult
    let outputs: [TissueSite: TissueScreeningOutput]
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Image(systemName: result.summary == .unableToAssess ? "questionmark.circle.fill" : "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(summaryColor)
            }
            Text(summaryTitle)
                .font(.title2.weight(.bold))
            Text(summaryDetail)
                .foregroundStyle(.secondary)

            Divider()
            ForEach(TissueSite.allCases, id: \.self) { tissue in
                HStack {
                    Label(tissue.displayName, systemImage: tissue.iconName)
                    Spacer()
                    Text(outputText(for: tissue))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(outputColor(for: tissue))
                }
            }

            Text("Research prototype — confirm with a laboratory test.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: onReset) {
                Label("Run the three-step scan again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                .fill(summaryColor)
                .frame(width: 5)
        }
    }

    private var summaryTitle: String {
        switch result.summary {
        case .lowerObservedRisk: "Lower observed risk"
        case .possibleAnemiaRisk: "Possible anemia risk"
        case .unableToAssess: "Unable to assess"
        }
    }

    private var summaryDetail: String {
        switch result.summary {
        case .lowerObservedRisk: "The three image models produced a lower combined visual proxy signal."
        case .possibleAnemiaRisk: "The three image models produced a possible combined visual pallor signal."
        case .unableToAssess: result.rejectionReasons.first ?? "One or more scans could not be combined."
        }
    }

    private var summaryColor: Color {
        switch result.summary {
        case .lowerObservedRisk: .green
        case .possibleAnemiaRisk: .orange
        case .unableToAssess: .gray
        }
    }

    private func outputText(for tissue: TissueSite) -> String {
        guard let output = outputs[tissue] else { return "Not available" }
        return output.proxySignalObserved ? "Visual proxy signal observed" : "Lower proxy signal"
    }

    private func outputColor(for tissue: TissueSite) -> Color {
        outputs[tissue]?.proxySignalObserved == true ? .orange : .green
    }
}
