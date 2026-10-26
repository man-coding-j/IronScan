import Foundation
import XCTest
@testable import IronScan

@MainActor
final class SmartColorCalibrationTests: XCTestCase {
    func testIdentityTransform() async throws {
        let sample = try await calibrate()
        XCTAssertTrue(sample.accepted, "\(sample.rejectionReasons)")
        XCTAssertEqual(sample.calibrationMode, .multiPatchReference, "\(sample.rejectionReasons)")
        XCTAssertLessThan(sample.medianReferenceDeltaE, 1)
        XCTAssertEqual(sample.calibrationMatrix[0], 1, accuracy: 0.01)
        XCTAssertEqual(sample.calibrationMatrix[4], 1, accuracy: 0.01)
        XCTAssertEqual(sample.calibrationMatrix[8], 1, accuracy: 0.01)
    }

    func testSyntheticWarmCastLowersMedianDeltaE() async throws {
        try await assertCastImproves(SIMD3(1.18, 0.94, 0.82))
    }

    func testSyntheticCoolCastLowersMedianDeltaE() async throws {
        try await assertCastImproves(SIMD3(0.84, 0.96, 1.16))
    }

    func testGreenCastLowersMedianDeltaE() async throws {
        try await assertCastImproves(SIMD3(0.92, 1.18, 0.90))
    }

    func testUnderexposureIsBounded() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.tongueExposure = 0.45
        let sample = try await calibrate(
            scenario: scenario,
            configuration: CalibrationTestSupport.configuration(targetTongueLuminance: 0.16)
        )
        XCTAssertEqual(sample.exposureScale, 1.25, accuracy: 0.001)
    }

    func testOverexposureIsBounded() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.tongueExposure = 1.7
        let sample = try await calibrate(
            scenario: scenario,
            configuration: CalibrationTestSupport.configuration(targetTongueLuminance: 0.16)
        )
        XCTAssertEqual(sample.exposureScale, 0.8, accuracy: 0.001)
    }

    func testSaturatedPatchRejects() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.saturatedPatchIndex = 0
        let sample = try await calibrate(scenario: scenario)
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.clippedReferencePatch))
    }

    func testMissingPatchesReject() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.missingPatchIndices = [0, 1, 2]
        let sample = try await calibrate(scenario: scenario)
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.insufficientReferencePatches))
    }

    func testNoisyPatchUsesRobustMedian() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.noisyPatchIndex = 1
        let sample = try await calibrate(scenario: scenario)
        XCTAssertTrue(sample.accepted)
        XCTAssertLessThan(sample.medianReferenceDeltaE, 2)
    }

    func testSpecularSalivaPixelsReject() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.specularFraction = 0.2
        let sample = try await calibrate(scenario: scenario)
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.excessiveSpecularFraction))
    }

    func testShadowGradientRejects() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.shadowGradient = true
        let sample = try await calibrate(
            scenario: scenario,
            configuration: CalibrationTestSupport.configuration(maximumShadowUniformity: 0.3)
        )
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.excessiveShadowGradient))
    }

    func testUnstableMatrixRejects() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.unstablePatches = true
        let sample = try await calibrate(
            scenario: scenario,
            configuration: CalibrationTestSupport.configuration(maximumConditionNumber: 10)
        )
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.unstableMatrix))
    }

    func testTeethFallbackGainClamping() async throws {
        let teeth = CalibrationPatch(
            normalizedRect: CalibrationTestSupport.patchRects[3],
            targetLinearRGB: SIMD3(0.55, 0.50, 0.42),
            weight: 0.35,
            isNeutral: true
        )
        let sample = try await calibrate(configuration: CalibrationTestSupport.configuration(
            includeCardPatches: false,
            teethPatch: teeth,
            maximumShadowUniformity: 1
        ))
        XCTAssertTrue(sample.accepted)
        XCTAssertEqual(sample.calibrationMode, .teethPseudoReference)
        XCTAssertEqual(sample.calibrationConfidence, 0.5)
        XCTAssertTrue([sample.calibrationMatrix[0], sample.calibrationMatrix[4], sample.calibrationMatrix[8]].allSatisfy {
            (0.8...1.2).contains($0)
        })
    }

    func testInvalidMetadataRejects() async throws {
        let sample = try await calibrate(metadata: CalibrationTestSupport.metadata(stable: false))
        XCTAssertFalse(sample.accepted)
        XCTAssertTrue(sample.rejectionReasons.contains(.invalidCaptureMetadata))
    }

    func testInvalidTongueMasksReject() async throws {
        var small = CalibrationTestSupport.Scenario()
        small.smallMask = true
        let smallSample = try await calibrate(scenario: small)
        XCTAssertTrue(smallSample.rejectionReasons.contains(.tongueMaskTooSmall))

        var boundary = CalibrationTestSupport.Scenario()
        boundary.boundaryMask = true
        let boundarySample = try await calibrate(scenario: boundary)
        XCTAssertTrue(boundarySample.rejectionReasons.contains(.tongueMaskTouchesBoundary))
    }

    func testPythonSwiftGoldenParity() async throws {
        let gains = SIMD3<Double>(1.18, 0.94, 0.82)
        var scenario = CalibrationTestSupport.Scenario()
        scenario.gains = gains
        let sample = try await calibrate(scenario: scenario)
        let golden = try JSONDecoder().decode(CalibrationGolden.self, from: try goldenData())
        XCTAssertEqual(sample.calibrationMatrix.count, golden.matrixRowMajor.count)
        for index in sample.calibrationMatrix.indices {
            XCTAssertEqual(sample.calibrationMatrix[index], golden.matrixRowMajor[index], accuracy: golden.tolerance)
        }
        XCTAssertEqual(sample.matrixConditionNumber, golden.conditionNumber, accuracy: 0.03)
    }

    func testRepeatedExecutionIsDeterministic() async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.gains = SIMD3(1.18, 0.94, 0.82)
        let first = try await calibrate(scenario: scenario)
        let second = try await calibrate(scenario: scenario)
        XCTAssertEqual(first.calibrationMatrix, second.calibrationMatrix)
        XCTAssertEqual(first.centralROIMask, second.centralROIMask)
        XCTAssertEqual(first.rejectionReasons, second.rejectionReasons)
        XCTAssertEqual(first.diagnosticFeatures, second.diagnosticFeatures)
    }

    func testTemporaryPixelBuffersReleaseAfterOneHundredCalibrations() async throws {
        let actor = SmartColorCalibrationActor()
        weak var lastOutput: CVPixelBuffer?
        for _ in 0..<100 {
            var sample: CalibratedTongueSample? = try await actor.calibrate(
                capture: CalibrationTestSupport.pixelBuffer(),
                metadata: CalibrationTestSupport.metadata(),
                segmentation: CalibrationTestSupport.segmentation(),
                configuration: CalibrationTestSupport.configuration()
            )
            lastOutput = sample?.calibratedPixelBuffer
            sample = nil
        }
        XCTAssertNil(lastOutput)
    }

    private func assertCastImproves(_ gains: SIMD3<Double>) async throws {
        var scenario = CalibrationTestSupport.Scenario()
        scenario.gains = gains
        let sample = try await calibrate(scenario: scenario)
        XCTAssertTrue(sample.accepted)
        XCTAssertLessThan(sample.medianReferenceDeltaE, CalibrationTestSupport.uncalibratedMedianDeltaE(gains: gains))
    }

    private func calibrate(
        scenario: CalibrationTestSupport.Scenario = CalibrationTestSupport.Scenario(),
        metadata: CalibrationCaptureMetadata = CalibrationTestSupport.metadata(),
        configuration: ColorCalibrationConfiguration = CalibrationTestSupport.configuration()
    ) async throws -> CalibratedTongueSample {
        try await SmartColorCalibrationActor().calibrate(
            capture: CalibrationTestSupport.pixelBuffer(scenario: scenario),
            metadata: metadata,
            segmentation: CalibrationTestSupport.segmentation(scenario: scenario),
            configuration: configuration
        )
    }

    private func goldenData() throws -> Data {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = Bundle(for: SmartColorCalibrationTests.self)
        #endif
        guard let url = bundle.url(
            forResource: "warm_cast",
            withExtension: "json",
            subdirectory: "GoldenOutputs/ColorCalibration"
        ) else {
            throw InferenceError.modelLoadingFailed("Calibration golden is missing")
        }
        return try Data(contentsOf: url)
    }
}

private struct CalibrationGolden: Decodable {
    let conditionNumber: Double
    let matrixRowMajor: [Double]
    let tolerance: Double

    enum CodingKeys: String, CodingKey {
        case conditionNumber = "condition_number"
        case matrixRowMajor = "matrix_row_major"
        case tolerance
    }
}
