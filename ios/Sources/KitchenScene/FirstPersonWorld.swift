import Foundation
import RealityKit
import KitchenCore
import simd

#if os(iOS)
import UIKit
typealias WorldColor = UIColor
#else
import AppKit
typealias WorldColor = NSColor
#endif

/// Świat do chodzenia po posesji: trawa, podjazd, dom z otwieranymi drzwiami,
/// pies i ogrodzenie. Wszystko w jednej encji-korzeniu, żeby widok FPS mógł
/// trzymać referencje do drzwi i psa.
/// Ściany wewnętrzne pomieszczenia, w którym stoją szafki (tryb edycji FPS).
public enum RoomSide: String, Sendable { case north, south, east, west }

/// Co wskazał magiczny ołówek w środku ekranu.
public enum FPSPick: Sendable {
    case cabinet(UUID)
    case wall(RoomSide)
    case none
}

@MainActor
public final class FirstPersonWorld {

    public let root = Entity()
    /// pomieszczenie, w którym stoją szafki (mm)
    public private(set) var room: Room
    private var roomWalls: [RoomSide: [ModelEntity]] = [:]
    private var cabinetsByID: [UUID: Cabinet] = [:]
    /// fronty i szuflady szafek — do animacji otwierania
    private var cabinetFronts: [UUID: [(entity: ModelEntity, rest: Transform)]] = [:]
    private var openCabinets: Set<UUID> = []
    private let accessoryRoot = Entity()
    private var wallColorHex: String
    /// zawias drzwi — obrót o kąt otwiera je
    public private(set) var doorPivot: Entity?
    /// pies (korzeń) i jego części do animacji
    public private(set) var dog: Entity?
    private var dogLegs: [Entity] = []
    private var dogTail: Entity?
    public private(set) var isDoorOpen = false

    /// Promień, w którym gracz może się poruszać (podjazd + trawnik przed domem).
    public let playRadius: Float = 16
    /// Obrys domu (do kolizji): połowa szerokości i głębokości.
    public private(set) var houseHalf = SIMD2<Float>(6.4, 4.8)
    /// Środek otworu drzwiowego na elewacji +Z.
    public private(set) var doorPoint = SIMD3<Float>(0, 0, 4.8)
    private let doorWidth: Float = 1.05

    public init(room: Room, cabinets: [Cabinet] = [], wallColor: String? = nil) {
        self.room = room
        self.wallColorHex = wallColor ?? "#e8e2d8"
        houseHalf = SIMD2(Float(room.width / 2000), Float(room.depth / 2000))
        doorPoint = SIMD3(0, 0, houseHalf.y)
        buildGround()
        buildHouse(room: room)
        buildDoor()
        buildInterior()
        buildCabinets(cabinets)
        NSLog("[fps] szafek w scenie: %d", cabinets.count)
        accessoryRoot.name = "fps-accessories"
        root.addChild(accessoryRoot)
        buildDog()
        buildFence()
    }

    // MARK: - podłoże

    private func buildGround() {
        var grass = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("grass_diff") {
            grass.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            grass.baseColor = .init(tint: WorldColor(red: 0.32, green: 0.40, blue: 0.22, alpha: 1))
        }
        grass.roughness = .init(floatLiteral: 0.95)

        if let mesh = MeshFactory.ground(size: 80, tile: 4) {
            let plane = ModelEntity(mesh: mesh, materials: [grass])
            plane.name = "fps-ground"
            root.addChild(plane)
        }

        // podjazd: pas kostki od drogi do drzwi
        var paving = PhysicallyBasedMaterial()
        paving.baseColor = .init(tint: WorldColor(red: 0.44, green: 0.43, blue: 0.42, alpha: 1))
        paving.roughness = .init(floatLiteral: 0.9)
        paving.roughness = .init(floatLiteral: 0.8)

        let drivewayLength = houseHalf.y + 14
        if let mesh = MeshFactory.texturedBox(width: 3.6, height: 0.08, depth: drivewayLength, tile: 1.2) {
            let drive = ModelEntity(mesh: mesh, materials: [paving])
            drive.position = [0, 0.04, houseHalf.y + drivewayLength / 2 - 0.4]
            drive.name = "fps-driveway"
            root.addChild(drive)
        }
    }

    // MARK: - dom

    /// Dom do widoku FPS budowany od zera.
    ///
    /// Świadomie NIE używamy `VillaBuilder` (ten ma wnętrze, przeszklenia i taras —
    /// z podjazdu byłoby widać jego kulisy). Tu liczy się czytelna elewacja
    /// z otworem drzwiowym, oknami i dachem, dopasowana do wymiarów pomieszczenia.
    private func buildHouse(room: Room) {
        // Dom w widoku FPS nie może być wielkości samej kuchni — bierzemy
        // minimum 9 × 8 m, a właściwe pomieszczenie mieści się w środku.
        let w = max(9.0, Float(room.width / 1000))
        let d = max(8.0, Float(room.depth / 1000))
        let h = max(2.7, Float(room.height / 1000))
        houseHalf = SIMD2(w / 2, d / 2)

        var wall = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("stucco_diff") {
            wall.baseColor = .init(tint: WorldColor(white: 0.97, alpha: 1), texture: .init(texture))
        } else {
            wall.baseColor = .init(tint: WorldColor(white: 0.94, alpha: 1))
        }
        wall.roughness = .init(floatLiteral: 0.85)

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: WorldColor(red: 0.20, green: 0.28, blue: 0.36, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.08)
        glass.metallic = .init(floatLiteral: 0.3)

        var roofMaterial = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("roof_diff") {
            roofMaterial.baseColor = .init(tint: WorldColor(white: 0.8, alpha: 1), texture: .init(texture))
        } else {
            roofMaterial.baseColor = .init(tint: WorldColor(white: 0.35, alpha: 1))
        }
        roofMaterial.roughness = .init(floatLiteral: 0.7)

        let thickness: Float = 0.24

        // elewacja frontowa: dwa segmenty, między nimi otwór drzwiowy
        let doorGap: Float = doorWidth + 0.12
        let sideWidth = max(0.4, (w - doorGap) / 2)
        for sign in [Float(-1), Float(1)] {
            if let mesh = MeshFactory.texturedBox(width: sideWidth, height: h, depth: thickness, tile: 2.5) {
                let panel = ModelEntity(mesh: mesh, materials: [wall])
                panel.position = [sign * (doorGap / 2 + sideWidth / 2), h / 2, d / 2]
                root.addChild(panel)
            }
        }
        // nadproże nad drzwiami
        let lintelHeight = h - 2.25
        if lintelHeight > 0.1, let mesh = MeshFactory.texturedBox(width: doorGap, height: lintelHeight, depth: thickness, tile: 1) {
            let lintel = ModelEntity(mesh: mesh, materials: [wall])
            lintel.position = [0, 2.25 + lintelHeight / 2, d / 2]
            root.addChild(lintel)
        }

        // ściany boczne i tylna
        if let mesh = MeshFactory.texturedBox(width: thickness, height: h, depth: d, tile: 2.5) {
            for sign in [Float(-1), Float(1)] {
                let side = ModelEntity(mesh: mesh, materials: [wall])
                side.position = [sign * (w / 2 + thickness / 2), h / 2, 0]
                root.addChild(side)
            }
        }
        if let mesh = MeshFactory.texturedBox(width: w + thickness * 2, height: h, depth: thickness, tile: 2.5) {
            let back = ModelEntity(mesh: mesh, materials: [wall])
            back.position = [0, h / 2, -d / 2 - thickness / 2]
            root.addChild(back)
        }

        // stopień przed drzwiami
        if let mesh = MeshFactory.texturedBox(width: 1.6, height: 0.14, depth: 0.6, tile: 1) {
            let step = ModelEntity(mesh: mesh, materials: [wall])
            step.position = [0, 0.07, d / 2 + 0.3]
            step.name = "fps-door-step"
            root.addChild(step)
        }

        // dach z okapem
        if let mesh = MeshFactory.texturedBox(width: w + 1.2, height: 0.26, depth: d + 1.2, tile: 1.6) {
            let roof = ModelEntity(mesh: mesh, materials: [roofMaterial])
            roof.position = [0, h + 0.13, 0]
            root.addChild(roof)
        }

        // okna na elewacji
        for x in [-w * 0.34, w * 0.34] {
            if let mesh = MeshFactory.texturedBox(width: 1.5, height: 1.2, depth: 0.08, tile: 1) {
                let window = ModelEntity(mesh: mesh, materials: [glass])
                window.position = [x, 1.55, d / 2 + 0.16]
                root.addChild(window)
            }
        }

        // podłoga wewnątrz (żeby przez drzwi nie było widać „dziury")
        if let mesh = MeshFactory.ground(size: max(w, d) + 0.2, tile: 2) {
            let floor = ModelEntity(mesh: mesh, materials: [wall])
            floor.position = [0, 0.01, 0]
            root.addChild(floor)
        }
    }

    /// Drzwi wejściowe na zawiasie po lewej stronie otworu.
    private func buildDoor() {
        var panel = PhysicallyBasedMaterial()
        panel.baseColor = .init(tint: WorldColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1))
        panel.roughness = .init(floatLiteral: 0.45)

        var frame = PhysicallyBasedMaterial()
        frame.baseColor = .init(tint: WorldColor(white: 0.12, alpha: 1))
        frame.roughness = .init(floatLiteral: 0.35)
        frame.metallic = .init(floatLiteral: 0.4)

        let height: Float = 2.15
        let width = doorWidth

        // ościeżnica
        if let mesh = MeshFactory.texturedBox(width: width + 0.14, height: height + 0.08, depth: 0.16, tile: 1) {
            let casing = ModelEntity(mesh: mesh, materials: [frame])
            casing.position = [doorPoint.x, height / 2, doorPoint.z + 0.02]
            casing.name = "door-frame"
            root.addChild(casing)
        }

        // zawias: pivot w krawędzi otworu, skrzydło jako dziecko przesunięte w bok
        let pivot = Entity()
        pivot.name = "door-hinge"
        pivot.position = [doorPoint.x - width / 2, 0, doorPoint.z + 0.04]
        root.addChild(pivot)
        doorPivot = pivot

        if let mesh = MeshFactory.texturedBox(width: width, height: height, depth: 0.06, tile: 1) {
            let leaf = ModelEntity(mesh: mesh, materials: [panel])
            leaf.position = [width / 2, height / 2, 0]
            leaf.name = "door-leaf"
            pivot.addChild(leaf)

            // klamka
            var brass = PhysicallyBasedMaterial()
            brass.baseColor = .init(tint: WorldColor(red: 0.82, green: 0.68, blue: 0.36, alpha: 1))
            brass.metallic = .init(floatLiteral: 0.9)
            brass.roughness = .init(floatLiteral: 0.25)
            let handle = ModelEntity(
                mesh: .generateCylinder(height: 0.16, radius: 0.022),
                materials: [brass]
            )
            handle.position = [width - 0.12, 1.05, 0.05]
            handle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            handle.name = "door-handle"
            pivot.addChild(handle)
        }
    }

    /// Otwarcie/zamknięcie skrzydła animacją.
    public func setDoor(open: Bool) {
        guard let pivot = doorPivot, open != isDoorOpen else { return }
        isDoorOpen = open
        let target = simd_quatf(angle: open ? -1.75 : 0, axis: [0, 1, 0])
        var transform = pivot.transform
        transform.rotation = target
        pivot.move(to: transform, relativeTo: pivot.parent, duration: 0.9, timingFunction: .easeInOut)
    }

    /// Czy gracz może przejść przez otwór (drzwi otwarte i jest w osi).
    public func canPassThrough(at position: SIMD3<Float>) -> Bool {
        guard isDoorOpen else { return false }
        let nearDoor = abs(position.x - doorPoint.x) < doorWidth * 0.5
        let nearWall = abs(position.z - doorPoint.z) < 0.6
        return nearDoor && nearWall
    }

    // MARK: - pies

    private func buildDog() {
        let dogRoot = Entity()
        dogRoot.name = "dog"
        dogRoot.position = [1.6, 0, houseHalf.y + 7.0]
        root.addChild(dogRoot)

        var fur = PhysicallyBasedMaterial()
        fur.baseColor = .init(tint: WorldColor(red: 0.46, green: 0.31, blue: 0.18, alpha: 1))
        fur.roughness = .init(floatLiteral: 0.8)

        var lightFur = PhysicallyBasedMaterial()
        lightFur.baseColor = .init(tint: WorldColor(red: 0.72, green: 0.60, blue: 0.44, alpha: 1))
        lightFur.roughness = .init(floatLiteral: 0.85)

        // tułów
        let body = ModelEntity(mesh: .generateCylinder(height: 0.62, radius: 0.17), materials: [fur])
        body.position = [0, 0.52, 0]
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        dogRoot.addChild(body)

        // głowa
        let head = ModelEntity(mesh: .generateBox(width: 0.24, height: 0.22, depth: 0.30, cornerRadius: 0.06), materials: [fur])
        head.position = [0, 0.72, 0.42]
        head.name = "dog-head"
        dogRoot.addChild(head)

        // pysk
        let muzzle = ModelEntity(mesh: .generateBox(width: 0.14, height: 0.12, depth: 0.16, cornerRadius: 0.05), materials: [lightFur])
        muzzle.position = [0, 0.66, 0.55]
        dogRoot.addChild(muzzle)

        // uszy
        for sign in [Float(-1), Float(1)] {
            let ear = ModelEntity(mesh: .generateBox(width: 0.07, height: 0.12, depth: 0.04, cornerRadius: 0.02), materials: [fur])
            ear.position = [sign * 0.09, 0.83, 0.40]
            ear.orientation = simd_quatf(angle: sign * 0.2, axis: [0, 0, 1])
            dogRoot.addChild(ear)
        }

        // łapy — animowane w update
        let offsets: [SIMD3<Float>] = [
            [-0.11, 0.22, 0.26], [0.11, 0.22, 0.26],
            [-0.11, 0.22, -0.26], [0.11, 0.22, -0.26],
        ]
        for (index, offset) in offsets.enumerated() {
            let leg = ModelEntity(mesh: .generateCylinder(height: 0.44, radius: 0.045), materials: [fur])
            leg.position = offset
            leg.name = "dog-leg-\(index)"
            dogRoot.addChild(leg)
            dogLegs.append(leg)
        }

        // ogon
        let tail = ModelEntity(mesh: .generateCylinder(height: 0.34, radius: 0.035), materials: [fur])
        tail.position = [0, 0.62, -0.42]
        tail.orientation = simd_quatf(angle: 0.9, axis: [1, 0, 0])
        tail.name = "dog-tail"
        dogRoot.addChild(tail)
        dogTail = tail

        dog = dogRoot
    }

    /// Animacja: nogi, ogon, podskok. `phase` w sekundach.
    public func animateDog(time: Float, running: Bool, excited: Bool) {
        guard let dog else { return }
        let speed: Float = running ? 12 : 3
        let amplitude: Float = running ? 0.42 : 0.12
        for (index, leg) in dogLegs.enumerated() {
            let offset: Float = index % 2 == 0 ? 0 : .pi
            let swing = sin(time * speed + offset) * amplitude
            var transform = leg.transform
            transform.rotation = simd_quatf(angle: swing, axis: [1, 0, 0])
            leg.transform = transform
        }
        if let tail = dogTail {
            let wagSpeed: Float = excited ? 18 : 7
            let wag = sin(time * wagSpeed) * (excited ? 0.55 : 0.3)
            var transform = tail.transform
            transform.rotation = simd_quatf(angle: 0.9, axis: [1, 0, 0]) * simd_quatf(angle: wag, axis: [0, 1, 0])
            tail.transform = transform
        }
        if running {
            var transform = dog.transform
            transform.translation.y = abs(sin(time * 12)) * 0.05
            dog.transform = transform
        }
    }

    /// Pies idzie do miejsca 3 m przed graczem (lekko z boku) i tam czeka.
    /// Zwraca `true`, gdy już stoi (wtedy animacja przechodzi w „czekanie").
    @discardableResult
    public func updateDog(player: SIMD3<Float>, cameraYaw: Float, deltaTime: Float) -> Bool {
        guard let dog else { return true }

        // „przed graczem" = w stronę, w którą patrzy kamera (−Z obrócone o yaw)
        let forward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        let standAt = player + forward * 5.2 + right * 1.7

        var position = dog.position
        let toTarget = SIMD3(standAt.x - position.x, 0, standAt.z - position.z)
        let distance = simd_length(toTarget)

        if distance > 0.25 {
            let direction = toTarget / max(distance, 0.001)
            let speed: Float = min(3.2, 0.8 + distance * 0.8)
            position += direction * speed * deltaTime
            dog.position = position
            dog.orientation = simd_quatf(angle: atan2(direction.x, direction.z), axis: [0, 1, 0])
            return false
        }

        // stoi i patrzy na gracza
        let look = SIMD3(player.x - position.x, 0, player.z - position.z)
        dog.orientation = simd_quatf(angle: atan2(look.x, look.z), axis: [0, 1, 0])
        return true
    }

    // MARK: - ogrodzenie

    private func buildFence() {
        var wood = PhysicallyBasedMaterial()
        wood.baseColor = .init(tint: WorldColor(red: 0.44, green: 0.34, blue: 0.24, alpha: 1))
        wood.roughness = .init(floatLiteral: 0.8)

        let radius: Float = 18
        let posts = 56
        for i in 0..<posts {
            let angle = Float(i) / Float(posts) * .pi * 2
            let position = SIMD3<Float>(cos(angle) * radius, 0.55, sin(angle) * radius)
            // brama: przerwa w miejscu podjazdu
            if abs(position.x) < 2.2, position.z > 0 { continue }
            let post = ModelEntity(mesh: .generateBox(width: 0.1, height: 1.1, depth: 0.1), materials: [wood])
            post.position = position
            post.name = "fence-\(i)"
            root.addChild(post)

            let nextAngle = Float(i + 1) / Float(posts) * .pi * 2
            let next = SIMD3<Float>(cos(nextAngle) * radius, 0.75, sin(nextAngle) * radius)
            if abs(next.x) < 2.2, next.z > 0 { continue }
            let rail = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.06, depth: simd_length(next - position)), materials: [wood])
            rail.position = (position + next) / 2 + SIMD3(0, 0.2, 0)
            rail.orientation = simd_quatf(angle: atan2(next.x - position.x, next.z - position.z), axis: [0, 1, 0])
            root.addChild(rail)
        }
    }
    // MARK: - wnętrze i szafki (magiczny ołówek)

    private func roomWallMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Self.color(wallColorHex))
        m.roughness = .init(floatLiteral: 0.9)
        m.metallic = .init(floatLiteral: 0)
        // delikatna emisja: wnętrze czytelne nawet bez lamp (FPS nie ma cieni)
        m.emissiveColor = .init(color: WorldColor(white: 0.55, alpha: 1))
        m.emissiveIntensity = 0.35
        return m
    }

    private static func color(_ hex: String) -> WorldColor {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            return WorldColor(white: 0.9, alpha: 1)
        }
        return WorldColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Podłoga i cztery ściany pomieszczenia (z otworem wejściowym od +Z).
    private func buildInterior() {
        let w = Float(room.width / 1000)
        let d = Float(room.depth / 1000)
        let h = Float(room.height / 1000)
        let thickness: Float = 0.08
        let mat = roomWallMaterial()

        // podłoga z desek (kontrast wobec trawy na zewnątrz)
        var wood = PhysicallyBasedMaterial()
        wood.baseColor = .init(tint: WorldColor(red: 0.62, green: 0.48, blue: 0.34, alpha: 1))
        wood.roughness = .init(floatLiteral: 0.75)
        if let mesh = MeshFactory.texturedBox(width: w, height: 0.02, depth: d, tile: 1.8) {
            let floor = ModelEntity(mesh: mesh, materials: [wood])
            floor.position = [0, 0.02, 0]
            floor.name = "fps-room-floor"
            root.addChild(floor)
        }

        func panel(_ side: RoomSide, size: SIMD3<Float>, pos: SIMD3<Float>) {
            guard let mesh = MeshFactory.texturedBox(width: size.x, height: size.y, depth: size.z, tile: 2.5) else { return }
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.position = pos
            e.name = "room-wall-\(side.rawValue)"
            root.addChild(e)
            roomWalls[side, default: []].append(e)
        }

        // sufit — zasłania połać dachu nad pomieszczeniem
        if let mesh = MeshFactory.texturedBox(width: w, height: 0.02, depth: d, tile: 2.5) {
            let ceil = ModelEntity(mesh: mesh, materials: [mat])
            ceil.position = [0, h, 0]
            ceil.name = "fps-ceiling"
            root.addChild(ceil)
        }

        // północ, wschód, zachód — pełne
        panel(.north, size: [w, h, thickness], pos: [0, h / 2, -d / 2])
        panel(.east, size: [thickness, h, d], pos: [w / 2, h / 2, 0])
        panel(.west, size: [thickness, h, d], pos: [-w / 2, h / 2, 0])

        // południe — wejście 1,1 m na środku + nadproże
        let opening: Float = 1.1
        let segW = max(0.2, (w - opening) / 2)
        panel(.south, size: [segW, h, thickness], pos: [-(opening / 2 + segW / 2), h / 2, d / 2])
        panel(.south, size: [segW, h, thickness], pos: [opening / 2 + segW / 2, h / 2, d / 2])
        if h > 2.1 {
            panel(.south, size: [opening, h - 2.1, thickness], pos: [0, 2.1 + (h - 2.1) / 2, d / 2])
        }

    }

    /// Wstawia zabudowę projektu do wnętrza (te same mm, ten sam układ).
    private func buildCabinets(_ cabinets: [Cabinet]) {
        guard !cabinets.isEmpty else { return }
        cabinetsByID = Dictionary(uniqueKeysWithValues: cabinets.map { ($0.id, $0) })
        let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
        built.root.name = "fps-cabinets"
        root.addChild(built.root)

        for entity in built.root.children {
            let name = entity.name
            guard let cabIDString = name.split(separator: ":").first,
                  let cabID = UUID(uuidString: String(cabIDString)) else { continue }
            let isFront = name.contains(":front") || name.contains(":drawerFront") || name.contains(":drawer:")
            if isFront, let mesh = entity as? ModelEntity {
                cabinetFronts[cabID, default: []].append((mesh, mesh.transform))
            }
        }
    }

    /// Zmiana koloru ściany (magiczny ołówek).
    public func setWallColor(_ hex: String, side: RoomSide) {
        wallColorHex = hex
        guard let walls = roomWalls[side] else { return }
        for e in walls {
            guard var m = e.model?.materials.first as? PhysicallyBasedMaterial else { continue }
            var updated = m
            updated.baseColor = .init(tint: Self.color(hex))
            m = updated
            e.model?.materials = [updated]
        }
    }

    /// Promień ze środka ekranu: szafka albo ściana (najbliższe trafienie).
    public func pick(origin: SIMD3<Float>, direction dir: SIMD3<Float>) -> FPSPick {
        var best: (distance: Float, pick: FPSPick)?
        let w = Float(room.width / 1000) / 2
        let d = Float(room.depth / 1000) / 2
        let h = Float(room.height / 1000)

        func consider(_ t: Float, _ pick: FPSPick) {
            guard t > 0.05, t < 12 else { return }
            if best == nil || t < best!.distance { best = (t, pick) }
        }

        // ściany pomieszczenia
        if abs(dir.z) > 0.0001 {
            let tN = (-d - origin.z) / dir.z
            let pN = origin + dir * tN
            if abs(pN.x) < w && pN.y > 0 && pN.y < h { consider(tN, .wall(.north)) }

            let tS = (d - origin.z) / dir.z
            let pS = origin + dir * tS
            let inOpening = abs(pS.x) < 0.55 && pS.y < 2.1
            if abs(pS.x) < w && pS.y > 0 && pS.y < h && !inOpening { consider(tS, .wall(.south)) }
        }
        if abs(dir.x) > 0.0001 {
            let tW = (-w - origin.x) / dir.x
            let pW = origin + dir * tW
            if abs(pW.z) < d && pW.y > 0 && pW.y < h { consider(tW, .wall(.west)) }

            let tE = (w - origin.x) / dir.x
            let pE = origin + dir * tE
            if abs(pE.z) < d && pE.y > 0 && pE.y < h { consider(tE, .wall(.east)) }
        }

        // szafki (AABB z uwzględnieniem obrotu 90/270)
        for (id, c) in cabinetsByID {
            let rotated = c.rotation == 90 || c.rotation == 270
            let halfW = Float((rotated ? c.depth : c.width) / 2000)
            let halfD = Float((rotated ? c.width : c.depth) / 2000)
            let center = SIMD3<Float>(Float(c.x / 1000), Float(c.height / 2000), Float(c.z / 1000))
            if let t = Self.rayBox(origin: origin, direction: dir,
                                   min: center - SIMD3(halfW, center.y, halfD),
                                   max: center + SIMD3(halfW, center.y, halfD)) {
                consider(t, .cabinet(id))
            }
        }
        return best?.pick ?? .none
    }

    private static func rayBox(origin o: SIMD3<Float>, direction d: SIMD3<Float>,
                               min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> Float? {
        var tmin: Float = 0
        var tmax: Float = .greatestFiniteMagnitude
        for i in 0..<3 {
            if abs(d[i]) < 1e-6 {
                if o[i] < lo[i] || o[i] > hi[i] { return nil }
            } else {
                var t1 = (lo[i] - o[i]) / d[i]
                var t2 = (hi[i] - o[i]) / d[i]
                if t1 > t2 { swap(&t1, &t2) }
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return tmin
    }

    /// Otwiera/zamyka fronty szafki animacją.
    public func toggleCabinet(_ id: UUID) {
        guard let fronts = cabinetFronts[id] else { return }
        let opening = !openCabinets.contains(id)
        if opening { openCabinets.insert(id) } else { openCabinets.remove(id) }
        let c = cabinetsByID[id]
        let rad = Float((c?.rotation ?? 0) * .pi / 180)
        let normal = SIMD3<Float>(sin(rad), 0, cos(rad))
        for (entity, rest) in fronts {
            var target = rest
            if opening { target.translation += normal * 0.34 }
            entity.move(to: target, relativeTo: entity.parent, duration: opening ? 0.45 : 0.35,
                        timingFunction: .easeInOut)
        }
    }

    public func isCabinetOpen(_ id: UUID) -> Bool { openCabinets.contains(id) }

    public var cabinetList: [Cabinet] { Array(cabinetsByID.values) }

    public func cabinet(_ id: UUID) -> Cabinet? { cabinetsByID[id] }

    /// Dokłada akcesorium do środka szafki (półka, kosz, drążek, szuflada).
    @discardableResult
    public func addAccessory(_ id: UUID, kind: String) -> Bool {
        guard let c = cabinetsByID[id] else { return false }
        let rad = Float(c.rotation * .pi / 180)
        let rot = simd_quatf(angle: rad, axis: [0, 1, 0])
        let center = SIMD3<Float>(Float(c.x / 1000), 0, Float(c.z / 1000))
        let innerW = Float(max(200, c.width - 60) / 1000)
        let innerD = Float(max(150, c.depth - 80) / 1000)
        let baseY = Float(c.plinth / 1000)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: WorldColor(red: 0.86, green: 0.82, blue: 0.74, alpha: 1))
        material.roughness = .init(floatLiteral: 0.7)

        let entity: ModelEntity
        switch kind {
        case "basket":
            material.baseColor = .init(tint: WorldColor(red: 0.24, green: 0.26, blue: 0.28, alpha: 1))
            entity = ModelEntity(mesh: .generateBox(width: innerW, height: 0.18, depth: innerD,
                                                    cornerRadius: 0.02), materials: [material])
            entity.position = center + SIMD3(0, baseY + 0.28, 0)
        case "rail":
            material.baseColor = .init(tint: WorldColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1))
            material.metallic = .init(floatLiteral: 0.8)
            entity = ModelEntity(mesh: .generateCylinder(height: innerW, radius: 0.012),
                                 materials: [material])
            entity.position = center + SIMD3(0, Float(c.height / 1000) * 0.62, 0)
            entity.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        case "drawer":
            entity = ModelEntity(mesh: .generateBox(width: innerW, height: 0.12, depth: innerD,
                                                    cornerRadius: 0.005), materials: [material])
            entity.position = center + SIMD3(0, baseY + 0.5, 0)
        default: // shelf
            entity = ModelEntity(mesh: .generateBox(width: innerW, height: 0.018, depth: innerD,
                                                    cornerRadius: 0.002), materials: [material])
            entity.position = center + SIMD3(0, Float(c.height / 1000) * 0.5, 0)
        }
        entity.orientation = rot
        entity.name = "accessory:\(id):\(kind):\(accessoryRoot.children.count)"
        accessoryRoot.addChild(entity)
        return true
    }

}
