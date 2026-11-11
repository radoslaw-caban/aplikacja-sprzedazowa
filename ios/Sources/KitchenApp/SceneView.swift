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
    /// tryb wskazywania punktów skanu
    var picking = false
    /// znormalizowany punkt ekranu (0…1) po dotknięciu
    var onPick: ((CGPoint, CGSize) -> Void)?

    var body: some View {
        RealityView { content in
            if let sky = await EnvironmentArt.environmentResource() {
                content.environment = .skybox(sky)
            }
            #if os(iOS)
            content.renderingEffects.depthOfField = interiorView ? .disabled : .enabled
            #endif
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil))
            if showEnvironment, scan == nil {
                content.add(EnvironmentBuilder.makeEntity(room: room))
            }
            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
            let cabinetRoot = built.root
            content.add(cabinetRoot)
            let scanEntity = scanEntityToAdd()
            if let scanEntity { content.add(scanEntity) }
            // kadr: skan, a bez skanu — zabudowa (nie cały pokój)
            let cam = makeCamera(scanEntity: scanEntity, built: built)
            content.add(cam)
            content.camera = .virtual
        } update: { content in
            content.entities.removeAll()
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil))
            if showEnvironment, scan == nil {
                content.add(EnvironmentBuilder.makeEntity(room: room))
            }
            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: false)
            let cabinetRoot = built.root
            content.add(cabinetRoot)
            let scanEntity = scanEntityToAdd()
            if let scanEntity { content.add(scanEntity) }
            // kadr: skan, a bez skanu — zabudowa (nie cały pokój)
            let cam = makeCamera(scanEntity: scanEntity, built: built)
            content.add(cam)
            content.camera = .virtual
        }
        .overlay {
            #if os(iOS)
            if picking {
                TapCatcher { point, size in onPick?(point, size) }
            }
            #endif
        }
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Encja skanu: gotowa powierzchnia albo chmura punktów.
    @MainActor
    private func scanEntityToAdd() -> Entity? {
        if let surfaceEntity, !showPoints { return surfaceEntity }
        if let scan { return PointCloudRenderer.makeEntity(scan, transform: transform) }
        return nil
    }

    private func makeCamera(scanEntity: Entity?, built: KitchenScene.SceneBuilder.Built) -> Entity {
        if !interiorView {
            // kadr zewnętrzny: dom w otoczeniu, z podjazdem i autem
            let cam = PreviewCamera.exterior(room: room)
            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent(near: 0.05, far: 9000, fieldOfViewInDegrees: cam.verticalFOVDegrees))
            camera.position = cam.position
            camera.look(at: cam.target, from: cam.position, relativeTo: nil)
            return camera
        }
        let cam: PreviewCamera
        if let scanEntity, scanEntity.children.count > 0 {
            cam = PreviewCamera.fit(center: built.center, extents: built.extents)
        } else if !built.extents.x.isZero {
            cam = PreviewCamera.fit(center: built.center, extents: built.extents)
        } else {
            cam = PreviewCamera.make(room: room, scanBounds: nil)
        }
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 9000,
            fieldOfViewInDegrees: cam.verticalFOVDegrees
        ))
        camera.position = cam.position
        camera.look(at: cam.target, from: cam.position, relativeTo: nil)
        return camera
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
