@preconcurrency import CoreML
import CoreVideo
import Foundation
import SwiftUI
import UIKit

enum DemographicCalibrationCategory: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case adultMale = "Adult Male"
    case adultFemale = "Adult Female"
    case pregnantFemale = "Pregnant Female"
    case pediatric = "Pediatric"
    case defaultCategory = "Standard / General"

    var id: String { rawValue }

    var badgeTitle: String {
        switch self {
        case .adultMale:
            return "Adult Male"
        case .adultFemale:
            return "Adult Female"
        case .pregnantFemale:
            return "Pregnancy"
        case .pediatric:
            return "Pediatric"
        case .defaultCategory:
            return "General"
        }
    }
}

enum TissueSite: String, CaseIterable, Sendable {
    case eye
    case nail
    case tongue
}

enum TriangulationMode: String, Sendable {
    case prototypeDemo
    case researchValidated
}

enum TriangulationConfigurationError: Error, Equatable, Sendable {
    case missingTissueConfiguration
    case invalidPriorityMultiplier(TissueSite)
    case invalidEpsilon
    case invalidHighVarianceThreshold
    case invalidDecisionThreshold
    case missingVersionContract(TissueSite)
}

struct TriangulationConfiguration: Equatable, Sendable {
    let identifier: String
    let semanticVersion: String
    let mode: TriangulationMode
    let priorityMultipliers: [TissueSite: Double]
    let inverseVarianceEpsilon: Double
    let highVarianceThreshold: Double
    let decisionThreshold: Double
    let calibrationCategory: DemographicCalibrationCategory
    let modelVersions: [TissueSite: String]
    let preprocessingVersions: [TissueSite: String]

    init(
        identifier: String,
        semanticVersion: String,
        mode: TriangulationMode,
        priorityMultipliers: [TissueSite: Double] = [.eye: 1.2, .nail: 0.9, .tongue: 0.9],
        inverseVarianceEpsilon: Double = 0.001,
        highVarianceThreshold: Double = 0.15,
        decisionThreshold: Double,
        calibrationCategory: DemographicCalibrationCategory = .defaultCategory,
        modelVersions: [TissueSite: String],
        preprocessingVersions: [TissueSite: String]
    ) throws {
        let requiredTissues = Set(TissueSite.allCases)
        guard Set(priorityMultipliers.keys) == requiredTissues,
              Set(modelVersions.keys) == requiredTissues,
              Set(preprocessingVersions.keys) == requiredTissues else {
            throw TriangulationConfigurationError.missingTissueConfiguration
        }
        for tissue in TissueSite.allCases {
            guard let multiplier = priorityMultipliers[tissue],
                  multiplier.isFinite,
                  multiplier > 0 else {
                throw TriangulationConfigurationError.invalidPriorityMultiplier(tissue)
            }
            guard modelVersions[tissue]?.isEmpty == false,
                  preprocessingVersions[tissue]?.isEmpty == false else {
                throw TriangulationConfigurationError.missingVersionContract(tissue)
            }
        }
        guard inverseVarianceEpsilon.isFinite, inverseVarianceEpsilon > 0 else {
            throw TriangulationConfigurationError.invalidEpsilon
        }
        guard highVarianceThreshold.isFinite, highVarianceThreshold > 0 else {
            throw TriangulationConfigurationError.invalidHighVarianceThreshold
        }
        guard decisionThreshold.isFinite, (0 ... 1).contains(decisionThreshold) else {
            throw TriangulationConfigurationError.invalidDecisionThreshold
        }
        self.identifier = identifier
        self.semanticVersion = semanticVersion
        self.mode = mode
        self.priorityMultipliers = priorityMultipliers
        self.inverseVarianceEpsilon = inverseVarianceEpsilon
        self.highVarianceThreshold = highVarianceThreshold
        self.decisionThreshold = decisionThreshold
        self.calibrationCategory = calibrationCategory
        self.modelVersions = modelVersions
        self.preprocessingVersions = preprocessingVersions
    }
}

struct TissueScreeningOutput: Equatable, Sendable {
    let tissue: TissueSite
    let probability: Double
    let lockedThreshold: Double
    let qualityAccepted: Bool
    let rejectionReasons: [String]
    let modelVersion: String
    let preprocessingVersion: String
    let isEngineeringFixture: Bool
    let predictiveUncertainty: Double?
    let uncertaintyThreshold: Double?
    let uncertaintyPassCount: Int
    let uncertaintyEnforced: Bool
    let inferenceDurationMs: Double
    let computeUnits: InferenceComputeUnits

    init(
        tissue: TissueSite,
        probability: Double,
        lockedThreshold: Double,
        qualityAccepted: Bool,
        rejectionReasons: [String],
        modelVersion: String,
        preprocessingVersion: String,
        isEngineeringFixture: Bool,
        predictiveUncertainty: Double? = nil,
        uncertaintyThreshold: Double? = nil,
        uncertaintyPassCount: Int = 0,
        uncertaintyEnforced: Bool = true,
        inferenceDurationMs: Double = 0,
        computeUnits: InferenceComputeUnits = .cpuOnly
    ) {
        self.tissue = tissue
        self.probability = probability
        self.lockedThreshold = lockedThreshold
        self.qualityAccepted = qualityAccepted
        self.rejectionReasons = rejectionReasons
        self.modelVersion = modelVersion
        self.preprocessingVersion = preprocessingVersion
        self.isEngineeringFixture = isEngineeringFixture
        self.predictiveUncertainty = predictiveUncertainty
        self.uncertaintyThreshold = uncertaintyThreshold
        self.uncertaintyPassCount = uncertaintyPassCount
        self.uncertaintyEnforced = uncertaintyEnforced
        self.inferenceDurationMs = inferenceDurationMs
        self.computeUnits = computeUnits
    }

    var proxySignalObserved: Bool {
        probability >= lockedThreshold
    }

    var uncertaintyAccepted: Bool {
        guard uncertaintyEnforced else { return true }
        guard let predictiveUncertainty, let uncertaintyThreshold else { return true }
        return predictiveUncertainty <= uncertaintyThreshold
    }

    var predictiveVariance: Double? {
        predictiveUncertainty.map { $0 * $0 }
    }
}

enum OpticalRiskSummary: String, Equatable, Sendable {
    case lowerObservedRisk
    case possibleAnemiaRisk
    case unableToAssess
}

enum AnemiaSeverity: String, Codable, CaseIterable, Sendable {
    case normal
    case mild
    case moderate
    case severe

    var themeColor: Color {
        switch self {
        case .normal:
            return .green
        case .mild:
            return .yellow
        case .moderate:
            return .orange
        case .severe:
            return .red
        }
    }

    var clinicalDescription: String {
        switch self {
        case .normal:
            return "Normal: No significant pallor detected."
        case .mild:
            return "Mild: Subtle pallor patterns suggest early concern."
        case .moderate:
            return "Moderate: Stronger pallor patterns merit prompt follow-up."
        case .severe:
            return "Severe: High probability of critical anemia."
        }
    }

    static func from(probability: Double?) -> AnemiaSeverity {
        guard let probability else { return .normal }
        switch probability {
        case ..<0.3:
            return .normal
        case ..<0.5:
            return .mild
        case ..<0.75:
            return .moderate
        default:
            return .severe
        }
    }
}

enum TissueFusionStatus: String, Equatable, Sendable {
    case included
    case uncertainRescanRecommended
    case qualityRejected
    case omitted
}

struct TissueContribution: Equatable, Sendable {
    let tissue: TissueSite
    let probability: Double
    let variance: Double?
    let inverseVarianceWeight: Double
    let normalizedWeight: Double
    let priorityMultiplier: Double
    let weightedValue: Double
    let proxySignalObserved: Bool
    let status: TissueFusionStatus

    var weight: Double {
        normalizedWeight
    }
}

struct TriangulationResult: Equatable, Sendable {
    let summary: OpticalRiskSummary
    let opticalPallorIndex: Double?
    let severity: AnemiaSeverity
    let estimatedHemoglobin: Double?
    let isCriticalEmergency: Bool
    let analyzedTissues: [TissueSite]
    let omittedTissues: [TissueSite]
    let reliabilityLabel: String
    let contributions: [TissueContribution]
    let rejectionReasons: [String]
    let configurationIdentifier: String
    let configurationVersion: String
    let mode: TriangulationMode
    let calibrationCategory: DemographicCalibrationCategory
    let calibratedDecisionThreshold: Double

    init(
        summary: OpticalRiskSummary,
        opticalPallorIndex: Double?,
        contributions: [TissueContribution],
        rejectionReasons: [String],
        configurationIdentifier: String,
        configurationVersion: String,
        mode: TriangulationMode,
        calibrationCategory: DemographicCalibrationCategory,
        calibratedDecisionThreshold: Double,
        severity: AnemiaSeverity? = nil,
        estimatedHemoglobin: Double? = nil,
        isCriticalEmergency: Bool = false,
        analyzedTissues: [TissueSite] = [],
        omittedTissues: [TissueSite] = [],
        reliabilityLabel: String = "Unavailable"
    ) {
        self.summary = summary
        self.opticalPallorIndex = opticalPallorIndex
        self.severity = severity ?? AnemiaSeverity.from(probability: opticalPallorIndex)
        self.estimatedHemoglobin = estimatedHemoglobin
        self.isCriticalEmergency = isCriticalEmergency
        self.analyzedTissues = analyzedTissues
        self.omittedTissues = omittedTissues
        self.reliabilityLabel = reliabilityLabel
        self.contributions = contributions
        self.rejectionReasons = rejectionReasons
        self.configurationIdentifier = configurationIdentifier
        self.configurationVersion = configurationVersion
        self.mode = mode
        self.calibrationCategory = calibrationCategory
        self.calibratedDecisionThreshold = calibratedDecisionThreshold
    }

    func contribution(for tissue: TissueSite) -> TissueContribution? {
        contributions.first { $0.tissue == tissue }
    }

    static func unableToAssess(
        reason: String,
        configuration: TriangulationConfiguration
    ) -> TriangulationResult {
        TriangulationResult(
            summary: OpticalRiskSummary.unableToAssess,
            opticalPallorIndex: nil as Double?,
            contributions: [],
            rejectionReasons: [reason],
            configurationIdentifier: configuration.identifier,
            configurationVersion: configuration.semanticVersion,
            mode: configuration.mode,
            calibrationCategory: configuration.calibrationCategory,
            calibratedDecisionThreshold: configuration.decisionThreshold,
            omittedTissues: TissueSite.allCases,
            reliabilityLabel: "Unavailable"
        )
    }
}

struct TriangulationEngine: Sendable {
    private static let coreMLImageDimension = 224
    private static let defaultUncertaintyThreshold = 1.0

    func evaluate(
        outputs: [TissueSite: TissueScreeningOutput],
        images: [TissueSite: UIImage],
        configuration: TriangulationConfiguration,
        allowEngineeringFixtures: Bool,
        biologicalSexRawValue: String? = nil,
        recentLabHemoglobin: Double? = nil,
        demographicProfile: DemographicProfile? = nil
    ) async -> TriangulationResult {
        var resolvedOutputs = outputs

        for tissue in [TissueSite.eye, .tongue, .nail] {
            guard let image = images[tissue],
                  let modelVersion = configuration.modelVersions[tissue],
                  let preprocessingVersion = configuration.preprocessingVersions[tissue],
                  let prediction = await evaluateTissueScreening(
                      tissue: tissue,
                      image: image,
                      lockedThreshold: configuration.decisionThreshold,
                      modelVersion: modelVersion,
                      preprocessingVersion: preprocessingVersion
                  ) else {
                continue
            }
            resolvedOutputs[tissue] = prediction
        }

        let baselineResult = evaluate(
            outputs: resolvedOutputs,
            configuration: configuration,
            allowEngineeringFixtures: allowEngineeringFixtures,
            biologicalSexRawValue: biologicalSexRawValue,
            recentLabHemoglobin: recentLabHemoglobin,
            demographicProfile: demographicProfile
        )

        let referenceImage = images[.eye] ?? images[.tongue] ?? images[.nail]
        let clinicalRiskMultiplier = clinicalRiskMultiplier(for: demographicProfile)
        let estimatedHemoglobin = await calculateEstimatedHemoglobin(
            from: referenceImage,
            probability: baselineResult.opticalPallorIndex,
            age: demographicProfile?.age,
            biologicalSexRawValue: biologicalSexRawValue ?? demographicProfile?.biologicalSex.rawValue,
            recentLabHemoglobin: recentLabHemoglobin ?? demographicProfile?.recentLabHemoglobin,
            clinicalRiskMultiplier: clinicalRiskMultiplier
        )

        return TriangulationResult(
            summary: baselineResult.summary,
            opticalPallorIndex: baselineResult.opticalPallorIndex,
            contributions: baselineResult.contributions,
            rejectionReasons: baselineResult.rejectionReasons,
            configurationIdentifier: baselineResult.configurationIdentifier,
            configurationVersion: baselineResult.configurationVersion,
            mode: baselineResult.mode,
            calibrationCategory: baselineResult.calibrationCategory,
            calibratedDecisionThreshold: baselineResult.calibratedDecisionThreshold,
            severity: baselineResult.severity,
            estimatedHemoglobin: estimatedHemoglobin,
            isCriticalEmergency: isCriticalEmergency(
                estimatedHemoglobin: estimatedHemoglobin,
                demographicProfile: demographicProfile
            ),
            analyzedTissues: baselineResult.analyzedTissues,
            omittedTissues: baselineResult.omittedTissues,
            reliabilityLabel: baselineResult.reliabilityLabel
        )
    }

    func evaluate(
        outputs: [TissueSite: TissueScreeningOutput],
        configuration: TriangulationConfiguration,
        allowEngineeringFixtures: Bool,
        biologicalSexRawValue: String? = nil,
        recentLabHemoglobin: Double? = nil,
        demographicProfile: DemographicProfile? = nil
    ) -> TriangulationResult {
        guard !outputs.isEmpty else {
            return TriangulationResult.unableToAssess(
                reason: "At least one tissue scan is required.",
                configuration: configuration
            )
        }

        var candidates = [FusionCandidate]()
        var excludedContributions = [TissueContribution]()
        var rejectionReasons = [String]()
        let omittedTissues = TissueSite.allCases.filter { outputs[$0] == nil }
        excludedContributions.append(contentsOf: omittedTissues.map(omittedContribution))

        for tissue in TissueSite.allCases where outputs[tissue] != nil {
            guard let output = outputs[tissue],
                  output.tissue == tissue,
                  let modelVersion = configuration.modelVersions[tissue],
                  let preprocessingVersion = configuration.preprocessingVersions[tissue] else {
                rejectionReasons.append("The \(tissue.rawValue) scan contract is incomplete.")
                continue
            }
            guard output.probability.isFinite,
                  (0 ... 1).contains(output.probability),
                  output.lockedThreshold.isFinite,
                  (0 ... 1).contains(output.lockedThreshold) else {
                rejectionReasons.append("The \(tissue.rawValue) model output is invalid.")
                continue
            }
            guard output.modelVersion == modelVersion,
                  output.preprocessingVersion == preprocessingVersion else {
                rejectionReasons.append("The \(tissue.rawValue) model contract does not match the fusion manifest.")
                continue
            }
            guard allowEngineeringFixtures || !output.isEngineeringFixture else {
                rejectionReasons.append("Engineering fixture output is disabled outside Prototype Demo mode.")
                continue
            }

            guard output.qualityAccepted else {
                excludedContributions.append(excludedContribution(
                    output: output,
                    priorityMultiplier: siteBaseWeight(for: tissue),
                    status: .qualityRejected
                ))
                rejectionReasons.append(contentsOf: output.rejectionReasons.isEmpty
                    ? ["The \(tissue.rawValue) scan did not meet quality requirements."]
                    : output.rejectionReasons)
                continue
            }
            guard let variance = output.predictiveVariance,
                  variance.isFinite,
                  variance >= 0 else {
                rejectionReasons.append("The \(tissue.rawValue) uncertainty output is unavailable.")
                continue
            }
            guard variance <= configuration.highVarianceThreshold else {
                excludedContributions.append(excludedContribution(
                    output: output,
                    priorityMultiplier: siteBaseWeight(for: tissue),
                    status: .uncertainRescanRecommended
                ))
                rejectionReasons.append("The \(tissue.rawValue) scan is uncertain; re-scan recommended.")
                continue
            }

            candidates.append(FusionCandidate(
                output: output,
                variance: variance,
                inverseVarianceWeight: 1 / (variance + configuration.inverseVarianceEpsilon),
                priorityMultiplier: siteBaseWeight(for: tissue)
            ))
        }

        guard !candidates.isEmpty else {
            return TriangulationResult(
                summary: .unableToAssess,
                opticalPallorIndex: nil as Double?,
                contributions: ordered(excludedContributions),
                rejectionReasons: rejectionReasons.isEmpty
                    ? ["At least one usable tissue scan is required."]
                    : rejectionReasons,
                configurationIdentifier: configuration.identifier,
                configurationVersion: configuration.semanticVersion,
                mode: configuration.mode,
                calibrationCategory: configuration.calibrationCategory,
                calibratedDecisionThreshold: configuration.decisionThreshold,
                omittedTissues: omittedTissues,
                reliabilityLabel: "Unavailable"
            )
        }

        let normalizedSiteWeights = dynamicSiteWeights(for: candidates.map { $0.output.tissue })
        let dynamicWeightTotal = normalizedSiteWeights.values.reduce(0, +)
        guard dynamicWeightTotal.isFinite, dynamicWeightTotal > 0 else {
            return TriangulationResult.unableToAssess(
                reason: "The modality weights could not be normalized.",
                configuration: configuration
            )
        }
        let includedContributions = candidates.map { candidate in
            let normalizedWeight = normalizedSiteWeights[candidate.output.tissue] ?? 0
            return TissueContribution(
                tissue: candidate.output.tissue,
                probability: candidate.output.probability,
                variance: candidate.variance,
                inverseVarianceWeight: candidate.priorityMultiplier,
                normalizedWeight: normalizedWeight,
                priorityMultiplier: candidate.priorityMultiplier,
                weightedValue: normalizedWeight * candidate.output.probability,
                proxySignalObserved: candidate.output.proxySignalObserved,
                status: .included
            )
        }
        let rawOpticalPallorIndex = includedContributions.reduce(0) { $0 + $1.weightedValue }
        let clinicalRiskMultiplier = clinicalRiskMultiplier(for: demographicProfile)
        let opticalNormalizationFactor = opticalNormalizationFactor(for: demographicProfile)
        let opticalPallorIndex = min(
            max(rawOpticalPallorIndex * opticalNormalizationFactor * clinicalRiskMultiplier, 0),
            1
        )
        let severity = AnemiaSeverity.from(probability: opticalPallorIndex)
        let estimatedHemoglobin = calculateEstimatedHemoglobin(
            probability: opticalPallorIndex,
            biologicalSexRawValue: biologicalSexRawValue ?? demographicProfile?.biologicalSex.rawValue,
            recentLabHemoglobin: recentLabHemoglobin ?? demographicProfile?.recentLabHemoglobin,
            clinicalRiskMultiplier: clinicalRiskMultiplier
        )
        let analyzedTissues = includedContributions.map(\.tissue)
        return TriangulationResult(
            summary: opticalPallorIndex >= configuration.decisionThreshold
                ? OpticalRiskSummary.possibleAnemiaRisk
                : OpticalRiskSummary.lowerObservedRisk,
            opticalPallorIndex: opticalPallorIndex,
            contributions: ordered(includedContributions + excludedContributions),
            rejectionReasons: rejectionReasons,
            configurationIdentifier: configuration.identifier,
            configurationVersion: configuration.semanticVersion,
            mode: configuration.mode,
            calibrationCategory: configuration.calibrationCategory,
            calibratedDecisionThreshold: configuration.decisionThreshold,
            severity: severity,
            estimatedHemoglobin: estimatedHemoglobin,
            isCriticalEmergency: isCriticalEmergency(
                estimatedHemoglobin: estimatedHemoglobin,
                demographicProfile: demographicProfile
            ),
            analyzedTissues: analyzedTissues,
            omittedTissues: omittedTissues,
            reliabilityLabel: reliabilityLabel(for: analyzedTissues.count)
        )
    }

    private func isCriticalEmergency(
        estimatedHemoglobin: Double?,
        demographicProfile: DemographicProfile?
    ) -> Bool {
        if let estimatedHemoglobin,
           estimatedHemoglobin.isFinite,
           estimatedHemoglobin < 7.0 {
            return true
        }

        guard let demographicProfile else { return false }
        return demographicProfile.hasActiveChestPain
            || demographicProfile.hasRecentSyncope
            || demographicProfile.hasSevereRestingShortnessOfBreath
    }

    private func siteBaseWeight(for tissue: TissueSite) -> Double {
        switch tissue {
        case .eye:
            return 0.45
        case .tongue:
            return 0.35
        case .nail:
            return 0.20
        }
    }

    private func dynamicSiteWeights(for tissues: [TissueSite]) -> [TissueSite: Double] {
        let uniqueTissues = Array(Set(tissues))
        let total = uniqueTissues.reduce(0.0) { partialResult, tissue in
            partialResult + siteBaseWeight(for: tissue)
        }
        guard total > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: uniqueTissues.map { tissue in
            (tissue, siteBaseWeight(for: tissue) / total)
        })
    }

    private func reliabilityLabel(for usableSiteCount: Int) -> String {
        switch usableSiteCount {
        case 3:
            return "Higher reliability"
        case 2:
            return "Moderate reliability"
        case 1:
            return "Lower reliability"
        default:
            return "Unavailable"
        }
    }

    private func excludedContribution(
        output: TissueScreeningOutput,
        priorityMultiplier: Double,
        status: TissueFusionStatus
    ) -> TissueContribution {
        TissueContribution(
            tissue: output.tissue,
            probability: output.probability,
            variance: output.predictiveVariance,
            inverseVarianceWeight: 0,
            normalizedWeight: 0,
            priorityMultiplier: priorityMultiplier,
            weightedValue: 0,
            proxySignalObserved: output.proxySignalObserved,
            status: status
        )
    }

    private func omittedContribution(for tissue: TissueSite) -> TissueContribution {
        TissueContribution(
            tissue: tissue,
            probability: 0,
            variance: nil,
            inverseVarianceWeight: 0,
            normalizedWeight: 0,
            priorityMultiplier: siteBaseWeight(for: tissue),
            weightedValue: 0,
            proxySignalObserved: false,
            status: .omitted
        )
    }

    private func ordered(_ contributions: [TissueContribution]) -> [TissueContribution] {
        TissueSite.allCases.compactMap { tissue in
            contributions.first { $0.tissue == tissue }
        }
    }

    func evaluateTissueScreening(
        tissue: TissueSite,
        image: UIImage,
        lockedThreshold: Double,
        modelVersion: String,
        preprocessingVersion: String
    ) async -> TissueScreeningOutput? {
        let imageBox = UnsafeUIImageBox(image: image)
        return try? await backgroundInference {
            let predictionStart = ContinuousClock.now
            let pixelBuffer: CVPixelBuffer? = switch tissue {
            case .eye:
                pixelBuffer(from: imageBox.image)
            case .tongue, .nail:
                nil as CVPixelBuffer?
            }

            guard let pixelBuffer else {
                return nil as TissueScreeningOutput?
            }

            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuOnly
                let probability: Double

                switch tissue {
                case .eye:
                    let model = try ConjunctivaModel(configuration: configuration)
                    let output = try model.prediction(image: pixelBuffer)
                    probability = try scalarProbability(
                        from: output.featureValue(for: "anemia_probability")?.multiArrayValue,
                        featureName: "anemia_probability",
                        classIndex: 1
                    )
                case .tongue, .nail:
                    return nil as TissueScreeningOutput?
                }

                return TissueScreeningOutput(
                    tissue: tissue,
                    probability: probability,
                    lockedThreshold: lockedThreshold,
                    qualityAccepted: true,
                    rejectionReasons: [],
                    modelVersion: modelVersion,
                    preprocessingVersion: preprocessingVersion,
                    isEngineeringFixture: false,
                    predictiveUncertainty: 0,
                    uncertaintyThreshold: Self.defaultUncertaintyThreshold,
                    uncertaintyPassCount: 1,
                    uncertaintyEnforced: false,
                    inferenceDurationMs: predictionStart.duration(to: .now).milliseconds,
                    computeUnits: .cpuOnly
                )
            } catch {
                return TissueScreeningOutput(
                    tissue: tissue,
                    probability: 0,
                    lockedThreshold: lockedThreshold,
                    qualityAccepted: false,
                    rejectionReasons: ["CoreML inference failed for \(tissue.rawValue): \(error.localizedDescription)"],
                    modelVersion: modelVersion,
                    preprocessingVersion: preprocessingVersion,
                    isEngineeringFixture: false,
                    predictiveUncertainty: nil as Double?,
                    uncertaintyThreshold: nil as Double?,
                    uncertaintyPassCount: 0,
                    uncertaintyEnforced: false,
                    inferenceDurationMs: predictionStart.duration(to: .now).milliseconds,
                    computeUnits: .cpuOnly
                )
            }
        }
    }

    func calculateEstimatedHemoglobin(
        probability: Double?,
        biologicalSexRawValue: String?,
        recentLabHemoglobin: Double?,
        clinicalRiskMultiplier: Double
    ) -> Double? {
        guard let probability else { return nil }

        let normalizedProbability = min(max(probability, 0), 1)
        let baseline = baselineHemoglobin(
            biologicalSexRawValue: biologicalSexRawValue,
            recentLabHemoglobin: recentLabHemoglobin
        )
        let riskAdjustedBaseline = max(5.5, baseline / max(clinicalRiskMultiplier, 1))
        let projectedReduction = min(4.5, normalizedProbability * 4.0)
        let estimatedValue = max(5.0, riskAdjustedBaseline - projectedReduction)

        return estimatedValue
    }

    func calculateEstimatedHemoglobin(
        from image: UIImage?,
        probability: Double?,
        age: Int?,
        biologicalSexRawValue: String?,
        recentLabHemoglobin: Double?,
        clinicalRiskMultiplier: Double
    ) async -> Double? {
        guard let image else {
            return calculateEstimatedHemoglobin(
                probability: probability,
                biologicalSexRawValue: biologicalSexRawValue,
                recentLabHemoglobin: recentLabHemoglobin,
                clinicalRiskMultiplier: clinicalRiskMultiplier
            )
        }

        do {
            return try await predictHemoglobin(
                from: image,
                age: age,
                biologicalSexRawValue: biologicalSexRawValue
            )
        } catch {
            return calculateEstimatedHemoglobin(
                probability: probability,
                biologicalSexRawValue: biologicalSexRawValue,
                recentLabHemoglobin: recentLabHemoglobin,
                clinicalRiskMultiplier: clinicalRiskMultiplier
            )
        }
    }

    func clinicalRiskMultiplier(for demographicProfile: DemographicProfile?) -> Double {
        guard let demographicProfile else { return 1.0 }

        var multiplier = 1.0
        if demographicProfile.experiencesFatigue { multiplier *= 1.08 }
        if demographicProfile.experiencesDizziness { multiplier *= 1.06 }
        if demographicProfile.veganOrVegetarian { multiplier *= 1.10 }
        if demographicProfile.heavyMenstrualBleeding { multiplier *= 1.12 }
        if demographicProfile.previousAnemiaDiagnosis { multiplier *= 1.20 }
        if demographicProfile.isPregnant { multiplier *= 1.05 }

        return multiplier
    }

    func opticalNormalizationFactor(for demographicProfile: DemographicProfile?) -> Double {
        guard let demographicProfile else { return 1.0 }

        var factor = 1.0

        switch demographicProfile.fitzpatrickSkinPhototype {
        case .typeI:
            factor *= 0.99
        case .typeII:
            factor *= 1.0
        case .typeIII:
            factor *= 1.01
        case .typeIV:
            factor *= 1.015
        case .typeV:
            factor *= 1.025
        case .typeVI:
            factor *= 1.035
        case .none, .notProvided:
            break
        }

        switch demographicProfile.lightingEnvironment {
        case .indoor:
            factor *= 1.0
        case .naturalSunlight:
            factor *= 0.99
        case .lowLight:
            factor *= 1.04
        case .none, .notProvided:
            break
        }

        return min(max(factor, 0.94), 1.08)
    }

    private func baselineHemoglobin(
        biologicalSexRawValue: String?,
        recentLabHemoglobin: Double?
    ) -> Double {
        if let recentLabHemoglobin,
           recentLabHemoglobin.isFinite,
           recentLabHemoglobin > 0 {
            return recentLabHemoglobin
        }

        switch biologicalSexRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "male":
            return 15.0
        case "female":
            return 13.5
        default:
            return 14.0
        }
    }

    private func predictHemoglobin(
        from image: UIImage,
        age: Int?,
        biologicalSexRawValue: String?
    ) async throws -> Double {
        let imageBox = UnsafeUIImageBox(image: image)
        return try await backgroundInference {
            guard let pixelBuffer = pixelBuffer(from: imageBox.image) else {
                throw HemoglobinPredictionError.invalidImage
            }
            let demographics = try demographicsArray(
                age: age,
                biologicalSexRawValue: biologicalSexRawValue
            )
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let model = try HbRegressionModel(configuration: configuration)
            let output = try model.prediction(image: pixelBuffer, demographics: demographics)
            return try scalarValue(
                from: output.featureValue(for: "hb_g_dl")?.multiArrayValue,
                featureName: "hb_g_dl"
            )
        }
    }

    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let targetSize = CGSize(
            width: Self.coreMLImageDimension,
            height: Self.coreMLImageDimension
        )
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var maybePixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &maybePixelBuffer
        )
        guard status == kCVReturnSuccess,
              let pixelBuffer = maybePixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                  data: baseAddress,
                  width: Int(targetSize.width),
                  height: Int(targetSize.height),
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: targetSize))

        guard let cgImage = image.cgImage else {
            return nil
        }
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return pixelBuffer
    }

    private func demographicsArray(
        age: Int?,
        biologicalSexRawValue: String?
    ) throws -> MLMultiArray {
        // The generated wrapper exposes only a 1x2 float tensor, so we pass
        // `[ageInYears, sexCode]` until the training-side feature contract is documented.
        let values = [
            Float(age ?? 0),
            demographicSexCode(from: biologicalSexRawValue),
        ]
        let array = try MLMultiArray(shape: [1, 2], dataType: .float32)
        for (index, value) in values.enumerated() {
            array[index] = NSNumber(value: value)
        }
        return array
    }

    private func demographicSexCode(from biologicalSexRawValue: String?) -> Float {
        switch biologicalSexRawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "male":
            return 1
        case "female":
            return 0
        default:
            return 0.5
        }
    }

    private func scalarProbability(
        from array: MLMultiArray?,
        featureName: String,
        classIndex: Int
    ) throws -> Double {
        let value = try scalarValue(
            from: array,
            featureName: featureName,
            fallbackIndex: classIndex
        )
        return min(max(value, 0), 1)
    }

    private func scalarValue(
        from array: MLMultiArray?,
        featureName: String,
        fallbackIndex: Int = 0
    ) throws -> Double {
        guard let array, array.count > 0 else {
            throw HemoglobinPredictionError.missingOutput(featureName)
        }
        let targetIndex = array.count > fallbackIndex ? fallbackIndex : 0
        switch array.dataType {
        case .double:
            return Double(array[targetIndex].doubleValue)
        case .float32, .float16:
            return array[targetIndex].doubleValue
        case .int32:
            return Double(array[targetIndex].intValue)
        case .int8:
            return Double(array[targetIndex].int8Value)
        @unknown default:
            return array[targetIndex].doubleValue
        }
    }

    private func backgroundInference<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private enum HemoglobinPredictionError: Error {
    case invalidImage
    case missingOutput(String)
}

private struct FusionCandidate {
    let output: TissueScreeningOutput
    let variance: Double
    let inverseVarianceWeight: Double
    let priorityMultiplier: Double
}

private struct UnsafeUIImageBox: @unchecked Sendable {
    let image: UIImage
}
