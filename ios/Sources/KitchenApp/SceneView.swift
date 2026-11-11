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
    /// tryb wskazywania punktów skanu
    var picking = false
    /// znormalizowany punkt ekranu (0…1) po dotknięciu
    var onPick: ((CGPoint, CGSize) -> Void)?
    /// true = projekt zablokowany: przeciąganie PRZESUWA widok.
    /// false = odblokowany: przeciąganie OBRACA projekt wokół celu.
    var locked: Bool = true

    /// Stan kamery niezależny od modelu: przesunięcie celu (m), obrót i zbliżenie.
    @State private var pan = SIMD2<Float>.zero
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var distanceScale: Float = 1
    @State private var lastDrag: CGSize = .zero

    /// Cache sceny: przebudowujemy ją TYLKO gdy zmienią się dane.
    /// Wcześniej `update:` kasowało i budowało całe otoczenie przy KAŻDEJ
    /// zmianie stanu (także przy każdym ruchu kamery) — stąd 1 klatka na sekundy.
    final class SceneCache {
        var signature: Int = .min
        var camera: Entity?
        var environment: Entity?
        var fitted: PreviewCamera?
        var cabinetFocus: SIMD3<Float>?
    }
    @State private var cache = SceneCache()

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
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil, scanPlan: scanPlan))
            if showEnvironment, scan == nil {
                let environment = EnvironmentBuilder.makeEntity(room: room)
                cache.environment = environment
                content.add(environment)
            }
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
                content.add(SceneBuilder.buildRoom(room, walls: scan == nil, scanPlan: scanPlan))
                if showEnvironment, scan == nil {
                    let environment = EnvironmentBuilder.makeEntity(room: room)
                    cache.environment = environment
                    content.add(environment)
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
                    pan.x -= dx * speed
                    pan.y -= dy * speed
                    pan.x = min(120, max(-120, pan.x))
                    pan.y = min(120, max(-120, pan.y))
                } else {
                    yaw -= dx * 0.006
                    pitch = min(1.15, max(-0.35, pitch + dy * 0.004))
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
                let next = distanceScale / Float(value.magnification)
                distanceScale = min(3.0, max(0.25, next))
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
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 20000,
            fieldOfViewInDegrees: cam.verticalFOVDegrees
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
            return PreviewCamera.fit(center: built.center, extents: built.extents)
        }
        return PreviewCamera.make(room: room, scanBounds: nil)
    }

    /// Nakłada sterowanie użytkownika na kamerę bazową.
    ///
    /// Zablokowany: przesuwamy cel i kamerę o `pan` (rzut na płaszczyznę XZ).
    /// Odblokowany: obracamy kamerę wokół celu o `yaw`/`pitch`, z odległością
    /// pomnożoną przez `distanceScale` (pinch).
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
