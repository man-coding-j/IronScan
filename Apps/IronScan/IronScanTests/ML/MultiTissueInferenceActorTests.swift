import CoreVideo
import XCTest
@testable import IronScan

final class MultiTissueInferenceActorTests: XCTestCase {
    func testModelsLoadOnceAcrossRepeatedPreloadAndPrediction() async throws {
        let actor = MultiTissueInferenceActor(computeUnits: .cpuOnly)
        let frame = try makeFrame()

        let firstReadiness = try await actor.preloadModels()
        let secondReadiness = try await actor.preloadModels()
        XCTAssertEqual(firstReadiness, secondReadiness)

        for tissue in TissueSite.allCases {
            _ = try await actor.predict(frame: frame, tissue: tissue)
            _ = try await actor.predict(frame: frame, tissue: tissue)
        }

        let counts = await actor.loadCounts
        XCTAssertEqual(counts, [.eye: 1, .nail: 1, .tongue: 1])
    }

    func testRepeatedPredictionsAreDeterministicForEveryTissue() async throws {
        let actor = MultiTissueInferenceActor(computeUnits: .cpuOnly)
        let frame = try makeFrame()

        for tissue in TissueSite.allCases {
            let first = try await actor.predict(frame: frame, tissue: tissue)
            let second = try await actor.predict(frame: frame, tissue: tissue)

            XCTAssertEqual(first.tissue, tissue)
            XCTAssertEqual(first.probability, second.probability, accuracy: 1e-6)
            XCTAssertEqual(
                try XCTUnwrap(first.predictiveUncertainty),
                try XCTUnwrap(second.predictiveUncertainty),
                accuracy: 1e-6
            )
            XCTAssertTrue((0...1).contains(first.probability))
            XCTAssertEqual(first.uncertaintyPassCount, 30)
            XCTAssertTrue(first.qualityAccepted)
            XCTAssertTrue(first.isEngineeringFixture)
            XCTAssertEqual(first.computeUnits, .cpuOnly)
        }
    }

    func testEyeUsesClinicalModelContract() async throws {
        let actor = MultiTissueInferenceActor(computeUnits: .cpuOnly)
        let output = try await actor.predict(frame: makeFrame(), tissue: .eye)

        XCTAssertEqual(output.modelVersion, "0.3.1-engineering.1")
        XCTAssertEqual(output.preprocessingVersion, "multimodal-eye-clinical-2.1.0")
        XCTAssertNotNil(output.predictiveUncertainty)
        XCTAssertNotNil(output.uncertaintyThreshold)
    }

    func testConjunctivaRegionUsesLowerQuarterOfEyeLandmarks() throws {
        let region = try ConjunctivaRegionCalculator.lowerQuarter(
            faceBoundingBox: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
            eyePoints: [
                CGPoint(x: 0.2, y: 0.6),
                CGPoint(x: 0.4, y: 0.6),
                CGPoint(x: 0.4, y: 0.7),
                CGPoint(x: 0.2, y: 0.7),
            ]
        )

        XCTAssertEqual(region.minX, 0.32, accuracy: 1e-12)
        XCTAssertEqual(region.maxX, 0.44, accuracy: 1e-12)
        XCTAssertEqual(region.minY, 0.58, accuracy: 1e-12)
        XCTAssertEqual(region.height, 0.02, accuracy: 1e-12)
    }

    func testConjunctivaRegionMatchesPythonGoldenGeometry() throws {
        struct Golden: Decodable {
            let faceBoundingBox: [Double]
            let eyePoints: [[Double]]
            let expectedLowerQuarter: [Double]
        }
        let golden = try MLTestSupport.fixtureJSON(
            named: "conjunctiva_crop_output",
            as: Golden.self
        )
        let face = golden.faceBoundingBox
        let expected = golden.expectedLowerQuarter
        let region = try ConjunctivaRegionCalculator.lowerQuarter(
            faceBoundingBox: CGRect(
                x: face[0],
                y: face[1],
                width: face[2],
                height: face[3]
            ),
            eyePoints: golden.eyePoints.map { CGPoint(x: $0[0], y: $0[1]) }
        )

        XCTAssertEqual(region.minX, expected[0], accuracy: 1e-12)
        XCTAssertEqual(region.minY, expected[1], accuracy: 1e-12)
        XCTAssertEqual(region.width, expected[2], accuracy: 1e-12)
        XCTAssertEqual(region.height, expected[3], accuracy: 1e-12)
    }

    func testEyePreviewAssessmentUsesLockedUncertaintyThreshold() {
        let accepted = EyePreviewAssessment(
            predictiveMean: 0.4,
            predictiveUncertainty: 0.03,
            uncertaintyThreshold: 0.05,
            uncertaintyPassCount: 30
        )
        let rejected = EyePreviewAssessment(
            predictiveMean: 0.4,
            predictiveUncertainty: 0.08,
            uncertaintyThreshold: 0.05,
            uncertaintyPassCount: 30
        )

        XCTAssertTrue(accepted.uncertaintyAccepted)
        XCTAssertFalse(rejected.uncertaintyAccepted)
        XCTAssertEqual(rejected.predictiveVariance, 0.0064, accuracy: 1e-12)
    }

    private func makeFrame() throws -> CapturedFrame {
        CapturedFrame(
            pixelBuffer: try SyntheticTongueFrameFactory.makePixelBuffer(width: 320, height: 240),
            metadata: CaptureMetadata(
                captureTimestamp: Date(timeIntervalSince1970: 1),
                deviceModelIdentifier: "synthetic-test-device",
                cameraDeviceType: "synthetic",
                activeFormatWidth: 320,
                activeFormatHeight: 240,
                pixelFormat: "32BGRA",
                exposureDurationSeconds: 1 / 60,
                iso: 100,
                lensPosition: 0.5,
                whiteBalanceGains: WhiteBalanceMetadata(redGain: 1, greenGain: 1, blueGain: 1),
                exposureTargetOffset: 0,
                torchLevel: 0,
                focusMode: "locked",
                exposureMode: "locked",
                whiteBalanceMode: "locked",
                orientation: "portrait",
                focusWasLocked: true,
                exposureWasLocked: true,
                whiteBalanceWasLocked: true,
                sourceColorSpace: "sRGB",
                photoWidth: 320,
                photoHeight: 240
            ),
            quality: QualityObservation(
                readiness: .ready,
                sharpnessScore: 1,
                clippedHighlightFraction: 0,
                motionScore: 0,
                meanLuminance: 0.5,
                tongueCoverage: 0.5,
                tongueCenterOffset: 0
            )
        )
    }
}
