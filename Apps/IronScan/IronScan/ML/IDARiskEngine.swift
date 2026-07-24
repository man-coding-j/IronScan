import Foundation

enum ResearchFollowUpPriority: String, Equatable, Sendable {
    case routine
    case monitor
    case laboratoryConfirmation
}

struct ContextRiskProfile: Equatable, Sendable {
    let reportedFactorCount: Int
    let dietFactorPresent: Bool
    let symptomFactorCount: Int

    var isLow: Bool {
        reportedFactorCount == 0
    }

    var hasMultipleFactors: Bool {
        reportedFactorCount >= 2
    }
}

struct IDARiskAssessment: Equatable, Sendable {
    let summary: OpticalRiskSummary
    let followUpPriority: ResearchFollowUpPriority
    let opticalScore: Double?
    let contextProfile: ContextRiskProfile
    let rationale: String
}

struct IDARiskEngine: Sendable {
    let lowerOpticalThreshold: Double
    let elevatedOpticalThreshold: Double

    init(
        lowerOpticalThreshold: Double = 0.35,
        elevatedOpticalThreshold: Double = 0.65
    ) {
        self.lowerOpticalThreshold = lowerOpticalThreshold
        self.elevatedOpticalThreshold = elevatedOpticalThreshold
    }

    func evaluate(
        triangulation: TriangulationResult,
        intake: ScreeningIntakeSnapshot
    ) -> IDARiskAssessment {
        let context = contextProfile(for: intake)
        guard let opticalScore = triangulation.opticalPallorIndex,
              opticalScore.isFinite,
              (0 ... 1).contains(opticalScore),
              triangulation.summary != .unableToAssess else {
            return IDARiskAssessment(
                summary: .unableToAssess,
                followUpPriority: .routine,
                opticalScore: nil,
                contextProfile: context,
                rationale: "The optical scans could not produce a usable combined result."
            )
        }

        if opticalScore >= elevatedOpticalThreshold || context.hasMultipleFactors {
            return IDARiskAssessment(
                summary: .possibleAnemiaRisk,
                followUpPriority: .laboratoryConfirmation,
                opticalScore: opticalScore,
                contextProfile: context,
                rationale: "The combined visual signal or multiple reported context factors support prompt laboratory confirmation."
            )
        }
        if opticalScore >= lowerOpticalThreshold || !context.isLow {
            return IDARiskAssessment(
                summary: .possibleAnemiaRisk,
                followUpPriority: .monitor,
                opticalScore: opticalScore,
                contextProfile: context,
                rationale: "The combined visual signal or reported context supports monitoring and laboratory confirmation."
            )
        }
        return IDARiskAssessment(
            summary: .lowerObservedRisk,
            followUpPriority: .routine,
            opticalScore: opticalScore,
            contextProfile: context,
            rationale: "The combined visual signal was lower and no selected context factors were reported."
        )
    }

    private func contextProfile(for intake: ScreeningIntakeSnapshot) -> ContextRiskProfile {
        let symptomCount = [intake.reportsFatigue, intake.reportsColdHands].filter { $0 }.count
        let dietFactorPresent = intake.diet == .plantBased
        return ContextRiskProfile(
            reportedFactorCount: symptomCount + (dietFactorPresent ? 1 : 0),
            dietFactorPresent: dietFactorPresent,
            symptomFactorCount: symptomCount
        )
    }
}
