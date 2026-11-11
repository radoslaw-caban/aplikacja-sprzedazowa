import Foundation
import RealityKit
import KitchenCore

#if os(iOS)
import UIKit
public typealias ScanColor = UIColor
#else
import AppKit
public typealias ScanColor = NSColor
#endif

/// Dom zbudowany z planu wyprowadzonego ze SKANU (chmura punktów X9).
///
/// Wymiary i położenie ścian pochodzą z danych (`ScanPlan`), nie z generatora:
/// obrys, wysokość i odcinki ścian wewnętrznych są zmierzone w chmurze.
/// Ten builder tylko zamienia je na geometrię — grubości i wysokości
/// elementów (tynk, strop, okna) to jedyne wartości dobrane tutaj.
@MainActor
public enum ScanHouseBuilder {

    /// Grubość ściany zewnętrznej (m) — mierzona w chmurze była ~0,25.
    public static let exteriorThickness: Float = 0.25
    /// Grubość ścianki działowej (m).
    public static let partitionThickness: Float = 0.10
    /// Grubość stropu/podłogi (m).
    public static let slabThickness: Float = 0.22

    public static func entity(plan: ScanPlan) -> Entity {
        let root = Entity()
        root.name = "scan-house"

        let w = plan.width
        let d = plan.depth
        let h = plan.height

        // MARK: materiały
        var plaster = PhysicallyBasedMaterial()
        plaster.baseColor = .init(tint: ScanColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1))
        plaster.roughness = .init(floatLiteral: 0.85)
        plaster.metallic = .init(floatLiteral: 0)

        var floorMaterial = PhysicallyBasedMaterial()
        if let wood = EnvironmentArt.photoTexture("wood_diff") {
            floorMaterial.baseColor = .init(tint: ScanColor(white: 0.95, alpha: 1), texture: .init(wood))
            floorMaterial.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(8, 8))
        } else {
            floorMaterial.baseColor = .init(tint: ScanColor(red: 0.62, green: 0.50, blue: 0.36, alpha: 1))
        }
        floorMaterial.roughness = .init(floatLiteral: 0.6)

        var slab = plaster
        slab.baseColor = .init(tint: ScanColor(white: 0.86, alpha: 1))

        // MARK: podłoga i strop
        let floorSlab = ModelEntity(
            mesh: .generateBox(width: w, height: slabThickness, depth: d),
            materials: [floorMaterial]
        )
        floorSlab.position = [0, -slabThickness / 2, 0]
        floorSlab.name = "scan-floor"
        root.addChild(floorSlab)

        let ceiling = ModelEntity(
            mesh: .generateBox(width: w, height: slabThickness, depth: d),
            materials: [slab]
        )
        ceiling.position = [0, h + slabThickness / 2, 0]
        ceiling.name = "scan-ceiling"
        root.addChild(ceiling)

        // MARK: ściany zewnętrzne z otworami okiennymi
        // Otwory rozstawiamy co ~2,6 m: bez nich dom jest zamkniętą skrzynią.
        let windowSill: Float = 0.9
        let windowTop: Float = 2.1

        func exteriorWall(center: SIMD3<Float>, length: Float, alongX: Bool) {
            let thickness = exteriorThickness
            let windowWidth: Float = 1.3
            let pitch: Float = 2.6
            let count = max(1, Int((length - 0.8) / pitch))
            let usable = length - 1.0
            let gap = (usable - Float(count) * windowWidth) / Float(max(1, count + 1))

            var cursor = -length / 2 + 0.5 + gap
            var pieces: [(Float, Float, Float, Float)] = []   // (offset, width, bottom, height)
            for _ in 0..<count {
                // słupek między oknami
                pieces.append((cursor - gap / 2, gap, 0, h))
                // pod oknem i nad oknem
                pieces.append((cursor + windowWidth / 2, windowWidth, 0, windowSill))
                pieces.append((cursor + windowWidth / 2, windowWidth, windowTop, h - windowTop))
                cursor += windowWidth + gap
            }
            pieces.append((length / 2 - 0.5 - gap / 2, gap, 0, h))

            for (offset, width, bottom, height) in pieces {
                guard width > 0.02, height > 0.02 else { continue }
                let box = ModelEntity(
                    mesh: .generateBox(width: alongX ? width : thickness,
                                       height: height,
                                       depth: alongX ? thickness : width),
                    materials: [plaster]
                )
                let shift = alongX
                    ? SIMD3<Float>(offset, bottom + height / 2, 0)
                    : SIMD3<Float>(0, bottom + height / 2, offset)
                box.position = center + shift
                box.name = "scan-wall-exterior"
                root.addChild(box)
            }
        }

        exteriorWall(center: [0, 0, -d / 2 + exteriorThickness / 2], length: w, alongX: true)
        exteriorWall(center: [0, 0, d / 2 - exteriorThickness / 2], length: w, alongX: true)
        exteriorWall(center: [-w / 2 + exteriorThickness / 2, 0, 0], length: d, alongX: false)
        exteriorWall(center: [w / 2 - exteriorThickness / 2, 0, 0], length: d, alongX: false)

        // MARK: ściany wewnętrzne — dokładnie tam, gdzie wykryto je w chmurze
        for (index, wall) in plan.walls.enumerated() {
            let length = wall.length
            guard length > 0.2 else { continue }
            let mid = (wall.from + wall.to) / 2
            let box = ModelEntity(
                mesh: .generateBox(width: wall.axis == "x" ? partitionThickness : length,
                                   height: h,
                                   depth: wall.axis == "x" ? length : partitionThickness),
                materials: [plaster]
            )
            box.position = wall.axis == "x"
                ? SIMD3<Float>(wall.pos, h / 2, mid)
                : SIMD3<Float>(mid, h / 2, wall.pos)
            box.name = "scan-wall-partition-\(index)"
            root.addChild(box)
        }

        return root
    }
}
