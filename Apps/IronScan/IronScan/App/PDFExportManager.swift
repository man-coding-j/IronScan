import SwiftUI
import UIKit

struct PDFLatestDiagnosticResult: Sendable {
    let tissueSummary: String
    let riskScore: Double?
    let qualitativeFindings: String
}

struct PDFReportPayload: Sendable {
    let generatedAt: Date
    let profile: DemographicProfile
    let calibrationCategory: DemographicCalibrationCategory
    let latestDiagnosticResult: PDFLatestDiagnosticResult
    let history: [ScanHistoryRecord]
}

@MainActor
final class PDFReportGenerator {
    static let shared = PDFReportGenerator()

    private init() {}

    func generateDoctorReport(
        result: TriangulationResult,
        outputs: [TissueSite: TissueScreeningOutput],
        history: [ScanHistoryRecord],
        defaults: UserDefaults = .standard
    ) throws -> URL {
        let payload = PDFReportPayload(
            generatedAt: Date(),
            profile: DemographicProfileStore.load(defaults: defaults),
            calibrationCategory: result.calibrationCategory,
            latestDiagnosticResult: PDFLatestDiagnosticResult(
                tissueSummary: tissueSummary(from: result, outputs: outputs),
                riskScore: result.opticalPallorIndex,
                qualitativeFindings: qualitativeFindings(for: result)
            ),
            history: history
        )
        return try generateDoctorReport(payload: payload)
    }

    func generateDoctorReport(
        latestRecord: ScanHistoryRecord?,
        history: [ScanHistoryRecord],
        defaults: UserDefaults = .standard
    ) throws -> URL {
        let profile = DemographicProfileStore.load(defaults: defaults)
        let calibrationCategory = latestRecord?.calibrationCategory ?? profile.calibration.category
        let payload = PDFReportPayload(
            generatedAt: Date(),
            profile: profile,
            calibrationCategory: calibrationCategory,
            latestDiagnosticResult: PDFLatestDiagnosticResult(
                tissueSummary: latestRecord?.tissues.isEmpty == false
                    ? latestRecord?.tissues.joined(separator: ", ") ?? "Multi-tissue screening"
                    : "Multi-tissue screening",
                riskScore: latestRecord?.opticalPatternIndex,
                qualitativeFindings: latestRecord.map { qualitativeFindings(for: $0) } ?? "No completed scan has been saved yet."
            ),
            history: history
        )
        return try generateDoctorReport(payload: payload)
    }

    func generateDoctorReport(payload: PDFReportPayload) throws -> URL {
        let pageSize = CGSize(width: 595.2, height: 841.8)
        let fileName = "IronScan-Doctor-Report-\(timestampSlug(for: payload.generatedAt)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let page = PDFReportPage(payload: payload)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .background(Color.white)

        let renderer = ImageRenderer(content: page)
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

    private func timestampSlug(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    private func tissueSummary(
        from result: TriangulationResult,
        outputs: [TissueSite: TissueScreeningOutput]
    ) -> String {
        let included = result.contributions
            .filter { $0.status == .included }
            .map { $0.tissue.glassTitle }
        if !included.isEmpty {
            return included.joined(separator: ", ")
        }
        let available = TissueSite.allCases.compactMap { tissue in
            outputs[tissue] != nil ? tissue.glassTitle : nil
        }
        return available.isEmpty ? "Multi-tissue screening" : available.joined(separator: ", ")
    }

    private func qualitativeFindings(for result: TriangulationResult) -> String {
        switch result.summary {
        case .lowerObservedRisk:
            return "Lower observed visual pallor signal across the completed scan."
        case .possibleAnemiaRisk:
            return "Possible visual pallor signal detected. Laboratory confirmation is recommended."
        case .unableToAssess:
            return result.rejectionReasons.first ?? "The scan could not be assessed confidently."
        }
    }

    private func qualitativeFindings(for record: ScanHistoryRecord) -> String {
        switch record.summary {
        case .lowerObservedRisk:
            return "Lower observed visual pallor signal across the saved scan."
        case .possibleAnemiaRisk:
            return "Possible visual pallor signal detected in the saved scan."
        case .unableToAssess:
            return "This saved scan was marked unable to assess."
        }
    }
}

private struct PDFReportPage: View {
    let payload: PDFReportPayload

    private var versionString: String {
        Bundle.main.ironScanDisplayVersion
    }

    private var displayedHistory: [ScanHistoryRecord] {
        Array(payload.history.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            profileSummary
            latestResults
            historyTable
            Spacer(minLength: 0)
            footer
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(IronTheme.terracottaPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("IronScan Medical Report")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                    Text("Educational screening summary for clinician review")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(payload.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                Text("Version \(versionString)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
            }
        }
    }

    private var profileSummary: some View {
        reportSection(title: "Patient Profile Summary") {
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Age", payload.profile.ageDescription)
                summaryRow("Biological Sex", payload.profile.biologicalSex.rawValue)
                summaryRow("Calibration", payload.calibrationCategory.badgeTitle)
                summaryRow("Reference Hb Baseline", payload.calibrationCategory.normalHemoglobinReference)
            }
        }
    }

    private var latestResults: some View {
        reportSection(title: "Latest Diagnostic Results") {
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Tissue Type", payload.latestDiagnosticResult.tissueSummary)
                summaryRow(
                    "Estimated Risk Score",
                    payload.latestDiagnosticResult.riskScore?.formatted(.number.precision(.fractionLength(2))) ?? "Unavailable"
                )
                Text(payload.latestDiagnosticResult.qualitativeFindings)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var historyTable: some View {
        reportSection(title: "Historical Trend") {
            VStack(spacing: 0) {
                HStack {
                    tableHeader("Date")
                    Spacer()
                    tableHeader("Score")
                    Spacer()
                    tableHeader("Summary")
                }
                .padding(.bottom, 8)

                if displayedHistory.isEmpty {
                    Text("No historical scans are stored yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(displayedHistory.enumerated()), id: \.element.id) { index, record in
                        HStack {
                            tableValue(record.capturedAt.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            tableValue(record.opticalPatternIndex?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                            Spacer()
                            tableValue(summaryTitle(for: record.summary))
                        }
                        .padding(.vertical, 10)

                        if index < displayedHistory.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("MEDICAL DISCLAIMER: IronScan is for preliminary screening only and does not diagnose anemia or any medical condition. Confirm all findings with a licensed physician and laboratory testing.")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.99, green: 0.95, blue: 0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func reportSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.black)
            content()
        }
        .padding(18)
        .background(Color(red: 0.98, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.62))
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tableHeader(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.54))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryTitle(for summary: OpticalRiskSummary) -> String {
        switch summary {
        case .lowerObservedRisk:
            return "Lower Risk"
        case .possibleAnemiaRisk:
            return "Possible Risk"
        case .unableToAssess:
            return "Unable to Assess"
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareablePDFDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private extension Bundle {
    var ironScanDisplayVersion: String {
        if let shortVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !shortVersion.isEmpty {
            return shortVersion
        }
        if let bundleVersion = object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return "Development"
    }
}
