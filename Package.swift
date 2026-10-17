// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cera",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        // Native Mermaid diagrams. Pinned: the project is young and moves fast, so upgrades are deliberate.
        .package(url: "https://github.com/2389-research/MermaidKit.git", exact: "2.4.0"),
        // Syntax highlighting. Pinned with the tree-sitter runtime it brings; the grammars are
        // copied into Grammars/ by scripts/update-grammars.sh.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
        .package(path: "Grammars")
    ],
    targets: [
        .executableTarget(
            name: "Cera",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "MermaidRender", package: "MermaidKit"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "Grammars", package: "Grammars")
            ],
            path: "Sources/Cera",
            resources: [.copy("Resources/Fonts"), .copy("Resources/Queries")]
        ),
        .testTarget(
            name: "CeraTests",
            dependencies: ["Cera"],
            path: "Tests/CeraTests"
        )
    ]
)
