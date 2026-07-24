import Foundation

enum VisualRiskCategory: Equatable, Sendable {
    case lowerObservedRisk
    case possibleAnemiaRisk
    case unableToAssess
}

enum VisualAssessmentQuality: Equatable, Sendable {
    case accepted
    case rejected(reasons: [String])
}

struct VisualRiskSummary: Equatable, Sendable {
    let category: VisualRiskCategory
    let title: String
    let detail: String
    let symbol: String
}

enum VisualRiskSummaryEngine {
    static func summarize(
        report: TongueVisualAttributeReport,
        quality: VisualAssessmentQuality,
        demoModeEnabled: Bool = PrototypeDemoMode.isEnabled
    ) -> VisualRiskSummary {
        guard case .accepted = quality else {
            return unableToAssess(
                detail: "Lighting, sharpness, or alignment checks did not allow a reliable visual assessment."
            )
        }
        guard !report.isEngineeringFixture || demoModeEnabled else {
            return unableToAssess(
                detail: "The installed model is an engineering fixture and cannot provide a participant-facing result."
            )
        }
        guard report.pallor.probability.isFinite,
              report.pallor.lockedThreshold.isFinite,
              (0 ... 1).contains(report.pallor.probability),
              (0 ... 1).contains(report.pallor.lockedThreshold) else {
            return unableToAssess(detail: "The visual model returned an invalid result.")
        }

        if report.pallor.exceedsLockedThreshold {
            return VisualRiskSummary(
                category: .possibleAnemiaRisk,
                title: "Possible anemia risk",
                detail: detail(
                    report: report,
                    finding: "A visual pallor pattern was highlighted. Confirm with a laboratory test."
                ),
                symbol: "eye.trianglebadge.exclamationmark"
            )
        }
        return VisualRiskSummary(
            category: .lowerObservedRisk,
            title: "Lower observed risk",
            detail: detail(
                report: report,
                finding: "No visual pallor pattern was highlighted in this image."
            ),
            symbol: "eye.circle.fill"
        )
    }

    private static func detail(report: TongueVisualAttributeReport, finding: String) -> String {
        guard report.isEngineeringFixture else { return finding }
        return "Prototype demo prediction from an unvalidated engineering model. \(finding)"
    }

    private static func unableToAssess(detail: String) -> VisualRiskSummary {
        VisualRiskSummary(
            category: .unableToAssess,
            title: "Unable to assess",
            detail: detail,
            symbol: "eye.slash.fill"
        )
    }
}
