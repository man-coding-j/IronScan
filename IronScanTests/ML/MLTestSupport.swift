import CoreVideo
import Foundation
@testable import IronScan

enum MLTestSupport {
    static func resources() throws -> ModelResourceLocations {
        let resources = ModelResourceLocations.runtimeBundle()
        guard resources.segmentationPackageURL != nil,
              resources.segmentationManifestURL != nil,
              resources.riskPackageURL != nil,
              resources.riskManifestURL != nil else {
            throw InferenceError.modelLoadingFailed("Swift package model resources are missing")
        }
        return resources
    }

    static func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
        guard let url = fixtureBundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "PythonGolden"
        ) else {
            throw InferenceError.modelLoadingFailed("Fixture \(name).\(fileExtension) is missing")
        }
        return try Data(contentsOf: url)
    }

    private static var fixtureBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: MLTestBundleToken.self)
        #endif
    }

    static func fixtureJSON<T: Decodable>(named name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: fixtureData(named: name, extension: "json"))
    }

    static func pixelBuffer(data: Data, width: Int, height: Int) throws -> CVPixelBuffer {
        guard data.count == width * height * 4 else { throw InferenceError.invalidDimensions }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw InferenceError.pixelBufferAllocationFailed(status)
        }
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess, let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw InferenceError.pixelBufferLockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        data.withUnsafeBytes { source in
            guard let sourceAddress = source.baseAddress else { return }
            for row in 0..<height {
                memcpy(baseAddress.advanced(by: row * rowBytes), sourceAddress.advanced(by: row * width * 4), width * 4)
            }
        }
        return buffer
    }

    static func riskSample(status: CalibrationStatus = .accepted) throws -> CalibratedTongueSample {
        CalibratedTongueSample(
            pixelBuffer: try pixelBuffer(
                data: fixtureData(named: "risk_input", extension: "bgra"),
                width: 32,
                height: 32
            ),
            colorSpace: "sRGB",
            calibrationStatus: status,
            calibrationDurationMs: 1.25,
            qualitySummary: InferenceQualitySummary(
                segmentationAreaRatio: 0.3,
                segmentationMeanConfidence: 0.8,
                calibrationResidual: 0.02,
                captureQualityScore: 0.9
            )
        )
    }

    static func registry(
        computeUnits: InferenceComputeUnits = .cpuOnly,
        metrics: InferenceMetricsRecorder
    ) throws -> ModelRegistryActor {
        ModelRegistryActor(resources: try resources(), computeUnits: computeUnits, metrics: metrics)
    }

    static func modifiedManifest(
        at url: URL,
        mutate: (inout [String: Any]) -> Void
    ) throws -> ModelManifest {
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw ModelContractError.unreadableManifest("Expected JSON object")
        }
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(ModelManifest.self, from: data)
    }
}

private final class MLTestBundleToken: NSObject { }

struct SegmentationGolden: Decodable {
    let expectedMaskRows: [String]
    let minimumDice: Double
    let probabilitySamples: [String: Double]
    let floatTolerance: Double
}

struct RiskGolden: Decodable {
    let expectedRawScore: Double
    let expectedCalibratedProbability: Double
    let probabilityTolerance: Double
    let expectedDecision: String
}
