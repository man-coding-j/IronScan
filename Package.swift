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
                "AGENTS.md",
                "IronScan/App",
                "IronScan/Camera",
                "IronScanTests",
                "Models/Manifests",
                "README.md",
                "SharedContracts",
                "compliance",
                "docs",
                "project.yml",
                "pyproject.toml",
                "uv.lock"
            ],
            sources: ["IronScan/ML", "IronScan/ImageProcessing"],
            resources: [.copy("Models")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "IronScanMLTests",
            dependencies: ["IronScan"],
            path: "IronScanTests/ML",
            exclude: ["Fixtures/generate_fixture_models.py", "Python"],
            resources: [.copy("Fixtures/PythonGolden")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
