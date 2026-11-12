import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene

/// Podgląd 3D: scena z KitchenScene, kamera z PreviewCamera,
/// opcjonalny tryb wybierania punktów skanu (tap → promień → woksel).
struct SceneView: View {
    let cabinets: [Cabinet]
    var room = Room()
    var scan: PointCloud?
    var transform = ScanTransform()
    /// gotowa powierzchnia skanu (woksele) — budowana raz, nie w każdym odświeżeniu
    var surfaceEntity: ScanSurface?
    /// pokaż chmurę punktów zamiast powierzchni
    var showPoints = false
    /// otoczenie: las, góry, podjazd, auto, ptaki
    var showEnvironment = true
    /// false = widok z zewnątrz (dom w otoczeniu)
    var interiorView = true
    /// plan domu wyprowadzony ze skanu (chmura X9) — jeśli jest, bryła domu
    /// powstaje z pomiaru, a nie z generatora willi
    var scanPlan: ScanPlan?
    /// nałóż chmurę punktów 1:1 na zbudowany dom (kontrola dopasowania)
    var showScanCloud = false
    /// tryb wskazywania punktów skanu
    var picking = false
    /// znormalizowany punkt ekranu (0…1) po dotknięciu
    var onPick: ((CGPoint, CGSize) -> Void)?
    /// true = projekt zablokowany: gesty tylko oglądają (brak edycji).
    /// false = odblokowany: można edytować projekt.
    var locked: Bool = true
    /// Pokaż SKAN (chmurę z X9 albo z iPada) — niezależnie od bryły budynku.
    ///
    /// Wymóg: „chcę mieć skan z X9 wyłączany oddzielnie i budynek oddzielnie".
    /// Dlatego to jest osobny przełącznik, a nie skutek uboczny posiadania skanu:
    /// wcześniej samo wczytanie chmury włączało ją na stałe i wyłączało ściany
    /// budynku (`walls: scan == nil`), więc nie dało się porównać jednego z drugim.
    var showScan = true
    /// Pokaż BRYŁĘ BUDYNKU (ściany, podłoga, sufit) — niezależnie od skanu.
    var showBuilding = true
    /// SIATKA POMIESZCZENIA ze skanu (ściany z otworami, UV w metrach, kolory).
    ///
    /// To jest właściwy wynik modułu LiDAR: geometria z modelu, a nie z
    /// triangulacji ARKit. Rysowana jako osobna warstwa, żeby można ją było
    /// porównać z chmurą (czy ściany pokrywają się ze skanem).
    var roomMesh: RoomMesh.Result?
    /// Kolory powierzchni siatki (z chmury).
    var roomMeshColors: [RoomMesh.SurfaceColor] = []
    /// Pokaż siatkę pomieszczenia (niezależny przełącznik).
    var showRoomMesh = true
    /// Zaznaczona szafka (kontury) — klik w scenie ustawia przez `onSelectCabinet`.
    var selectedCabinetID: UUID?
    var onSelectCabinet: ((UUID?) -> Void)?

    /// Stan kamery niezależny od modelu: przesunięcie celu (m), obrót i zbliżenie.
    // Kamera trzymana poza @State: modyfikowana co klatkę (płynność), bez
    // wywoływania przebudowy SwiftUI 60 razy na sekundę.
    @State private var lastDragStart = CGPoint.zero
    @State private var lastDrag: CGSize = .zero
    /// osobny licznik dla gestu dwoma palcami (przesuwanie widoku)
    @State private var lastPanDrag: CGSize = .zero

    /// Cache sceny: przebudowujemy ją TYLKO gdy zmienią się dane.
    /// Wcześniej `update:` kasowało i budowało całe otoczenie przy KAŻDEJ
    /// zmianie stanu (także przy każdym ruchu kamery) — stąd 1 klatka na sekundy.
    final class SceneCache {
        var signature: Int = .min
        // kamera: wartości bieżące, cele (dokąd zmierza) i prędkości (bezwładność)
        var pan = SIMD2<Float>.zero
        var panTarget = SIMD2<Float>.zero
        var panVelocity = SIMD2<Float>.zero
        var yaw: Float = 0
        var yawTarget: Float = 0
        var yawVelocity: Float = 0
        var pitch: Float = 0
        var pitchTarget: Float = 0
        var zoom: Float = 1
        var zoomTarget: Float = 1
        var lastFrame = Date()
        var lastDragTranslation = CGSize.zero
        var camera: Entity?
        var environment: Entity?
        var fitted: PreviewCamera?
        var currentCamera: PreviewCamera?
        var cabinetFocus: SIMD3<Float>?
        /// gwiazdki podglądu strefy (mrugają co klatkę)
        var sparkles: Entity?
        /// ściany pokoju — do przezroczystości, gdy zasłaniają kamerę
        var walls: [ModelEntity] = []
        var wallAlphas: [Float] = []
    }
    @State private var cache = SceneCache()
    /// Ustawienia: ogniskowa (domyślnie 47°), czułości gestów.
    @State private var settings = AppSettings.load()

    var body: some View {
        RealityView { content in
            if let sky = await EnvironmentArt.environmentResource() {
                content.environment = .skybox(sky)
            }
            #if os(iOS)
            // Efekty fotograficzne dostępne natywnie: rozmycie głębi i motion blur.
            // Aberracji chromatycznej i lens flar RealityKit nie ma — to overlay
            // albo własny łańcuch Metal (patrz dokumentacja w repo).
            content.renderingEffects.depthOfField = .enabled
            content.renderingEffects.motionBlur = .enabled
            #endif
            content.add(SceneBuilder.sunlight())
            // ściany budynku tylko gdy włączone (niezależnie od skanu)
            if showBuilding {
                content.add(SceneBuilder.buildRoom(room, walls: true, scanPlan: scanPlan,
                                                   scanCloud: showScanCloud))
            }
            if showEnvironment, !showScan {
                let environment = EnvironmentBuilder.makeEntity(room: room)
                cache.environment = environment
                content.add(environment)
            }
            if showScanCloud, let scanPlan {
                content.add(ScanCloudOverlay.entity(plan: scanPlan))
            }
            #if DEBUG
            NSLog("[scena] pokój %.0f × %.0f mm, wys. %.0f, szafek %d",
                  room.width, room.depth, room.height, cabinets.count)
            #endif
            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
            let cabinetRoot = built.root
            cache.sparkles = cabinetRoot.findEntity(named: "sparkles")
            content.add(cabinetRoot)
            // SIATKA POMIESZCZENIA z modelu (niezależna warstwa)
            if showRoomMesh, let roomMesh, !roomMesh.surfaces.isEmpty {
                let meshEntity = RoomMeshEntity.make(roomMesh, colors: roomMeshColors)
                content.add(meshEntity)
            }
            // chmura skanu tylko gdy włączona (niezależnie od bryły)
            let scanEntity = showScan ? scanEntityToAdd() : nil
            if let scanEntity { content.add(scanEntity) }
            // kadr: skan, a bez skanu — zabudowa (nie cały pokój)
            let base = baseCamera(scanEntity: scanEntity, built: built)
            cache.fitted = base
            let cam = makeCamera(base: base)
            cache.camera = cam
            cache.signature = sceneSignature
            content.add(cam)
            content.camera = .virtual

            // LOD co klatkę: liczy odległości i przełącza gotowe encje (tanio)
            var frames = 0
            var lastLog = Date()
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                stepCamera()
                MainActor.assumeIsolated {
                    if let sparks = cache.sparkles {
                        Sparkles.update(root: sparks, time: Float(Date().timeIntervalSinceReferenceDate))
                    }
                }
                if let camera = cache.camera, let base = cache.fitted {
                    applyCameraControl(camera, base: base)
                }
                if let environment = cache.environment, let camera = cache.camera {
                    DetailLOD.update(root: environment, cameraPosition: camera.position(relativeTo: nil))
                }
                if let camera = cache.camera {
                    updateWallTransparency(cameraPosition: camera.position(relativeTo: nil))
                }
                #if DEBUG
                frames += 1
                let now = Date()
                if now.timeIntervalSince(lastLog) > 2 {
                    let fps = Double(frames) / now.timeIntervalSince(lastLog)
                    NSLog("[scena] %.1f kl./s", fps)
                    frames = 0
                    lastLog = now
                }
                #endif
            }
        } update: { content in
            let signature = sceneSignature
            if signature != cache.signature {
                cache.signature = signature
                content.entities.removeAll()
                content.add(SceneBuilder.sunlight())
                if showBuilding {
                    let roomEntity = SceneBuilder.buildRoom(room, walls: true, scanPlan: scanPlan,
                                                            scanCloud: showScanCloud,
                                                            includeShell: !interiorView)
                    content.add(roomEntity)
                    cache.walls = (0..<4).compactMap { roomEntity.findEntity(named: "wall-\($0)") as? ModelEntity }
                    cache.wallAlphas = Array(repeating: -1, count: cache.walls.count)
                } else {
                    cache.walls = []
                }
                if showEnvironment, !showScan {
                    let environment = EnvironmentBuilder.makeEntity(room: room)
                    cache.environment = environment
                    content.add(environment)
                }
                if showScanCloud, let scanPlan {
                content.add(ScanCloudOverlay.entity(plan: scanPlan))
            }
            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
                cache.sparkles = built.root.findEntity(named: "sparkles")
                content.add(built.root)
                let scanEntity = scanEntityToAdd()
                if let scanEntity { content.add(scanEntity) }

                let base = baseCamera(scanEntity: scanEntity, built: built)
                NSLog("[kamera] kadr pos=(%.2f, %.2f, %.2f) cel=(%.2f, %.2f, %.2f) obrys=(%.2f x %.2f x %.2f) wnetrze=%@",
                      base.position.x, base.position.y, base.position.z,
                      base.target.x, base.target.y, base.target.z,
                      built.extents.x, built.extents.y, built.extents.z,
                      interiorView ? "tak" : "nie")
                cache.fitted = base
                // po każdej zmianie projektu kamera WRACA do kadru na zabudowę
                // (wcześniej zostawała tam, gdzie ją użytkownik obrócił —
                // wstawiona szafka była poza ekranem)
                cache.pan = .zero; cache.panTarget = .zero; cache.panVelocity = .zero
                cache.yaw = 0; cache.yawTarget = 0; cache.yawVelocity = 0
                cache.pitch = 0; cache.pitchTarget = 0
                cache.zoom = 1; cache.zoomTarget = 1
                let cam = makeCamera(base: base)
                cache.camera = cam
                content.add(cam)
                content.camera = .virtual
            } else if let cam = cache.camera, let base = cache.fitted {
                // tylko kamera — kilkanaście operacji zamiast budowy całego świata
                applyCameraControl(cam, base: base)
            }
        }
        .overlay {
            #if os(iOS)
            if picking {
                TapCatcher { point, size in onPick?(point, size) }
            }
            #endif
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .simultaneousGesture(cameraDrag)
        #endif
        // Na iOS gesty obsługuje warstwa UIKit — tylko ona rozróżnia palce.
        .overlay {
            #if os(iOS)
            // Warstwa gestów NIE działa przy wskazywaniu punktów skanu:
            // wtedy nad sceną jest `TapCatcher` i gesty muszą do niego trafić,
            // inaczej nie da się kliknąć punktu w chmurze.
            if !picking {
                CameraGestureLayer(
                    onRotate: { rotate(dx: $0, dy: $1) },
                    onPan: { pan(dx: $0, dy: $1) },
                    onZoom: { zoom(scale: $0) },
                    onEndRotate: { endRotation(velocityX: $0) },
                    onEndPan: { endPan(velocityX: $0, velocityY: $1) },
                    onTap: { point, size in select(at: point, size: size) }
                )
            }
            #endif
        }
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Tap w scenie: promień z kamery i najbliższa szafka.
    private func select(at point: CGPoint, size: CGSize) {
        guard let cam = cache.currentCamera, size.width > 0, size.height > 0 else { return }
        let ray = cam.ray(normalizedPoint: point, aspect: Float(size.width / size.height))
        var best: (Float, UUID)?
        for c in cabinets {
            let rotated = c.rotation == 90 || c.rotation == 270
            let halfW = Float((rotated ? c.depth : c.width) / 2000)
            let halfD = Float((rotated ? c.width : c.depth) / 2000)
            let center = SIMD3<Float>(Float(c.x / 1000), Float(c.height / 2000), Float(c.z / 1000))
            if let t = Self.rayBox(origin: ray.origin, direction: ray.direction,
                              min: center - SIMD3(halfW, center.y, halfD),
                              max: center + SIMD3(halfW, center.y, halfD)) {
                if best == nil || t < best!.0 { best = (t, c.id) }
            }
        }
        onSelectCabinet?(best?.1)
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

    /// Kontury wszystkich brył szafki (12 krawędzi na każdą bryłę).
    @MainActor
    private func outlineEntity(for c: Cabinet) -> Entity {
        let root = Entity()
        root.name = "selection-outline"
        root.position = [Float(c.x / 1000), 0, Float(c.z / 1000)]
        root.orientation = simd_quatf(angle: Float(c.rotation * .pi / 180), axis: [0, 1, 0])
        let material = UnlitMaterial(color: .cyan)
        let t: Float = 0.008
        for b in Generator.build(c) {
            let w = Float(b.size.x / 1000), h = Float(b.size.y / 1000), d = Float(b.size.z / 1000)
            let p = SIMD3<Float>(Float(b.position.x / 1000), Float(b.position.y / 1000), Float(b.position.z / 1000))
            func edge(_ sx: Float, _ sy: Float, _ sz: Float, _ x: Float, _ y: Float, _ z: Float) {
                let e = ModelEntity(mesh: .generateBox(width: sx, height: sy, depth: sz), materials: [material])
                e.position = p + [x, y, z]
                root.addChild(e)
            }
            for sx in [-1 as Float, 1] {
                for sz in [-1 as Float, 1] { edge(t, h, t, sx * w / 2, 0, sz * d / 2) }
            }
            for sy in [-1 as Float, 1] {
                for sz in [-1 as Float, 1] { edge(w, t, t, 0, sy * h / 2, sz * d / 2) }
                for sx in [-1 as Float, 1] { edge(t, t, d, sx * w / 2, sy * h / 2, 0) }
            }
        }
        return root
    }

    /// Podpis danych sceny — tani do policzenia, zmienia się tylko przy realnych zmianach.
    private var sceneSignature: Int {
        var hasher = Hasher()
        hasher.combine(room.width); hasher.combine(room.depth); hasher.combine(room.height)
        // tryb widoku zmienia CAŁĄ scenę (skorupa willi vs same ściany),
        // więc musi być w sygnaturze — inaczej przełączenie nie przebudowywało
        hasher.combine(interiorView); hasher.combine(showBuilding); hasher.combine(showScan)
        hasher.combine(cabinets.count)
        for cabinet in cabinets {
            hasher.combine(cabinet.id)
            hasher.combine(cabinet.x); hasher.combine(cabinet.z)
            hasher.combine(cabinet.width); hasher.combine(cabinet.height); hasher.combine(cabinet.depth)
            hasher.combine(cabinet.rotation)
            hasher.combine(cabinet.doorCount ?? 1)
            hasher.combine(cabinet.color)
            hasher.combine(cabinet.texture)
            hasher.combine(cabinet.elements.count)
            for e in cabinet.elements {
                hasher.combine(e.kind.rawValue)
                hasher.combine(e.y); hasher.combine(e.height)
            }
            hasher.combine(cabinet.cutouts?.count ?? 0)
            hasher.combine(cabinet.hinge?.rawValue ?? "standard")
            hasher.combine(cabinet.accessories?.count ?? 0)
            for a in cabinet.accessories ?? [] {
                hasher.combine(a.id); hasher.combine(a.kind.rawValue); hasher.combine(a.y)
            }
            for cut in cabinet.cutouts ?? [] {
                hasher.combine(cut.id)
                hasher.combine(cut.plane.rawValue)
                hasher.combine(cut.x); hasher.combine(cut.y)
                hasher.combine(cut.width); hasher.combine(cut.height)
            }
        }
        hasher.combine(selectedCabinetID?.uuidString ?? "")
        hasher.combine(showEnvironment)
        hasher.combine(interiorView)
        hasher.combine(showScan)
        hasher.combine(showBuilding)
        hasher.combine(showRoomMesh)
        hasher.combine(roomMesh?.surfaces.count ?? 0)
        hasher.combine(scan != nil)
        hasher.combine(surfaceEntity != nil)
        hasher.combine(showPoints)
        hasher.combine(transform.scale); hasher.combine(transform.rotationDeg); hasher.combine(transform.offset.x); hasher.combine(transform.offset.z)
        return hasher.finalize()
    }

    // MARK: - sterowanie kamerą

    // MARK: - sterowanie kamerą (macOS)
    //
    // NA iOS GESTY OBSŁUGUJE `CameraGestureLayer` (UIKit) — patrz niżej.
    // Powód: `DragGesture` w tym SDK przyjmuje wyłącznie `minimumDistance`
    // i `coordinateSpace`, więc NIE MA sposobu, by rozróżnić jeden palec od
    // dwóch (próba `maximumNumberOfTouches:` kończy się błędem kompilacji).
    // Bez tego rozróżnienia obrót i przesuwanie wchodziłyby naraz — dokładnie
    // to zgłoszony problem „wariuje obrót".

    #if os(macOS)
    private var cameraDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = Float(value.translation.width - lastDrag.width)
                let dy = Float(value.translation.height - lastDrag.height)
                lastDrag = value.translation
                rotate(dx: dx, dy: dy)
            }
            .onEnded { _ in
                lastDrag = .zero
                cache.yawVelocity = 0
            }
    }
    #endif

    /// Obrót projektu jednym palcem (lub myszą na Macu).
    func rotate(dx: Float, dy: Float) {
        let yawSpeed = Float(0.006 * settings.panSensitivity)
        cache.yawTarget -= dx * yawSpeed
        // pod podłogę nie schodzimy; nad horyzontem można patrzeć z góry
        cache.pitchTarget = min(1.15, max(-0.35, cache.pitchTarget + dy * 0.004))
        cache.yawVelocity = -dx * yawSpeed * 0.5
    }

    /// Przesuwanie widoku dwoma palcami.
    func pan(dx: Float, dy: Float) {
        let speed = Float((interiorView ? 0.006 : 0.05) * settings.panSensitivity)
        cache.panTarget.x = min(120, max(-120, cache.panTarget.x - dx * speed))
        cache.panTarget.y = min(120, max(-120, cache.panTarget.y - dy * speed))
        cache.panVelocity = SIMD2(-dx * speed, -dy * speed) * 0.55
    }

    /// Zbliżenie szczypaniem — wykładniczo, żeby nie „latało".
    func zoom(scale: Float) {
        let factor = pow(1 / Float(max(0.2, scale)), Float(settings.zoomSensitivity))
        cache.zoomTarget = min(2.6, max(0.35, cache.zoomTarget * factor))
    }

    /// Prędkość po puszczeniu palca — bezwładność obrotu i przesuwania.
    func endRotation(velocityX: Float) {
        let yawSpeed = Float(0.006 * settings.panSensitivity)
        cache.yawVelocity = -velocityX * yawSpeed * 0.02
    }

    func endPan(velocityX: Float, velocityY: Float) {
        let speed = Float((interiorView ? 0.006 : 0.05) * settings.panSensitivity)
        cache.panVelocity = SIMD2(velocityX * speed * 0.02, velocityY * speed * 0.02)
    }

    /// Encja skanu: gotowa powierzchnia albo chmura punktów.
    @MainActor
    private func scanEntityToAdd() -> Entity? {
        if let surfaceEntity, !showPoints { return surfaceEntity }
        if let scan { return PointCloudRenderer.makeEntity(scan, transform: transform) }
        return nil
    }

    /// Ściany, które stoją między kamerą a pomieszczeniem, robią się przezroczyste.
    /// Dzięki temu widok z zewnątrz (i kamera cofnięta przed elewację) nie jest
    /// „zasłonięty białym murem", a wnętrze z zabudową pozostaje widoczne.
    private func updateWallTransparency(cameraPosition: SIMD3<Float>) {
        guard !cache.walls.isEmpty else { return }
        let halfW = Float(room.width / 1000) / 2
        let halfD = Float(room.depth / 1000) / 2
        for (index, wall) in cache.walls.enumerated() {
            let pos = room.wallPosition(index)
            let center = SIMD3<Float>(Float(pos.x) / 1000, 0, Float(pos.z) / 1000)
            // normalna zewnętrzna: ściana leży na ±W/2 albo ±D/2
            var normal = SIMD3<Float>(0, 0, 0)
            if abs(center.x) > abs(center.z) {
                normal.x = center.x > 0 ? 1 : -1
            } else {
                normal.z = center.z > 0 ? 1 : -1
            }
            // kamera po zewnętrznej stronie ściany = ta ściana zasłania widok
            let side = simd_dot(cameraPosition - center, normal)
            let blocked = interiorView && side > 0.05
            let target: Float = blocked ? 0.16 : 1.0
            let current = cache.wallAlphas[index]
            guard abs(current - target) > 0.01 else { continue }
            cache.wallAlphas[index] = target
            guard var model = wall.model,
                  var material = model.materials.first as? PhysicallyBasedMaterial else { continue }
            if target < 0.99 {
                material.blending = .transparent(opacity: .init(floatLiteral: target))
            } else {
                material.blending = .opaque
            }
            model.materials[0] = material
            wall.model = model
        }
    }

    private func makeCamera(base: PreviewCamera) -> Entity {
        let cam = controlled(base)

        let camera = Entity()
        // Ogniskowa jest STAŁA (domyślnie 47°) i zmienia się tylko w Ustawieniach —
        // wcześniej FOV zmieniał się razem z kadrem i widok „latał".
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 20000,
            fieldOfViewInDegrees: Float(settings.clampedFieldOfView)
        ))
        camera.position = cam.position
        camera.look(at: cam.target, from: cam.position, relativeTo: nil)
        return camera
    }

    /// Kamera wynikająca z danych (kadr zewnętrzny lub dopasowany do zabudowy).
    private func baseCamera(scanEntity: Entity?, built: KitchenScene.SceneBuilder.Built) -> PreviewCamera {
        if !interiorView {
            return PreviewCamera.exterior(room: room)
        }
        // Kadr wewnętrzny liczony z zabudowy, nie ze skanu — skan potrafi
        // otoczyć kamerę chmurą i zasłonić meble.
        if !built.extents.x.isZero {
            // kadr dopasowany do bryły zabudowy: kamera staje naprzeciw mebla
            // i cofa się tak, żeby cały bieg był w kadrze
            return PreviewCamera.fitting(center: built.center,
                                         extents: built.extents,
                                         room: room,
                                         verticalFOVDegrees: Float(settings.clampedFieldOfView))
        }
        if let scanEntity, scanEntity.children.count > 0 {
            return PreviewCamera.fit(center: built.center, extents: built.extents)
        }
        if !built.extents.x.isZero {
            // Kadr wewnętrzny: kamera między zabudową a przeciwległą ścianą,
            // zawsze w świetle pomieszczenia (bez patrzenia przez elewację).
            if interiorView {
                let c = built.center
                let e = built.extents
                let halfW = Float(room.width / 1000) / 2 - 0.45
                let halfD = Float(room.depth / 1000) / 2 - 0.45
                let radius = max(0.001, sqrt(c.x * c.x + c.z * c.z))
                let dir = SIMD2<Float>(-c.x / radius, -c.z / radius)
                let dist = min(6.4, max(2.6, max(e.x, e.z) * 1.15 + 1.5))
                let px = min(halfW, max(-halfW, c.x + dir.x * dist))
                let pz = min(halfD, max(-halfD, c.z + dir.y * dist))
                let eyeY = min(Float(room.height / 1000) - 0.3,
                               max(1.55, c.y + 0.3))
                return PreviewCamera(position: [px, eyeY, pz],
                                     target: [c.x, max(0.6, c.y), c.z])
            }
            return PreviewCamera.fit(center: built.center, extents: built.extents)
        }
        return PreviewCamera.make(room: room, scanBounds: nil)
    }

    /// Nakłada sterowanie użytkownika na kamerę bazową.
    ///
    /// Zablokowany: przesuwamy cel i kamerę o `pan` (rzut na płaszczyznę XZ).
    /// Odblokowany: obracamy kamerę wokół celu o `yaw`/`pitch`, z odległością
    /// pomnożoną przez `distanceScale` (pinch).
    /// Krok kamery liczony co klatkę: bezwładność po puszczeniu palca
    /// i wygładzanie (lerp) do celu. Bez tego ruch „skacze" na 120 Hz ekranie.
    private func stepCamera() {
        let now = Date()
        let dt = Float(min(0.05, now.timeIntervalSince(cache.lastFrame)))
        cache.lastFrame = now
        guard dt > 0 else { return }

        // bezwładność: puszczony palec jeszcze chwilę „wiezie" widok
        if simd_length(cache.panVelocity) > 0.0004 {
            cache.panTarget += cache.panVelocity
            cache.panTarget.x = min(120, max(-120, cache.panTarget.x))
            cache.panTarget.y = min(120, max(-120, cache.panTarget.y))
            cache.panVelocity *= pow(0.06, dt)     // tłumienie ~6 % na sekundę
        } else {
            cache.panVelocity = .zero
        }
        if abs(cache.yawVelocity) > 0.0004 {
            cache.yawTarget += cache.yawVelocity
            cache.yawVelocity *= pow(0.06, dt)
        } else {
            cache.yawVelocity = 0
        }

        // wygładzanie: różnica domykana w ~0,15 s, niezależnie od liczby klatek
        let k = 1 - pow(0.0001, dt)
        cache.pan += (cache.panTarget - cache.pan) * k
        cache.yaw += (cache.yawTarget - cache.yaw) * k
        cache.pitch += (cache.pitchTarget - cache.pitch) * k
        cache.zoom += (cache.zoomTarget - cache.zoom) * k
    }

    /// Tania aktualizacja samej kamery (bez przebudowy sceny).
    private func applyCameraControl(_ camera: Entity, base: PreviewCamera) {
        let cam = controlled(base)
        cache.currentCamera = cam
        camera.position = cam.position
        camera.look(at: cam.target, from: cam.position, relativeTo: nil)
        if var perspective = camera.components[PerspectiveCameraComponent.self] {
            perspective.fieldOfViewInDegrees = cam.verticalFOVDegrees
            camera.components.set(perspective)
        }
    }

    private func controlled(_ base: PreviewCamera) -> PreviewCamera {
        let pan = cache.pan
        let yaw = cache.yaw
        let pitch = cache.pitch
        let distanceScale = cache.zoom
        let target = base.target + SIMD3<Float>(pan.x, 0, pan.y)
        var position = base.position + SIMD3<Float>(pan.x, 0, pan.y)

        if yaw != 0 || pitch != 0 || distanceScale != 1 {
            let offset = position - target
            // Promień orbity mnożymy przez ustawienie użytkownika. Bez tego
            // obrót jest „lotem wokół odległego celu" — przy automatycznym
            // kadrze promień bywa większy niż samo pomieszczenie, więc palec
            // na ekranie przesuwa kamerę po wielkim łuku zamiast obracać
            // projektem w ręku.
            let orbitScale = Float(settings.clampedOrbitRadiusScale)
            let radius = max(0.5, simd_length(offset) * distanceScale * orbitScale)
            let baseYaw = atan2(offset.x, offset.z)
            let horizontal = max(0.001, sqrt(offset.x * offset.x + offset.z * offset.z))
            let basePitch = atan2(offset.y, horizontal)
            let angle = baseYaw + yaw
            let elevation = min(1.45, max(0.04, basePitch + pitch))
            position = target + SIMD3<Float>(
                radius * cos(elevation) * sin(angle),
                radius * sin(elevation),
                radius * cos(elevation) * cos(angle)
            )
        } else if distanceScale != 1 {
            position = target + (position - target) * distanceScale
        }
        return PreviewCamera(position: position, target: target, verticalFOVDegrees: base.verticalFOVDegrees)
    }

    /// Obrys chmury po transformacji (metry) — do kadrowania.
    var scanBounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let scan else { return nil }
        let k = scan.unitScaleToMeters
        let b = scan.robustBounds()
        return transform.transformedBounds(min: b.min * k, max: b.max * k)
    }
}

#if os(iOS)

/// Warstwa gestów dla sceny 3D: JEDEN palec obraca, DWA przesuwają, szczypanie zbliża.
///
/// DLACZEGO UIKit, A NIE `DragGesture`: `DragGesture` w tym SDK nie ma
/// parametrów liczby palców, więc nie da się nim rozróżnić jednego palca od
/// dwóch. Bez tego rozróżnienia obrót i przesuwanie uruchamiały się naraz —
/// projekt kręcił się i jednocześnie uciekał w bok (zgłoszony „wariujący obrót").
/// `UIPanGestureRecognizer` ma `minimumNumberOfTouches`/`maximumNumberOfTouches`
/// wprost, więc reguła jest jednoznaczna.
struct CameraGestureLayer: UIViewRepresentable {
    var onRotate: (Float, Float) -> Void
    var onPan: (Float, Float) -> Void
    var onZoom: (Float) -> Void
    var onEndRotate: (Float) -> Void
    var onEndPan: (Float, Float) -> Void
    var onTap: (CGPoint, CGSize) -> Void = { _, _ in }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        // JEDEN palec → obrót
        let rotate = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotate(_:))
        )
        rotate.minimumNumberOfTouches = 1
        rotate.maximumNumberOfTouches = 1
        view.addGestureRecognizer(rotate)

        // DWA palce → przesuwanie
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        // szczypanie → zbliżenie (jednocześnie z przesuwaniem, jak w mapach)
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        // pojedyncze dotknięcie → zaznaczenie elementu
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        // Szczypanie MUSI działać równolegle z przesuwaniem dwoma palcami.
        // Wcześniej `pinch.require(toFail: pan)` przy panie na 2 palce
        // blokowało pinch na zawsze — stąd „nie ma przybliżania".
        pinch.delegate = context.coordinator
        pan.delegate = context.coordinator

        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraGestureLayer

        /// Dwa palce = jednocześnie przesuwanie i szczypanie (jak w Mapach).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
        init(parent: CameraGestureLayer) { self.parent = parent }

        @objc func handleRotate(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            let v = g.velocity(in: g.view)
            switch g.state {
            case .changed:
                parent.onRotate(Float(t.x), Float(t.y))
                // zerujemy, żeby liczyć przyrosty, a nie sumę od początku
                g.setTranslation(.zero, in: g.view)
            case .ended, .cancelled:
                parent.onEndRotate(Float(v.x))
            default: break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            let v = g.velocity(in: g.view)
            switch g.state {
            case .changed:
                parent.onPan(Float(t.x), Float(t.y))
                g.setTranslation(.zero, in: g.view)
            case .ended, .cancelled:
                parent.onEndPan(Float(v.x), Float(v.y))
            default: break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            let p = g.location(in: g.view)
            guard let size = g.view?.bounds.size, size.width > 0, size.height > 0 else { return }
            parent.onTap(CGPoint(x: p.x / size.width, y: p.y / size.height), size)
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed else { return }
            parent.onZoom(Float(g.scale))
            g.scale = 1
        }
    }
}

/// Przechwytywanie dotknięć nad sceną 3D (RealityView sam nie zwraca punktu ekranu).
struct TapCatcher: UIViewRepresentable {
    var onTap: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = TapView()
        view.backgroundColor = .clear
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? TapView)?.onTap = onTap
    }

    final class TapView: UIView {
        var onTap: ((CGPoint, CGSize) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handle(_:)))
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) nie jest używany") }

        @objc private func handle(_ gesture: UITapGestureRecognizer) {
            let p = gesture.location(in: self)
            let size = bounds.size
            guard size.width > 0, size.height > 0 else { return }
            onTap?(CGPoint(x: p.x / size.width, y: p.y / size.height), size)
        }
    }
}
#endif
