import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene

/// Podgląd 3D: budowa sceny w KitchenScene.SceneBuilder,
/// tutaj kamera, światło i obsługa obrotu/powierzchni.
struct SceneView: View {
    let cabinets: [Cabinet]

    var body: some View {
        RealityView { content in
            content.add(SceneBuilder.sunlight())

            let built = SceneBuilder.build(cabinets: cabinets)
            content.add(built.root)

            // kamera: wysokość oczu, patrzy na środek zabudowy
            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent(
                near: 0.02,
                far: 200,
                fieldOfViewInDegrees: 55
            ))
            camera.position = [0, 1.55, 3.4]
            camera.look(at: [0, 0.75, -1.6], from: camera.position, relativeTo: nil)
            content.add(camera)
            content.camera = .virtual
        } update: { content in
            content.entities.removeAll()
            content.add(SceneBuilder.sunlight())
            let built = SceneBuilder.build(cabinets: cabinets)
            content.add(built.root)
        }
        .realityViewCameraControls(.orbit)
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
    }
}
