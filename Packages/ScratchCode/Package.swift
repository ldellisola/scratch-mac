// swift-tools-version:6.2
import PackageDescription

// Every dependency is pinned with `exact:`, the tree-sitter runtime included (SwiftTreeSitter would otherwise let it
// float within 0.25.x). The Xcode project is generated and never committed, so a Package.resolved of its own would not
// survive: exact versions here are what keeps the app and `swift test` on the same code. Versions, licences and the
// steps to add a language are in docs/decisions/0007-tree-sitter.md.
let package = Package(
    name: "ScratchCode",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ScratchCode", targets: ["ScratchCode"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
        // The Swift grammar's generated parser.c is on the `-with-generated-files` tags only.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.4-with-generated-files"),
    ],
    targets: [
        // The Python grammar, vendored: its Package.swift cannot be used as a dependency (Sources/GrammarPython/README.md).
        .target(name: "GrammarPython", exclude: ["LICENSE", "README.md"]),
        .target(
            name: "ScratchCode",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                "GrammarPython",
            ],
            // One directory per language with its highlights.scm: Bundle.module is the one accessor that works on
            // Linux, under `swift test` on macOS and inside the app, which the grammar packages' own bundles are not.
            resources: [.copy("Queries")]
        ),
        .testTarget(name: "ScratchCodeTests", dependencies: ["ScratchCode"]),
    ],
    swiftLanguageModes: [.v6]
)
