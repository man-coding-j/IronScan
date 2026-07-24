@preconcurrency import CoreML
import Foundation

struct ModelResourceLocations: Sendable {
    let segmentationPackageURL: URL?
    let segmentationManifestURL: URL?
    let riskPackageURL: URL?
    let riskManifestURL: URL?
    let pallorPackageURL: URL?
    let pallorManifestURL: URL?
    let multiScreenPackageURL: URL?
    let multiScreenManifestURL: URL?

    static func mainBundle(_ bundle: Bundle = .main) -> ModelResourceLocations {
        ModelResourceLocations(
            segmentationPackageURL: bundle.url(
                forResource: "TongueSegmentation",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ) ?? bundle.url(forResource: "TongueSegmentation", withExtension: "mlpackage"),
            segmentationManifestURL: bundle.url(
                forResource: "segmentation_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ) ?? bundle.url(forResource: "segmentation_manifest", withExtension: "json"),
            riskPackageURL: bundle.url(
                forResource: "AnemiaRisk",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ) ?? bundle.url(forResource: "AnemiaRisk", withExtension: "mlpackage"),
            riskManifestURL: bundle.url(
                forResource: "risk_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ) ?? bundle.url(forResource: "risk_manifest", withExtension: "json"),
            pallorPackageURL: bundle.url(
                forResource: "IronScanPallorClassifier",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ) ?? bundle.url(forResource: "IronScanPallorClassifier", withExtension: "mlpackage"),
            pallorManifestURL: bundle.url(
                forResource: "pallor_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ) ?? bundle.url(forResource: "pallor_manifest", withExtension: "json"),
            multiScreenPackageURL: bundle.url(
                forResource: "IronScanMultiScreen",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ) ?? bundle.url(forResource: "IronScanMultiScreen", withExtension: "mlpackage"),
            multiScreenManifestURL: bundle.url(
                forResource: "multi_screen_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ) ?? bundle.url(forResource: "multi_screen_manifest", withExtension: "json")
        )
    }

    static func runtimeBundle() -> ModelResourceLocations {
        #if SWIFT_PACKAGE
        .moduleBundle()
        #else
        .mainBundle(Bundle(for: ModelRuntimeBundleToken.self))
        #endif
    }

    #if SWIFT_PACKAGE
    static func moduleBundle() -> ModelResourceLocations {
        return ModelResourceLocations(
            segmentationPackageURL: Bundle.module.url(
                forResource: "TongueSegmentation",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ),
            segmentationManifestURL: Bundle.module.url(
                forResource: "segmentation_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ),
            riskPackageURL: Bundle.module.url(
                forResource: "AnemiaRisk",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ),
            riskManifestURL: Bundle.module.url(
                forResource: "risk_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ),
            pallorPackageURL: Bundle.module.url(
                forResource: "IronScanPallorClassifier",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ),
            pallorManifestURL: Bundle.module.url(
                forResource: "pallor_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            ),
            multiScreenPackageURL: Bundle.module.url(
                forResource: "IronScanMultiScreen",
                withExtension: "mlpackage",
                subdirectory: "Models/CoreML"
            ),
            multiScreenManifestURL: Bundle.module.url(
                forResource: "multi_screen_manifest",
                withExtension: "json",
                subdirectory: "Models/Manifests"
            )
        )
    }
    #endif
}

struct SegmentationModelHandle: @unchecked Sendable {
    let model: TongueSegmentation
    let manifest: ModelManifest
    let computeUnits: InferenceComputeUnits
}

struct RiskModelHandle: @unchecked Sendable {
    let model: AnemiaRisk
    let manifest: ModelManifest
    let computeUnits: InferenceComputeUnits
}

struct PallorModelHandle: @unchecked Sendable {
    let model: IronScanPallorClassifier
    let manifest: ModelManifest
    let computeUnits: InferenceComputeUnits
}

struct MultiScreenModelHandle: @unchecked Sendable {
    let model: IronScanMultiScreen
    let manifest: ModelManifest
    let computeUnits: InferenceComputeUnits
}

struct ModelRegistryReadiness: Codable, Equatable, Sendable {
    let segmentationModelIdentifier: String
    let segmentationModelVersion: String
    let riskModelIdentifier: String
    let riskModelVersion: String
    let pallorModelIdentifier: String
    let pallorModelVersion: String
    let multiScreenModelIdentifier: String
    let multiScreenModelVersion: String
}

actor ModelRegistryActor {
    static let shared = ModelRegistryActor(
        resources: .runtimeBundle(),
        computeUnits: .all,
        metrics: InferenceMetricsRecorder()
    )


    private let resources: ModelResourceLocations
    private let computeUnits: InferenceComputeUnits
    private let metrics: InferenceMetricsRecorder
    private let validator: ModelContractValidator
    private var segmentationHandle: SegmentationModelHandle?
    private var riskHandle: RiskModelHandle?
    private var pallorHandle: PallorModelHandle?
    private var multiScreenHandle: MultiScreenModelHandle?
    private(set) var segmentationLoadCount = 0
    private(set) var riskLoadCount = 0
    private(set) var pallorLoadCount = 0
    private(set) var multiScreenLoadCount = 0

    init(
        resources: ModelResourceLocations,
        computeUnits: InferenceComputeUnits,
        metrics: InferenceMetricsRecorder,
        validator: ModelContractValidator = ModelContractValidator()
    ) {
        self.resources = resources
        self.computeUnits = computeUnits
        self.metrics = metrics
        self.validator = validator
    }

    func preloadModels() async throws -> ModelRegistryReadiness {
        try checkCancellation()
        let segmentation = try await segmentationModel()
        try checkCancellation()
        let risk = try await riskModel()
        try checkCancellation()
        let pallor = try await pallorModel()
        try checkCancellation()
        let multiScreen = try await multiScreenModel()
        return ModelRegistryReadiness(
            segmentationModelIdentifier: segmentation.manifest.modelIdentifier,
            segmentationModelVersion: segmentation.manifest.semanticVersion,
            riskModelIdentifier: risk.manifest.modelIdentifier,
            riskModelVersion: risk.manifest.semanticVersion,
            pallorModelIdentifier: pallor.manifest.modelIdentifier,
            pallorModelVersion: pallor.manifest.semanticVersion,
            multiScreenModelIdentifier: multiScreen.manifest.modelIdentifier,
            multiScreenModelVersion: multiScreen.manifest.semanticVersion
        )
    }

    func segmentationModel() async throws -> SegmentationModelHandle {
        if let segmentationHandle { return segmentationHandle }
        try checkCancellation()
        guard let packageURL = resources.segmentationPackageURL,
              let manifestURL = resources.segmentationManifestURL else {
            throw InferenceError.modelLoadingFailed("Segmentation package or manifest is missing")
        }
        let start = ContinuousClock.now
        do {
            let manifest = try validator.decodeManifest(at: manifestURL)
            let model = try loadModel(packageURL: packageURL)
            try validator.validate(manifest: manifest, kind: .segmentation, packageURL: packageURL, model: model)
            let handle = SegmentationModelHandle(
                model: TongueSegmentation(model: model),
                manifest: manifest,
                computeUnits: computeUnits
            )
            segmentationHandle = handle
            segmentationLoadCount += 1
            await metrics.record(
                stage: .modelLoading,
                durationMs: start.duration(to: .now).milliseconds,
                modelIdentifier: manifest.modelIdentifier,
                computeUnits: computeUnits
            )
            return handle
        } catch let error as ModelContractError {
            throw error
        } catch let error as InferenceError {
            throw error
        } catch {
            throw InferenceError.modelLoadingFailed(error.localizedDescription)
        }
    }

    func riskModel() async throws -> RiskModelHandle {
        if let riskHandle { return riskHandle }
        try checkCancellation()
        guard let packageURL = resources.riskPackageURL,
              let manifestURL = resources.riskManifestURL else {
            throw InferenceError.modelLoadingFailed("Risk package or manifest is missing")
        }
        let start = ContinuousClock.now
        do {
            let manifest = try validator.decodeManifest(at: manifestURL)
            let model = try loadModel(packageURL: packageURL)
            try validator.validate(manifest: manifest, kind: .risk, packageURL: packageURL, model: model)
            let handle = RiskModelHandle(
                model: AnemiaRisk(model: model),
                manifest: manifest,
                computeUnits: computeUnits
            )
            riskHandle = handle
            riskLoadCount += 1
            await metrics.record(
                stage: .modelLoading,
                durationMs: start.duration(to: .now).milliseconds,
                modelIdentifier: manifest.modelIdentifier,
                computeUnits: computeUnits
            )
            return handle
        } catch let error as ModelContractError {
            throw error
        } catch let error as InferenceError {
            throw error
        } catch {
            throw InferenceError.modelLoadingFailed(error.localizedDescription)
        }
    }

    func pallorModel() async throws -> PallorModelHandle {
        if let pallorHandle { return pallorHandle }
        try checkCancellation()
        guard let packageURL = resources.pallorPackageURL,
              let manifestURL = resources.pallorManifestURL else {
            throw InferenceError.modelLoadingFailed("Pallor package or manifest is missing")
        }
        let start = ContinuousClock.now
        do {
            let manifest = try validator.decodeManifest(at: manifestURL)
            let model = try loadModel(packageURL: packageURL)
            try validator.validate(manifest: manifest, kind: .pallor, packageURL: packageURL, model: model)
            let handle = PallorModelHandle(
                model: IronScanPallorClassifier(model: model),
                manifest: manifest,
                computeUnits: computeUnits
            )
            pallorHandle = handle
            pallorLoadCount += 1
            await metrics.record(
                stage: .modelLoading,
                durationMs: start.duration(to: .now).milliseconds,
                modelIdentifier: manifest.modelIdentifier,
                computeUnits: computeUnits
            )
            return handle
        } catch let error as ModelContractError {
            throw error
        } catch let error as InferenceError {
            throw error
        } catch {
            throw InferenceError.modelLoadingFailed(error.localizedDescription)
        }
    }

    func multiScreenModel() async throws -> MultiScreenModelHandle {
        if let multiScreenHandle { return multiScreenHandle }
        try checkCancellation()
        guard let packageURL = resources.multiScreenPackageURL,
              let manifestURL = resources.multiScreenManifestURL else {
            throw InferenceError.modelLoadingFailed("Multi-screen package or manifest is missing")
        }
        let start = ContinuousClock.now
        do {
            let manifest = try validator.decodeManifest(at: manifestURL)
            let model = try loadModel(packageURL: packageURL)
            try validator.validate(
                manifest: manifest,
                kind: .multiScreen,
                packageURL: packageURL,
                model: model
            )
            let handle = MultiScreenModelHandle(
                model: IronScanMultiScreen(model: model),
                manifest: manifest,
                computeUnits: computeUnits
            )
            multiScreenHandle = handle
            multiScreenLoadCount += 1
            await metrics.record(
                stage: .modelLoading,
                durationMs: start.duration(to: .now).milliseconds,
                modelIdentifier: manifest.modelIdentifier,
                computeUnits: computeUnits
            )
            return handle
        } catch let error as ModelContractError {
            throw error
        } catch let error as InferenceError {
            throw error
        } catch {
            throw InferenceError.modelLoadingFailed(error.localizedDescription)
        }
    }

    private func loadModel(packageURL: URL) throws -> MLModel {
        let compiledURL = try MLModel.compileModel(at: packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits.coreMLValue
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw InferenceError.cancelled }
    }
}

private final class ModelRuntimeBundleToken: NSObject { }

extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
