// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SprechenCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "SprechenCore", targets: ["SprechenCore"])],
    targets: [
        .target(name: "SprechenCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "SprechenCoreTests", dependencies: ["SprechenCore"])
    ]
)
