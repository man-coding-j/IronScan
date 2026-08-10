import Foundation

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
        calibrationCategory: DemographicCalibrationCategory = .generalResearchProfile,
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

enum TissueFusionStatus: String, Equatable, Sendable {
    case included
    case uncertainRescanRecommended
    case qualityRejected
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
    let contributions: [TissueContribution]
    let rejectionReasons: [String]
    let configurationIdentifier: String
    let configurationVersion: String
    let mode: TriangulationMode
    let calibrationCategory: DemographicCalibrationCategory
    let calibratedDecisionThreshold: Double

    func contribution(for tissue: TissueSite) -> TissueContribution? {
        contributions.first { $0.tissue == tissue }
    }
}

struct TriangulationEngine: Sendable {
    func evaluate(
        outputs: [TissueSite: TissueScreeningOutput],
        configuration: TriangulationConfiguration,
        allowEngineeringFixtures: Bool
    ) -> TriangulationResult {
        guard Set(outputs.keys) == Set(TissueSite.allCases) else {
            return unableToAssess(
                reason: "All three tissue scans are required.",
                configuration: configuration
            )
        }

        var candidates = [FusionCandidate]()
        var excludedContributions = [TissueContribution]()
        var rejectionReasons = [String]()
        for tissue in TissueSite.allCases {
            guard let output = outputs[tissue],
                  output.tissue == tissue,
                  let priorityMultiplier = configuration.priorityMultipliers[tissue],
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
                    priorityMultiplier: priorityMultiplier,
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
                    priorityMultiplier: priorityMultiplier,
                    status: .uncertainRescanRecommended
                ))
                rejectionReasons.append("The \(tissue.rawValue) scan is uncertain; re-scan recommended.")
                continue
            }

            candidates.append(FusionCandidate(
                output: output,
                variance: variance,
                inverseVarianceWeight: 1 / (variance + configuration.inverseVarianceEpsilon),
                priorityMultiplier: priorityMultiplier
            ))
        }

        guard candidates.count >= 2 else {
            return TriangulationResult(
                summary: .unableToAssess,
                opticalPallorIndex: nil,
                contributions: ordered(excludedContributions),
                rejectionReasons: rejectionReasons.isEmpty
                    ? ["At least two usable tissue scans are required."]
                    : rejectionReasons,
                configurationIdentifier: configuration.identifier,
                configurationVersion: configuration.semanticVersion,
                mode: configuration.mode,
                calibrationCategory: configuration.calibrationCategory,
                calibratedDecisionThreshold: configuration.decisionThreshold
            )
        }

        let inverseVarianceTotal = candidates.reduce(0) { $0 + $1.inverseVarianceWeight }
        guard inverseVarianceTotal.isFinite, inverseVarianceTotal > 0 else {
            return unableToAssess(
                reason: "The uncertainty weights could not be normalized.",
                configuration: configuration
            )
        }
        let includedContributions = candidates.map { candidate in
            let normalizedWeight = candidate.inverseVarianceWeight / inverseVarianceTotal
            return TissueContribution(
                tissue: candidate.output.tissue,
                probability: candidate.output.probability,
                variance: candidate.variance,
                inverseVarianceWeight: candidate.inverseVarianceWeight,
                normalizedWeight: normalizedWeight,
                priorityMultiplier: candidate.priorityMultiplier,
                weightedValue: normalizedWeight * candidate.output.probability * candidate.priorityMultiplier,
                proxySignalObserved: candidate.output.proxySignalObserved,
                status: .included
            )
        }
        let rawOpticalPallorIndex = includedContributions.reduce(0) { $0 + $1.weightedValue }
        let opticalPallorIndex = min(max(rawOpticalPallorIndex, 0), 1)
        return TriangulationResult(
            summary: opticalPallorIndex >= configuration.decisionThreshold
                ? .possibleAnemiaRisk
                : .lowerObservedRisk,
            opticalPallorIndex: opticalPallorIndex,
            contributions: ordered(includedContributions + excludedContributions),
            rejectionReasons: rejectionReasons,
            configurationIdentifier: configuration.identifier,
            configurationVersion: configuration.semanticVersion,
            mode: configuration.mode,
            calibrationCategory: configuration.calibrationCategory,
            calibratedDecisionThreshold: configuration.decisionThreshold
        )
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

    private func ordered(_ contributions: [TissueContribution]) -> [TissueContribution] {
        TissueSite.allCases.compactMap { tissue in
            contributions.first { $0.tissue == tissue }
        }
    }

    private func unableToAssess(
        reason: String,
        configuration: TriangulationConfiguration
    ) -> TriangulationResult {
        TriangulationResult(
            summary: .unableToAssess,
            opticalPallorIndex: nil,
            contributions: [],
            rejectionReasons: [reason],
            configurationIdentifier: configuration.identifier,
            configurationVersion: configuration.semanticVersion,
            mode: configuration.mode,
            calibrationCategory: configuration.calibrationCategory,
            calibratedDecisionThreshold: configuration.decisionThreshold
        )
    }
}

private struct FusionCandidate {
    let output: TissueScreeningOutput
    let variance: Double
    let inverseVarianceWeight: Double
    let priorityMultiplier: Double
}
