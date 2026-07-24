import Foundation

enum PersonalizedPlanTone: Equatable, Sendable {
    case routine
    case monitor
    case laboratoryConfirmation
    case unableToAssess
}

struct PersonalizedPlanItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

struct PersonalizedIronPlan: Equatable, Sendable {
    let tone: PersonalizedPlanTone
    let title: String
    let summary: String
    let items: [PersonalizedPlanItem]
    let disclaimer: String
}

struct PersonalizedPlanEngine: Sendable {
    let lowerOpticalThreshold: Double

    init(lowerOpticalThreshold: Double = 0.35) {
        self.lowerOpticalThreshold = lowerOpticalThreshold
    }

    func makePlan(
        fusedScore: Double?,
        opticalSummary: OpticalRiskSummary,
        outputs: [TissueSite: TissueScreeningOutput],
        intake: ScreeningIntakeSnapshot
    ) -> PersonalizedIronPlan {
        guard let fusedScore,
              fusedScore.isFinite,
              (0 ... 1).contains(fusedScore),
              opticalSummary != .unableToAssess else {
            return unablePlan(intake: intake)
        }

        let visualPatternHighlighted = fusedScore >= lowerOpticalThreshold
            || opticalSummary == .possibleAnemiaRisk
        let eyePatternHighlighted = outputs[.eye].map {
            $0.qualityAccepted && $0.proxySignalObserved
        } ?? false
        return buildPlan(
            visualPatternHighlighted: visualPatternHighlighted,
            eyePatternHighlighted: eyePatternHighlighted,
            intake: intake
        )
    }

    func makeTongueOnlyPlan(
        visualSummary: VisualRiskSummary,
        intake: ScreeningIntakeSnapshot
    ) -> PersonalizedIronPlan {
        switch visualSummary.category {
        case .lowerObservedRisk:
            buildPlan(
                visualPatternHighlighted: false,
                eyePatternHighlighted: false,
                intake: intake
            )
        case .possibleAnemiaRisk:
            buildPlan(
                visualPatternHighlighted: true,
                eyePatternHighlighted: false,
                intake: intake
            )
        case .unableToAssess:
            unablePlan(intake: intake)
        }
    }

    private func buildPlan(
        visualPatternHighlighted: Bool,
        eyePatternHighlighted: Bool,
        intake: ScreeningIntakeSnapshot
    ) -> PersonalizedIronPlan {
        var items = contextItems(intake: intake)

        if intake.diet == .plantBased {
            items.insert(PersonalizedPlanItem(
                id: "plant-based-pairing",
                title: "Plant-based meal pairing",
                detail: "For general education, pair lentils, beans, or leafy greens with vitamin C-containing foods such as citrus, tomatoes, or bell peppers.",
                symbol: "leaf.fill"
            ), at: 0)
        }

        if visualPatternHighlighted {
            items.append(PersonalizedPlanItem(
                id: "laboratory-confirmation",
                title: "Confirm the visual finding",
                detail: "Confirm concerns with a laboratory test. A licensed clinician can determine whether a CBC or ferritin test is appropriate.",
                symbol: "cross.case.fill"
            ))
            return PersonalizedIronPlan(
                tone: .laboratoryConfirmation,
                title: "Laboratory confirmation is appropriate",
                summary: eyePatternHighlighted
                    ? "The combined research model highlighted a visual pallor pattern, including the accepted eye image."
                    : "The combined research model highlighted a visual pallor pattern in the accepted images.",
                items: items,
                disclaimer: Self.disclaimer
            )
        }

        if !items.isEmpty {
            items.append(PersonalizedPlanItem(
                id: "reported-context",
                title: "Share persistent concerns",
                detail: "The accepted images did not highlight a combined pallor pattern. If reported symptoms or bleeding concerns continue, share them with a licensed clinician.",
                symbol: "person.crop.circle.badge.questionmark"
            ))
            return PersonalizedIronPlan(
                tone: .monitor,
                title: "Lower visual signal with reported context",
                summary: "The accepted optical images showed a lower visual pallor signal. Reported context is shown separately and does not change the model output.",
                items: items,
                disclaimer: Self.disclaimer
            )
        }

        return PersonalizedIronPlan(
            tone: .routine,
            title: "Maintain general wellness habits",
            summary: "The accepted optical images showed a lower visual pallor signal. This does not confirm normal iron status.",
            items: [
                PersonalizedPlanItem(
                    id: "balanced-food-sources",
                    title: "Use varied food sources",
                    detail: "General iron-containing food examples include beans, lentils, leafy greens, fortified grains, meat, seafood, and poultry.",
                    symbol: "fork.knife"
                ),
                PersonalizedPlanItem(
                    id: "routine-confirmation",
                    title: "Use laboratory testing for concerns",
                    detail: "If symptoms or concerns arise, confirm with a laboratory test rather than relying on an optical scan.",
                    symbol: "checkmark.shield.fill"
                ),
            ],
            disclaimer: Self.disclaimer
        )
    }

    private func contextItems(intake: ScreeningIntakeSnapshot) -> [PersonalizedPlanItem] {
        var items = [PersonalizedPlanItem]()
        if intake.reportsFatigue || intake.reportsColdHands {
            items.append(PersonalizedPlanItem(
                id: "reported-symptoms",
                title: "Reported symptoms",
                detail: "Fatigue and cold hands can have many causes. If they persist or worsen, discuss them with a licensed clinician.",
                symbol: "waveform.path.ecg"
            ))
        }
        if intake.menstrualHistory == .reportsHeavyBleeding {
            items.append(PersonalizedPlanItem(
                id: "reported-menstrual-history",
                title: "Reported menstrual history",
                detail: "Heavy menstrual bleeding was reported. Share this context with a licensed clinician; an optical scan cannot determine its cause or effects.",
                symbol: "calendar.badge.exclamationmark"
            ))
        }
        return items
    }

    private func unablePlan(intake: ScreeningIntakeSnapshot) -> PersonalizedIronPlan {
        var items = contextItems(intake: intake)
        items.insert(PersonalizedPlanItem(
            id: "repeat-unusable-images",
            title: "Repeat unusable images",
            detail: "The optical images could not be assessed. Follow the lighting and alignment guidance before trying again.",
            symbol: "arrow.clockwise.circle.fill"
        ), at: 0)
        if intake.reportsFatigue
            || intake.reportsColdHands
            || intake.menstrualHistory == .reportsHeavyBleeding {
            items.append(PersonalizedPlanItem(
                id: "laboratory-over-scan",
                title: "Do not rely on an unusable scan",
                detail: "For ongoing concerns, confirm with a laboratory test and a licensed clinician.",
                symbol: "cross.case.fill"
            ))
        }
        return PersonalizedIronPlan(
            tone: .unableToAssess,
            title: "Optical assessment unavailable",
            summary: "No scan-based food or health conclusion can be made from the current images.",
            items: items,
            disclaimer: Self.disclaimer
        )
    }

    private static let disclaimer = "This research guidance does not diagnose anemia, measure iron, or provide treatment recommendations. Questionnaire responses remain separate from Core ML output."
}
