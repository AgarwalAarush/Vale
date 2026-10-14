// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Vale", platforms: [.macOS(.v14)], products: [.executable(name: "Lilt", targets: ["Lilt"])], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")], targets: [
    .target(name: "LiltCore"),
    .executableTarget(name: "Lilt", dependencies: ["LiltCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "LiltCoreChecks", dependencies: ["LiltCore"], path: "Tests/LiltCoreTests", resources: [.copy("Fixtures")])
])
