import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene
import simd

#if os(iOS)
import UIKit
typealias FPSColor = UIColor
#else
import AppKit
typealias FPSColor = NSColor
#endif

enum MagicHand: String { case left, right }

/// Widok pierwszoosobowy: stoisz na podjeździe przed domem.
///
/// Sterowanie: lewa połowa ekranu = chodzenie (drążek), prawa = rozglądanie.
/// Dotknięcie drzwi otwiera je animacją. Pies podbiega i czeka na głaskanie.
struct FirstPersonView: View {
    let room: Room
    var cabinets: [Cabinet] = []
    var wallColor: String? = nil
    var onExit: (() -> Void)? = nil
    var onAddElement: ((UUID, CabinetElement) -> Void)? = nil
    var onWallColor: ((String) -> Void)? = nil
    var onSaveCabinet: ((Cabinet) -> Void)? = nil
    var onDeleteCabinet: ((UUID) -> Void)? = nil

    @State private var world: FirstPersonWorld?
    @State private var yaw: Float = 0.10         // lekko z boku, żeby kadr nie był symetryczny
    @State private var pitch: Float = -0.10
    @State private var eyeHeight: Float = 1.65
    @State private var moveVector = SIMD2<Float>.zero
    @State private var lastFrame = Date()
    @State private var dogClose = false
    @State private var petting = false
    @State private var pettingUntil: Date = .distantPast
    @State private var handsUp = false
    @State private var hint = "Przeciągnij w lewo, aby iść · w prawo, aby się rozejrzeć"
    @State private var settings = AppSettings.load()
    @State private var frameCount = 0
    /// ręka klienta (odpowiedź z wcześniejszych pytań); domyślnie prawa
    @AppStorage("magicHand") private var handRaw = "right"
    @State private var cameraEntity: Entity?
    @State private var pencil: Entity?
    @State private var editingWall: RoomSide?
    @State private var editingCabinet: UUID?
    @State private var editorMode: CabinetEditorMode = .body
    @State private var workingCabinets: [Cabinet] = []
    @State private var accessoryNote: String?
    @State private var flourishUntil: Date = .distantPast

    private let walkSpeed: Float = 1.7
    private var hand: MagicHand { handRaw == "left" ? .left : .right }
    private let wallPalette = ["#e8e2d8", "#d9c7a8", "#b7c4b0", "#8fa6b8", "#c9a227", "#6b7280", "#2f3437"]

    var body: some View {
        ZStack {
            RealityView { content in
                if let sky = await EnvironmentArt.environmentResource() {
                    content.environment = .skybox(sky)
                }
                let built = FirstPersonWorld(room: room, cabinets: cabinets, wallColor: wallColor)
                world = built
                content.add(built.root)

                // światło
                let sun = Entity()
                var light = DirectionalLightComponent(color: .white, intensity: 9000)
                light.isRealWorldProxy = false
                sun.components.set(light)
                sun.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
                content.add(sun)

                // kamera na wysokości oczu, na podjeździe
                let camera = Entity()
                camera.components.set(PerspectiveCameraComponent(
                    near: 0.05, far: 400,
                    fieldOfViewInDegrees: Float(settings.clampedFieldOfView)
                ))
                camera.position = [0, eyeHeight, world0DoorDistance()]
                camera.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                #if DEBUG
                // weryfikacja: start wewnątrz kuchni, twarzą do zabudowy
                if UserDefaults.standard.bool(forKey: "demoFPSInside") {
                    yaw = 0
                    pitch = UserDefaults.standard.bool(forKey: "demoFPSAutoColor") ? 0.12 : -0.16
                    camera.position = [0, 1.6, Float(room.depth / 1000) / 2 - 0.8]
                }
                #endif
                camera.name = "fps-camera"
                content.add(camera)
                content.camera = .virtual
                cameraEntity = camera
                // magiczny ołówek w dłoni wskazanej przez klienta
                let wand = makePencil(hand: hand)
                content.add(wand)
                pencil = wand
                NSLog("[fps] kamera z=%.2f, drzwi z=%.2f, dom %.1f x %.1f",
                      camera.position.z, built.doorPoint.z, built.houseHalf.x, built.houseHalf.y)

                startLoop(content: content, camera: camera)
            } placeholder: {
                ProgressView("Buduję posesję…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
            .ignoresSafeArea()

            // dłonie w kadrze (podnoszą się przy głaskaniu psa)
            HandsOverlay(petting: handsUp)
                .opacity(handsUp ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // celownik = czubek magicznego ołówka
            crosshair

            // sterowanie
            HStack(spacing: 0) {
                JoystickPad { vector in
                    moveVector = vector
                    if vector != .zero { hint = "" }
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(lookGesture)
                    .onTapGesture(count: 2) { doubleTap() }
                    .onTapGesture { singleTap() }
            }

            VStack {
                HStack {
                    Button {
                        onExit?()
                    } label: {
                        Label("Wyjdź", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if !hint.isEmpty {
                        Text(hint)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    Spacer()
                    Button {
                        handRaw = hand == .right ? "left" : "right"
                    } label: {
                        Label(hand == .right ? "Ręka P" : "Ręka L", systemImage: "hand.raised.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        world?.setDoor(open: !(world?.isDoorOpen ?? false))
                    } label: {
                        Label("Drzwi", systemImage: "door.left.hand.open")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }

            if let side = editingWall {
                wallPalette(side)
            }
            if let id = editingCabinet, let cab = workingCabinets.first(where: { $0.id == id }) {
                HStack {
                    Spacer()
                    CabinetEditorPanel(
                        cabinet: cab,
                        room: room,
                        mode: editorMode,
                        isOpen: world?.isCabinetOpen(id) ?? false,
                        onLiveChange: { applyLive($0) },
                        onSave: { onSaveCabinet?($0) },
                        onClose: { closeEditor() },
                        onDelete: {
                            deleteCabinet(id)
                        },
                        onOpenFront: { open in
                            world?.setCabinetOpen(id, open: open)
                        },
                        onModeChange: { editorMode = $0 }
                    )
                    .id(id)
                }
                .padding(.top, 64)
                .padding(.bottom, 26)
            }
            if let note = accessoryNote {
                VStack {
                    Spacer()
                    Text(note)
                        .font(.caption)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 190)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if workingCabinets.isEmpty { workingCabinets = cabinets }
            #if DEBUG
            if let match = UserDefaults.standard.string(forKey: "demoSelectCabinet"), !match.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    debugSelectCabinet(match)
                }
            }
            #endif
        }
        .background(Color.black)
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    // MARK: - pętla

    private func startLoop(content: RealityViewCameraContent, camera: Entity) {
        lastFrame = Date()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoFPSPoint") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if UserDefaults.standard.bool(forKey: "demoFPSDouble") {
                    doubleTap()
                } else {
                    singleTap()
                }
            }
        }
        #endif
        _ = content.subscribe(to: SceneEvents.Update.self) { _ in
            let now = Date()
            let dt = Float(min(0.05, now.timeIntervalSince(lastFrame)))
            lastFrame = now
            guard let world else { return }

            // ruch gracza
            if moveVector != .zero {
                // kamera patrzy w −Z; przy obrocie yaw „przód" to −sin/−cos
                let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
                let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
                var position = camera.position
                position += (forward * moveVector.y + right * moveVector.x) * walkSpeed * dt
                position = clamp(position, world: world)
                camera.position = position
            }

            camera.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])

            // magiczny ołówek: buja się w dłoni, a po dotknięciu robi ruch czarodzieja
            if let pencil {
                let t = Float(now.timeIntervalSinceReferenceDate)
                let flourish = now < flourishUntil
                let spin = flourish ? sin(t * 20) * 0.55 : 0
                let side: Float = hand == .right ? 1 : -1
                let head = simd_quatf(angle: yaw, axis: [0, 1, 0])
                    * simd_quatf(angle: pitch, axis: [1, 0, 0])
                let local = SIMD3<Float>(side * 0.18, -0.20 + sin(t * 1.6) * 0.006, -0.55)
                pencil.position = camera.position + head.act(local)
                pencil.orientation = head
                    * simd_quatf(angle: side * 0.80, axis: [0, 1, 0])
                    * simd_quatf(angle: spin, axis: [0, 0, 1])
                    * simd_quatf(angle: 0.65 + (flourish ? sin(t * 14) * 0.12 : 0), axis: [1, 0, 0])
            }

            // pies
            let running = !world.updateDog(player: camera.position, cameraYaw: yaw, deltaTime: dt)
            if frameCount % 90 == 0, let dog = world.dog {
                let p = dog.position(relativeTo: nil)
                NSLog("[fps] pies %.2f %.2f %.2f | kamera %.2f %.2f %.2f | dzieci %d",
                      p.x, p.y, p.z, camera.position.x, camera.position.y, camera.position.z, dog.children.count)
            }
            frameCount += 1
            dogClose = !running
            let excited = now < pettingUntil
            world.animateDog(time: Float(now.timeIntervalSinceReferenceDate), running: running, excited: excited)

            if excited && !handsUp {
                withAnimation(.easeInOut(duration: 0.25)) { handsUp = true }
            } else if !excited && handsUp {
                withAnimation(.easeInOut(duration: 0.35)) { handsUp = false }
            }
        }
    }

    private func clamp(_ position: SIMD3<Float>, world: FirstPersonWorld) -> SIMD3<Float> {
        var p = position
        let radius = world.playRadius
        p.x = min(radius, max(-radius, p.x))
        p.z = min(radius + 6, max(-radius, p.z))

        // ściany domu: nie wchodzimy w bryłę, chyba że drzwi są otwarte i jesteśmy w osi
        let half = world.houseHalf
        let insideX = abs(p.x) < half.x + 0.25
        let insideZ = p.z < half.y + 0.25 && p.z > -half.y - 0.25
        if insideX && insideZ && !world.canPassThrough(at: p) {
            // wypychamy na zewnątrz najbliższą ścianą
            let dx = half.x + 0.3 - abs(p.x)
            let dzFront = (half.y + 0.3) - p.z
            let dzBack = p.z + half.y + 0.3
            if dzFront < dx && dzFront < dzBack {
                p.z = half.y + 0.3
            } else if dzBack < dx {
                p.z = -half.y - 0.3
            } else {
                p.x = (p.x < 0 ? -1 : 1) * (half.x + 0.3)
            }
        }
        return p
    }

    /// Jedno dotknięcie: zaznaczenie szafki i edycja bryły.
    private func singleTap() {
        flourishUntil = Date().addingTimeInterval(0.85)
        guard let target = pickTarget() else { return }
        switch target {
        case .wall(let side):
            world?.setSelected(nil)
            editingWall = side
            editingCabinet = nil
        case .cabinet(let id):
            editingWall = nil
            editingCabinet = id
            editorMode = .body
            accessoryNote = nil
            world?.setSelected(id)
        case .none:
            closeEditor()
            if dogClose {
                pettingUntil = Date().addingTimeInterval(2.4)
            } else {
                world?.setDoor(open: !(world?.isDoorOpen ?? false))
            }
        }
    }

    /// Dwa dotknięcia: otwarcie frontu i edycja wnętrza (półki, szuflady, asortyment).
    private func doubleTap() {
        flourishUntil = Date().addingTimeInterval(0.85)
        guard let target = pickTarget() else { return }
        switch target {
        case .cabinet(let id):
            editingWall = nil
            editingCabinet = id
            editorMode = .interior
            accessoryNote = nil
            world?.setSelected(id)
            world?.setCabinetOpen(id, open: true)
        case .wall(let side):
            world?.setSelected(nil)
            editingWall = side
            editingCabinet = nil
        case .none:
            if dogClose {
                pettingUntil = Date().addingTimeInterval(2.4)
            } else {
                world?.setDoor(open: !(world?.isDoorOpen ?? false))
            }
        }
    }

    private func debugSelectCabinet(_ match: String) {
        guard let c = workingCabinets.first(where: { $0.name.localizedCaseInsensitiveContains(match) }),
              let world, let cam = cameraEntity else { return }
        editingCabinet = c.id
        editorMode = .interior
        accessoryNote = nil
        world.setSelected(c.id)
        world.setCabinetOpen(c.id, open: true)
        let rad = Float(c.rotation * .pi / 180)
        let normal = SIMD3<Float>(sin(rad), 0, cos(rad))
        let distance = UserDefaults.standard.object(forKey: "demoSelectDistance") != nil
            ? UserDefaults.standard.double(forKey: "demoSelectDistance") : 2.6
        cam.position = [Float(c.x / 1000) + normal.x * Float(distance),
                        Float((c.mountHeight > 0 ? c.mountHeight : 1500) / 1000),
                        Float(c.z / 1000) + normal.z * Float(distance)]
        yaw = atan2(normal.x, normal.z)
        pitch = -0.35
    }

    private func pickTarget() -> FPSPick? {
        guard let world, let camera = cameraEntity else { return nil }
        let dir = SIMD3<Float>(
            -sin(yaw) * cos(pitch),
            sin(pitch),
            -cos(yaw) * cos(pitch)
        )
        return world.pick(origin: camera.position, direction: dir)
    }

    private func applyLive(_ cab: Cabinet) {
        if let i = workingCabinets.firstIndex(where: { $0.id == cab.id }) {
            workingCabinets[i] = cab
        } else {
            workingCabinets.append(cab)
        }
        world?.updateCabinets(workingCabinets)
    }

    private func closeEditor() {
        if let id = editingCabinet { world?.setSelected(nil) }
        editingCabinet = nil
        editingWall = nil
    }

    private func deleteCabinet(_ id: UUID) {
        workingCabinets.removeAll { $0.id == id }
        world?.updateCabinets(workingCabinets)
        world?.setSelected(nil)
        onDeleteCabinet?(id)
        editingCabinet = nil
        accessoryNote = "Usunięto szafkę"
    }

    private func world0DoorDistance() -> Float {
        // start na podjeździe, ~7 m przed drzwiami
        max(4.8, Float(room.depth / 2000)) + 13.0
    }

    // MARK: - magiczny ołówek i edycja

    private var crosshair: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
                        .frame(width: 26, height: 26)
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 4, height: 4)
                    Circle()
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 6)
                        .frame(width: 26, height: 26)
                        .blur(radius: 4)
                }
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// Ołówek (rozka) w dłoni: korpus, złoty grot i świecąca gwiazdka.
    private func makePencil(hand: MagicHand) -> Entity {
        let root = Entity()
        root.name = "magic-pencil"

        // ołówek jest zawsze widoczny (unlit) — jak świecący przedmiot magiczny
        let wood = UnlitMaterial(color: FPSColor(red: 0.52, green: 0.33, blue: 0.18, alpha: 1))
        let gold = UnlitMaterial(color: FPSColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1))
        let skin = UnlitMaterial(color: FPSColor(red: 0.88, green: 0.72, blue: 0.58, alpha: 1))

        let body = ModelEntity(mesh: .generateCylinder(height: 0.34, radius: 0.017), materials: [wood])
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(body)

        let tip = ModelEntity(mesh: .generateCone(height: 0.08, radius: 0.017), materials: [gold])
        tip.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        tip.position = [0, 0, -0.21]
        root.addChild(tip)

        let star = ModelEntity(mesh: .generateSphere(radius: 0.014),
                               materials: [UnlitMaterial(color: FPSColor(red: 1, green: 0.9, blue: 0.55, alpha: 1))])
        star.position = [0, 0, -0.26]
        root.addChild(star)

        // dłoń trzymająca ołówek
        let palm = ModelEntity(mesh: .generateBox(width: 0.075, height: 0.095, depth: 0.12, cornerRadius: 0.03),
                               materials: [skin])
        palm.position = [0, -0.035, 0.10]
        root.addChild(palm)

        let side: Float = hand == .right ? 1 : -1
        root.position = [side * 0.18, -0.20, -0.55]
        root.orientation = simd_quatf(angle: side * 0.80, axis: [0, 1, 0])
            * simd_quatf(angle: 0.65, axis: [1, 0, 0])
        return root
    }

    private func wallPalette(_ side: RoomSide) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Ściana \(sideLabel(side)) — kolor", systemImage: "paintbrush.fill")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Zamknij") { editingWall = nil }
                        .font(.caption)
                }
                HStack(spacing: 10) {
                    ForEach(wallPalette, id: \.self) { hex in
                        Button {
                            world?.setWallColor(hex, side: side)
                            onWallColor?(hex)
                            editingWall = nil
                            accessoryNote = "Kolor ściany zmieniony"
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
    }

    private func sideLabel(_ side: RoomSide) -> String {
        switch side {
        case .north: "północna"
        case .south: "południowa"
        case .east: "wschodnia"
        case .west: "zachodnia"
        }
    }

    private func accessoryPicker(_ id: UUID) -> some View {
        let name = world?.cabinet(id)?.name ?? "Szafka"
        return VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(name, systemImage: "cabinet.fill")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("Zamknij") {
                        editingCabinet = nil
                        accessoryNote = nil
                    }
                    .font(.caption)
                }
                Text("Szafka otwarta — dodaj akcesorium do środka:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(accessories, id: \.id) { a in
                        Button {
                            if world?.addAccessory(id, kind: a.id) == true {
                                onAddElement?(id, element(for: a.id))
                                accessoryNote = "Dodano: \(a.label)"
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: a.icon).font(.title3)
                                Text(a.label).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
    }

    private var accessories: [(id: String, label: String, icon: String)] {
        [
            ("shelf", "Półka", "rectangle.split.3x1"),
            ("basket", "Kosz", "basket.fill"),
            ("rail", "Drążek", "hanger"),
            ("drawer", "Szuflada", "tray.fill"),
        ]
    }

    private func element(for kind: String) -> CabinetElement {
        switch kind {
        case "drawer":
            CabinetElement(kind: .drawer, y: 400, height: 90, drawer: .m)
        case "rail":
            CabinetElement(kind: .shelf, y: 1800, height: Standards.panel)
        case "basket":
            CabinetElement(kind: .shelf, y: 300, height: Standards.panel)
        default:
            CabinetElement(kind: .shelf, y: 900, height: Standards.panel)
        }
    }

    private var lookGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                yaw -= Float(value.translation.width) * 0.0025
                pitch = min(0.6, max(-0.7, pitch - Float(value.translation.height) * 0.002))
            }
    }
}

/// Drążek do chodzenia (lewa strona ekranu).
struct JoystickPad: View {
    var onChange: (SIMD2<Float>) -> Void
    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 132, height: 132)
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let limit: CGFloat = 60
                    let x = max(-limit, min(limit, value.translation.width))
                    let y = max(-limit, min(limit, value.translation.height))
                    knob = CGSize(width: x, height: y)
                    // w górę = do przodu (−y), w prawo = w bok
                    onChange(SIMD2(Float(x / limit), Float(-y / limit)))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(.zero)
                }
        )
    }
}

/// Dłonie w dolnej części kadru — podnoszą się przy głaskaniu.
struct HandsOverlay: View {
    let petting: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                hand(width: width * 0.22)
                    .rotationEffect(.degrees(petting ? -18 : -6), anchor: .bottomLeading)
                    .offset(x: petting ? width * 0.06 : -width * 0.01, y: petting ? -height * 0.02 : height * 0.10)
                    .position(x: width * 0.14, y: height * 0.99)

                hand(width: width * 0.22)
                    .rotationEffect(.degrees(petting ? 16 : 4), anchor: .bottomTrailing)
                    .scaleEffect(x: -1)
                    .offset(x: petting ? -width * 0.06 : width * 0.01, y: petting ? -height * 0.02 : height * 0.10)
                    .position(x: width * 0.86, y: height * 0.99)
            }
            .animation(.easeInOut(duration: 0.35), value: petting)
        }
    }

    private func hand(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.34, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.66),
                                        Color(red: 0.84, green: 0.66, blue: 0.54)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: width, height: width * 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.34, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: -6)
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16) ?? 0xCCCCCC
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}
