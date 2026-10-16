// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DIFFMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "DIFFMac", targets: ["DIFFMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", branch: "with-generated-files")
    ],
    targets: [
        .executableTarget(
            name: "DIFFMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift")
            ],
            path: "Sources/DIFFMac",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "DIFFMacTests",
            dependencies: ["DIFFMac"],
            path: "Tests/DIFFMacTests"
        )
    ]
)
