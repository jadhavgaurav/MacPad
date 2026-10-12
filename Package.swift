// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotePad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotePad", targets: ["NotePad"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "NotePadCore"),
        .target(
            name: "MarkdownRendering",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .executableTarget(
            name: "NotePad",
            dependencies: ["NotePadCore", "MarkdownRendering"]
        ),
        .testTarget(name: "NotePadCoreTests", dependencies: ["NotePadCore"]),
        .testTarget(name: "MarkdownRenderingTests", dependencies: ["MarkdownRendering"]),
    ],
    swiftLanguageModes: [.v5]
)
