@preconcurrency import CoreML
import CoreVideo
import Foundation

private final class ImageFeatureProvider: MLFeatureProvider, @unchecked Sendable {
    let image: CVPixelBuffer
    let featureNames: Set<String> = ["image"]

    init(image: CVPixelBuffer) {
        self.image = image
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        featureName == "image" ? MLFeatureValue(pixelBuffer: image) : nil
    }
}

final class TongueSegmentationOutput: MLFeatureProvider, @unchecked Sendable {
    private let provider: any MLFeatureProvider

    var featureNames: Set<String> { provider.featureNames }

    init(features: any MLFeatureProvider) {
        provider = features
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }
}

final class TongueSegmentation: @unchecked Sendable {
    let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    func prediction(image: CVPixelBuffer) throws -> TongueSegmentationOutput {
        TongueSegmentationOutput(features: try model.prediction(from: ImageFeatureProvider(image: image)))
    }
}

final class AnemiaRiskOutput: MLFeatureProvider, @unchecked Sendable {
    private let provider: any MLFeatureProvider

    var featureNames: Set<String> { provider.featureNames }

    init(features: any MLFeatureProvider) {
        provider = features
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }
}

final class AnemiaRisk: @unchecked Sendable {
    let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    func prediction(image: CVPixelBuffer) throws -> AnemiaRiskOutput {
        AnemiaRiskOutput(features: try model.prediction(from: ImageFeatureProvider(image: image)))
    }
}
