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
        .executable(name: "KitchenApp", targets: ["KitchenApp"]),
        .executable(name: "KitchenChecks", targets: ["KitchenChecks"]),
    ],
    targets: [
        .target(name: "KitchenCore"),
        .executableTarget(
            name: "KitchenApp",
            dependencies: ["KitchenCore"]
        ),
        .executableTarget(
            name: "KitchenChecks",
            dependencies: ["KitchenCore"]
        ),
    ]
)
