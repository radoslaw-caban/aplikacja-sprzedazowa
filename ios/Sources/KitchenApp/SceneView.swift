import SwiftUI
import RealityKit
import KitchenCore
import KitchenScene

/// Podgląd 3D: cała budowa sceny siedzi w KitchenScene.SceneBuilder —
/// tutaj tylko SwiftUI i cykl życia widoku.
struct SceneView: View {
    let cabinets: [Cabinet]

    var body: some View {
        RealityView { content in
            let built = SceneBuilder.build(cabinets: cabinets)
            content.add(built.root)
            content.add(SceneBuilder.sunlight())
        } update: { content in
            content.entities.removeAll()
            let built = SceneBuilder.build(cabinets: cabinets)
            content.add(built.root)
            content.add(SceneBuilder.sunlight())
        }
        .background(Color(white: 0.93))
    }
}
