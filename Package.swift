// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SQLiteo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SQLiteo", targets: ["SQLiteo"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/mchakravarty/CodeEditorView.git", "0.12.0"..<"0.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "SQLiteo",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CodeEditorView", package: "CodeEditorView"),
                .product(name: "LanguageSupport", package: "CodeEditorView"),
            ],
            exclude: [],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SQLiteoTests",
            dependencies: ["SQLiteo"]
        ),
    ]
)
