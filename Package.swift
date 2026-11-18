// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ZenSweep", platforms: [.macOS(.v14)], products: [.executable(name: "ZenSweep", targets: ["ZenSweep"])], targets: [.executableTarget(name: "ZenSweep")], swiftLanguageModes: [.v5])
