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
    /// true = projekt zablokowany: przeciąganie PRZESUWA widok.
    /// false = odblokowany: przeciąganie OBRACA projekt wokół celu.
    var locked: Bool = true

    /// Stan kamery niezależny od modelu: przesunięcie celu (m), obrót i zbliżenie.
    // Kamera trzymana poza @State: modyfikowana co klatkę (płynność), bez
    // wywoływania przebudowy SwiftUI 60 razy na sekundę.
    @State private var lastDragStart = CGPoint.zero
    @State private var lastDrag: CGSize = .zero

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
        var cabinetFocus: SIMD3<Float>?
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
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil, scanPlan: scanPlan, scanCloud: showScanCloud))
            if showEnvironment, scan == nil {
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
            content.add(cabinetRoot)
            let scanEntity = scanEntityToAdd()
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
                if let camera = cache.camera, let base = cache.fitted {
                    applyCameraControl(camera, base: base)
                }
                if let environment = cache.environment, let camera = cache.camera {
                    DetailLOD.update(root: environment, cameraPosition: camera.position(relativeTo: nil))
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
                content.add(SceneBuilder.buildRoom(room, walls: scan == nil, scanPlan: scanPlan, scanCloud: showScanCloud))
                if showEnvironment, scan == nil {
                    let environment = EnvironmentBuilder.makeEntity(room: room)
                    cache.environment = environment
                    content.add(environment)
                }
                if showScanCloud, let scanPlan {
                content.add(ScanCloudOverlay.entity(plan: scanPlan))
            }
            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
                content.add(built.root)
                let scanEntity = scanEntityToAdd()
                if let scanEntity { content.add(scanEntity) }

                let base = baseCamera(scanEntity: scanEntity, built: built)
                cache.fitted = base
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
        .simultaneousGesture(cameraDrag)
        #if os(iOS)
        .simultaneousGesture(cameraZoom)
        #endif
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Podpis danych sceny — tani do policzenia, zmienia się tylko przy realnych zmianach.
    private var sceneSignature: Int {
        var hasher = Hasher()
        hasher.combine(room.width); hasher.combine(room.depth); hasher.combine(room.height)
        hasher.combine(cabinets.count)
        for cabinet in cabinets {
            hasher.combine(cabinet.id)
            hasher.combine(cabinet.x); hasher.combine(cabinet.z)
            hasher.combine(cabinet.width); hasher.combine(cabinet.height); hasher.combine(cabinet.depth)
        }
        hasher.combine(showEnvironment)
        hasher.combine(interiorView)
        hasher.combine(scan != nil)
        hasher.combine(surfaceEntity != nil)
        hasher.combine(showPoints)
        hasher.combine(transform.scale); hasher.combine(transform.rotationDeg); hasher.combine(transform.offset.x); hasher.combine(transform.offset.z)
        return hasher.finalize()
    }

    // MARK: - sterowanie kamerą

    /// Zablokowany: przesuwanie widoku (góra/dół/lewo/prawo).
    /// Odblokowany: obrót projektu wokół celu (yaw + pochylenie).
    private var cameraDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = Float(value.translation.width - lastDrag.width)
                let dy = Float(value.translation.height - lastDrag.height)
                lastDrag = value.translation
                if locked {
                    // przesunięcie w metrach, proporcjonalne do skali sceny
                    let speed: Float = interiorView ? 0.006 : 0.05
                    cache.panTarget.x = min(120, max(-120, cache.panTarget.x - dx * speed))
                    cache.panTarget.y = min(120, max(-120, cache.panTarget.y - dy * speed))
                    // prędkość do „dogonienia" po puszczeniu palca
                    cache.panVelocity = SIMD2(-dx * speed, -dy * speed) * 0.55
                } else {
                    cache.yawTarget -= dx * 0.006
                    cache.pitchTarget = min(1.15, max(-0.35, cache.pitchTarget + dy * 0.004))
                    cache.yawVelocity = -dx * 0.006 * 0.5
                }
            }
            .onEnded { _ in
                lastDrag = .zero
            }
    }

    #if os(iOS)
    /// Zbliżenie: pinch zmienia odległość kamery od celu.
    private var cameraZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // wykładniczo i z czułością z Ustawień — brak „latania" przy szczypaniu
                let factor = pow(1 / Float(max(0.2, value.magnification)), Float(settings.zoomSensitivity))
                cache.zoomTarget = min(2.6, max(0.35, cache.zoomTarget * factor))
            }
    }
    #endif

    /// Encja skanu: gotowa powierzchnia albo chmura punktów.
    @MainActor
    private func scanEntityToAdd() -> Entity? {
        if let surfaceEntity, !showPoints { return surfaceEntity }
        if let scan { return PointCloudRenderer.makeEntity(scan, transform: transform) }
        return nil
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
                let dist = min(4.6, max(2.2, max(e.x, e.z) * 1.1 + 1.3))
                let px = min(halfW, max(-halfW, c.x + dir.x * dist))
                let pz = min(halfD, max(-halfD, c.z + dir.y * dist))
                let eyeY = min(Float(room.height / 1000) - 0.25,
                               max(1.5, c.y + e.y * 0.75))
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
            let radius = max(0.5, simd_length(offset) * distanceScale)
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
