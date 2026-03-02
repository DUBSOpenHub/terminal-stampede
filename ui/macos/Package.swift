// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StampedeUI",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "StampedeUI", targets: ["StampedeUI"])],
    targets: [.executableTarget(name: "StampedeUI", path: "Sources/StampedeUI")]
)
