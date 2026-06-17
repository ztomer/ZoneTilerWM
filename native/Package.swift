// swift-tools-version:5.9
import PackageDescription

// Native Swift port of ZoneTilerWM (v2). Lives under native/ to stay cleanly separated
// from the Lua source tree (modules/, tests/) which remains the executable spec.
//
//   ZTCore     — pure logic, NO AppKit/ApplicationServices import. Value snapshots.
//                Headless-testable; the algorithmic IP.
//   ZTSystem   — adapter layer (Foundation now; AppKit/AX/Carbon later). JSON storage,
//                config.toml loading. Conforms to ZTCore protocols.
//   zt-oracle  — executable mirroring the Lua oracles' JSON contracts for differential tests.
let package = Package(
    name: "ZoneTilerWM",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZTCore", targets: ["ZTCore"]),
        .library(name: "ZTSystem", targets: ["ZTSystem"]),
        .executable(name: "zt-oracle", targets: ["zt-oracle"]),
        .executable(name: "zt-axspike", targets: ["zt-axspike"]),
        .executable(name: "zt-probe", targets: ["zt-probe"]),
        .executable(name: "zt-tile", targets: ["zt-tile"]),
        .executable(name: "zt-agent", targets: ["zt-agent"]),
        .executable(name: "zt-autotile", targets: ["zt-autotile"]),
    ],
    dependencies: [
        // Maintained TOML parser (toml++-backed, Codable support) for reading config.toml.
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(name: "ZTCore"),
        .target(name: "ZTSystem", dependencies: ["ZTCore", "TOMLKit"]),
        .executableTarget(name: "zt-oracle", dependencies: ["ZTCore"]),
        .executableTarget(name: "zt-axspike", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-probe", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-tile", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-agent", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-autotile", dependencies: ["ZTSystem"]),
        .testTarget(name: "ZTCoreTests", dependencies: ["ZTCore"]),
        .testTarget(name: "ZTSystemTests", dependencies: ["ZTSystem"]),
    ]
)
