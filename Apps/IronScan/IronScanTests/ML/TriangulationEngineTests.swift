import XCTest
@testable import IronScan

final class TriangulationEngineTests: XCTestCase {
    func testValidatedConfigurationProducesDeterministicInverseVarianceIndex() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        let outputs = makeOutputs(
            eye: 0.8,
            nail: 0.4,
            tongue: 0.2,
            uncertainty: 0.1,
            engineeringFixture: false
        )
        let engine = TriangulationEngine()

        let first = engine.evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )
        let second = engine.evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(try XCTUnwrap(first.opticalPallorIndex), 0.5, accuracy: 1e-12)
        XCTAssertEqual(first.summary, .possibleAnemiaRisk)
        XCTAssertEqual(first.contributions.map(\.tissue), TissueSite.allCases)
        let expectedWeights = [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
        zip(first.contributions.map(\.normalizedWeight), expectedWeights).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 1e-12)
        }
        XCTAssertEqual(first.contributions.map(\.priorityMultiplier), [1.2, 0.9, 0.9])
    }

    func testLowerVarianceReceivesGreaterNormalizedWeight() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        let outputs = [
            TissueSite.eye: makeOutput(
                tissue: .eye,
                probability: 0.5,
                uncertainty: 0.05,
                modelVersion: "eye-1",
                preprocessingVersion: "eye-preprocessing-1",
                engineeringFixture: false
            ),
            TissueSite.nail: makeOutput(
                tissue: .nail,
                probability: 0.5,
                uncertainty: 0.2,
                modelVersion: "nail-1",
                preprocessingVersion: "nail-preprocessing-1",
                engineeringFixture: false
            ),
            TissueSite.tongue: makeOutput(
                tissue: .tongue,
                probability: 0.5,
                uncertainty: 0.3,
                modelVersion: "tongue-1",
                preprocessingVersion: "tongue-preprocessing-1",
                engineeringFixture: false
            ),
        ]

        let result = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        let eyeWeight = try XCTUnwrap(result.contribution(for: .eye)?.normalizedWeight)
        let nailWeight = try XCTUnwrap(result.contribution(for: .nail)?.normalizedWeight)
        let tongueWeight = try XCTUnwrap(result.contribution(for: .tongue)?.normalizedWeight)
        XCTAssertGreaterThan(eyeWeight, nailWeight)
        XCTAssertGreaterThan(nailWeight, tongueWeight)
        XCTAssertEqual(eyeWeight + nailWeight + tongueWeight, 1, accuracy: 1e-12)
    }

    func testConfigurationRequiresAllPriorityMultipliers() {
        XCTAssertThrowsError(try TriangulationConfiguration(
            identifier: "fixture",
            semanticVersion: "1.0.0",
            mode: .prototypeDemo,
            priorityMultipliers: [.eye: 1.2, .tongue: 0.9],
            decisionThreshold: 0.5,
            modelVersions: modelVersions,
            preprocessingVersions: preprocessingVersions
        )) { error in
            XCTAssertEqual(error as? TriangulationConfigurationError, .missingTissueConfiguration)
        }
    }

    func testHighVarianceScanIsExcludedWithoutInvalidatingOtherTwo() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        var outputs = makeOutputs(
            eye: 0.9,
            nail: 0.2,
            tongue: 0.2,
            uncertainty: 0.1,
            engineeringFixture: false
        )
        outputs[.eye] = makeOutput(
            tissue: .eye,
            probability: 0.9,
            uncertainty: 0.4,
            modelVersion: "eye-1",
            preprocessingVersion: "eye-preprocessing-1",
            engineeringFixture: false
        )

        let result = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        XCTAssertEqual(result.summary, .lowerObservedRisk)
        XCTAssertEqual(try XCTUnwrap(result.opticalPallorIndex), 0.18, accuracy: 1e-12)
        XCTAssertEqual(result.contribution(for: .eye)?.status, .uncertainRescanRecommended)
        XCTAssertEqual(result.contribution(for: .eye)?.normalizedWeight, 0.0, accuracy: 1e-12)
        XCTAssertTrue(result.rejectionReasons.contains { $0.contains("re-scan recommended") })
    }

    func testQualityRejectedScanIsExcludedWithoutInvalidatingOtherTwo() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        var outputs = makeOutputs(
            eye: 0.2,
            nail: 0.2,
            tongue: 0.2,
            uncertainty: 0.1,
            engineeringFixture: false
        )
        outputs[.nail] = TissueScreeningOutput(
            tissue: .nail,
            probability: 0.2,
            lockedThreshold: 0.5,
            qualityAccepted: false,
            rejectionReasons: ["Nail image was blurred."],
            modelVersion: "nail-1",
            preprocessingVersion: "nail-preprocessing-1",
            isEngineeringFixture: false,
            predictiveUncertainty: 0.1
        )

        let result = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        XCTAssertEqual(result.summary, .lowerObservedRisk)
        XCTAssertNotNil(result.opticalPallorIndex)
        XCTAssertEqual(result.contribution(for: .nail)?.status, .qualityRejected)
        XCTAssertEqual(result.rejectionReasons, ["Nail image was blurred."])
    }

    func testFewerThanTwoUsableScansReturnsUnableToAssess() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        var outputs = makeOutputs(
            eye: 0.2,
            nail: 0.2,
            tongue: 0.2,
            uncertainty: 0.4,
            engineeringFixture: false
        )
        outputs[.tongue] = makeOutput(
            tissue: .tongue,
            probability: 0.2,
            uncertainty: 0.1,
            modelVersion: "tongue-1",
            preprocessingVersion: "tongue-preprocessing-1",
            engineeringFixture: false
        )

        let result = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        XCTAssertEqual(result.summary, .unableToAssess)
        XCTAssertNil(result.opticalPallorIndex)
    }

    func testEngineeringFixturesRequireExplicitPrototypeDemoAllowance() throws {
        let configuration = try makeConfiguration(mode: .prototypeDemo)
        let outputs = makeOutputs(
            eye: 0.2,
            nail: 0.2,
            tongue: 0.2,
            uncertainty: 0.1,
            engineeringFixture: true
        )

        let blocked = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )
        let allowed = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: true
        )

        XCTAssertEqual(blocked.summary, .unableToAssess)
        XCTAssertEqual(allowed.summary, .lowerObservedRisk)
        XCTAssertEqual(allowed.mode, .prototypeDemo)
    }

    func testModelContractMismatchReturnsUnableToAssessWhenOnlyOneUsableScanRemains() throws {
        let configuration = try makeConfiguration(mode: .researchValidated)
        var outputs = makeOutputs(
            eye: 0.2,
            nail: 0.2,
            tongue: 0.2,
            uncertainty: 0.4,
            engineeringFixture: false
        )
        outputs[.eye] = makeOutput(
            tissue: .eye,
            probability: 0.2,
            uncertainty: 0.1,
            modelVersion: "unexpected",
            preprocessingVersion: "eye-preprocessing-1",
            engineeringFixture: false
        )

        let result = TriangulationEngine().evaluate(
            outputs: outputs,
            configuration: configuration,
            allowEngineeringFixtures: false
        )

        XCTAssertEqual(result.summary, .unableToAssess)
        XCTAssertTrue(result.rejectionReasons.contains { $0.contains("fusion manifest") })
    }

    private var modelVersions: [TissueSite: String] {
        [.eye: "eye-1", .nail: "nail-1", .tongue: "tongue-1"]
    }

    private var preprocessingVersions: [TissueSite: String] {
        [
            .eye: "eye-preprocessing-1",
            .nail: "nail-preprocessing-1",
            .tongue: "tongue-preprocessing-1",
        ]
    }

    private func makeConfiguration(mode: TriangulationMode) throws -> TriangulationConfiguration {
        try TriangulationConfiguration(
            identifier: "org.ironscan.engineering.triangulation",
            semanticVersion: "0.2.0-engineering.1",
            mode: mode,
            decisionThreshold: 0.5,
            modelVersions: modelVersions,
            preprocessingVersions: preprocessingVersions
        )
    }

    private func makeOutputs(
        eye: Double,
        nail: Double,
        tongue: Double,
        uncertainty: Double,
        engineeringFixture: Bool
    ) -> [TissueSite: TissueScreeningOutput] {
        [
            .eye: makeOutput(
                tissue: .eye,
                probability: eye,
                uncertainty: uncertainty,
                modelVersion: "eye-1",
                preprocessingVersion: "eye-preprocessing-1",
                engineeringFixture: engineeringFixture
            ),
            .nail: makeOutput(
                tissue: .nail,
                probability: nail,
                uncertainty: uncertainty,
                modelVersion: "nail-1",
                preprocessingVersion: "nail-preprocessing-1",
                engineeringFixture: engineeringFixture
            ),
            .tongue: makeOutput(
                tissue: .tongue,
                probability: tongue,
                uncertainty: uncertainty,
                modelVersion: "tongue-1",
                preprocessingVersion: "tongue-preprocessing-1",
                engineeringFixture: engineeringFixture
            ),
        ]
    }

    private func makeOutput(
        tissue: TissueSite,
        probability: Double,
        uncertainty: Double,
        modelVersion: String,
        preprocessingVersion: String,
        engineeringFixture: Bool
    ) -> TissueScreeningOutput {
        TissueScreeningOutput(
            tissue: tissue,
            probability: probability,
            lockedThreshold: 0.5,
            qualityAccepted: true,
            rejectionReasons: [],
            modelVersion: modelVersion,
            preprocessingVersion: preprocessingVersion,
            isEngineeringFixture: engineeringFixture,
            predictiveUncertainty: uncertainty,
            uncertaintyThreshold: 0.05,
            uncertaintyPassCount: 30
        )
    }
}
