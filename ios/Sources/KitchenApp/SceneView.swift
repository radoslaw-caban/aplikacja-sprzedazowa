import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene

/// Podgląd 3D: budowa sceny w KitchenScene.SceneBuilder,
/// tutaj kamera, światło i obsługa obrotu/powierzchni.
struct SceneView: View {
    let cabinets: [Cabinet]
    var scan: PointCloud?

    var body: some View {
        RealityView { content in
            content.add(SceneBuilder.sunlight())

            let built = SceneBuilder.build(cabinets: cabinets, includeFloor: scan == nil)
            content.add(built.root)

            if let scan {
                content.add(PointCloudRenderer.makeEntity(scan))
            }

            content.add(Self.cameraEntity())
            content.camera = .virtual
        } update: { content in
            content.entities.removeAll()
            content.add(SceneBuilder.sunlight())
            content.add(SceneBuilder.build(cabinets: cabinets, includeFloor: scan == nil).root)
            if let scan {
                content.add(PointCloudRenderer.makeEntity(scan))
            }
            content.add(Self.cameraEntity())
            content.camera = .virtual
        }
        .realityViewCameraControls(.orbit)
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }

    /// Kamera: wysokość oczu, patrzy na środek zabudowy.
    static func cameraEntity() -> Entity {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02,
            far: 200,
            fieldOfViewInDegrees: 55
        ))
        camera.position = [0, 1.55, 3.4]
        camera.look(at: [0, 0.75, -1.6], from: camera.position, relativeTo: nil)
        return camera
    }
}
