import Foundation
import simd
import RealityKit
import KitchenCore

// Kolory platformy: iOS → UIColor, macOS → NSColor. Ten sam alias co w SceneBuilder,
// żeby jedna implementacja działała na obu platformach (pakiet buduje się także na Macu).
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Buduje encję RealityKit z siatki pomieszczenia (`RoomMesh.Result`).
///
/// PO CO: `RoomMesh` liczy ściany z otworami i UV w metrach, ale to są zwykłe
/// tablice. Tutaj zamieniamy je na geometrię, którą widać w scenie.
///
/// UV W METRACH: `RoomMesh` zwraca współrzędne tekstury równe wymiarowi
/// w metrach (kafel = 1 m). RealityKit oczekuje UV w zakresie 0…1 na kafelek,
/// więc dzielimy przez rozmiar kafla — dzięki temu cegła czy płytka na ścianie
/// 4 m i na ścianie 1 m wygląda tak samo duża.
///
/// KOLORY: każda powierzchnia (ściana, podłoga, sufit) dostaje własny materiał
/// z kolorem wyliczonym z chmury (`RoomMesh.averageColors`). Bez tego cała
/// siatka byłaby jednolita i nie dałoby się odróżnić podłogi od ściany.
public enum RoomMeshEntity {

    /// Rozmiar jednej kafelki tekstury w metrach (musi zgadzać się z UV z RoomMesh).
    public static let tile: Float = 1.0

    /// Buduje encję całego pomieszczenia.
    ///
    /// - Parameters:
    ///   - mesh: siatka z `RoomMesh.build`
    ///   - colors: kolory powierzchni z `RoomMesh.averageColors` (może być pusta)
    ///   - opacity: przezroczystość (1 = pełne, 0.5 = widać przez ściany)
    @MainActor
    public static func make(_ mesh: RoomMesh.Result,
                            colors: [RoomMesh.SurfaceColor] = [],
                            opacity: Float = 1.0) -> Entity {
        let root = Entity()
        root.name = "room-mesh"

        // kolory dopasowujemy do powierzchni po pozycji (kolejność ta sama,
        // ale przy braku kolorów i tak używamy domyślnych)
        for (i, surface) in mesh.surfaces.enumerated() {
            guard !surface.vertices.isEmpty, !surface.indices.isEmpty else { continue }

            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(surface.vertices.count)
            var normals: [SIMD3<Float>] = []
            normals.reserveCapacity(surface.vertices.count)
            var uvs: [SIMD2<Float>] = []
            uvs.reserveCapacity(surface.vertices.count)

            for v in surface.vertices {
                positions.append(v.position)
                normals.append(v.normal)
                // UV w metrach → kafelki: dzielimy przez rozmiar kafla
                uvs.append(v.uv / tile)
            }

            var descriptor = MeshDescriptor(name: "surface-\(i)")
            descriptor.positions = MeshBuffer(positions)
            descriptor.normals = MeshBuffer(normals)
            descriptor.textureCoordinates = MeshBuffer(uvs)
            descriptor.primitives = .triangles(surface.indices)
            guard let resource = try? MeshResource.generate(from: [descriptor]) else { continue }

            let material = makeMaterial(kind: surface.kind,
                                        rgb: colorFor(surface: surface, index: i, colors: colors),
                                        opacity: opacity)
            let entity = ModelEntity(mesh: resource, materials: [material])
            entity.name = "\(surface.kind.rawValue)-\(i)"
            root.addChild(entity)
        }
        return root
    }

    /// Kolor powierzchni: z chmury, a gdy brak danych — sensowna domyślna paleta.
    ///
    /// Domyślne kolory nie są przypadkowe: podłoga ciemna i ciepła, ściany jasne,
    /// sufit najjaśniejszy. Dzięki temu nawet bez danych z kamery pomieszczenie
    /// czyta się od razu (widać, co jest czym).
    static func colorFor(surface: RoomMesh.Surface, index: Int,
                         colors: [RoomMesh.SurfaceColor]) -> SIMD3<Float> {
        if colors.indices.contains(index), colors[index].samples >= 20 {
            return colors[index].rgb
        }
        switch surface.kind {
        case .floor: return SIMD3(0.52, 0.40, 0.29)
        case .wall: return SIMD3(0.86, 0.85, 0.82)
        case .ceiling: return SIMD3(0.95, 0.95, 0.94)
        }
    }

    /// Materiał z kolorem powierzchni.
    ///
    /// Cechy istotne dla wnętrza:
    ///  - `roughness = 1` — ściana nie odbija światła jak plastik; przy 0,5
    ///    wnętrze wyglądało jak makieta z tworzywa,
    ///  - `isDoubleSided` wyłączone — gdyby render była obustronna, patrząc
    ///    z zewnątrz widziałbyś wnętrze przez ścianę (ten sam błąd, który
    ///    naprawialiśmy w podglądzie AR).
    static func makeMaterial(kind: RoomMesh.Surface.Kind, rgb: SIMD3<Float>,
                             opacity: Float) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color(rgb))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    static func color(_ rgb: SIMD3<Float>) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor(red: CGFloat(min(1, max(0, rgb.x))),
                       green: CGFloat(min(1, max(0, rgb.y))),
                       blue: CGFloat(min(1, max(0, rgb.z))),
                       alpha: 1)
        #else
        return NSColor(red: CGFloat(min(1, max(0, rgb.x))),
                       green: CGFloat(min(1, max(0, rgb.y))),
                       blue: CGFloat(min(1, max(0, rgb.z))),
                       alpha: 1)
        #endif
    }
}
