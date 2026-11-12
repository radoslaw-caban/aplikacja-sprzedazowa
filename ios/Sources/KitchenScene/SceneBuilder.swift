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
                // wszystkie widoczne powierzchnie szafki dostają teksturę
                // (front, boki, góra/dół); domyślnie dąb naturalny
                let finish = c.texture ?? CabinetFinishes.defaultFinish.fileName
                let textured: [Box.Role] = [.front, .drawerFront, .side, .top, .bottom]
                let texture = textured.contains(b.role) ? finish : nil
                boxes.append(Box(
                    id: b.id,
                    role: b.role,
                    cabinetID: b.cabinetID,
                    size: b.size,
                    position: SIMD3(b.position.x + c.x, b.position.y, b.position.z + c.z),
                    color: b.color,
                    texture: texture,
                    rotationY: b.rotationY,
                    preview: c.preview == true
                ))
            }
        }
        let worktops = Runs.worktops(runs)
        boxes += worktops
        boxes += Runs.plinths(runs)

        for b in boxes {
            root.addChild(entity(for: b))
        }
        // okucia i akcesoria (modele GLB: zawiasy, prowadnice, uchwyty)
        #if DEBUG
        let skipHardware = UserDefaults.standard.bool(forKey: "demoNoHardware")
        #else
        let skipHardware = false
        #endif
        if !skipHardware, let hardware = hardwareEntity(cabinets: cabinets) {
            root.addChild(hardware)
        }
        if !skipHardware, let accessories = accessoryEntity(cabinets: cabinets) {
            root.addChild(accessories)
        }

        // magiczne gwiazdki nad podglądem strefy (cień szafek)
        root.addChild(Sparkles.entity(cabinets: cabinets))

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

    /// Kosze, drążki, organizery i LED — proste bryły w układzie szafki.
    @MainActor
    private static func accessoryEntity(cabinets: [Cabinet]) -> Entity? {
        let root = Entity()
        root.name = "accessories"
        var added = false

        for c in cabinets where c.preview != true {
            guard let accessories = c.accessories, !accessories.isEmpty else { continue }
            let group = Entity()
            group.position = [meters(c.x), 0, meters(c.z)]
            group.orientation = simd_quatf(angle: Float(c.rotation * .pi / 180), axis: [0, 1, 0])
            let baseY = c.type == .base ? c.plinth : c.mountHeight

            func material(_ hex: String, metallic: Double = 0, alpha: Double = 1) -> PhysicallyBasedMaterial {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: color(hex))
                m.metallic = .init(floatLiteral: Float(metallic))
                m.roughness = .init(floatLiteral: 0.45)
                if alpha < 1 { m.blending = .transparent(opacity: .init(floatLiteral: Float(alpha))) }
                return m
            }

            func box(_ w: Double, _ h: Double, _ d: Double, _ color: String,
                     _ x: Double, _ y: Double, _ z: Double, metallic: Double = 0,
                     alpha: Double = 1, name: String) {
                let e = ModelEntity(mesh: .generateBox(width: meters(w), height: meters(h),
                                                       depth: meters(d), cornerRadius: 0.004),
                                    materials: [material(color, metallic: metallic, alpha: alpha)])
                e.position = [meters(x), meters(baseY + y), meters(z)]
                e.name = name
                group.addChild(e)
                added = true
            }

            func cylinder(_ radius: Double, _ height: Double, _ color: String,
                          _ x: Double, _ y: Double, _ z: Double, name: String) {
                let e = ModelEntity(mesh: .generateCylinder(height: meters(height), radius: meters(radius)),
                                    materials: [material(color, metallic: 0.8)])
                e.position = [meters(x), meters(baseY + y), meters(z)]
                e.name = name
                group.addChild(e)
                added = true
            }

            for a in accessories {
                let w = max(200, c.width - 100)
                let d = max(160, c.depth - 100)
                switch a.kind {
                case .basket:
                    box(w, 180, d, "#3b3f43", 0, a.y + 90, 0, name: "acc-basket")
                    for x in stride(from: -w / 2, through: w / 2, by: 80) {
                        box(3, 190, d, "#8d9499", x, a.y + 95, 0, name: "acc-basket-bar")
                    }
                case .rail:
                    let e = ModelEntity(mesh: .generateCylinder(height: meters(w), radius: 0.012),
                                        materials: [material("#c8ccd0", metallic: 0.9)])
                    e.position = [0, meters(baseY + a.y), 0]
                    e.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                    e.name = "acc-rail"
                    group.addChild(e)
                    added = true
                case .cutleryTray:
                    box(w, 45, d, "#b9b4a8", 0, a.y + 22, 0, name: "acc-cutlery")
                    for x in stride(from: -w / 3, through: w / 3, by: w / 3) {
                        box(4, 55, d, "#8f8a7e", x, a.y + 28, 0, name: "acc-cutlery-div")
                    }
                case .wasteBin:
                    cylinder(160, 380, "#6f7478", 0, a.y + 190, 0, name: "acc-bin")
                case .organizer:
                    box(w, 80, d, "#a9a49a", 0, a.y + 40, 0, name: "acc-organizer")
                    for x in [-w / 4, 0, w / 4] {
                        box(4, 90, d, "#7f7a70", x, a.y + 45, 0, name: "acc-organizer-div")
                    }
                case .glassShelf:
                    box(w, 10, d, "#9fc3d0", 0, a.y, 0, alpha: 0.45, name: "acc-glass")
                case .led:
                    box(w * 0.9, 8, 12, "#fff4d0", 0, min(a.y, c.bodyHeight - 20), c.depth / 2 - 40,
                        name: "acc-led")
                }
            }

            if !group.children.isEmpty { root.addChild(group) }
        }
        return added ? root : nil
    }

    /// Zawiasy, prowadnice i uchwyty jako modele GLB w układzie szafki.
    @MainActor
    private static func hardwareEntity(cabinets: [Cabinet]) -> Entity? {
        let root = Entity()
        root.name = "hardware"
        var added = false

        for c in cabinets where c.preview != true {
            let group = Entity()
            group.position = [meters(c.x), 0, meters(c.z)]
            group.orientation = simd_quatf(angle: Float(c.rotation * .pi / 180), axis: [0, 1, 0])
            let baseY = c.type == .base ? c.plinth : c.mountHeight
            let bodyH = c.type == .base ? max(0, c.height - c.plinth) : c.height
            let hasDrawers = c.elements.contains { $0.kind == .drawer }

            // zawiasy na skrzydłach (2 na skrzydło, po obu stronach przy 2 drzwiach)
            if !hasDrawers, c.type != .panel, c.hinge != .none {
                let sides: [Double] = (c.doorCount ?? 1) == 2 ? [-1, 1] : [1]
                for side in sides {
                    for frac in [0.22, 0.78] {
                        if let hinge = ModelLibrary.entity(named: "hardware_hinge_35", targetSize: 0.07) {
                            hinge.position = [meters(side * (c.width / 2 - 70)),
                                              meters(baseY + bodyH * frac), meters(c.depth / 2)]
                            group.addChild(hinge)
                            added = true
                        }
                    }
                }
            }

            // uchwyty: po jednym na szufladę, inaczej jeden na skrzydło
            let handleZ = c.depth / 2 + 24
            if hasDrawers {
                for drawer in c.elements where drawer.kind == .drawer {
                    if let handle = ModelLibrary.entity(named: "hardware_handle_160", targetSize: 0.16) {
                        handle.position = [0, meters(baseY + drawer.y + drawer.height / 2), meters(handleZ)]
                        group.addChild(handle)
                        added = true
                    }
                }
            } else if c.type != .panel,
                      let handle = ModelLibrary.entity(named: "hardware_handle_160", targetSize: 0.16) {
                handle.position = [0, meters(baseY + bodyH * 0.5), meters(handleZ)]
                group.addChild(handle)
                added = true
            }

            // prowadnice szuflad po obu stronach
            for drawer in c.elements where drawer.kind == .drawer {
                for side in [-1.0, 1.0] {
                    let length = Float(max(250, c.depth * 0.8) / 1000)
                    if let slide = ModelLibrary.entity(named: "hardware_slide_250", targetLength: length, axis: 0) {
                        slide.position = [meters(side * (c.width / 2 - 25)),
                                          meters(baseY + drawer.y + drawer.height / 2),
                                          0]
                        group.addChild(slide)
                        added = true
                    }
                }
            }

            // wkłady szuflad: mata / stojak na talerze / segregator / organizer…
            // Rysujemy też samą „wannę" szuflady, żeby wkład nie wisiał w powietrzu.
            for drawer in c.elements where drawer.kind == .drawer && drawer.insert != nil {
                guard let spec = DrawerInsertCatalog.insert(id: drawer.insert) else { continue }
                let innerW = DrawerInsertCatalog.innerWidth(cabinetWidth: c.width)
                let innerD = DrawerInsertCatalog.innerDepth(cabinetDepth: c.depth)
                let innerH = DrawerInsertCatalog.innerHeight(drawerFrontHeight: drawer.height)

                if let insertEntity = DrawerInsertBuilder.entity(insert: spec, innerWidth: innerW,
                                                                innerDepth: innerD, available: innerH) {
                    insertEntity.position = [0, meters(baseY + drawer.y + 12), 0]
                    group.addChild(insertEntity)
                    added = true
                }
            }

            if !group.children.isEmpty { root.addChild(group) }
        }
        return added ? root : nil
    }

    /// Tekstura użytkownika z biblioteki albo wbudowane wykończenie z bundle.
    private static func textureURL(named name: String) -> URL? {
        if let url = TextureStore.shared.url(for: name) { return url }
        for ext in ["jpg", "png"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext,
                                         subdirectory: "Textures/Finishes") { return url }
            if let url = Bundle.main.url(forResource: name, withExtension: ext,
                                         subdirectory: "Finishes") { return url }
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
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
        if b.preview {
            // CIEŃ SZAFEK: półprzezroczysty błękit, bez tekstur i metaliczności.
            var ghost = PhysicallyBasedMaterial()
            ghost.baseColor = .init(tint: color("#4f7f9e"))
            ghost.roughness = .init(floatLiteral: 0.9)
            ghost.metallic = .init(floatLiteral: 0)
            ghost.blending = .transparent(opacity: .init(floatLiteral: 0.28))
            let ghostEntity = ModelEntity(mesh: mesh, materials: [ghost])
            ghostEntity.position = [meters(b.position.x), meters(b.position.y), meters(b.position.z)]
            ghostEntity.name = b.id
            if b.rotationY != 0 {
                ghostEntity.orientation = simd_quatf(angle: Float(b.rotationY * .pi / 180), axis: [0, 1, 0])
            }
            return ghostEntity
        }
        var material = PhysicallyBasedMaterial()
        // front może mieć teksturę z biblioteki (nazwa pliku w `Box.texture`)
        if let textureName = b.texture,
           let url = textureURL(named: textureName),
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
    public static func buildRoom(_ room: Room, walls: Bool = true, scanPlan: ScanPlan? = nil,
                                 scanCloud: Bool = false, includeShell: Bool = true) -> Entity {
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

        // skorupa willi: elewacja, płaskie dachy, przeszklenia, taras, basen.
        // W widoku WNĘTRZA jej nie dodajemy — zamknięte pudło zasłaniało
        // zabudowę od środka i „prześwitywało" przez ściany.
        if includeShell {
            root.addChild(VillaBuilder.shell(room: room))
        }

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
