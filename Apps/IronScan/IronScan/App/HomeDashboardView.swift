import Foundation
import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var history: ScanHistoryStore
    let startScan: () -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var latest: ScanHistoryRecord? {
        history.records.first
    }

    private var displayName: String {
        let storedName = UserDefaults.standard.string(forKey: "userFirstName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (storedName?.isEmpty == false ? storedName : nil) ?? "there"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    heroCard
                    metricsGrid
                    recentHistorySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(IronScreenBackground())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hello, \(displayName)")
                    .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)

                Text("Your latest iron screening snapshots, organized in one place.")
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Spacer(minLength: 16)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 48, height: 48)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(IronTheme.terracottaPrimary)
            }
            .modifier(LiquidGlassCardStyle(cornerRadius: 24))
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Measurement")
                        .font(IronTheme.roundedFont(.caption, weight: .bold))
                        .foregroundStyle(IronTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(latest.map { title(for: $0.summary) } ?? "No scan recorded")
                        .font(IronTheme.roundedFont(.title2, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)
                }

                Spacer()

                Image(systemName: latest.map { symbol(for: $0.summary) } ?? "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(latest.map { color(for: $0.summary) } ?? IronTheme.terracottaPrimary)
                    .padding(14)
                    .background(Color.white.opacity(0.45), in: Circle())
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(latest?.opticalPatternIndex?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)

                Text("Optical Pattern Index")
                    .font(IronTheme.roundedFont(.subheadline, weight: .medium))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Text(heroSupportText)
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textSecondary)

            Button(latest == nil ? "Take First Scan" : "View Details", action: startScan)
                .buttonStyle(OrganicPrimaryButtonStyle())
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 30, interactive: true)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            metricCard(
                title: "Total Scans",
                value: "\(history.records.count)",
                detail: history.records.isEmpty ? "No data yet" : "Stored locally"
            )

            metricCard(
                title: "Baseline Threshold",
                value: "0.50",
                detail: "Prototype reference"
            )

            metricCard(
                title: "Last Summary",
                value: latest.map { compactTitle(for: $0.summary) } ?? "None",
                detail: latest.map { $0.capturedAt.formatted(date: .abbreviated, time: .omitted) } ?? "Awaiting scan"
            )

            metricCard(
                title: "Trend Points",
                value: "\(history.records.filter { $0.opticalPatternIndex != nil }.count)",
                detail: "Index-ready scans"
            )
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent History")
                    .font(IronTheme.roundedFont(.title3, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)
                Spacer()
                Button("Start Scan", action: startScan)
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.terracottaPrimary)
            }

            if history.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(IronTheme.textSecondary)

                    Text("No scans yet")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text("Take your first scan to see your trends!")
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .liquidGlassCard(cornerRadius: 26)
            } else {
                VStack(spacing: 12) {
                    ForEach(history.records.prefix(6)) { record in
                        historyRow(record)
                    }
                }
            }
        }
    }

    private func metricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(IronTheme.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(IronTheme.roundedFont(.title2, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(IronTheme.roundedFont(.caption))
                .foregroundStyle(IronTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(18)
        .liquidGlassCard(cornerRadius: 24)
    }

    private func historyRow(_ record: ScanHistoryRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color(for: record.summary).opacity(0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: symbol(for: record.summary))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color(for: record.summary))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: record.summary))
                    .font(IronTheme.roundedFont(.headline, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)

                Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(IronTheme.roundedFont(.caption))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(record.opticalPatternIndex?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 22)
    }

    private var heroSupportText: String {
        guard latest != nil else {
            return "Start your first three-step scan to populate your dashboard and view research trends over time."
        }
        return "Research prototype output only. Confirm concerns with laboratory testing and a licensed clinician."
    }

    private func compactTitle(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "Lower Risk"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "Possible Risk"
        default:
            return "Unknown"
        }
    }

    private func title(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "Lower observed risk"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "Possible anemia risk"
        default:
            return "Unable to assess"
        }
    }

    private func symbol(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "checkmark.circle.fill"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "exclamationmark.triangle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private func color(for summary: String) -> Color {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return IronTheme.sageAccent
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return IronTheme.warning
        default:
            return IronTheme.textSecondary
        }
    }
}
