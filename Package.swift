// swift-tools-version:5.9
import PackageDescription
import Foundation

// Private-API gate (ZT_PRIVATE_APIS): the binary build scripts pass `-Xswiftc -DZT_PRIVATE_APIS` for
// `swift build`, but that cannot reach the package targets when the .app is built by xcodebuild. So we
// ALSO honor a `ZT_PRIVATE_APIS` environment variable here: the package_*.sh app builders set it, and
// this manifest adds the `.define` to the targets that contain `#if ZT_PRIVATE_APIS` (currently just
// ZTSystem). Either mechanism enables the same code; with neither, the build is strict-MAS-clean.
let ztPrivateAPIs = ProcessInfo.processInfo.environment["ZT_PRIVATE_APIS"] != nil
let ztPrivateSettings: [SwiftSetting] = ztPrivateAPIs ? [.define("ZT_PRIVATE_APIS")] : []

// Native Swift port of ZoneTilerWM (v2). Lives under  to stay cleanly separated
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
        .library(name: "ZTUI", targets: ["ZTUI"]),
        .executable(name: "zt-oracle", targets: ["zt-oracle"]),
        .executable(name: "zt-axspike", targets: ["zt-axspike"]),
        .executable(name: "zt-probe", targets: ["zt-probe"]),
        .executable(name: "zt-tile", targets: ["zt-tile"]),
        .executable(name: "zt-agent", targets: ["zt-agent"]),
        .executable(name: "zt-autotile", targets: ["zt-autotile"]),
        .executable(name: "zt-mcp", targets: ["zt-mcp"]),
        .executable(name: "zonetiler-cli", targets: ["zonetiler-cli"]),
    ],
    dependencies: [
        // Maintained TOML parser (toml++-backed, Codable support) for reading config.toml.
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(name: "ZTCore"),
        // `ZT_PRIVATE_APIS` gates ALL private-API code here (SkyLight Spaces reader, _AXUIElementGetWindow
        // AX SPI, SkyLight focus-border renderer). It is NEVER hardcoded on — it comes from the build
        // scripts (`-Xswiftc -DZT_PRIVATE_APIS`) or the `ZT_PRIVATE_APIS` env var (see top of file), so
        // the default build is strict-MAS-clean (public fallbacks only).
        .target(name: "ZTSystem", dependencies: ["ZTCore", "TOMLKit"], swiftSettings: ztPrivateSettings),
        .target(name: "ZTUI", dependencies: ["ZTCore", "ZTSystem"], resources: [.process("Resources")]),
        .executableTarget(name: "zt-oracle", dependencies: ["ZTCore"]),
        .executableTarget(name: "zt-axspike", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-probe", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-tile", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-agent", dependencies: ["ZTSystem", "ZTUI"]),
        .executableTarget(name: "zt-autotile", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zt-mcp", dependencies: ["ZTSystem"]),
        .executableTarget(name: "zonetiler-cli", dependencies: ["ZTSystem"]),
        .testTarget(name: "ZTCoreTests", dependencies: ["ZTCore"]),
        .testTarget(name: "ZTSystemTests", dependencies: ["ZTSystem"]),
    ]
)
