// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tarelka",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tarelka", targets: ["Tarelka"]),
        .executable(name: "TarelkaWidget", targets: ["TarelkaWidget"])
    ],
    targets: [
        .target(name: "NutritionCore", resources: [.process("Resources")]),
        .executableTarget(name: "Tarelka", dependencies: ["NutritionCore"]),
        .executableTarget(name: "TarelkaWidget", dependencies: ["NutritionCore"]),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"]),
        .testTarget(name: "TarelkaTests", dependencies: ["Tarelka", "NutritionCore"])
    ]
)
