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
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.25.1"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c-sharp", exact: "0.23.5"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", exact: "0.23.4"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", exact: "0.23.5"),
    ],
    targets: [
        // The Python grammar, vendored: its Package.swift cannot be used as a dependency (Sources/GrammarPython/README.md).
        // `-w`: Xcode's build of the generated C warns (-Wshorten-64-to-32), and the app builds without warnings.
        .target(
            name: "GrammarPython",
            exclude: ["LICENSE", "README.md"],
            cSettings: [.unsafeFlags(["-w"])]
        ),
        // The PowerShell grammar, vendored for the same reason (Sources/GrammarPowerShell/README.md).
        .target(
            name: "GrammarPowerShell",
            exclude: ["LICENSE", "README.md"],
            cSettings: [.unsafeFlags(["-w"])]
        ),
        // The SQL grammar, vendored: its generated parser.c (41 MB) is on the gh-pages branch of its repository only, so
        // a dependency can only pin a commit of that branch, which nothing else here does (Sources/GrammarSQL/README.md).
        .target(
            name: "GrammarSQL",
            exclude: ["LICENSE", "README.md"],
            cSettings: [.unsafeFlags(["-w"])]
        ),
        .target(
            name: "ScratchCode",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterCSharp", package: "tree-sitter-c-sharp"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                "GrammarPython",
                "GrammarPowerShell",
                "GrammarSQL",
            ],
            // One directory per language with its highlights.scm: Bundle.module is the one accessor that works on
            // Linux, under `swift test` on macOS and inside the app, which the grammar packages' own bundles are not.
            resources: [.copy("Queries")]
        ),
        .testTarget(
            name: "ScratchCodeTests", dependencies: ["ScratchCode"], resources: [.copy("Samples"), .copy("Corpus")]),
    ],
    swiftLanguageModes: [.v6]
)
