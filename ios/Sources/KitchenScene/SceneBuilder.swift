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
        /// obrys zabudowy w metrach — liczony z danych, nie z RealityKit
        /// (encje nie mają jeszcze geometrii w chwili tworzenia widoku)
        public let center: SIMD3<Float>
        public let extents: SIMD3<Float>
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

        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for b in boxes {
            let half = SIMD3(meters(b.size.x) / 2, meters(b.size.y) / 2, meters(b.size.z) / 2)
            let p = SIMD3(meters(b.position.x), meters(b.position.y), meters(b.position.z))
            lo = SIMD3(Swift.min(lo.x, p.x - half.x), Swift.min(lo.y, p.y - half.y), Swift.min(lo.z, p.z - half.z))
            hi = SIMD3(Swift.max(hi.x, p.x + half.x), Swift.max(hi.y, p.y + half.y), Swift.max(hi.z, p.z + half.z))
        }
        let center = boxes.isEmpty ? SIMD3<Float>.zero : (lo + hi) / 2
        let extents = boxes.isEmpty ? SIMD3<Float>.zero : (hi - lo)

        return Built(
            root: root,
            bodyCount: cabinets.count,
            totalBoxes: boxes.count,
            widthMeters: maxX - minX,
            center: center,
            extents: extents
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
    public static func buildRoom(_ room: Room, walls: Bool = true) -> Entity {
        let root = Entity()
        root.name = "room"

        let floor = ModelEntity(
            mesh: .generateBox(width: meters(room.width), height: 0.02, depth: meters(room.depth), cornerRadius: 0),
            materials: [SimpleMaterial(color: color("#c8b39a"), isMetallic: false)]
        )
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        var wallMaterial = PhysicallyBasedMaterial()
        if let diff = EnvironmentArt.photoTexture("stucco_diff") {
            wallMaterial.baseColor = .init(tint: .white, texture: .init(diff))
        } else {
            wallMaterial.baseColor = .init(tint: color("#e8e0d5"))
        }
        if let nor = EnvironmentArt.photoTexture("stucco_nor", semantic: .normal) {
            wallMaterial.normal = .init(texture: .init(nor))
        }
        wallMaterial.roughness = .init(floatLiteral: 0.85)
        for i in 0..<(walls ? 4 : 0) {
            let size = room.wallSize(i)
            let pos = room.wallPosition(i)
            let wall = ModelEntity(
                mesh: MeshFactory.texturedBox(
                    width: meters(size.x), height: meters(size.y), depth: meters(size.z), tile: 2.5
                ) ?? .generateBox(width: meters(size.x), height: meters(size.y), depth: meters(size.z), cornerRadius: 0),
                materials: [wallMaterial]
            )
            wall.position = [meters(pos.x), meters(pos.y), meters(pos.z)]
            wall.name = "wall-\(i)"
            root.addChild(wall)
        }

        // dach: płaski, z lekkim nawisem — bez niego dom wygląda jak otwarte pudełko
        var roofMaterial = PhysicallyBasedMaterial()
        if let diff = EnvironmentArt.photoTexture("roof_diff") {
            roofMaterial.baseColor = .init(tint: .white, texture: .init(diff))
        } else {
            roofMaterial.baseColor = .init(tint: color("#54585e"))
        }
        if let nor = EnvironmentArt.photoTexture("roof_nor", semantic: .normal) {
            roofMaterial.normal = .init(texture: .init(nor))
        }
        roofMaterial.roughness = .init(floatLiteral: 0.7)

        let roofWidth = meters(room.width) + 0.7
        let roofDepth = meters(room.depth) + 0.7
        let rise = min(1.6, roofDepth * 0.28)

        // dach dwuspadowy z okapem — dopiero to czyta się jako dom, nie pudełko
        if let mesh = MeshFactory.gabledRoof(
            width: roofWidth,
            depth: roofDepth,
            rise: rise,
            eaveOverhang: 0.45,
            gableOverhang: 0.35,
            tile: 1.6
        ) {
            let gableRoof = ModelEntity(mesh: mesh, materials: [roofMaterial])
            gableRoof.position = [0, meters(room.height), 0]
            gableRoof.name = "roof"
            root.addChild(gableRoof)

            // szczyty pod dachem (trójkąty) — inaczej widać dziurę nad ścianą
            if let ends = MeshFactory.gableEnds(width: meters(room.width) + 0.02, rise: rise, depth: meters(room.depth) + 0.02) {
                let gables = ModelEntity(mesh: ends, materials: [wallMaterial])
                gables.position = [0, meters(room.height), 0]
                gables.name = "gables"
                root.addChild(gables)
            }

            // rynna i obróbka kalenicy
            var trim = PhysicallyBasedMaterial()
            trim.baseColor = .init(tint: color("#3c3f42"))
            trim.roughness = .init(floatLiteral: 0.45)
            trim.metallic = .init(floatLiteral: 0.6)

            let ridge = ModelEntity(
                mesh: .generateBox(width: roofWidth + 0.7, height: 0.09, depth: 0.16, cornerRadius: 0.01),
                materials: [trim]
            )
            ridge.position = [0, meters(room.height) + rise + 0.04, 0]
            ridge.name = "ridge"
            root.addChild(ridge)

            for sign in [Float(1), Float(-1)] {
                let gutter = ModelEntity(
                    mesh: .generateBox(width: roofWidth + 0.7, height: 0.12, depth: 0.14, cornerRadius: 0.02),
                    materials: [trim]
                )
                gutter.position = [0, meters(room.height) - 0.04, sign * (roofDepth / 2 + 0.42)]
                gutter.name = "gutter"
                root.addChild(gutter)
            }
        } else {
            let roof = ModelEntity(
                mesh: MeshFactory.texturedBox(width: roofWidth, height: 0.24, depth: roofDepth, tile: 1.6)
                    ?? .generateBox(width: roofWidth, height: 0.24, depth: roofDepth, cornerRadius: 0.02),
                materials: [roofMaterial]
            )
            roof.position = [0, meters(room.height) + 0.11, 0]
            roof.name = "roof"
            root.addChild(roof)
        }

        // elewacja: okna i drzwi po stronie podjazdu (+Z), żeby dom czytał się z zewnątrz
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: color("#2b3a4a"))
        glass.roughness = .init(floatLiteral: 0.08)
        glass.metallic = .init(floatLiteral: 0.35)

        var frame = PhysicallyBasedMaterial()
        frame.baseColor = .init(tint: color("#f4f2ec"))
        frame.roughness = .init(floatLiteral: 0.6)

        let facadeZ = meters(room.depth) / 2 + 0.06
        for (index, xOffset) in [-1, 1].enumerated() {
            let window = ModelEntity(
                mesh: .generateBox(width: 1.4, height: 1.1, depth: 0.08, cornerRadius: 0.01),
                materials: [frame]
            )
            window.position = [Float(xOffset) * meters(room.width) * 0.22, 1.5, facadeZ + 0.05]
            window.name = "window-\(index)"
            root.addChild(window)

            let pane = ModelEntity(
                mesh: .generateBox(width: 1.24, height: 0.94, depth: 0.06, cornerRadius: 0.005),
                materials: [glass]
            )
            pane.position = [window.position.x, 1.5, facadeZ + 0.07]
            root.addChild(pane)

            // parapet: cienka płyta pod oknem, żeby elewacja nie była „naklejką"
            var sillMat = PhysicallyBasedMaterial()
            sillMat.baseColor = .init(tint: color("#d8d2c6"))
            sillMat.roughness = .init(floatLiteral: 0.5)
            let sill = ModelEntity(
                mesh: .generateBox(width: 1.56, height: 0.06, depth: 0.18, cornerRadius: 0.008),
                materials: [sillMat]
            )
            sill.position = [window.position.x, 0.93, facadeZ + 0.09]
            sill.name = "sill-\(index)"
            root.addChild(sill)
        }

        let doorFrame = ModelEntity(
            mesh: .generateBox(width: 1.0, height: 2.1, depth: 0.1, cornerRadius: 0.01),
            materials: [frame]
        )
        doorFrame.position = [0, 1.05, facadeZ]
        root.addChild(doorFrame)

        var doorMaterial = PhysicallyBasedMaterial()
        doorMaterial.baseColor = .init(tint: color("#3c3a36"))
        doorMaterial.roughness = .init(floatLiteral: 0.5)
        let door = ModelEntity(
            mesh: .generateBox(width: 0.88, height: 2.0, depth: 0.08, cornerRadius: 0.005),
            materials: [doorMaterial]
        )
        door.position = [0, 1.0, facadeZ + 0.02]
        root.addChild(door)

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
        #if os(iOS)
        // cień to osobny komponent (macOS SDK go nie ma)
        entity.components.set(DirectionalLightComponent.Shadow(maximumDistance: 60, depthBias: 1.0))
        #endif
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
