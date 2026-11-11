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

    var body: some View {
        RealityView { content in
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room))
            content.add(SceneBuilder.build(cabinets: cabinets, includeFloor: false).root)

            if let scan {
                content.add(PointCloudRenderer.makeEntity(scan, transform: transform))
            }

            content.add(Self.cameraEntity(room: room))
            content.camera = .virtual
        } update: { content in
            content.entities.removeAll()
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.buildRoom(room))
            content.add(SceneBuilder.build(cabinets: cabinets, includeFloor: false).root)
            if let scan {
                content.add(PointCloudRenderer.makeEntity(scan, transform: transform))
            }
            content.add(Self.cameraEntity(room: room))
            content.camera = .virtual
        }
        .realityViewCameraControls(.orbit)
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Kamera: wewnątrz pokoju, na wysokości oczu, patrzy na ścianę z zabudową.
    static func cameraEntity(room: Room = Room()) -> Entity {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 200,
            fieldOfViewInDegrees: 55
        ))
        let halfDepth = Float(room.depth / 2000)
        let halfWidth = Float(room.width / 2000)
        camera.position = [0, 1.65, halfDepth * 0.62]
        camera.look(at: [0, 1.0, -halfDepth * 0.6], from: camera.position, relativeTo: nil)
        _ = halfWidth
        return camera
    }
}
