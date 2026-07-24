// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IronScan",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "IronScan", targets: ["IronScan"])
    ],
    targets: [
        .target(
            name: "IronScan",
            path: ".",
            exclude: [
                ".github",
                "AGENTS.md",
                "Apps",
                "CODEOWNERS",
                "LICENSE",
                "MLTraining",
                "Models/Manifests",
                "Packages/IronScanCore/README.md",
                "Packages/IronScanModels/README.md",
                "Packages/IronScanNetworking",
                "Packages/IronScanTestSupport",
                "PythonReference",
                "README.md",
                "SECURITY.md",
                "Server",
                "SharedContracts",
                "TestFixtures",
                "THIRD_PARTY_NOTICES.md",
                "compliance",
                "docs",
                "scripts",
                "pyproject.toml",
                "uv.lock"
            ],
            sources: [
                "Packages/IronScanModels/Sources/IronScanModels/ML",
                "Packages/IronScanCore/Sources/IronScanCore/ImageProcessing",
                "Packages/IronScanCore/Sources/IronScanCore/ColorCalibration"
            ],
            resources: [.copy("Models")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])
            ]
        ),
        .testTarget(
            name: "IronScanMLTests",
            dependencies: ["IronScan"],
            path: ".",
            exclude: [
                ".github",
                "AGENTS.md",
                "Apps/IronScan/Config",
                "Apps/IronScan/project.yml",
                "Apps/IronScan/IronScan",
                "Apps/IronScan/IronScan.xcodeproj",
                "Apps/IronScan/IronScanTests/App",
                "Apps/IronScan/IronScanTests/CameraStateMachineTests.swift",
                "Apps/IronScan/IronScanUITests",
                "CODEOWNERS",
                "LICENSE",
                "MLTraining",
                "Models",
                "Package.swift",
                "Packages",
                "PythonReference",
                "README.md",
                "SECURITY.md",
                "Server",
                "SharedContracts",
                "THIRD_PARTY_NOTICES.md",
                "compliance",
                "docs",
                "pyproject.toml",
                "scripts",
                "TestFixtures/LicensedPublic",
                "TestFixtures/Synthetic",
                "uv.lock"
            ],
            sources: ["Apps/IronScan/IronScanTests/ML"],
            resources: [
                .copy("TestFixtures/GoldenInputs"),
                .copy("TestFixtures/GoldenOutputs")
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
