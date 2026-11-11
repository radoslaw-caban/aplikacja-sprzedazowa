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

        // MARK: fundament
        //
        // Dom musi stać NA czymś. Bez ławy i cokołu budynek „pływa" na trawie,
        // a w rzeczywistości każdy dom ma betonowy fundament wystający ponad
        // teren o 20–40 cm. Tu: ława schowana w gruncie + widoczny cokół.
        var concreteMaterial = PhysicallyBasedMaterial()
        if let tex = EnvironmentArt.concrete() {
            concreteMaterial.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            concreteMaterial.baseColor = .init(tint: color("#8d8a84"))
        }
        concreteMaterial.roughness = .init(floatLiteral: 0.9)
        concreteMaterial.metallic = .init(floatLiteral: 0)

        let houseW = meters(room.width)
        let houseD = meters(room.depth)
        // Willa ma DWIE kondygnacje: dane pokoju opisują parter (tu stoi kuchnia),
        // a bryła domu dostaje piętro tej samej wielkości. Bez tego balkon
        // wypadałby na wysokości 1,3 m — czyli w drzwiach.
        let storeyHeight = Float(room.height / 1000)   // parter = wysokość z danych pomieszczenia
        let houseHeight = storeyHeight * 2

        // ława: szersza niż ściany, schowana 60 cm w gruncie
        if let mesh = MeshFactory.texturedBox(width: houseW + 0.9, height: 0.95, depth: houseD + 0.9, tile: 1.2) {
            let footing = ModelEntity(mesh: mesh, materials: [concreteMaterial])
            footing.position = [0, -0.42, 0]
            footing.name = "foundation-footing"
            root.addChild(footing)
        }

        // cokół: cztery pasy po zewnętrznej stronie ścian (0,5 m pod terenem,
        // 0,35 m nad nim) — wnętrze zostaje czyste, a elewacja ma podstawę
        let skirtThickness: Float = 0.34
        let skirtHeight: Float = 0.95
        let skirtTop: Float = 0.40
        for side in [Float(-1), Float(1)] {
            if let mesh = MeshFactory.texturedBox(width: houseW + skirtThickness * 2, height: skirtHeight,
                                                  depth: skirtThickness, tile: 1.2) {
                let skirt = ModelEntity(mesh: mesh, materials: [concreteMaterial])
                skirt.position = [0, skirtTop - skirtHeight / 2, side * (houseD / 2 + skirtThickness / 2)]
                skirt.name = "foundation-skirt-z"
                root.addChild(skirt)
            }
            if let mesh = MeshFactory.texturedBox(width: skirtThickness, height: skirtHeight,
                                                  depth: houseD + skirtThickness * 2, tile: 1.2) {
                let skirt = ModelEntity(mesh: mesh, materials: [concreteMaterial])
                skirt.position = [side * (houseW / 2 + skirtThickness / 2), skirtTop - skirtHeight / 2, 0]
                skirt.name = "foundation-skirt-x"
                root.addChild(skirt)
            }
        }

        // schody wejściowe (3 stopnie) — inaczej drzwi są 32 cm nad trawnikiem
        var stepMaterial = PhysicallyBasedMaterial()
        stepMaterial.baseColor = .init(tint: color("#a8a49c"))
        stepMaterial.roughness = .init(floatLiteral: 0.85)
        for step in 0..<3 {
            let height = skirtTop * Float(3 - step) / 3
            let stair = ModelEntity(
                mesh: .generateBox(width: 2.6, height: max(0.06, height), depth: 0.36, cornerRadius: 0.01),
                materials: [stepMaterial]
            )
            stair.position = [0, max(0.03, height / 2), houseD / 2 + 0.18 + Float(step) * 0.34]
            stair.name = "entrance-step-\(step)"
            root.addChild(stair)
        }

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

        // ściany piętra — ta sama elewacja, przesunięte o wysokość parteru
        for i in 0..<(walls ? 4 : 0) {
            let size = room.wallSize(i)
            let pos = room.wallPosition(i)
            let upper = ModelEntity(
                mesh: MeshFactory.texturedBox(
                    width: meters(size.x), height: storeyHeight, depth: meters(size.z), tile: 2.5
                ) ?? .generateBox(width: meters(size.x), height: storeyHeight, depth: meters(size.z), cornerRadius: 0),
                materials: [wallMaterial]
            )
            upper.position = [meters(pos.x), storeyHeight + storeyHeight / 2, meters(pos.z)]
            upper.name = "wall-upper-\(i)"
            root.addChild(upper)
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
            gableRoof.position = [0, houseHeight, 0]
            gableRoof.name = "roof"
            root.addChild(gableRoof)

            // szczyty pod dachem (trójkąty) — inaczej widać dziurę nad ścianą
            if let ends = MeshFactory.gableEnds(width: meters(room.width) + 0.02, rise: rise, depth: meters(room.depth) + 0.02) {
                let gables = ModelEntity(mesh: ends, materials: [wallMaterial])
                gables.position = [0, houseHeight, 0]
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
            ridge.position = [0, houseHeight + rise + 0.04, 0]
            ridge.name = "ridge"
            root.addChild(ridge)

            for sign in [Float(1), Float(-1)] {
                let gutter = ModelEntity(
                    mesh: .generateBox(width: roofWidth + 0.7, height: 0.12, depth: 0.14, cornerRadius: 0.02),
                    materials: [trim]
                )
                gutter.position = [0, houseHeight - 0.04, sign * (roofDepth / 2 + 0.42)]
                gutter.name = "gutter"
                root.addChild(gutter)
            }
        } else {
            let roof = ModelEntity(
                mesh: MeshFactory.texturedBox(width: roofWidth, height: 0.24, depth: roofDepth, tile: 1.6)
                    ?? .generateBox(width: roofWidth, height: 0.24, depth: roofDepth, cornerRadius: 0.02),
                materials: [roofMaterial]
            )
            roof.position = [0, houseHeight + 0.11, 0]
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

        // MARK: willa — piętro, balkon, portyk, komin
        //
        // Te trzy elementy decydują, czy bryła czyta się jako willa, czy jako
        // pudełko z dachem: gzyms dzielący kondygnacje, balkon nad wejściem
        // na kolumnach i komin wystający z połaci.
        // gzyms dokładnie na styku kondygnacji
        let storeyY = storeyHeight

        if let mesh = MeshFactory.texturedBox(width: houseW + 0.30, height: 0.16, depth: houseD + 0.30, tile: 1.5) {
            let cornice = ModelEntity(mesh: mesh, materials: [wallMaterial])
            cornice.position = [0, storeyY, 0]
            cornice.name = "cornice"
            root.addChild(cornice)
        }

        // rząd okien piętra — na wysokości 1,5 m nad stropem parteru
        let upperY = storeyHeight + 1.5
        for (index, xOffset) in [Float(-0.62), 0, 0.62].enumerated() {
            let frameEntity = ModelEntity(
                mesh: .generateBox(width: 1.24, height: 1.06, depth: 0.08, cornerRadius: 0.01),
                materials: [frame]
            )
            frameEntity.position = [xOffset * houseW * 0.55, upperY, facadeZ + 0.05]
            frameEntity.name = "window-upper-\(index)"
            root.addChild(frameEntity)

            let pane = ModelEntity(
                mesh: .generateBox(width: 1.10, height: 0.92, depth: 0.06, cornerRadius: 0.005),
                materials: [glass]
            )
            pane.position = [frameEntity.position.x, upperY, facadeZ + 0.07]
            root.addChild(pane)

            let sill = ModelEntity(
                mesh: .generateBox(width: 1.42, height: 0.06, depth: 0.18, cornerRadius: 0.008),
                materials: [frame]
            )
            sill.position = [frameEntity.position.x, upperY - 0.56, facadeZ + 0.09]
            root.addChild(sill)
        }

        // balkon nad wejściem
        let balconyWidth: Float = min(4.6, houseW * 0.55)
        let balconyDepth: Float = 1.35
        let balconyZ = houseD / 2 + balconyDepth / 2
        let balcony = ModelEntity(
            mesh: .generateBox(width: balconyWidth, height: 0.18, depth: balconyDepth, cornerRadius: 0.03),
            materials: [SimpleMaterial(color: color("#d8d2c6"), isMetallic: false)]
        )
        balcony.position = [0, storeyY, balconyZ]
        balcony.name = "balcony"
        root.addChild(balcony)

        // balustrada: szkło + pochwyt
        var railingGlass = PhysicallyBasedMaterial()
        railingGlass.baseColor = .init(tint: PlatformColor(red: 0.55, green: 0.62, blue: 0.66, alpha: 0.55))
        railingGlass.roughness = .init(floatLiteral: 0.12)
        railingGlass.metallic = .init(floatLiteral: 0.1)
        railingGlass.blending = .transparent(opacity: .init(floatLiteral: 0.30))

        let panel = ModelEntity(
            mesh: .generateBox(width: balconyWidth - 0.1, height: 0.95, depth: 0.04, cornerRadius: 0),
            materials: [railingGlass]
        )
        panel.position = [0, storeyY + 0.55, balconyZ + balconyDepth / 2 - 0.05]
        panel.name = "balcony-glass"
        root.addChild(panel)

        var railMaterial = PhysicallyBasedMaterial()
        railMaterial.baseColor = .init(tint: color("#3c3f42"))
        railMaterial.roughness = .init(floatLiteral: 0.4)
        railMaterial.metallic = .init(floatLiteral: 0.6)
        let handrail = ModelEntity(
            mesh: .generateBox(width: balconyWidth, height: 0.06, depth: 0.10, cornerRadius: 0.01),
            materials: [railMaterial]
        )
        handrail.position = [0, storeyY + 1.06, balconyZ + balconyDepth / 2 - 0.05]
        root.addChild(handrail)

        // portyk: dwie kolumny podtrzymujące balkon
        for side in [Float(-1), Float(1)] {
            let column = ModelEntity(
                mesh: .generateCylinder(height: storeyY, radius: 0.18),
                materials: [wallMaterial]
            )
            column.position = [side * (balconyWidth / 2 - 0.35), storeyY / 2, houseD / 2 + balconyDepth - 0.35]
            column.name = "portico-column"
            root.addChild(column)

            let base = ModelEntity(
                mesh: .generateBox(width: 0.46, height: 0.12, depth: 0.46, cornerRadius: 0.01),
                materials: [stepMaterial]
            )
            base.position = [column.position.x, 0.06, column.position.z]
            root.addChild(base)
        }

        // komin z cegły — musi WYSTAWAĆ nad kalenicę, inaczej chowa się w połaci
        var brickMaterial = PhysicallyBasedMaterial()
        brickMaterial.baseColor = .init(tint: color("#8d5a44"))
        brickMaterial.roughness = .init(floatLiteral: 0.9)
        let chimneyHeight: Float = 2.6
        let chimney = ModelEntity(
            mesh: MeshFactory.texturedBox(width: 0.86, height: chimneyHeight, depth: 0.86, tile: 0.5)
                ?? .generateBox(width: 0.86, height: chimneyHeight, depth: 0.86, cornerRadius: 0.01),
            materials: [brickMaterial]
        )
        // na kalenicy (z = 0), przesunięty w bok — typowe miejsce komina w willi
        chimney.position = [-houseW * 0.26, houseHeight + rise + chimneyHeight / 2 - 0.9, 0]
        chimney.name = "chimney"
        root.addChild(chimney)

        let cap = ModelEntity(
            mesh: .generateBox(width: 1.02, height: 0.12, depth: 1.02, cornerRadius: 0.01),
            materials: [stepMaterial]
        )
        cap.position = [chimney.position.x, chimney.position.y + chimneyHeight / 2 + 0.06, chimney.position.z]
        root.addChild(cap)

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
