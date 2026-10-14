// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cera",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Cera",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/Cera",
            resources: [.copy("Resources/Fonts")]
        ),
        .testTarget(
            name: "CeraTests",
            dependencies: ["Cera"],
            path: "Tests/CeraTests"
        )
    ]
)
