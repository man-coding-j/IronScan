import CoreVideo
import XCTest
@testable import IronScan

final class LiveInferenceEngineTests: XCTestCase {
    func testPallorModelInitializesWithAllComputeUnits() async throws {
        let registry = ModelRegistryActor(
            resources: .runtimeBundle(),
            computeUnits: .all,
            metrics: InferenceMetricsRecorder()
        )

        let handle = try await registry.pallorModel()

        XCTAssertEqual(handle.computeUnits, .all)
        XCTAssertEqual(handle.manifest.input.dimensions, [1, 224, 224, 3])
        XCTAssertEqual(handle.manifest.resize.method, .scaleFill)
    }

    func testLivePallorPredictionUsesLockedManifestThreshold() async throws {
        let engine = makeEngine(minimumInterval: .zero)
        let frame = try makeFrame()

        let result = try await engine.predict(frame)
        let prediction = try XCTUnwrap(result)

        XCTAssertTrue((0...1).contains(prediction.calibratedProbability))
        XCTAssertEqual(prediction.lockedThreshold, 0.16261848541234136, accuracy: 1e-12)
        XCTAssertEqual(
            prediction.exceedsLockedThreshold,
            prediction.calibratedProbability >= prediction.lockedThreshold
        )
        XCTAssertTrue(prediction.isEngineeringFixture)
    }

    func testLivePallorInferenceIsThrottled() async throws {
        let engine = makeEngine(minimumInterval: .seconds(60))
        let frame = try makeFrame()

        let first = try await engine.predict(frame)
        let second = try await engine.predict(frame)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
    }

    func testRepeatedPallorInferenceIsDeterministic() async throws {
        let engine = makeEngine(minimumInterval: .zero)
        let frame = try makeFrame()

        let firstResult = try await engine.predict(frame)
        let secondResult = try await engine.predict(frame)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)

        XCTAssertEqual(first.calibratedProbability, second.calibratedProbability, accuracy: 1e-6)
    }

    func testPixelBufferConversionPerformance() throws {
        let source = try SyntheticTongueFrameFactory.makePixelBuffer(width: 1280, height: 720)
        let resize = ModelManifest.Resize(method: .scaleFill, interpolation: "vImageHighQuality")
        let preflight = try PixelBufferFactory.makeBuffer(from: source, width: 224, height: 224, resize: resize)
        XCTAssertEqual(CVPixelBufferGetWidth(preflight), 224)
        XCTAssertEqual(CVPixelBufferGetHeight(preflight), 224)

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        var conversionError: Error?
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            do {
                _ = try PixelBufferFactory.makeBuffer(from: source, width: 224, height: 224, resize: resize)
            } catch {
                conversionError = error
            }
        }
        if let conversionError {
            throw conversionError
        }
    }

    private func makeFrame() throws -> AnalyzableFrame {
        AnalyzableFrame(
            pixelBuffer: try SyntheticTongueFrameFactory.makePixelBuffer(width: 224, height: 224),
            timestamp: .zero
        )
    }

    private func makeEngine(minimumInterval: Duration) -> LiveInferenceEngine {
        let metrics = InferenceMetricsRecorder()
        let registry = ModelRegistryActor(
            resources: .runtimeBundle(),
            computeUnits: .cpuOnly,
            metrics: metrics
        )
        return LiveInferenceEngine(
            registry: registry,
            metrics: metrics,
            minimumInterval: minimumInterval
        )
    }
}
