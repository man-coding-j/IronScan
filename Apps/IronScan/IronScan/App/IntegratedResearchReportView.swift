import SwiftUI

struct IntegratedResearchReportView: View {
    private enum Content {
        case tongue(TongueVisualAttributeReport)
        case multiTissue(TriangulationResult, [TissueSite: TissueScreeningOutput])
    }

    private let content: Content
    private let onScanAgain: () -> Void

    @AppStorage(ScreeningIntakeStorageKeys.biologicalSex)
    private var biologicalSexRaw = BiologicalSexContext.preferNotToSay.rawValue
    @AppStorage(ScreeningIntakeStorageKeys.diet)
    private var dietRaw = DietContext.preferNotToSay.rawValue
    @AppStorage(ScreeningIntakeStorageKeys.fatigue)
    private var reportsFatigue = false
    @AppStorage(ScreeningIntakeStorageKeys.coldHands)
    private var reportsColdHands = false
    @AppStorage(ScreeningIntakeStorageKeys.menstrualHistory)
    private var menstrualHistoryRaw = MenstrualHistoryContext.preferNotToSay.rawValue

    init(report: TongueVisualAttributeReport, onScanAgain: @escaping () -> Void) {
        content = .tongue(report)
        self.onScanAgain = onScanAgain
    }

    init(
        triangulation: TriangulationResult,
        outputs: [TissueSite: TissueScreeningOutput],
        onScanAgain: @escaping () -> Void
    ) {
        content = .multiTissue(triangulation, outputs)
        self.onScanAgain = onScanAgain
    }

    private var intake: ScreeningIntakeSnapshot {
        ScreeningIntakeSnapshot(
            biologicalSex: BiologicalSexContext(rawValue: biologicalSexRaw) ?? .preferNotToSay,
            diet: DietContext(rawValue: dietRaw) ?? .preferNotToSay,
            reportsFatigue: reportsFatigue,
            reportsColdHands: reportsColdHands,
            menstrualHistory: MenstrualHistoryContext(rawValue: menstrualHistoryRaw) ?? .preferNotToSay
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch content {
            case let .tongue(report):
                tongueReport(report)
            case let .multiTissue(triangulation, outputs):
                multiTissueReport(triangulation: triangulation, outputs: outputs)
            }
            Button {
                onScanAgain()
            } label: {
                Label("Run another scan", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    @ViewBuilder
    private func tongueReport(_ report: TongueVisualAttributeReport) -> some View {
        let visualSummary = VisualRiskSummaryEngine.summarize(report: report, quality: .accepted)
        summaryCard(
            title: visualSummary.title,
            detail: visualSummary.detail,
            symbol: visualSummary.symbol,
            color: color(for: visualSummary.category)
        )
        reportedContextCard
        HealthGuidanceView(
            plan: PersonalizedPlanEngine().makeTongueOnlyPlan(
                visualSummary: visualSummary,
                intake: intake
            )
        )
        recommendedActionCard(
            priority: .laboratoryConfirmation,
            isEngineeringFixture: report.isEngineeringFixture
        )
    }

    @ViewBuilder
    private func multiTissueReport(
        triangulation: TriangulationResult,
        outputs: [TissueSite: TissueScreeningOutput]
    ) -> some View {
        let assessment = IDARiskEngine().evaluate(
            triangulation: triangulation,
            intake: intake
        )
        summaryCard(
            title: title(for: assessment.summary),
            detail: assessment.rationale,
            symbol: symbol(for: assessment.summary),
            color: color(for: assessment.summary)
        )

        VStack(alignment: .leading, spacing: 12) {
            Label("Tissue breakdown", systemImage: "square.grid.2x2.fill")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(TissueSite.allCases, id: \.self) { tissue in
                    tissueCard(
                        tissue: tissue,
                        output: outputs[tissue],
                        contribution: triangulation.contribution(for: tissue),
                        highVarianceThreshold: 0.15
                    )
                }
            }
            Text("Model consistency describes repeatability across the model ensemble; it is not clinical confidence.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        reportedContextCard
        HealthGuidanceView(
            plan: PersonalizedPlanEngine().makePlan(
                fusedScore: triangulation.opticalPallorIndex,
                opticalSummary: triangulation.summary,
                outputs: outputs,
                intake: intake
            )
        )
        recommendedActionCard(
            priority: assessment.followUpPriority,
            isEngineeringFixture: outputs.values.contains { $0.isEngineeringFixture }
        )
    }

    private func summaryCard(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RESEARCH TRIAGE SUMMARY")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(color)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
    }

    private func tissueCard(
        tissue: TissueSite,
        output: TissueScreeningOutput?,
        contribution: TissueContribution?,
        highVarianceThreshold: Double
    ) -> some View {
        let status = contribution?.status ?? .qualityRejected
        let variance = output?.predictiveVariance
        let consistency = variance.map {
            max(0, min(1, 1 - ($0 / highVarianceThreshold)))
        }
        let tint: Color = status == .included
            ? (output?.proxySignalObserved == true ? .orange : .green)
            : .orange

        return VStack(alignment: .leading, spacing: 8) {
            Label(tissue.displayName, systemImage: iconName(for: tissue))
                .font(.headline)
            Text(tissueFinding(output: output, status: status))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            if let consistency {
                Text("Model consistency \(consistency, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption.weight(.semibold))
            } else {
                Text("Model consistency unavailable")
                    .font(.caption)
            }
            Text(uncertaintyText(status))
                .font(.caption)
                .foregroundStyle(status == .included ? Color.secondary : Color.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
    }

    private var reportedContextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reported context", systemImage: "person.text.rectangle")
                .font(.headline)
            contextRow(title: "Biological sex", value: intake.biologicalSex.title)
            contextRow(title: "Diet", value: intake.diet.title)
            contextRow(title: "Reported symptoms", value: intake.symptomSummary)
            contextRow(title: "Menstrual history", value: intake.menstrualHistory.title)
            Text("This local context can change follow-up guidance, but it never changes the Core ML outputs.")
                .font(.caption)
                .foregroundStyle(.secondary)
            NavigationLink {
                ScreeningIntakeView()
            } label: {
                Label("Edit optional context", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func recommendedActionCard(
        priority: ResearchFollowUpPriority,
        isEngineeringFixture: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Recommended action", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text(priority == .routine
                ? "Use routine care and confirm concerns with a laboratory test."
                : "Confirm with a laboratory test.")
                .font(.headline)
            Text("IronScan is an optical screening research prototype and cannot establish a clinical diagnosis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isEngineeringFixture {
                Text("The displayed category includes unvalidated engineering model output and must not be treated as a participant result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private func contextRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func tissueFinding(
        output: TissueScreeningOutput?,
        status: TissueFusionStatus
    ) -> String {
        guard let output else { return "Unable to assess" }
        guard status == .included else { return "Unable to assess" }
        return output.proxySignalObserved ? "Possible visual pallor signal" : "Lower visual pallor signal"
    }

    private func uncertaintyText(_ status: TissueFusionStatus) -> String {
        switch status {
        case .included: "Included in combined result"
        case .uncertainRescanRecommended: "Uncertain — re-scan recommended"
        case .qualityRejected: "Image quality rejected — re-scan recommended"
        case .omitted: "Skipped by the participant for this session"
        }
    }

    private func title(for summary: OpticalRiskSummary) -> String {
        switch summary {
        case .lowerObservedRisk: "Lower observed risk"
        case .possibleAnemiaRisk: "Possible anemia risk"
        case .unableToAssess: "Unable to assess"
        }
    }

    private func symbol(for summary: OpticalRiskSummary) -> String {
        switch summary {
        case .lowerObservedRisk: "checkmark.circle.fill"
        case .possibleAnemiaRisk: "exclamationmark.triangle.fill"
        case .unableToAssess: "questionmark.circle.fill"
        }
    }

    private func color(for summary: OpticalRiskSummary) -> Color {
        switch summary {
        case .lowerObservedRisk: .green
        case .possibleAnemiaRisk: .orange
        case .unableToAssess: .gray
        }
    }

    private func color(for category: VisualRiskCategory) -> Color {
        switch category {
        case .lowerObservedRisk: .green
        case .possibleAnemiaRisk: .orange
        case .unableToAssess: .gray
        }
    }

    private func iconName(for tissue: TissueSite) -> String {
        switch tissue {
        case .eye: "eye.fill"
        case .nail: "hand.raised.fill"
        case .tongue: "mouth.fill"
        }
    }
}
