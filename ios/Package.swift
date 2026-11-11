// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AplikacjaSprzedazowa",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "KitchenCore", targets: ["KitchenCore"]),
        .library(name: "KitchenScene", targets: ["KitchenScene"]),
        .executable(name: "KitchenApp", targets: ["KitchenApp"]),
        .executable(name: "KitchenChecks", targets: ["KitchenChecks"]),
        .executable(name: "FitDebug", targets: ["FitDebug"]),
    ],
    targets: [
        .target(name: "KitchenCore"),
        .target(name: "KitchenScene", dependencies: ["KitchenCore"]),
        .executableTarget(
            name: "KitchenApp",
            dependencies: ["KitchenCore", "KitchenScene"]
        ),
        .executableTarget(
            name: "KitchenChecks",
            dependencies: ["KitchenCore", "KitchenScene"]
        ),
        .executableTarget(
            name: "FitDebug",
            dependencies: ["KitchenCore"]
        ),
        .testTarget(
            name: "KitchenCoreTests",
            dependencies: ["KitchenCore"]
        ),
    ]
)
