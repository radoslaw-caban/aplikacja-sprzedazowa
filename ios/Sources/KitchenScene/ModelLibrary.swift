import Foundation
import RealityKit

/// Biblioteka modeli 3D wczytanych z plików GLB.
///
/// Modele leżą w `Resources/Models` (w aplikacji: bundle, w testach: ścieżka repo)
/// i są wczytywane raz, z cache — bo parsowanie GLB nie jest darmowe.
@MainActor
public enum ModelLibrary {

    public struct Entry: Sendable {
        public let name: String
        public let license: String
        public let author: String
    }

    /// Spis modeli z licencjami (wymóg CC-BY: podanie autora).
    public static let catalog: [Entry] = [
        Entry(name: "IslandTree", license: "CC0", author: "Poly Haven"),
        Entry(name: "IslandTree_LOD1", license: "CC0", author: "Poly Haven"),
        Entry(name: "IslandTree_LOD2", license: "CC0", author: "Poly Haven"),
        Entry(name: "TeslaModel3", license: "CC-BY-4.0",
              author: "Ameer Studio · https://sketchfab.com/3d-models/tesla-2018-model-3-5ef9b845aaf44203b6d04e2c677e444f"),
        Entry(name: "TerraceSofa", license: "CC0", author: "Poly Haven · Sofa 01"),
        Entry(name: "TerracePlant", license: "CC0", author: "Poly Haven · Anthurium Botany 01"),
        Entry(name: "boulder_01", license: "CC0", author: "Poly Haven · Boulder 01"),
        Entry(name: "stone_01", license: "CC0", author: "Poly Haven · Stone 01"),
        Entry(name: "fern_02", license: "CC0", author: "Poly Haven · Fern 02"),
        Entry(name: "nettle_plant", license: "CC0", author: "Poly Haven · Nettle Plant"),
        Entry(name: "shrub_01", license: "CC0", author: "Poly Haven · Shrub 01"),
        Entry(name: "grass_medium_01", license: "CC0", author: "Poly Haven · Grass Medium 01"),
    ]

    private static var cache: [String: Entity] = [:]

    /// Ścieżka do katalogu z modelami: bundle aplikacji albo repo (podczas testów).
    public static func modelsDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        if let direct = Bundle.main.url(forResource: "Models", withExtension: nil) {
            return direct
        }
        // ścieżki deweloperskie: uruchomienie z katalogu ios/ lub repo
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in ["Resources/Models", "ios/Resources/Models"] {
            let url = cwd.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Wczytuje model (z cache) lub zwraca nil, gdy pliku nie ma.
    public static func entity(named name: String) -> Entity? {
        if let cached = cache[name] {
            return cached.clone(recursive: true)
        }
        guard let dir = modelsDirectory() else { return nil }
        let url = dir.appendingPathComponent("\(name).glb")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let loaded = try? GLBLoader.load(url: url) else { return nil }
        let entity = loaded.entity
        entity.name = name
        cache[name] = entity
        return entity.clone(recursive: true)
    }

    /// Skalowanie po NAJWIĘKSZYM wymiarze — modele z różnych źródeł mają różne
    /// osie i jednostki, więc „wysokość" bywa bokiem bryły.
    public static func entity(named name: String, targetSize: Float) -> Entity? {
        guard let entity = entity(named: name) else { return nil }
        let bounds = entity.visualBounds(relativeTo: nil)
        let largest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard largest > 0.0001 else { return entity }
        entity.scale = .one * (targetSize / largest)
        let scaled = entity.visualBounds(relativeTo: nil)
        entity.position = [-scaled.center.x, -scaled.min.y, -scaled.center.z]
        let wrapper = Entity()
        wrapper.addChild(entity)
        return wrapper
    }

    /// Model przeskalowany po najdłuższym wymiarze (dobre dla auta).
    public static func entity(named name: String, targetLength: Float, axis: Int) -> Entity? {
        guard let entity = entity(named: name) else { return nil }
        let bounds = entity.visualBounds(relativeTo: nil)
        let extent = axis == 0 ? bounds.extents.x : (axis == 1 ? bounds.extents.y : bounds.extents.z)
        guard extent > 0.0001 else { return entity }
        entity.scale = .one * (targetLength / extent)
        let scaled = entity.visualBounds(relativeTo: nil)
        entity.position = [-scaled.center.x, -scaled.min.y, -scaled.center.z]
        let wrapper = Entity()
        wrapper.addChild(entity)
        return wrapper
    }

    /// Model przeskalowany do zadanej wysokości (metry) — modele mają różne jednostki.
    public static func entity(named name: String, targetHeight: Float) -> Entity? {
        guard let entity = entity(named: name) else { return nil }
        let bounds = entity.visualBounds(relativeTo: nil)
        let height = bounds.extents.y
        guard height > 0.0001 else { return entity }
        let scale = targetHeight / height
        entity.scale = .one * scale
        // po skalowaniu postaw model na ziemi i wyśrodkuj w XZ
        let scaled = entity.visualBounds(relativeTo: nil)
        entity.position = [-scaled.center.x, -scaled.min.y, -scaled.center.z]
        let wrapper = Entity()
        wrapper.addChild(entity)
        return wrapper
    }
}
