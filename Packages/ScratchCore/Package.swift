// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ScratchCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ScratchCore", targets: ["ScratchCore"])
    ],
    targets: [
        // No `pkgConfig` on purpose: on macOS pkg-config could pick up Homebrew's SQLite and link the app
        // against /opt/homebrew instead of the system library.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "ScratchCore", dependencies: ["CSQLite"]),
        .testTarget(name: "ScratchCoreTests", dependencies: ["ScratchCore"]),
    ],
    swiftLanguageModes: [.v6]
)
