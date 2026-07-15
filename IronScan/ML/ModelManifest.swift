import Foundation

struct ModelManifest: Codable, Equatable, Sendable {
    enum DeploymentStatus: String, Codable, Sendable {
        case engineeringFixture
        case validated
    }

    struct Input: Codable, Equatable, Sendable {
        let name: String
        let dimensions: [Int]
        let dataType: String
        let pixelFormat: String
        let colorSpace: String
    }

    struct Resize: Codable, Equatable, Sendable {
        enum Method: String, Codable, Sendable {
            case scaleFill
            case centerCrop
        }

        let method: Method
        let interpolation: String
    }

    struct Normalization: Codable, Equatable, Sendable {
        let kind: String
        let scale: Double
        let biases: [Double]
    }

    struct Output: Codable, Equatable, Sendable {
        let name: String
        let dimensions: [Int]
        let dataType: String
    }

    struct Postprocessing: Codable, Equatable, Sendable {
        let largestConnectedComponent: Bool
        let maximumHoleAreaPixels: Int
        let closingRadiusPixels: Int
        let minimumComponentAreaPixels: Int
        let boundaryErosionPercentage: Double
    }

    let schemaVersion: Int
    let modelIdentifier: String
    let semanticVersion: String
    let sha256: String
    let deploymentStatus: DeploymentStatus
    let input: Input
    let resize: Resize
    let normalization: Normalization
    let outputs: [Output]
    let decisionThreshold: Double
    let trainingCommit: String
    let datasetVersion: String
    let preprocessingVersion: String
    let postprocessing: Postprocessing?
}

enum ModelKind: String, Sendable {
    case segmentation
    case risk

    var expectedIdentifier: String {
        switch self {
        case .segmentation: "org.ironscan.engineering.tongue-segmentation"
        case .risk: "org.ironscan.engineering.anemia-risk"
        }
    }
}
