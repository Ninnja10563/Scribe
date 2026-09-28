// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "ImportExport", targets: ["ImportExport"]),
        .executable(name: "Scribe", targets: ["Scribe"])
    ],
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "DocumentCore"),
        .target(name: "ImportExport", dependencies: ["DocumentCore", "CZlib"]),
        .executableTarget(name: "Scribe", dependencies: ["DocumentCore", "ImportExport"]),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "ImportExportTests", dependencies: ["ImportExport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ScribeTests", dependencies: ["Scribe"])
    ],
    swiftLanguageModes: [.v5]
)
