import CoreML
import XCTest
@testable import IronScan

@MainActor
final class ModelContractValidatorTests: XCTestCase {
    func testValidContractsAndChecksums() async throws {
        let metrics = InferenceMetricsRecorder()
        let registry = try MLTestSupport.registry(metrics: metrics)

        _ = try await registry.segmentationModel()
        _ = try await registry.riskModel()

        let segmentationCount = await registry.segmentationLoadCount
        let riskCount = await registry.riskLoadCount
        XCTAssertEqual(segmentationCount, 1)
        XCTAssertEqual(riskCount, 1)
    }

    func testManifestSchemaMismatch() async throws {
        let context = try await segmentationContext()
        let manifest = try MLTestSupport.modifiedManifest(at: context.manifestURL) { $0["schemaVersion"] = 2 }

        XCTAssertThrowsError(try context.validator.validate(
            manifest: manifest,
            kind: .segmentation,
            packageURL: context.packageURL,
            model: context.model
        )) { error in
            XCTAssertEqual(error as? ModelContractError, .unsupportedSchemaVersion(2))
        }
    }

    func testChecksumMismatch() async throws {
        let context = try await segmentationContext()
        let manifest = try MLTestSupport.modifiedManifest(at: context.manifestURL) {
            $0["sha256"] = String(repeating: "0", count: 64)
        }

        XCTAssertThrowsError(try context.validator.validate(
            manifest: manifest,
            kind: .segmentation,
            packageURL: context.packageURL,
            model: context.model
        ))
    }

    func testWrongInputShape() async throws {
        let context = try await segmentationContext()
        let manifest = try MLTestSupport.modifiedManifest(at: context.manifestURL) { object in
            var input = object["input"] as? [String: Any] ?? [:]
            input["dimensions"] = [1, 32, 32, 3]
            object["input"] = input
        }

        XCTAssertThrowsError(try context.validator.validate(
            manifest: manifest,
            kind: .segmentation,
            packageURL: context.packageURL,
            model: context.model
        ))
    }

    func testWrongOutputShape() async throws {
        let context = try await segmentationContext()
        let manifest = try MLTestSupport.modifiedManifest(at: context.manifestURL) { object in
            var outputs = object["outputs"] as? [[String: Any]] ?? []
            if !outputs.isEmpty { outputs[0]["dimensions"] = [1, 32, 32] }
            object["outputs"] = outputs
        }

        XCTAssertThrowsError(try context.validator.validate(
            manifest: manifest,
            kind: .segmentation,
            packageURL: context.packageURL,
            model: context.model
        ))
    }

    private struct Context {
        let validator: ModelContractValidator
        let packageURL: URL
        let manifestURL: URL
        let model: MLModel
    }

    private func segmentationContext() async throws -> Context {
        let resources = try MLTestSupport.resources()
        guard let packageURL = resources.segmentationPackageURL,
              let manifestURL = resources.segmentationManifestURL else {
            throw InferenceError.modelLoadingFailed("Segmentation resources missing")
        }
        let compiledURL = try await MLModel.compileModel(at: packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return Context(
            validator: ModelContractValidator(),
            packageURL: packageURL,
            manifestURL: manifestURL,
            model: try MLModel(contentsOf: compiledURL, configuration: configuration)
        )
    }
}
