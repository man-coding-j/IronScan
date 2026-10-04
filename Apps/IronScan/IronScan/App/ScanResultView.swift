import SwiftUI
import UIKit

struct ScanResultView: View {
    @Environment(\.openURL) private var openURL
    let result: TriangulationResult
    let outputs: [TissueSite: TissueScreeningOutput]
    let tissueImages: [TissueSite: UIImage]
    var onScanAgain: (() -> Void)? = nil
    @Namespace private var glassNamespace
    @State private var selectedTissue: TissueSite = .eye
    @State private var shareDocument: ShareablePDFDocument?
    @State private var exportError: String?
    @State private var isGeneratingDoctorReport = false

    private var score: Double {
        min(max(result.opticalPallorIndex ?? 0.32, 0), 1)
    }

    private var availableTissues: [TissueSite] {
        if !result.analyzedTissues.isEmpty {
            return result.analyzedTissues
        }
        return TissueSite.allCases.filter { outputs[$0] != nil }
    }

    private var riskBand: ResultRiskBand {
        ResultRiskBand(score: score)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let horizontalPadding = min(max(geometry.size.width * 0.06, 18), 42)
                let availableWidth = max(geometry.size.width - (horizontalPadding * 2), 0)
                let contentWidth = max(0, min(availableWidth, 620))

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

            if result.isCriticalEmergency {
                emergencyBannerCard
            }

            gaugeCard
            summaryCard
            calibrationBadge
            tissueDetailCard
            tissueBreakdownCard
            clinicalContextCard
            actionBar

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
        .frame(maxWidth: max(0, contentWidth))
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
        .onAppear {
            if !availableTissues.contains(selectedTissue), let fallback = availableTissues.first {
                selectedTissue = fallback
            }
        }
    }

    private var emergencyBannerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.red)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Urgent Medical Evaluation Advised")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Your reported symptoms or estimated optical pallor indicate potential severe physiological strain. Please seek immediate evaluation at an urgent care or emergency medical facility.")
                        .font(IronTheme.roundedFont(.subheadline, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
            }

            HStack(spacing: 12) {
                Button {
                    callEmergencyServices()
                } label: {
                    Label("Find Nearest Emergency Services", systemImage: "cross.case.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OrganicPrimaryButtonStyle())

                Button {
                    openEmergencyMapSearch()
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.82), IronTheme.warning.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
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

            HStack(alignment: .top, spacing: 14) {
                metricPill(
                    title: "Estimated Hemoglobin",
                    value: result.estimatedHemoglobin.map {
                        "\($0.formatted(.number.precision(.fractionLength(1)))) g/dL"
                    } ?? "Unavailable",
                    tint: IronTheme.textSlate
                )

                metricPill(
                    title: "Severity",
                    value: result.severity.rawValue.capitalized,
                    tint: result.severity.themeColor
                )
            }

            VStack(spacing: 8) {
                Text(riskBand.title)
                    .font(IronTheme.roundedFont(.title2, weight: .bold))
                    .foregroundStyle(riskBand.color)

                Text(result.reliabilityLabel)
                    .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                Text("Prototype estimate only. Confirm with a CBC or lab hemoglobin test.")
                    .font(IronTheme.roundedFont(.caption, weight: .semibold))
                    .foregroundStyle(IronTheme.textMuted)
                    .multilineTextAlignment(.center)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(summaryText)
                    .font(IronTheme.roundedFont(.body, weight: .medium))
                    .foregroundStyle(IronTheme.textSlate)

                Text(result.severity.clinicalDescription)
                    .font(IronTheme.roundedFont(.caption, weight: .semibold))
                    .foregroundStyle(result.severity.themeColor)

                if let modalityNotice {
                    Text(modalityNotice)
                        .font(IronTheme.roundedFont(.caption, weight: .semibold))
                        .foregroundStyle(IronTheme.textMuted)
                }
            }

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

            Text("Calibrated for: \(result.calibrationCategory.rawValue)")
                .font(IronTheme.roundedFont(.subheadline, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Spacer()
        }
        .padding(16)
        .resultContentCard(cornerRadius: 22)
    }

    private var tissueBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tissue Breakdown")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            ForEach(result.contributions, id: \.tissue.rawValue) { contribution in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(displayName(for: contribution.tissue))
                            .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                            .foregroundStyle(IronTheme.textSlate)

                        if let sourceImage = tissueImages[contribution.tissue] {
                            HeatmapThumbnailView(image: sourceImage)
                        }

                        Spacer()

                        Text(contributionStatusTitle(for: contribution))
                            .font(IronTheme.roundedFont(.caption, weight: .bold))
                            .foregroundStyle(contributionStatusColor(for: contribution))

                        Circle()
                            .fill(contributionColor(for: contribution))
                            .frame(width: 10, height: 10)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.28))
                            Capsule()
                                .fill(contributionColor(for: contribution))
                                .frame(width: max(0, geometry.size.width * contributionBarValue(for: contribution)))
                        }
                    }
                    .frame(height: 10)

                    Text(contributionFootnote(for: contribution))
                        .font(IronTheme.roundedFont(.caption))
                        .foregroundStyle(IronTheme.textMuted)
                }
            }
        }
        .padding(18)
        .resultContentCard(cornerRadius: 22)
    }

    private var clinicalContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clinical Context")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Text("Educational purposes only. Not a medical diagnosis.")
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(IronTheme.warning)

            Text(clinicalContextText)
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textMuted)
        }
        .padding(18)
        .resultContentCard(cornerRadius: 22)
    }

    private var summaryText: String {
        switch result.summary {
        case .lowerObservedRisk:
            return result.analyzedTissues.count == 1
                ? "Your single-site scan showed lower visual pallor patterns."
                : "Your combined scan showed lower overall pallor patterns."
        case .possibleAnemiaRisk:
            return result.analyzedTissues.count == 1
                ? "Your single-site scan showed possible pallor patterns. Consider follow-up."
                : "Your multi-site scan showed possible pallor patterns. Consider follow-up."
        case .unableToAssess:
            return "We could not confidently assess this scan. A rescan may help."
        }
    }

    private var clinicalContextText: String {
        if result.analyzedTissues.count == 1 {
            return "This estimate was generated from a single tissue site, so reliability is lower than a full multi-site session. Please prioritize confirmatory laboratory testing if symptoms persist."
        }
        switch result.severity {
        case .moderate, .severe:
            return "While iron deficiency is the most common cause of these pallor patterns, other potential factors include Vitamin B12 deficiency, chronic inflammation, or acute blood loss. Please consult a physician for a complete blood count (CBC) test."
        case .normal, .mild:
            return "This prototype result suggests lower overall concern, but symptoms, nutrition status, and other clinical findings still matter when interpreting pallor."
        }
    }

    private var modalityNotice: String? {
        guard !result.analyzedTissues.isEmpty else { return nil }
        let analyzed = formattedTissueList(result.analyzedTissues)
        guard !result.omittedTissues.isEmpty else {
            return "Calculated using \(analyzed) analysis."
        }
        let omitted = formattedTissueList(result.omittedTissues)
        return "Calculated using \(analyzed) analysis (\(omitted) omitted)."
    }

    private var selectedOutputStatus: String {
        if result.omittedTissues.contains(selectedTissue) {
            return "Omitted"
        }
        guard let output = outputs[selectedTissue] else { return "Unavailable" }
        guard output.qualityAccepted else { return "Re-scan" }
        return output.proxySignalObserved ? "Signal Observed" : "Lower Signal"
    }

    private var selectedOutputDetail: String {
        if result.omittedTissues.contains(selectedTissue) {
            return "\(displayName(for: selectedTissue)) was omitted from this calculation."
        }
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
        if result.omittedTissues.contains(selectedTissue) { return IronTheme.textSecondary }
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

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(IronTheme.textMuted)
                .textCase(.uppercase)

            Text(value)
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await exportClinicalReport()
                }
            } label: {
                HStack(spacing: 12) {
                    if isGeneratingDoctorReport {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text(isGeneratingDoctorReport ? "Preparing Doctor Report..." : "Download Doctor Report (PDF)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }
            .buttonStyle(OrganicPrimaryButtonStyle())
            .disabled(isGeneratingDoctorReport)

            NavigationLink {
                MedicalTiersView()
            } label: {
                IronCTAButtonLabel(title: "View Details")
            }
            .buttonStyle(OrganicPrimaryButtonStyle())
        }
        .padding(18)
        .resultContentCard(cornerRadius: 24)
    }

    private func displayName(for tissue: TissueSite) -> String {
        switch tissue {
        case .eye:
            return "Conjunctiva"
        case .nail:
            return "Lip"
        case .tongue:
            return "Tongue"
        }
    }

    private func formattedTissueList(_ tissues: [TissueSite]) -> String {
        let labels = tissues
            .sorted(by: tissueDisplayPriority)
            .map(displayName(for:))
        switch labels.count {
        case 0:
            return "no tissues"
        case 1:
            return labels[0]
        case 2:
            return "\(labels[0]) + \(labels[1])"
        default:
            return labels.dropLast().joined(separator: ", ") + " + " + (labels.last ?? "")
        }
    }

    private func tissueDisplayPriority(_ lhs: TissueSite, _ rhs: TissueSite) -> Bool {
        tissueDisplayOrderIndex(lhs) < tissueDisplayOrderIndex(rhs)
    }

    private func tissueDisplayOrderIndex(_ tissue: TissueSite) -> Int {
        switch tissue {
        case .eye:
            return 0
        case .tongue:
            return 1
        case .nail:
            return 2
        }
    }

    private func contributionStatusTitle(for contribution: TissueContribution) -> String {
        switch contribution.status {
        case .included:
            return contribution.proxySignalObserved ? "Flagged" : "Normal"
        case .uncertainRescanRecommended:
            return "Uncertain"
        case .qualityRejected:
            return "Rejected"
        case .omitted:
            return "Omitted"
        }
    }

    private func contributionStatusColor(for contribution: TissueContribution) -> Color {
        switch contribution.status {
        case .included:
            return contribution.proxySignalObserved ? IronTheme.warning : .green
        case .uncertainRescanRecommended, .qualityRejected:
            return .orange
        case .omitted:
            return IronTheme.textSecondary
        }
    }

    private func contributionFootnote(for contribution: TissueContribution) -> String {
        switch contribution.status {
        case .included:
            return "Contribution weight \(contribution.weight.formatted(.percent.precision(.fractionLength(0))))"
        case .uncertainRescanRecommended:
            return "Excluded due to elevated uncertainty."
        case .qualityRejected:
            return "Excluded because image quality was not accepted."
        case .omitted:
            return "This modality was skipped for the current calculation."
        }
    }

    private func contributionBarValue(for contribution: TissueContribution) -> CGFloat {
        CGFloat(min(max(contribution.weight == 0 ? contribution.probability : contribution.weight, 0), 1))
    }

    private func contributionColor(for contribution: TissueContribution) -> Color {
        switch contribution.status {
        case .included:
            return contribution.proxySignalObserved ? result.severity.themeColor : IronTheme.sageAccent
        case .uncertainRescanRecommended, .qualityRejected:
            return IronTheme.warning
        case .omitted:
            return IronTheme.textSecondary
        }
    }

    private func exportClinicalReport() async {
        guard !isGeneratingDoctorReport else { return }
        isGeneratingDoctorReport = true
        defer { isGeneratingDoctorReport = false }

        let demographicProfile = DemographicProfileStore.load()
        let heatmaps = await buildHeatmaps()
        let pdfData = ClinicalReportGenerator.generatePDF(
            result: result,
            demographicProfile: demographicProfile,
            images: tissueImages,
            heatmaps: heatmaps
        )

        do {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("IronScan_Clinical_Research_Summary_\(UUID().uuidString).pdf")
            try pdfData.write(to: outputURL, options: .atomic)
            shareDocument = ShareablePDFDocument(url: outputURL)
        } catch {
            exportError = "The PDF could not be created."
        }
    }

    private func callEmergencyServices() {
        guard let emergencyURL = URL(string: "tel://911") else {
            openEmergencyMapSearch()
            return
        }
        openURL(emergencyURL)
    }

    private func openEmergencyMapSearch() {
        guard let mapsURL = URL(string: "http://maps.apple.com/?q=Emergency%20Services") else { return }
        openURL(mapsURL)
    }

    private func buildHeatmaps() async -> [TissueSite: UIImage] {
        await withTaskGroup(of: (TissueSite, UIImage?).self, returning: [TissueSite: UIImage].self) { group in
            for (tissue, image) in tissueImages {
                let encodedImage = image.jpegData(compressionQuality: 0.9)
                group.addTask {
                    guard let encodedImage,
                          let image = UIImage(data: encodedImage) else {
                        return (tissue, nil)
                    }
                    let heatmap = await SaliencyHeatmapGenerator.generateHeatmap(from: image)
                    return (tissue, heatmap)
                }
            }

            var results = [TissueSite: UIImage]()
            for await (tissue, heatmap) in group {
                if let heatmap {
                    results[tissue] = heatmap
                }
            }
            return results
        }
    }
}

private struct HeatmapThumbnailView: View {
    let image: UIImage

    @State private var heatmapImage: UIImage?

    var body: some View {
        Group {
            if let heatmapImage {
                Image(uiImage: heatmapImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
        .task {
            heatmapImage = await SaliencyHeatmapGenerator.generateHeatmap(from: image)
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
        liquidGlassCard(cornerRadius: cornerRadius, interactive: true)
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

struct ShareablePDFDocument: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

class PDFReportGenerator {
    static func generateReport(for result: Any?, history: [Any]? = nil) -> URL? {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("IronScan_Report.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let summaryText: String = {
            if let triangulation = result as? TriangulationResult {
                switch triangulation.summary {
                case .lowerObservedRisk:
                    return "Lower observed risk"
                case .possibleAnemiaRisk:
                    return "Possible anemia risk"
                case .unableToAssess:
                    return "Unable to assess"
                }
            }

            if let record = result as? ScanHistoryRecord {
                return record.summary
            }

            return "No scan summary available."
        }()

        let timestampText: String = {
            if result is TriangulationResult {
                return DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            }

            if let record = result as? ScanHistoryRecord {
                return DateFormatter.localizedString(from: record.capturedAt, dateStyle: .medium, timeStyle: .short)
            }

            return DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        }()

        let historyCount = history?.count ?? 0

        do {
            try renderer.writePDF(to: outputURL) { context in
                context.beginPage()

                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                let headingAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.darkGray
                ]
                let bodyAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                let noteAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]

                let margin: CGFloat = 48
                var cursorY: CGFloat = 56

                NSString(string: "IronScan Medical Summary").draw(
                    at: CGPoint(x: margin, y: cursorY),
                    withAttributes: titleAttributes
                )
                cursorY += 48

                NSString(string: "Generated").draw(
                    at: CGPoint(x: margin, y: cursorY),
                    withAttributes: headingAttributes
                )
                cursorY += 22

                NSString(string: timestampText).draw(
                    in: CGRect(x: margin, y: cursorY, width: bounds.width - margin * 2, height: 24),
                    withAttributes: bodyAttributes
                )
                cursorY += 52

                NSString(string: "Diagnostic Summary").draw(
                    at: CGPoint(x: margin, y: cursorY),
                    withAttributes: headingAttributes
                )
                cursorY += 24

                NSString(string: summaryText).draw(
                    in: CGRect(x: margin, y: cursorY, width: bounds.width - margin * 2, height: 60),
                    withAttributes: bodyAttributes
                )
                cursorY += 84

                NSString(string: "Stored History Count").draw(
                    at: CGPoint(x: margin, y: cursorY),
                    withAttributes: headingAttributes
                )
                cursorY += 24

                NSString(string: "\(historyCount) scan record(s)").draw(
                    in: CGRect(x: margin, y: cursorY, width: bounds.width - margin * 2, height: 24),
                    withAttributes: bodyAttributes
                )
                cursorY += 52

                let disclaimer = "Research prototype only. IronScan does not diagnose anemia or any medical condition. Confirm all findings with a licensed physician and laboratory testing."
                NSString(string: disclaimer).draw(
                    in: CGRect(x: margin, y: cursorY, width: bounds.width - margin * 2, height: 120),
                    withAttributes: noteAttributes
                )
            }

            return outputURL
        } catch {
            return nil
        }
    }
}
