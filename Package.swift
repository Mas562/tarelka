// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tarelka",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tarelka", targets: ["Tarelka"])],
    targets: [
        .target(name: "NutritionCore", resources: [.process("Resources")]),
        .executableTarget(name: "Tarelka", dependencies: ["NutritionCore"]),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"]),
        .testTarget(name: "TarelkaTests", dependencies: ["Tarelka", "NutritionCore"])
    ]
)
