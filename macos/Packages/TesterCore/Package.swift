// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TesterCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TesterCore", targets: ["TesterCore"]),
    ],
    targets: [
        .target(
            name: "TesterCore",
            resources: [
                // Learning content (missions, rubric presets, judge exercises, seed test cases).
                .process("Resources"),
                // The Learn tab's course. Copied as a folder so lessons/, cheatsheets/ and images/ keep their structure.
                .copy("LearnContent"),
            ]
        ),
        .testTarget(
            name: "TesterCoreTests",
            dependencies: ["TesterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
