// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacPad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPad", targets: ["MacPad"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "MacPadCore"),
        .target(
            name: "MarkdownRendering",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .executableTarget(
            name: "MacPad",
            dependencies: ["MacPadCore", "MarkdownRendering"]
        ),
        .testTarget(name: "MacPadCoreTests", dependencies: ["MacPadCore"]),
        .testTarget(name: "MarkdownRenderingTests", dependencies: ["MarkdownRendering"]),
    ],
    swiftLanguageModes: [.v5]
)
