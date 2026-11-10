import SwiftUI
import RealityKit
import KitchenCore

#if os(iOS)
typealias PlatformColor = UIColor
#else
typealias PlatformColor = NSColor
#endif

/// Podgląd 3D na RealityKit: bryły z KitchenCore (mm) → encje w metrach.
struct SceneView: View {
    let cabinets: [Cabinet]

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.position = [0, 0, 0]

            let runs = Runs.compute(cabinets)
            var boxes: [Box] = []
            for c in cabinets { boxes += Generator.build(c) }
            boxes += Runs.worktops(runs)
            boxes += Runs.contacts(runs)

            for b in boxes {
                let mesh = MeshResource.generateBox(
                    width: Float(b.size.x / 1000),
                    height: Float(b.size.y / 1000),
                    depth: Float(b.size.z / 1000),
                    cornerRadius: 0.002
                )
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: PlatformColor.from(hex: b.color))
                material.roughness = .init(floatLiteral: b.role == .plinth ? 0.95 : 0.55)
                material.metallic = .init(floatLiteral: 0)

                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.position = [
                    Float(b.position.x / 1000),
                    Float(b.position.y / 1000),
                    Float(b.position.z / 1000),
                ]
                if b.rotationY != 0 { entity.orientation = simd_quatf(angle: Float(b.rotationY * .pi / 180), axis: [0, 1, 0]) }
                root.addChild(entity)
            }

            // podłoga i światło
            let floor = ModelEntity(
                mesh: .generateBox(width: 6, height: 0.02, depth: 6),
                materials: [SimpleMaterial(color: .init(red: 0.78, green: 0.70, blue: 0.58, alpha: 1), isMetallic: false)]
            )
            floor.position = [0, -0.01, 0]
            root.addChild(floor)

            content.add(root)

            var sun = DirectionalLightComponent()
            sun.intensity = 3500
            sun.color = .init(red: 1, green: 0.96, blue: 0.9, alpha: 1)
            let sunEntity = Entity()
            sunEntity.components.set(sun)
            sunEntity.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
            content.add(sunEntity)
        }
        .background(Color(white: 0.93))
    }
}

extension Runs {
    /// Wersja zbiorcza dla sceny (blat + cokół).
    static func contacts(_ runs: [Run]) -> [Box] { plinths(runs) }
}

extension PlatformColor {
    static func from(hex: String) -> PlatformColor {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .gray }
        return PlatformColor(
            red: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: 1
        )
    }
}
