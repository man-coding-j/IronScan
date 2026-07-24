import XCTest
@testable import IronScan

@MainActor
final class InferenceParityTests: XCTestCase {
    func testSegmentationMaskParityWithPython() async throws {
        let metrics = InferenceMetricsRecorder()
        let actor = SegmentationInferenceActor(
            registry: try MLTestSupport.registry(metrics: metrics),
            metrics: metrics
        )
        let input = try MLTestSupport.pixelBuffer(
            data: MLTestSupport.fixtureData(named: "segmentation_input", extension: "bgra"),
            width: 64,
            height: 64
        )
        let golden = try MLTestSupport.fixtureJSON(named: "segmentation_output", as: SegmentationGolden.self)

        let result = try await actor.segment(OrientationNormalizedCapture(pixelBuffer: input, colorSpace: "sRGB"))
        let expected = golden.expectedMaskRows.flatMap { row in row.map { $0 == "1" ? UInt8(1) : UInt8(0) } }
        XCTAssertEqual(expected.count, result.binaryMask.count)
        let intersection = zip(expected, result.binaryMask).filter { $0 == 1 && $1 == 1 }.count
        let totalForeground = expected.filter { $0 == 1 }.count + result.binaryMask.filter { $0 == 1 }.count
        let dice = totalForeground == 0 ? 1 : Double(2 * intersection) / Double(totalForeground)
        XCTAssertGreaterThanOrEqual(dice, golden.minimumDice)
        XCTAssertEqual(result.probabilityMask[32 * 64 + 32], Float(golden.probabilitySamples["center"] ?? 0), accuracy: Float(golden.floatTolerance))
        XCTAssertEqual(result.probabilityMask[0], Float(golden.probabilitySamples["corner"] ?? 0), accuracy: Float(golden.floatTolerance))
    }

    func testRiskScoreParityWithPython() async throws {
        let metrics = InferenceMetricsRecorder()
        let actor = RiskInferenceActor(
            registry: try MLTestSupport.registry(metrics: metrics),
            metrics: metrics
        )
        let golden = try MLTestSupport.fixtureJSON(named: "risk_output", as: RiskGolden.self)

        let prediction = try await actor.predict(MLTestSupport.riskSample())

        XCTAssertEqual(prediction.rawScore, golden.expectedRawScore, accuracy: golden.probabilityTolerance)
        XCTAssertEqual(
            prediction.calibratedProbability,
            golden.expectedCalibratedProbability,
            accuracy: golden.probabilityTolerance
        )
        XCTAssertEqual(prediction.decision.rawValue, golden.expectedDecision)
    }

    func testRepeatedInferenceIsDeterministic() async throws {
        let metrics = InferenceMetricsRecorder()
        let actor = RiskInferenceActor(
            registry: try MLTestSupport.registry(metrics: metrics),
            metrics: metrics
        )
        let sample = try MLTestSupport.riskSample()
        let first = try await actor.predict(sample)

        for _ in 0..<10 {
            let result = try await actor.predict(sample)
            XCTAssertEqual(result.rawScore, first.rawScore, accuracy: 0.000_001)
            XCTAssertEqual(result.calibratedProbability, first.calibratedProbability, accuracy: 0.000_001)
            XCTAssertEqual(result.decision, first.decision)
        }
    }

    func testCPUOnlyAndAllComputeUnitsAreWithinTolerance() async throws {
        let cpuMetrics = InferenceMetricsRecorder()
        let allMetrics = InferenceMetricsRecorder()
        let cpuActor = RiskInferenceActor(
            registry: try MLTestSupport.registry(computeUnits: .cpuOnly, metrics: cpuMetrics),
            metrics: cpuMetrics
        )
        let allActor = RiskInferenceActor(
            registry: try MLTestSupport.registry(computeUnits: .all, metrics: allMetrics),
            metrics: allMetrics
        )
        let sample = try MLTestSupport.riskSample()

        let cpu = try await cpuActor.predict(sample)
        let all = try await allActor.predict(sample)

        XCTAssertEqual(cpu.calibratedProbability, all.calibratedProbability, accuracy: 0.01)
        XCTAssertEqual(cpu.decision, all.decision)
    }

    func testPixelBufferPreprocessingIsByteExactAtLockedDimensions() throws {
        let sourceData = try MLTestSupport.fixtureData(named: "risk_input", extension: "bgra")
        let source = try MLTestSupport.pixelBuffer(data: sourceData, width: 32, height: 32)
        let resized = try PixelBufferFactory.makeBuffer(
            from: source,
            width: 32,
            height: 32,
            resize: ModelManifest.Resize(method: .scaleFill, interpolation: "vImageHighQuality")
        )
        XCTAssertEqual(try bytes(from: resized), sourceData)
    }

    func testPhysicalYUVPhotoBufferConvertsToBGRAWithoutEncoding() throws {
        let source = try makeYUVPixelBuffer(width: 32, height: 24)

        let converted = try PixelBufferFactory.makeBGRA(from: source)

        XCTAssertEqual(CVPixelBufferGetPixelFormatType(converted), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(CVPixelBufferGetWidth(converted), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(converted), 24)
        XCTAssertEqual(try bytes(from: converted).count, 32 * 24 * 4)
    }

    private func makeYUVPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let creationStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &optionalBuffer
        )
        guard creationStatus == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw InferenceError.pixelBufferAllocationFailed(creationStatus)
        }
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw InferenceError.pixelBufferLockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let luminanceBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
            throw InferenceError.invalidDimensions
        }
        memset(luminanceBase, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * height)
        memset(chromaBase, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * (height / 2))
        return buffer
    }

    private func bytes(from buffer: CVPixelBuffer) throws -> Data {
        let status = CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard status == kCVReturnSuccess, let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw InferenceError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var data = Data(capacity: width * height * 4)
        for row in 0..<height {
            data.append(baseAddress.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self), count: width * 4)
        }
        return data
    }
}
