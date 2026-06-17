// swift-tools-version:5.9
import PackageDescription

// Native Swift port of ZoneTilerWM (v2). Lives under native/ to stay cleanly separated
// from the Lua source tree (modules/, tests/) which remains the executable spec.
//
//   ZTCore     — pure logic, NO AppKit/ApplicationServices import. Operates on value
//                snapshots. Headless-testable; the algorithmic IP lives here.
//   zt-oracle  — executable mirroring tools/oracle_solver.lua's JSON contract, used for
//                differential testing against the Lua implementation.
let package = Package(
    name: "ZoneTilerWM",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZTCore", targets: ["ZTCore"]),
        .executable(name: "zt-oracle", targets: ["zt-oracle"]),
    ],
    targets: [
        .target(name: "ZTCore"),
        .executableTarget(name: "zt-oracle", dependencies: ["ZTCore"]),
        .testTarget(name: "ZTCoreTests", dependencies: ["ZTCore"]),
    ]
)
