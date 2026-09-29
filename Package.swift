// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let updaterPackages: [Package.Dependency] = [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")]
let updaterTargets: [Target.Dependency] = [.product(name: "Sparkle", package: "Sparkle")]
#else
let updaterPackages: [Package.Dependency] = []
let updaterTargets: [Target.Dependency] = []
#endif

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "ImportExport", targets: ["ImportExport"]),
        .executable(name: "Scribe", targets: ["Scribe"])
    ],
    dependencies: updaterPackages,
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "DocumentCore"),
        .target(name: "ImportExport", dependencies: ["DocumentCore", "CZlib"]),
        .executableTarget(name: "Scribe", dependencies: [.byName(name: "DocumentCore"), .byName(name: "ImportExport")] + updaterTargets, resources: [.copy("Resources/MathFont")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS]))]),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "ImportExportTests", dependencies: ["ImportExport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ScribeTests", dependencies: ["Scribe"])
    ],
    swiftLanguageModes: [.v5]
)
