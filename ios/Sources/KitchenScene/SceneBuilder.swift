import Foundation
import RealityKit
import KitchenCore

#if os(iOS)
import UIKit
public typealias PlatformColor = UIColor
#else
import AppKit
public typealias PlatformColor = NSColor
#endif

/// Budowa sceny RealityKit z brył domenowych (mm → metry).
/// Jedno miejsce mapowania: podmiana geometrii na importowane siatki to zmiana tutaj.
public enum SceneBuilder {

    /// Metry z milimetrów — cała konwersja w jednym miejscu.
    public static func meters(_ mm: Double) -> Float { Float(mm / 1000) }

    public struct Built {
        public let root: Entity
        public let bodyCount: Int
        public let totalBoxes: Int
        public let widthMeters: Float
    }

    /// Składa całą scenę: szafki, blaty, cokoły, podłogę, światło.
    @MainActor
    public static func build(cabinets: [Cabinet], includeFloor: Bool = true) -> Built {
        let root = Entity()

        let runs = Runs.compute(cabinets)
        var boxes: [Box] = []
        for c in cabinets {
            // Generator zwraca układ lokalny (środek szafki = 0,0,0) —
            // dopiero tutaj trafia do pokoju, tak jak cabinetsOrigin w wersji web.
            for b in Generator.build(c) {
                boxes.append(Box(
                    id: b.id,
                    role: b.role,
                    cabinetID: b.cabinetID,
                    size: b.size,
                    position: SIMD3(b.position.x + c.x, b.position.y, b.position.z + c.z),
                    color: b.color,
                    rotationY: b.rotationY
                ))
            }
        }
        let worktops = Runs.worktops(runs)
        boxes += worktops
        boxes += Runs.plinths(runs)

        for b in boxes {
            root.addChild(entity(for: b))
        }

        // podłoga
        if includeFloor {
        let floorMaterial = SimpleMaterial(color: color("#c8b39a"), isMetallic: false)
        let floor = ModelEntity(
            mesh: .generateBox(width: 8, height: 0.02, depth: 8, cornerRadius: 0),
            materials: [floorMaterial]
        )
        floor.position = [0, -0.01, 0]
        root.addChild(floor)
        }

        // szerokość całej zabudowy — do kadrowania kamery
        let minX = boxes.map { meters($0.position.x) - meters($0.size.x) / 2 }.min() ?? 0
        let maxX = boxes.map { meters($0.position.x) + meters($0.size.x) / 2 }.max() ?? 0

        return Built(
            root: root,
            bodyCount: cabinets.count,
            totalBoxes: boxes.count,
            widthMeters: maxX - minX
        )
    }

    /// Pojedyncza bryła: siatka w metrach, materiał PBR, obrót wokół Y.
    @MainActor
    public static func entity(for b: Box) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: meters(b.size.x),
            height: meters(b.size.y),
            depth: meters(b.size.z),
            cornerRadius: 0.0015
        )
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color(b.color))
        material.roughness = .init(floatLiteral: b.role == .plinth ? 0.95 : 0.55)
        material.metallic = .init(floatLiteral: 0)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = [meters(b.position.x), meters(b.position.y), meters(b.position.z)]
        entity.name = b.id
        if b.rotationY != 0 {
            entity.orientation = simd_quatf(angle: Float(b.rotationY * .pi / 180), axis: [0, 1, 0])
        }
        return entity
    }

    /// Pomieszczenie: podłoga, cztery ściany i listwy przypodłogowe.
    @MainActor
    public static func buildRoom(_ room: Room) -> Entity {
        let root = Entity()
        root.name = "room"

        let floor = ModelEntity(
            mesh: .generateBox(width: meters(room.width), height: 0.02, depth: meters(room.depth), cornerRadius: 0),
            materials: [SimpleMaterial(color: color("#c8b39a"), isMetallic: false)]
        )
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        let wallMaterial = SimpleMaterial(color: color("#e8e0d5"), isMetallic: false)
        for i in 0..<4 {
            let size = room.wallSize(i)
            let pos = room.wallPosition(i)
            let wall = ModelEntity(
                mesh: .generateBox(width: meters(size.x), height: meters(size.y), depth: meters(size.z), cornerRadius: 0),
                materials: [wallMaterial]
            )
            wall.position = [meters(pos.x), meters(pos.y), meters(pos.z)]
            wall.name = "wall-\(i)"
            root.addChild(wall)
        }

        // listwy 80 × 20 mm
        let skirting = SimpleMaterial(color: color("#f4f1ea"), isMetallic: false)
        for i in 0..<4 {
            let along: Float = (i < 2) ? meters(room.width) : 0.02
            let deep: Float = (i < 2) ? 0.02 : meters(room.depth)
            let strip = ModelEntity(
                mesh: .generateBox(width: along, height: 0.08, depth: deep, cornerRadius: 0),
                materials: [skirting]
            )
            let pos = room.wallPosition(i, thickness: 40)
            strip.position = [meters(pos.x), 0.04, meters(pos.z)]
            root.addChild(strip)
        }
        return root
    }

    /// Kierunkowe światło dzienne jako komponent (na macOS nie ma `.shadow`).
    @MainActor
    public static func sunlight() -> Entity {
        var sun = DirectionalLightComponent()
        sun.intensity = 3200
        sun.color = .init(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        let entity = Entity()
        entity.components.set(sun)
        entity.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        return entity
    }

    /// #rrggbb → kolor platformy (iOS: UIColor, macOS: NSColor).
    public static func color(_ hex: String) -> PlatformColor {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .gray }
        return PlatformColor(
            red: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: 1
        )
    }
}
