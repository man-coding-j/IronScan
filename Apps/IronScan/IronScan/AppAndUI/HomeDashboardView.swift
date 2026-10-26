import Charts
import Foundation
import SwiftUI

@MainActor
struct HomeDashboardView: View {
    @EnvironmentObject var historyManager: ScanHistoryManager
    @ObservedObject var history: ScanHistoryStore
    @State private var showFatigueWarning = false
    let startScan: () -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var latest: ScanHistoryRecord? {
        dashboardRecords.first
    }

    private var dashboardRecords: [ScanHistoryRecord] {
        TutorialCapture.isEnabled ? history.records : historyManager.displayRecords
    }

    private var displayName: String {
        if TutorialCapture.isEnabled { return "Explorer" }
        let storedName = UserDefaults.standard.string(forKey: "userFirstName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (storedName?.isEmpty == false ? storedName : nil) ?? "there"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if showFatigueWarning {
                        DemoFatigueBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    header
                    heroCard
                    MockWatchVitalsView()
                    metricsGrid
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .frame(maxWidth: .infinity)
            .background(IronScreenBackground())
            .navigationBarHidden(true)
        }
        .onAppear {
            guard !TutorialCapture.isEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showFatigueWarning = true }
            }
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

                syncStatusIndicator
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

                    Text(latest.map { record in
                        if let hemoglobin = record.estimatedHemoglobin {
                            return "\(hemoglobin.formatted(.number.precision(.fractionLength(1)))) g/dL · \(record.severity.rawValue.capitalized)"
                        }
                        return title(for: record.summary)
                    } ?? "No scan recorded")
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

            if latest?.estimatedHemoglobin == nil {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(latest?.opticalPatternIndex?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                        .font(.system(size: 52, weight: .bold, design: .serif))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text("Optical Pattern Index")
                        .font(IronTheme.roundedFont(.subheadline, weight: .medium))
                        .foregroundStyle(IronTheme.textSecondary)
                }
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

    private var syncStatusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(history.pendingSyncCount == 0 ? IronTheme.sageAccent : IronTheme.warning)
                .frame(width: 8, height: 8)

            Text(history.syncStatusText)
                .font(IronTheme.roundedFont(.caption, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.34), in: Capsule())
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            metricCard(
                title: "Total Scans",
                value: "\(dashboardRecords.count)",
                detail: dashboardRecords.isEmpty ? "No data yet" : "Stored locally"
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
                value: "\(dashboardRecords.filter { $0.opticalPatternIndex != nil }.count)",
                detail: "Index-ready scans"
            )
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
            return summary
        }
    }

    private func title(for summary: String) -> String {
        switch summary {
        case OpticalRiskSummary.lowerObservedRisk.rawValue:
            return "Lower observed risk"
        case OpticalRiskSummary.possibleAnemiaRisk.rawValue:
            return "Possible anemia risk"
        default:
            return summary
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

enum DashboardHistoryRecords {
    static func merging(_ records: [ScanRecord], legacy: [ScanHistoryRecord]) -> [ScanHistoryRecord] {
        let canonical = from(records)
        let ids = Set(canonical.map(\.id))
        return (canonical + legacy.filter { !ids.contains($0.id) })
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    static func from(_ records: [ScanRecord]) -> [ScanHistoryRecord] {
        records.map { record in
            let severity: AnemiaSeverity = switch record.riskLevel {
            case .normal: .normal
            case .mild: .mild
            case .moderate: .moderate
            case .severe: .severe
            }
            return ScanHistoryRecord(
                id: record.id,
                capturedAt: record.timestamp,
                summary: record.isDemoSample == true ? "Synthetic demo baseline" : record.riskLevel.rawValue,
                opticalPatternIndex: (record.conjunctivaScore + record.nailScore + record.tongueScore) / 3,
                severity: severity,
                estimatedHemoglobin: record.hemoglobinG_dL
            )
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }
}

struct HistoricalHemoglobinTrendCard: View {
    let records: [ScanHistoryRecord]
    var height: CGFloat = 260
    var emptyMessage: String

    @State private var selectedPointID: UUID?

    private let healthyRange: ClosedRange<Double> = 12.0 ... 15.5

    private var points: [HistoricalHemoglobinPoint] {
        records
            .compactMap { record in
                guard let estimatedHemoglobin = record.estimatedHemoglobin else { return nil }
                return HistoricalHemoglobinPoint(record: record, hemoglobin: estimatedHemoglobin)
            }
            .sorted { $0.date < $1.date }
    }

    private var selectedPoint: HistoricalHemoglobinPoint? {
        if let selectedPointID,
           let exactMatch = points.first(where: { $0.id == selectedPointID }) {
            return exactMatch
        }
        return points.last
    }

    var supportsTrendChart: Bool {
        !points.isEmpty
    }

    var xDomain: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        let last = points.last?.date ?? first
        // A single point (or equal timestamps) still needs a nonzero plot width.
        let padding = max(43_200, last.timeIntervalSince(first) * 0.05)
        return first.addingTimeInterval(-padding) ... last.addingTimeInterval(padding)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.hemoglobin) + [healthyRange.lowerBound, healthyRange.upperBound]
        let minValue = (values.min() ?? healthyRange.lowerBound) - 0.6
        let maxValue = (values.max() ?? healthyRange.upperBound) + 0.6
        return minValue ... maxValue
    }

    var body: some View {
        Group {
            if supportsTrendChart {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedPoint {
                        selectedSummary(for: selectedPoint)
                    }

                    Chart {
                        if !points.isEmpty {
                            RectangleMark(
                                xStart: .value("Start", xDomain.lowerBound),
                                xEnd: .value("End", xDomain.upperBound),
                                yStart: .value("Healthy Lower", healthyRange.lowerBound),
                                yEnd: .value("Healthy Upper", healthyRange.upperBound)
                            )
                            .foregroundStyle(IronTheme.sageAccent.opacity(0.12))
                        }

                        ForEach(points) { point in
                            if points.count >= 2 {
                            LineMark(
                                x: .value("Timestamp", point.date),
                                y: .value("Hemoglobin", point.hemoglobin)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(.init(lineWidth: 3, lineCap: .round))
                            .foregroundStyle(Color.brandMarigold)
                            }

                            PointMark(
                                x: .value("Timestamp", point.date),
                                y: .value("Hemoglobin", point.hemoglobin)
                            )
                            .foregroundStyle(point.severity.themeColor)
                            .symbolSize(selectedPointID == point.id ? 110 : 70)
                        }

                        if let selectedPoint {
                            RuleMark(x: .value("Selected Timestamp", selectedPoint.date))
                                .foregroundStyle(IronTheme.textMuted.opacity(0.4))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                            PointMark(
                                x: .value("Selected Timestamp", selectedPoint.date),
                                y: .value("Selected Hemoglobin", selectedPoint.hemoglobin)
                            )
                            .foregroundStyle(Color.white)
                            .symbolSize(180)

                            PointMark(
                                x: .value("Selected Timestamp", selectedPoint.date),
                                y: .value("Selected Hemoglobin", selectedPoint.hemoglobin)
                            )
                            .foregroundStyle(Color.brandMarigold)
                            .symbolSize(95)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: yDomain)
                    .chartXScale(domain: xDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: max(2, min(points.count, 4)))) { value in
                            AxisGridLine(stroke: .init(lineWidth: 0.6))
                                .foregroundStyle(Color.white.opacity(0.18))
                            AxisTick(stroke: .init(lineWidth: 0.6))
                                .foregroundStyle(Color.white.opacity(0.32))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                                .font(IronTheme.roundedFont(.caption))
                                .foregroundStyle(IronTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: .init(lineWidth: 0.6))
                                .foregroundStyle(Color.white.opacity(0.18))
                            AxisTick(stroke: .init(lineWidth: 0.6))
                                .foregroundStyle(Color.white.opacity(0.32))
                            AxisValueLabel {
                                if let hb = value.as(Double.self) {
                                    Text("\(hb.formatted(.number.precision(.fractionLength(1)))) g/dL")
                                        .font(IronTheme.roundedFont(.caption))
                                        .foregroundStyle(IronTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else { return }
                                            let originX = value.location.x - plotFrame.origin.x
                                            guard originX >= 0, originX <= plotFrame.size.width,
                                                  let hoveredDate: Date = proxy.value(atX: originX) else { return }
                                            selectedPointID = nearestPoint(to: hoveredDate)?.id
                                        }
                                        .onEnded { _ in
                                            selectedPointID = points.last?.id
                                        }
                                )
                        }
                    }
                    .frame(height: height)

                    Text("The shaded band marks the prototype's healthy adult reference range.")
                        .font(IronTheme.roundedFont(.caption))
                        .foregroundStyle(IronTheme.textSecondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(IronTheme.textMuted)

                    Text("Trend Coming Into Focus")
                        .font(IronTheme.roundedFont(.headline, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text(emptyMessage)
                        .font(IronTheme.roundedFont(.subheadline))
                        .foregroundStyle(IronTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: height)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 26)
        .onAppear {
            selectedPointID = points.last?.id
        }
        .onChange(of: points.map(\.id)) { _, updatedIDs in
            selectedPointID = updatedIDs.last
        }
    }

    private func selectedSummary(for point: HistoricalHemoglobinPoint) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(point.date.formatted(date: .abbreviated, time: .shortened))
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)

                Text("\(point.hemoglobin.formatted(.number.precision(.fractionLength(1)))) g/dL estimated hemoglobin")
                    .font(IronTheme.roundedFont(.caption))
                    .foregroundStyle(IronTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(point.severity.rawValue.capitalized)
                .font(IronTheme.roundedFont(.caption, weight: .bold))
                .foregroundStyle(point.severity.themeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(point.severity.themeColor.opacity(0.12), in: Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nearestPoint(to hoveredDate: Date) -> HistoricalHemoglobinPoint? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(hoveredDate)) < abs(rhs.date.timeIntervalSince(hoveredDate))
        }
    }
}

private struct HistoricalHemoglobinPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let hemoglobin: Double
    let severity: AnemiaSeverity

    init(record: ScanHistoryRecord, hemoglobin: Double) {
        id = record.id
        date = record.capturedAt
        self.hemoglobin = hemoglobin
        severity = record.severity
    }
}
