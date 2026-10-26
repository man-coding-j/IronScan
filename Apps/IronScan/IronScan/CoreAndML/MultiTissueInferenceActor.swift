@preconcurrency import CoreML
@preconcurrency import Vision
import CoreVideo
import Foundation

enum ConjunctivaCropError: Error, Equatable, Sendable {
    case faceNotDetected
    case eyeLandmarksNotDetected
    case regionTooSmall
}

struct ConjunctivaCropResult: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let normalizedRegion: CGRect
}

protocol ConjunctivaCropping: Sendable {
    func cropConjunctiva(from pixelBuffer: CVPixelBuffer) throws -> ConjunctivaCropResult
}

struct ConjunctivaRegionCalculator: Sendable {
    static func lowerQuarter(
        faceBoundingBox: CGRect,
        eyePoints: [CGPoint]
    ) throws -> CGRect {
        guard !eyePoints.isEmpty else {
            throw ConjunctivaCropError.eyeLandmarksNotDetected
        }
        let imagePoints = eyePoints.map { point in
            CGPoint(
                x: faceBoundingBox.minX + point.x * faceBoundingBox.width,
                y: faceBoundingBox.minY + point.y * faceBoundingBox.height
            )
        }
        guard let minimumX = imagePoints.map(\.x).min(),
              let maximumX = imagePoints.map(\.x).max(),
              let minimumY = imagePoints.map(\.y).min(),
              let maximumY = imagePoints.map(\.y).max() else {
            throw ConjunctivaCropError.eyeLandmarksNotDetected
        }
        let eyeBounds = CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
        let lowerQuarter = CGRect(
            x: eyeBounds.minX,
            y: eyeBounds.minY,
            width: eyeBounds.width,
            height: eyeBounds.height * 0.25
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard lowerQuarter.width >= 0.02, lowerQuarter.height >= 0.004 else {
            throw ConjunctivaCropError.regionTooSmall
        }
        return lowerQuarter
    }
}

struct VisionConjunctivaCropper: ConjunctivaCropping {
    func cropConjunctiva(from pixelBuffer: CVPixelBuffer) throws -> ConjunctivaCropResult {
        let request = VNDetectFaceLandmarksRequest()
        try VisionComputeSafety.requireCPU(for: request)
        try VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        ).perform([request])
        guard let face = request.results?
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            throw ConjunctivaCropError.faceNotDetected
        }
        guard let landmarks = face.landmarks else {
            throw ConjunctivaCropError.eyeLandmarksNotDetected
        }
        let eyeRegions = [landmarks.leftEye, landmarks.rightEye].compactMap { region -> CGRect? in
            guard let region else { return nil }
            return try? ConjunctivaRegionCalculator.lowerQuarter(
                faceBoundingBox: face.boundingBox,
                eyePoints: region.normalizedPoints
            )
        }
        guard let selectedRegion = eyeRegions.min(by: {
            abs($0.midX - 0.5) < abs($1.midX - 0.5)
        }) else {
            throw ConjunctivaCropError.eyeLandmarksNotDetected
        }
        let bgraBuffer = try PixelBufferFactory.makeBGRA(from: pixelBuffer)
        return ConjunctivaCropResult(
            pixelBuffer: try PixelBufferFactory.makeCrop(
                from: bgraBuffer,
                normalizedRect: selectedRegion
            ),
            normalizedRegion: selectedRegion
        )
    }
}

struct EyePreviewAssessment: Equatable, Sendable {
    let predictiveMean: Double
    let predictiveUncertainty: Double
    let uncertaintyThreshold: Double
    let uncertaintyPassCount: Int

    var uncertaintyAccepted: Bool {
        predictiveUncertainty <= uncertaintyThreshold
    }

    var predictiveVariance: Double {
        predictiveUncertainty * predictiveUncertainty
    }
}

struct MultiTissueModelResources: Sendable {
    struct Resource: Sendable {
        let packageURL: URL?
        let manifestURL: URL?
    }

    let resources: [TissueSite: Resource]

    static func mainBundle(_ bundle: Bundle = .main) -> MultiTissueModelResources {
        MultiTissueModelResources(resources: Dictionary(uniqueKeysWithValues: TissueSite.allCases.map { tissue in
            let names = tissue.resourceNames
            return (tissue, Resource(
                packageURL: bundle.url(
                    forResource: names.package,
                    withExtension: "mlpackage",
                    subdirectory: "Models/CoreML"
                ) ?? bundle.url(forResource: names.package, withExtension: "mlpackage"),
                manifestURL: bundle.url(
                    forResource: names.manifest,
                    withExtension: "json",
                    subdirectory: "Models/Manifests"
                ) ?? bundle.url(forResource: names.manifest, withExtension: "json")
            ))
        }))
    }
}

struct MultiTissueReadiness: Equatable, Sendable {
    let modelVersions: [TissueSite: String]
    let preprocessingVersions: [TissueSite: String]
}

private struct TissueModelHandle: @unchecked Sendable {
    let model: IronScanTissueClassifier
    let manifest: ModelManifest
}

actor MultiTissueInferenceActor {
    private let resources: MultiTissueModelResources
    private let computeUnits: InferenceComputeUnits
    private let validator: ModelContractValidator
    private let conjunctivaCropper: any ConjunctivaCropping
    private var handles: [TissueSite: TissueModelHandle] = [:]
    private(set) var loadCounts: [TissueSite: Int] = [:]

    init(
        resources: MultiTissueModelResources = .mainBundle(),
        computeUnits: InferenceComputeUnits = .cpuOnly,
        validator: ModelContractValidator = ModelContractValidator(),
        conjunctivaCropper: any ConjunctivaCropping = VisionConjunctivaCropper()
    ) {
        self.resources = resources
        self.computeUnits = computeUnits
        self.validator = validator
        self.conjunctivaCropper = conjunctivaCropper
    }

    func preloadModels() throws -> MultiTissueReadiness {
        try checkCancellation()
        var modelVersions: [TissueSite: String] = [:]
        var preprocessingVersions: [TissueSite: String] = [:]
        for tissue in TissueSite.allCases {
            let handle = try model(for: tissue)
            modelVersions[tissue] = handle.manifest.semanticVersion
            preprocessingVersions[tissue] = handle.manifest.preprocessingVersion
        }
        return MultiTissueReadiness(
            modelVersions: modelVersions,
            preprocessingVersions: preprocessingVersions
        )
    }

    func predict(frame: CapturedFrame, tissue: TissueSite) throws -> TissueScreeningOutput {
        try checkCancellation()
        let handle = try model(for: tissue)
        let inputBuffer = try prepareInput(
            frame.pixelBuffer,
            tissue: tissue,
            manifest: handle.manifest,
            requiresConjunctivaCrop: tissue == .eye && frame.metadata.cameraDeviceType != "synthetic"
        )
        try checkCancellation()
        let predictionStart = ContinuousClock.now
        let values = try predictionValues(model: handle.model, inputBuffer: inputBuffer, manifest: handle.manifest)
        let captureQualityAccepted = frame.quality.readiness == .ready
        let isSyntheticFixture = frame.metadata.cameraDeviceType == "synthetic"
        let uncertaintyAccepted = isSyntheticFixture || values.uncertainty <= values.uncertaintyThreshold
        var rejectionReasons = [String]()
        if !captureQualityAccepted {
            rejectionReasons.append("The captured image did not meet demo quality requirements.")
        }
        if !uncertaintyAccepted {
            rejectionReasons.append(uncertaintyWarning(for: tissue))
        }
        return TissueScreeningOutput(
            tissue: tissue,
            probability: values.probability,
            lockedThreshold: values.decisionThreshold,
            qualityAccepted: captureQualityAccepted,
            rejectionReasons: rejectionReasons,
            modelVersion: handle.manifest.semanticVersion,
            preprocessingVersion: handle.manifest.preprocessingVersion,
            isEngineeringFixture: handle.manifest.deploymentStatus == .engineeringFixture,
            predictiveUncertainty: values.uncertainty,
            uncertaintyThreshold: values.uncertaintyThreshold,
            uncertaintyPassCount: values.uncertaintyPassCount,
            uncertaintyEnforced: !isSyntheticFixture,
            inferenceDurationMs: predictionStart.duration(to: .now).milliseconds,
            computeUnits: computeUnits
        )
    }

    func assessEyePreview(pixelBuffer: CVPixelBuffer) throws -> EyePreviewAssessment {
        try checkCancellation()
        let handle = try model(for: .eye)
        let inputBuffer = try prepareInput(
            pixelBuffer,
            tissue: .eye,
            manifest: handle.manifest,
            requiresConjunctivaCrop: true
        )
        try checkCancellation()
        let values = try predictionValues(model: handle.model, inputBuffer: inputBuffer, manifest: handle.manifest)
        return EyePreviewAssessment(
            predictiveMean: values.probability,
            predictiveUncertainty: values.uncertainty,
            uncertaintyThreshold: values.uncertaintyThreshold,
            uncertaintyPassCount: values.uncertaintyPassCount
        )
    }

    private struct PredictionValues {
        let probability: Double
        let uncertainty: Double
        let decisionThreshold: Double
        let uncertaintyThreshold: Double
        let uncertaintyPassCount: Int
    }

    private func prepareInput(
        _ source: CVPixelBuffer,
        tissue: TissueSite,
        manifest: ModelManifest,
        requiresConjunctivaCrop: Bool
    ) throws -> CVPixelBuffer {
        guard manifest.input.dimensions.count == 4 else {
            throw InferenceError.invalidDimensions
        }
        let regionBuffer = if requiresConjunctivaCrop {
            try conjunctivaCropper.cropConjunctiva(from: source).pixelBuffer
        } else {
            try PixelBufferFactory.makeBGRA(from: source)
        }
        return try PixelBufferFactory.makeBuffer(
            from: regionBuffer,
            width: manifest.input.dimensions[2],
            height: manifest.input.dimensions[1],
            resize: manifest.resize
        )
    }

    private func predictionValues(
        model: IronScanTissueClassifier,
        inputBuffer: CVPixelBuffer,
        manifest: ModelManifest
    ) throws -> PredictionValues {
        let output: IronScanTissueClassifierOutput
        do {
            output = try model.prediction(image: inputBuffer)
        } catch {
            throw InferenceError.predictionFailed(error.localizedDescription)
        }
        let probability = try scalar(from: output, feature: "calibrated_proxy_probability")
        let uncertainty = try scalar(from: output, feature: "predictive_uncertainty")
        guard probability.isFinite, (0...1).contains(probability),
              uncertainty.isFinite, uncertainty >= 0,
              let decisionThreshold = manifest.decisionThreshold,
              let uncertaintyThreshold = manifest.uncertaintyThreshold,
              let uncertaintyPassCount = manifest.uncertaintyPassCount else {
            throw InferenceError.invalidOutputShape("calibrated_proxy_probability or predictive_uncertainty")
        }
        return PredictionValues(
            probability: probability,
            uncertainty: uncertainty,
            decisionThreshold: decisionThreshold,
            uncertaintyThreshold: uncertaintyThreshold,
            uncertaintyPassCount: uncertaintyPassCount
        )
    }

    private func uncertaintyWarning(for tissue: TissueSite) -> String {
        switch tissue {
        case .eye:
            "High image uncertainty. Move to better lighting and lower your eyelid to expose the conjunctiva."
        case .nail:
            "High image uncertainty. Improve lighting and keep the fingernail steady."
        case .tongue:
            "High image uncertainty. Improve lighting and keep the tongue steady."
        }
    }

    private func model(for tissue: TissueSite) throws -> TissueModelHandle {
        if let handle = handles[tissue] { return handle }
        do {
            guard let resource = resources.resources[tissue],
                  let packageURL = resource.packageURL,
                  let manifestURL = resource.manifestURL else {
                throw InferenceError.modelLoadingFailed("\(tissue.displayName) model package or manifest is missing")
            }
            let manifest = try validator.decodeManifest(at: manifestURL)
            let compiledURL = try MLModel.compileModel(at: packageURL)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = computeUnits.coreMLValue
            let coreMLModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
            try validator.validate(
                manifest: manifest,
                kind: tissue.modelKind,
                packageURL: packageURL,
                model: coreMLModel
            )
            let handle = TissueModelHandle(
                model: IronScanTissueClassifier(model: coreMLModel),
                manifest: manifest
            )
            handles[tissue] = handle
            loadCounts[tissue, default: 0] += 1
            return handle
        } catch {
            print("\(tissue.displayName) model initialization failed: \(error)")
            if let inferenceError = error as? InferenceError {
                throw inferenceError
            }
            throw InferenceError.modelLoadingFailed(error.localizedDescription)
        }
    }

    private func scalar(from output: any MLFeatureProvider, feature: String) throws -> Double {
        guard let array = output.featureValue(for: feature)?.multiArrayValue,
              array.count == 1,
              array.dataType == .float32 else {
            throw InferenceError.invalidOutputShape(feature)
        }
        return Double(array.dataPointer.bindMemory(to: Float.self, capacity: 1).pointee)
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw InferenceError.cancelled }
    }
}

extension TissueSite {
    var displayName: String {
        switch self {
        case .eye: "Eye"
        case .nail: "Fingernail"
        case .tongue: "Tongue"
        }
    }

    var modelKind: ModelKind {
        switch self {
        case .eye: .eyeLaboratoryScreening
        case .nail: .nailPallorProxy
        case .tongue: .tonguePallorProxy
        }
    }

    fileprivate var resourceNames: (package: String, manifest: String) {
        switch self {
        case .eye: ("IronScanEye_Clinical", "eye_clinical_manifest")
        case .nail: ("IronScanNail", "nail_manifest")
        case .tongue: ("IronScanTongue", "tongue_manifest")
        }
    }
}
