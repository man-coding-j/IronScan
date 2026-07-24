@preconcurrency import CoreML
import CoreVideo
import CryptoKit
import Foundation

struct ModelContractValidator: Sendable {
    static let supportedSchemaVersion = 1

    func decodeManifest(at url: URL) throws -> ModelManifest {
        do {
            return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
        } catch {
            throw ModelContractError.unreadableManifest(error.localizedDescription)
        }
    }

    func validate(
        manifest: ModelManifest,
        kind: ModelKind,
        packageURL: URL,
        model: MLModel
    ) throws {
        guard manifest.schemaVersion == Self.supportedSchemaVersion else {
            throw ModelContractError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard manifest.modelIdentifier == kind.expectedIdentifier else {
            throw ModelContractError.modelIdentifier(expected: kind.expectedIdentifier, actual: manifest.modelIdentifier)
        }
        guard manifest.semanticVersion.range(
            of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"#,
            options: .regularExpression
        ) != nil else {
            throw ModelContractError.invalidSemanticVersion(manifest.semanticVersion)
        }
        let checksum = try packageSHA256(at: packageURL)
        guard checksum == manifest.sha256 else {
            throw ModelContractError.checksum(expected: manifest.sha256, actual: checksum)
        }
        try validateInput(manifest: manifest, description: model.modelDescription)
        try validateOutputs(manifest: manifest, description: model.modelDescription)
        try validateMetadata(manifest: manifest, description: model.modelDescription)
    }

    func packageSHA256(at packageURL: URL) throws -> String {
        let fileManager = FileManager.default
        let canonicalPackageURL = packageURL.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: canonicalPackageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ModelContractError.checksum(expected: "package", actual: "unreadable")
        }
        let files = enumerator.compactMap { $0 as? URL }.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.path < $1.path }
        var hasher = SHA256()
        for file in files {
            let components = file.pathComponents
            guard let packageIndex = components.lastIndex(of: canonicalPackageURL.lastPathComponent),
                  packageIndex + 1 < components.count else {
                throw ModelContractError.checksum(expected: "relative package path", actual: file.path)
            }
            let relativePath = components[(packageIndex + 1)...].joined(separator: "/")
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: file))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateInput(manifest: ModelManifest, description: MLModelDescription) throws {
        let inputs = description.inputDescriptionsByName
        guard inputs.keys.sorted() == [manifest.input.name] else {
            throw ModelContractError.inputFeatureName(expected: manifest.input.name, actual: inputs.keys.sorted().first)
        }
        guard let feature = inputs[manifest.input.name] else {
            throw ModelContractError.inputFeatureName(expected: manifest.input.name, actual: inputs.keys.sorted().first)
        }
        guard let image = feature.imageConstraint else {
            throw ModelContractError.inputDimensions(expected: manifest.input.dimensions, actual: [])
        }
        let actualDimensions = [1, image.pixelsHigh, image.pixelsWide, 3]
        guard actualDimensions == manifest.input.dimensions else {
            throw ModelContractError.inputDimensions(expected: manifest.input.dimensions, actual: actualDimensions)
        }
        let actualPixelFormat = image.pixelFormatType == kCVPixelFormatType_32BGRA ? "32BGRA" : String(image.pixelFormatType)
        guard actualPixelFormat == manifest.input.pixelFormat else {
            throw ModelContractError.pixelFormat(expected: manifest.input.pixelFormat, actual: actualPixelFormat)
        }
    }

    private func validateOutputs(manifest: ModelManifest, description: MLModelDescription) throws {
        let actualNames = description.outputDescriptionsByName.keys.sorted()
        let expectedNames = manifest.outputs.map(\.name).sorted()
        guard actualNames == expectedNames else {
            throw ModelContractError.outputFeatureNames(expected: expectedNames, actual: actualNames)
        }
        for output in manifest.outputs {
            guard let feature = description.outputDescriptionsByName[output.name],
                  let constraint = feature.multiArrayConstraint else {
                throw ModelContractError.outputDimensions(feature: output.name, expected: output.dimensions, actual: [])
            }
            let actualDimensions = constraint.shape.map(\.intValue)
            guard actualDimensions == output.dimensions else {
                throw ModelContractError.outputDimensions(
                    feature: output.name,
                    expected: output.dimensions,
                    actual: actualDimensions
                )
            }
            let actualType = constraint.dataType == .float32 ? "float32" : String(describing: constraint.dataType)
            guard actualType == output.dataType else {
                throw ModelContractError.outputDataType(feature: output.name, expected: output.dataType, actual: actualType)
            }
        }
    }

    private func validateMetadata(manifest: ModelManifest, description: MLModelDescription) throws {
        guard let metadata = description.metadata[.creatorDefinedKey] as? [String: String] else {
            throw ModelContractError.missingModelMetadata("creatorDefined")
        }
        try require(metadata, key: "manifestSchemaVersion", equals: String(manifest.schemaVersion))
        try require(metadata, key: "modelIdentifier", equals: manifest.modelIdentifier)
        try require(metadata, key: "semanticVersion", equals: manifest.semanticVersion)
        try require(metadata, key: "inputFeatureName", equals: manifest.input.name)
        try require(metadata, key: "pixelFormat", equals: manifest.input.pixelFormat)
        guard metadata["colorSpace"] == manifest.input.colorSpace else {
            throw ModelContractError.colorSpace(expected: manifest.input.colorSpace, actual: metadata["colorSpace"] ?? "missing")
        }
        guard let normalizationData = metadata["normalization"]?.data(using: .utf8),
              try JSONDecoder().decode(ModelManifest.Normalization.self, from: normalizationData) == manifest.normalization else {
            throw ModelContractError.normalization
        }
        if let expectedThreshold = manifest.decisionThreshold {
            let actualThreshold = metadata["decisionThreshold"].flatMap(Double.init)
            guard actualThreshold == expectedThreshold else {
                throw ModelContractError.decisionThreshold(expected: expectedThreshold, actual: actualThreshold)
            }
        } else if let expectedThresholds = manifest.decisionThresholds {
            let actualThresholds: [String: Double]?
            if let data = metadata["decisionThresholds"]?.data(using: .utf8) {
                actualThresholds = try? JSONDecoder().decode([String: Double].self, from: data)
            } else {
                actualThresholds = nil
            }
            guard actualThresholds == expectedThresholds else {
                throw ModelContractError.decisionThresholds(
                    expected: expectedThresholds,
                    actual: actualThresholds
                )
            }
        } else {
            throw ModelContractError.missingModelMetadata("decisionThreshold or decisionThresholds")
        }
        if let expectedUncertaintyThreshold = manifest.uncertaintyThreshold {
            let actualUncertaintyThreshold = metadata["uncertaintyThreshold"].flatMap(Double.init)
            guard actualUncertaintyThreshold == expectedUncertaintyThreshold else {
                throw ModelContractError.uncertaintyThreshold(
                    expected: expectedUncertaintyThreshold,
                    actual: actualUncertaintyThreshold
                )
            }
        }
        if let expectedUncertaintyPassCount = manifest.uncertaintyPassCount {
            let actualUncertaintyPassCount = metadata["uncertaintyPassCount"].flatMap(Int.init)
            guard actualUncertaintyPassCount == expectedUncertaintyPassCount else {
                throw ModelContractError.uncertaintyPassCount(
                    expected: expectedUncertaintyPassCount,
                    actual: actualUncertaintyPassCount
                )
            }
        }
        guard metadata["preprocessingVersion"] == manifest.preprocessingVersion else {
            throw ModelContractError.preprocessingVersion(
                expected: manifest.preprocessingVersion,
                actual: metadata["preprocessingVersion"]
            )
        }
    }

    private func require(_ metadata: [String: String], key: String, equals expected: String) throws {
        guard let actual = metadata[key] else { throw ModelContractError.missingModelMetadata(key) }
        guard actual == expected else {
            if key == "modelIdentifier" {
                throw ModelContractError.modelIdentifier(expected: expected, actual: actual)
            }
            throw ModelContractError.missingModelMetadata(key)
        }
    }
}
