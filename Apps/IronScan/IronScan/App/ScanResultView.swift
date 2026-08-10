import SwiftUI

struct ScanResultView: View {
    @EnvironmentObject private var dependencies: IronScanAppDependencies
    let result: TriangulationResult
    let outputs: [TissueSite: TissueScreeningOutput]
    var onScanAgain: (() -> Void)? = nil
    @Namespace private var glassNamespace
    @State private var selectedTissue: TissueSite = .eye
    @State private var shareDocument: ShareablePDFDocument?
    @State private var exportError: String?

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
                        resultContent(contentWidth: contentWidth, horizontalPadding: horizontalPadding)
                    }
                }
                .background(IronScreenBackground())
                .safeAreaInset(edge: .top) {
                    floatingTissueFilters
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 4)
                }
            }
            .navigationTitle("Diagnostic Results")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func resultContent(contentWidth: CGFloat, horizontalPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your Result")
                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)
                .padding(.top, 4)

            gaugeCard
            summaryCard
            calibrationBadge
            tissueDetailCard

            Button(action: exportPDF) {
                IronCTAButtonLabel(title: "Export PDF for Doctor")
            }
            .buttonStyle(OrganicPrimaryButtonStyle())

            NavigationLink {
                MedicalTiersView()
            } label: {
                IronCTAButtonLabel(title: "View Details")
            }
            .buttonStyle(OrganicPrimaryButtonStyle())

            if let onScanAgain {
                Button("Scan Again") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        onScanAgain()
                    }
                }
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .liquidGlassButtonStyle()
            }
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .sheet(item: $shareDocument) { document in
            ActivityShareSheet(activityItems: [document.url])
        }
        .alert("PDF Export Unavailable", isPresented: exportAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "The PDF could not be created.")
        }
    }

    private var floatingTissueFilters: some View {
        HStack {
            Spacer()

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(TissueSite.allCases, id: \.self) { tissue in
                            tissueFilterChip(for: tissue)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(TissueSite.allCases, id: \.self) { tissue in
                        tissueFilterChip(for: tissue)
                    }
                }
            }
        }
    }

    private func tissueFilterChip(for tissue: TissueSite) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedTissue = tissue
            }
        } label: {
            Label(tissue.glassTitle, systemImage: tissue.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTissue == tissue ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .resultGlassCapsule(
            id: "result.filter.\(tissue.rawValue)",
            in: glassNamespace,
            active: selectedTissue == tissue
        )
        .buttonStyle(.plain)
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
        .resultContentCard(cornerRadius: 24)
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
        .resultContentCard(cornerRadius: 22)
    }

    private var tissueDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(selectedTissue.glassTitle, systemImage: selectedTissue.iconName)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                Spacer()

                Text(selectedOutputStatus)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedOutputColor)
            }

            Text(selectedOutputDetail)
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .foregroundStyle(IronTheme.textMuted)

            if let output = outputs[selectedTissue] {
                VStack(alignment: .leading, spacing: 8) {
                    metricRow("Probability", value: output.probability.formatted(.percent.precision(.fractionLength(0))))
                    metricRow("Threshold", value: output.lockedThreshold.formatted(.percent.precision(.fractionLength(0))))
                    metricRow("Quality", value: output.qualityAccepted ? "Accepted" : "Rejected")
                }
            }
        }
        .padding(18)
        .resultContentCard(cornerRadius: 22)
    }

    private var calibrationBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IronTheme.terracottaPrimary)

            Text("Calibrated for: \(result.calibrationCategory.badgeTitle)")
                .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Spacer()
        }
        .padding(16)
        .resultContentCard(cornerRadius: 22)
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

    private var selectedOutputStatus: String {
        guard let output = outputs[selectedTissue] else { return "Unavailable" }
        guard output.qualityAccepted else { return "Re-scan" }
        return output.proxySignalObserved ? "Signal Observed" : "Lower Signal"
    }

    private var selectedOutputDetail: String {
        guard let output = outputs[selectedTissue] else {
            return "No local output is available for this tissue in the current result."
        }
        guard output.qualityAccepted else {
            return output.rejectionReasons.first ?? "Image quality was not accepted for this tissue."
        }
        return output.proxySignalObserved
            ? "\(selectedTissue.glassTitle) contributed a possible visual pallor signal to the combined result."
            : "\(selectedTissue.glassTitle) contributed a lower visual pallor signal to the combined result."
    }

    private var selectedOutputColor: Color {
        guard let output = outputs[selectedTissue] else { return .gray }
        guard output.qualityAccepted else { return .orange }
        return output.proxySignalObserved ? IronTheme.warning : .green
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(IronTheme.textSlate)
        }
        .font(IronTheme.roundedFont(.subheadline))
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private func exportPDF() {
        do {
            let history = dependencies.history?.records ?? []
            let url = try PDFReportGenerator.shared.generateDoctorReport(
                result: result,
                outputs: outputs,
                history: history
            )
            shareDocument = ShareablePDFDocument(url: url)
        } catch {
            exportError = error.localizedDescription
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
        .resultContentCard(cornerRadius: 24)
    }
}

private struct ResultGlassCapsuleModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(active ? IronTheme.cardGlass.opacity(0.92) : IronTheme.cardGlass.opacity(0.72))
                        .interactive(),
                    in: Capsule()
                )
                .glassEffectID(id, in: namespace)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background((active ? IronTheme.cardGlass.opacity(0.8) : IronTheme.cardGlass.opacity(0.56)), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                }
        }
    }
}

private extension View {
    func resultContentCard(cornerRadius: CGFloat = 24) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
            }
    }

    func resultGlassCapsule(id: String, in namespace: Namespace.ID, active: Bool) -> some View {
        modifier(ResultGlassCapsuleModifier(id: id, namespace: namespace, active: active))
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

extension TissueSite {
    var glassTitle: String {
        switch self {
        case .eye:
            "Conjunctiva"
        case .nail:
            "Nail"
        case .tongue:
            "Tongue"
        }
    }

    var iconName: String {
        switch self {
        case .eye:
            "eye.fill"
        case .nail:
            "hand.raised.fill"
        case .tongue:
            "mouth.fill"
        }
    }
}
