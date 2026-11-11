import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene

/// Podgląd 3D: budowa sceny w KitchenScene.SceneBuilder,
/// tutaj kamera, światło i obsługa obrotu/powierzchni.
struct SceneView: View {
    let cabinets: [Cabinet]
    var room = Room()
    var scan: PointCloud?
    var transform = ScanTransform()
    /// gotowa powierzchnia skanu (woksele) — budowana raz, nie w każdym odświeżeniu
    var surfaceEntity: ScanSurface?
    /// pokaż chmurę punktów zamiast powierzchni
    var showPoints = false

    var body: some View {
        RealityView { content in
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil))
            content.add(SceneBuilder.build(cabinets: cabinets, includeFloor: false).root)

            if let surfaceEntity, !showPoints {
                content.add(surfaceEntity)
            } else if let scan {
                content.add(PointCloudRenderer.makeEntity(scan, transform: transform))
            }

            content.add(Self.cameraEntity(room: room, scan: scan, transform: transform))
            content.camera = .virtual
        } update: { content in
            content.entities.removeAll()
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room, walls: scan == nil))
            content.add(SceneBuilder.build(cabinets: cabinets, includeFloor: false).root)
            if let surfaceEntity, !showPoints {
                content.add(surfaceEntity)
            } else if let scan {
                content.add(PointCloudRenderer.makeEntity(scan, transform: transform))
            }
            content.add(Self.cameraEntity(room: room, scan: scan, transform: transform))
            content.camera = .virtual
        }
        .realityViewCameraControls(.orbit)
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Kamera: kadruje skan, jeśli jest; inaczej pokój. Zawsze na wysokości oczu.
    static func cameraEntity(room: Room = Room(), scan: PointCloud? = nil, transform: ScanTransform = ScanTransform()) -> Entity {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 200,
            fieldOfViewInDegrees: 55
        ))
        if let scan {
            // kadr na obrys chmury: cofamy się o 1,6 × największy wymiar w rzucie
            let k = scan.unitScaleToMeters
            let b = scan.robustBounds()
            let t = transform.transformedBounds(min: b.min * k, max: b.max * k)
            let cx = (t.min.x + t.max.x) / 2
            let cz = (t.min.z + t.max.z) / 2
            let spanX = t.max.x - t.min.x
            let spanZ = t.max.z - t.min.z
            // kamera MUSI zostać w pomieszczeniu: narożnik + spojrzenie na środek
            let roomHalfX = Float(room.width / 2000) - 0.45
            let roomHalfZ = Float(room.depth / 2000) - 0.45
            let eyeY = min(Float(room.height / 1000) - 0.35, max(1.5, t.min.y + (t.max.y - t.min.y) * 0.5))
            let px = max(-roomHalfX, min(roomHalfX, cx + spanX * 0.30))
            let pz = max(-roomHalfZ, min(roomHalfZ, cz + spanZ * 0.55))
            camera.position = [px, min(eyeY + 0.25, Float(room.height / 1000) - 0.3), pz]
            camera.look(at: [cx, t.min.y + 1.0, cz], from: camera.position, relativeTo: nil)
        } else {
            let halfDepth = Float(room.depth / 2000)
            camera.position = [0, 1.65, halfDepth * 0.62]
            camera.look(at: [0, 1.0, -halfDepth * 0.6], from: camera.position, relativeTo: nil)
        }
        return camera
    }
}
