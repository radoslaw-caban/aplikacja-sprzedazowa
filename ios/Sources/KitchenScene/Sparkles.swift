import Foundation
import RealityKit
import KitchenCore

/// Magiczne gwiazdki podglądu strefy — małe, świecące kulki na froncie cienia
/// szafek, migające w rytmie sinusa. Aktualizacja co klatkę w SceneView.
public enum Sparkles {

    @MainActor
    public static func entity(cabinets: [Cabinet]) -> Entity {
        let root = Entity()
        root.name = "sparkles"
        let preview = cabinets.filter { $0.preview == true }
        guard !preview.isEmpty else { return root }

        let mesh = MeshResource.generateSphere(radius: 0.007)
        let material = UnlitMaterial(color: PlatformColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 1.0))

        for c in preview {
            let count = max(6, Int(c.width / 90))
            let rad = c.rotation * .pi / 180
            let front = SIMD2<Double>(sin(rad), cos(rad))   // lokalne +Z
            let right = SIMD2<Double>(cos(rad), -sin(rad))  // lokalne +X
            for _ in 0..<count {
                let u = Double.random(in: (-c.width / 2 + 50)...(c.width / 2 - 50))
                let y = Double.random(in: 120...max(220, c.height - 80))
                let d = c.depth / 2 + 40
                let x = c.x + front.x * d + right.x * u
                let z = c.z + front.y * d + right.y * u
                let phase = Double.random(in: 0...6.283)
                let speed = Double.random(in: 1.1...3.0)

                let star = ModelEntity(mesh: mesh, materials: [material])
                star.position = [
                    Float(x / 1000),
                    Float(y / 1000),
                    Float(z / 1000),
                ]
                star.name = "sparkle:\(phase):\(speed)"
                star.scale = SIMD3<Float>(repeating: 0.2)
                root.addChild(star)
            }
        }
        return root
    }

    /// Mruganie: skala 0,2–1,5 zależnie od fazy i czasu.
    @MainActor
    public static func update(root: Entity, time: Float) {
        for child in root.children {
            let parts = child.name.split(separator: ":")
            guard parts.count == 3,
                  parts[0] == "sparkle",
                  let phase = Double(parts[1]),
                  let speed = Double(parts[2]) else { continue }
            let s = 0.2 + 1.3 * Float(abs(sin(Double(time) * speed + phase)))
            child.scale = SIMD3<Float>(repeating: s)
        }
    }
}
