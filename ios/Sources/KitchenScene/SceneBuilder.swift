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
                // tekstura z biblioteki trafia tylko na fronty — korpus zostaje płytą
                let texture = (b.role == .front || b.role == .drawerFront) ? c.texture : nil
                boxes.append(Box(
                    id: b.id,
                    role: b.role,
                    cabinetID: b.cabinetID,
                    size: b.size,
                    position: SIMD3(b.position.x + c.x, b.position.y, b.position.z + c.z),
                    color: b.color,
                    texture: texture,
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
        // front może mieć teksturę z biblioteki (nazwa pliku w `Box.texture`)
        if let textureName = b.texture,
           let url = TextureStore.shared.url(for: textureName),
           let texture = try? TextureResource.load(contentsOf: url) {
            material.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: color(b.color))
        }
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

    /// Pomieszczenie + skorupa nowoczesnej willi.
    ///
    /// Wnętrze (podłoga, ściany, listwy) jest potrzebne do widoku kuchni;
    /// elewacja, dachy, przeszklenia, taras i basen powstają w `VillaBuilder`.
    @MainActor
    public static func buildRoom(_ room: Room, walls: Bool = true, scanPlan: ScanPlan? = nil, scanCloud: Bool = false) -> Entity {
        let root = Entity()
        root.name = "room"

        // Dom ZE SKANU: cała bryła (podłoga, strop, ściany zewnętrzne z oknami,
        // ścianki działowe) powstaje z planu zmierzonego w chmurze punktów.
        // Wtedy nie rysujemy ścian z `Room`, bo zdublowałyby zmierzone.
        if let scanPlan {
            // Bez stropu, gdy nakładamy chmurę — inaczej nie widać punktów
            // i nie da się ocenić, czy ściany pokrywają się ze skanem.
            root.addChild(ScanHouseBuilder.entity(plan: scanPlan, includeCeiling: !scanCloud, ghostWalls: scanCloud))
            return root
        }

        let houseW = meters(room.width)
        let houseD = meters(room.depth)

        // podłoga wewnętrzna
        let floor = ModelEntity(
            mesh: .generateBox(width: houseW, height: 0.02, depth: houseD, cornerRadius: 0),
            materials: [SimpleMaterial(color: color("#c8b39a"), isMetallic: false)]
        )
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        // płyta fundamentowa — w nowoczesnym domu nie ma wysokiego cokołu,
        // ale budynek musi stać na betonie, a nie na trawie
        var concreteMaterial = PhysicallyBasedMaterial()
        if let tex = EnvironmentArt.photoTexture("concrete_diff") {
            concreteMaterial.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            concreteMaterial.baseColor = .init(tint: color("#a9a69f"))
        }
        concreteMaterial.roughness = .init(floatLiteral: 0.9)
        if let mesh = MeshFactory.texturedBox(width: houseW + 0.7, height: 0.9, depth: houseD + 0.7, tile: 1.2) {
            let footing = ModelEntity(mesh: mesh, materials: [concreteMaterial])
            footing.position = [0, -0.33, 0]
            footing.name = "foundation"
            root.addChild(footing)
        }

        // ściany wewnętrzne parteru (tło dla zabudowy kuchennej)
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

        // skorupa willi: elewacja, płaskie dachy, przeszklenia, taras, basen
        root.addChild(VillaBuilder.shell(room: room))

        // listwy przypodłogowe 80 × 20 mm
        let skirting = SimpleMaterial(color: color("#f4f1ea"), isMetallic: false)
        for i in 0..<4 {
            let along: Float = (i < 2) ? houseW : 0.02
            let deep: Float = (i < 2) ? 0.02 : houseD
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
        let sunEntity = makeSun()
        // Drugie, słabe światło z przeciwnej strony: bez niego zacienione
        // strony drzew i elewacji były czarne (scena „nocna" w dzień).
        let fillEntity = makeFill()
        let root = Entity()
        root.addChild(sunEntity)
        root.addChild(fillEntity)
        return root
    }

    @MainActor
    static func makeSun() -> Entity {
        var sun = DirectionalLightComponent()
        sun.intensity = 6800
        sun.color = .init(red: 1.0, green: 0.95, blue: 0.86, alpha: 1)

        let entity = Entity()
        entity.components.set(sun)
        #if os(iOS)
        // cień to osobny komponent (macOS SDK go nie ma)
        // Zasięg 60 m kończył się na trawniku — drzewa i willa rzucały cień
        // tylko w promieniu kilkudziesięciu metrów, dalej scena była „płaska".
        entity.components.set(DirectionalLightComponent.Shadow(maximumDistance: 45, depthBias: 0.5))
        #endif
        // Słońce z góry-lewej-przodu: cień pada w prawo i do tyłu, jak na
        // zdjęciach architektonicznych (nie „pod światło").
        let yaw = simd_quatf(angle: .pi * 0.30, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: -.pi * 0.30, axis: [1, 0, 0])
        entity.orientation = pitch * yaw
        return entity
    }

    /// Światło wypełniające: chłodne, bez cienia, tylko rozjaśnia mroki.
    @MainActor
    static func makeFill() -> Entity {
        var fill = DirectionalLightComponent()
        fill.intensity = 750
        fill.color = .init(red: 0.72, green: 0.80, blue: 0.92, alpha: 1)
        let entity = Entity()
        entity.components.set(fill)
        entity.orientation = simd_quatf(angle: .pi * 0.75, axis: [1, 0, 0])
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
