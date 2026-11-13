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
        .executable(name: "RoomDiag", targets: ["RoomDiag"]),
        // Moduł katalogu: samoistny, niepodpięty do aplikacji (rejestr, konwersja, legalność, marże)
        .library(name: "CatalogCore", targets: ["CatalogCore"]),
        .library(name: "CatalogUI", targets: ["CatalogUI"]),
        .executable(name: "CatalogTool", targets: ["CatalogTool"]),
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
        .executableTarget(
            name: "RoomDiag",
            dependencies: ["KitchenCore"]
        ),
        .testTarget(
            name: "KitchenCoreTests",
            dependencies: ["KitchenCore"]
        ),
        .target(name: "CatalogCore"),
        .target(name: "CatalogUI", dependencies: ["CatalogCore"]),
        .executableTarget(name: "CatalogTool", dependencies: ["CatalogCore"]),
        .testTarget(name: "CatalogCoreTests", dependencies: ["CatalogCore"]),
    ]
)
