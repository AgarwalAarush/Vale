// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Lilt", platforms: [.macOS(.v14)], products: [.executable(name: "Lilt", targets: ["Lilt"])], targets: [
    .target(name: "LiltCore"),
    .executableTarget(name: "Lilt", dependencies: ["LiltCore"]),
    .executableTarget(name: "LiltCoreChecks", dependencies: ["LiltCore"], path: "Tests/LiltCoreTests")
])
