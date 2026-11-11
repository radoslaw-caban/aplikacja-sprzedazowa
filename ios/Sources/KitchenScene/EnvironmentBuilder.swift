import Foundation
import CoreGraphics
import RealityKit
import KitchenCore
import simd

/// Otoczenie domu: trawa, las, góry, podjazd, auto, ptaki.
///
/// Wszystko liczone deterministycznie z ziarna — ten sam krajobraz przy każdym
/// uruchomieniu, bez pobierania assetów (działa offline u klienta).
@MainActor
public enum EnvironmentBuilder {

    public struct Options: Sendable {
        public var radius: Float = 120          // promień terenu (m)
        public var forestTrees: Int = 220
        public var mountains: Int = 26
        public var birds: Int = 6
        public var seed: UInt64 = 20261111
        public init() {}
    }

    // MARK: - liczby losowe (deterministyczne)

    struct RNG {
        var state: UInt64
        init(_ seed: UInt64) { state = seed == 0 ? 1 : seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    }

    // MARK: - scena

    /// Całe otoczenie domu: dom stoi w środku, wjazd od strony +Z.
    public static func makeEntity(room: Room, options: Options = Options()) -> Entity {
        let root = Entity()
        root.name = "environment"
        var rng = RNG(options.seed)

        root.addChild(sky(radius: 7000))
        root.addChild(ground(radius: options.radius))
        root.addChild(mountainRange(options: options, rng: &rng))
        root.addChild(forest(options: options, rng: &rng, room: room))
        root.addChild(driveway(room: room))
        root.addChild(car(position: SIMD3(0, 0, Float(room.depth / 2000) + 7)))
        root.addChild(birds(options: options, rng: &rng))
        return root
    }

    // MARK: - elementy

    /// Tekstura gradientu nieba: błękit u góry, ciepła mgła przy horyzoncie.
    static func skyGradientTexture() -> TextureResource? {
        let size = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 1, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [
            CGColor(red: 0.29, green: 0.52, blue: 0.82, alpha: 1),
            CGColor(red: 0.47, green: 0.66, blue: 0.88, alpha: 1),
            CGColor(red: 0.78, green: 0.85, blue: 0.90, alpha: 1),
            CGColor(red: 0.92, green: 0.91, blue: 0.86, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.45, 0.72, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Niebo: kula widziana od środka, z gradientem od błękitu do mgły.
    static func sky(radius: Float) -> Entity {
        let root = Entity()
        root.name = "sky"

        var upper = UnlitMaterial()
        if let texture = skyGradientTexture() {
            upper.color = .init(tint: .white, texture: .init(texture))
        } else {
            upper.color = .init(tint: PlatformColor(red: 0.47, green: 0.66, blue: 0.88, alpha: 1))
        }
        upper.faceCulling = .none
        var lower = UnlitMaterial(color: PlatformColor(red: 0.86, green: 0.89, blue: 0.85, alpha: 1))
        lower.faceCulling = .none

        let domeTop = ModelEntity(mesh: .generateSphere(radius: radius), materials: [upper])
        domeTop.scale = [1, 1, 1]
        domeTop.position = [0, 0, 0]
        root.addChild(domeTop)

        // dolna „mgła" — mniejsza kula, żeby horyzont nie był ostry
        let haze = ModelEntity(mesh: .generateSphere(radius: radius * 0.98), materials: [lower])
        haze.position = [0, -radius * 0.35, 0]
        root.addChild(haze)
        return root
    }

    static func ground(radius: Float) -> Entity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(red: 0.36, green: 0.46, blue: 0.26, alpha: 1))
        material.roughness = .init(floatLiteral: 0.95)
        material.metallic = .init(floatLiteral: 0)
        let mesh = MeshResource.generateCylinder(height: 0.4, radius: radius)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = [0, -0.2, 0]
        entity.name = "ground"
        return entity
    }

    static func mountainRange(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "mountains"
        for i in 0..<options.mountains {
            let angle = Float(i) / Float(options.mountains) * .pi * 2 + rng.range(-0.1, 0.1)
            // góry jako tło: kilka kilometrów dalej, żeby były małe kątowo
            let distance = rng.range(6000, 9000)
            let height = rng.range(700, 1500)
            let base = height * rng.range(1.4, 2.2)

            // stożek = góra; im dalej, tym bledsza (perspektywa powietrzna)
            let fade = 1 - min(1, distance / 9000)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: PlatformColor(
                red: CGFloat(Double(0.58 + 0.16 * (1 - fade))),
                green: CGFloat(Double(0.64 + 0.15 * (1 - fade))),
                blue: CGFloat(Double(0.74 + 0.12 * (1 - fade))),
                alpha: 1
            ))
            material.roughness = .init(floatLiteral: 0.95)

            let cone = ModelEntity(
                mesh: .generateCone(height: height, radius: base / 2),
                materials: [material]
            )
            cone.position = [cos(angle) * distance, height / 2 - 1, sin(angle) * distance]
            cone.name = "mountain-\(i)"
            root.addChild(cone)

            if height > 500 {
                var snow = PhysicallyBasedMaterial()
                snow.baseColor = .init(tint: PlatformColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1))
                snow.roughness = .init(floatLiteral: 0.8)
                let capHeight = height * 0.26
                let cap = ModelEntity(
                    mesh: .generateCone(height: capHeight, radius: base * 0.28),
                    materials: [snow]
                )
                cap.position = [cone.position.x, height - 1 - capHeight / 2 + 1, cone.position.z]
                root.addChild(cap)
            }
        }
        return root
    }

    static func forest(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "forest"

        var trunkMaterial = PhysicallyBasedMaterial()
        trunkMaterial.baseColor = .init(tint: PlatformColor(red: 0.24, green: 0.17, blue: 0.11, alpha: 1))
        trunkMaterial.roughness = .init(floatLiteral: 0.95)

        let leavesMaterials: [PhysicallyBasedMaterial] = (0..<3).map { i in
            var m = PhysicallyBasedMaterial()
            let g = 0.26 + Double(i) * 0.06
            m.baseColor = .init(tint: PlatformColor(red: 0.10, green: CGFloat(g), blue: 0.13, alpha: 1))
            m.roughness = .init(floatLiteral: 1.0)
            m.metallic = .init(floatLiteral: 0)
            return m
        }

        let houseRadius = max(Float(room.width), Float(room.depth)) / 2000 + 12
        var placed = 0
        var guardCount = 0
        while placed < options.forestTrees && guardCount < options.forestTrees * 6 {
            guardCount += 1
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(houseRadius + 2, options.radius * 0.85)
            let x = cos(angle) * distance
            let z = sin(angle) * distance
            // nie sadzimy na podjeździe (pas szerokości 6 m wzdłuż +Z)
            if abs(x) < 9 && z > 0 { continue }   // pas podjazdu i trawnika przed domem

            let height = rng.range(5.5, 12)
            let trunk = ModelEntity(
                mesh: .generateCylinder(height: height * 0.34, radius: height * 0.028),
                materials: [trunkMaterial]
            )
            trunk.position = [x, height * 0.17, z]

            let tree = Entity()
            tree.addChild(trunk)
            for tier in 0..<3 {
                let tierHeight = height * (0.42 - Float(tier) * 0.08)
                let radius = height * (0.20 - Float(tier) * 0.05)
                let cone = ModelEntity(
                    mesh: .generateCone(height: tierHeight, radius: max(0.4, radius)),
                    materials: [leavesMaterials[tier]]
                )
                cone.position = [0, height * (0.30 + Float(tier) * 0.22), 0]
                tree.addChild(cone)
            }
            tree.position = [x, 0, z]
            tree.name = "tree-\(placed)"
            root.addChild(tree)
            placed += 1
        }
        return root
    }

    static func driveway(room: Room) -> Entity {
        let root = Entity()
        root.name = "driveway"
        let halfDepth = Float(room.depth / 2000)
        let length: Float = 26

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(red: 0.44, green: 0.43, blue: 0.41, alpha: 1))
        material.roughness = .init(floatLiteral: 0.85)

        let slab = ModelEntity(
            mesh: .generateBox(width: 5.5, height: 0.12, depth: length, cornerRadius: 0.02),
            materials: [material]
        )
        slab.position = [0, 0.05, halfDepth + length / 2]
        root.addChild(slab)

        // krawężniki
        let kerbMaterial = SimpleMaterial(color: .init(red: 0.55, green: 0.54, blue: 0.52, alpha: 1), isMetallic: false)
        for side in [-1.0 as Float, 1.0] {
            let kerb = ModelEntity(
                mesh: .generateBox(width: 0.25, height: 0.18, depth: length, cornerRadius: 0.01),
                materials: [kerbMaterial]
            )
            kerb.position = [side * 2.9, 0.09, halfDepth + length / 2]
            root.addChild(kerb)
        }
        return root
    }

    /// Auto stojące na podjeździe (proste bryły, czytelne z odległości).
    static func car(position: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.name = "car"

        var bodyMaterial = PhysicallyBasedMaterial()
        bodyMaterial.baseColor = .init(tint: PlatformColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1))
        bodyMaterial.roughness = .init(floatLiteral: 0.35)
        bodyMaterial.metallic = .init(floatLiteral: 0.5)

        var glassMaterial = PhysicallyBasedMaterial()
        glassMaterial.baseColor = .init(tint: PlatformColor(red: 0.15, green: 0.20, blue: 0.26, alpha: 1))
        glassMaterial.roughness = .init(floatLiteral: 0.1)
        glassMaterial.metallic = .init(floatLiteral: 0.2)

        let body = ModelEntity(
            mesh: .generateBox(width: 1.85, height: 0.65, depth: 4.4, cornerRadius: 0.12),
            materials: [bodyMaterial]
        )
        body.position = [0, 0.62, 0]

        let cabin = ModelEntity(
            mesh: .generateBox(width: 1.62, height: 0.55, depth: 2.2, cornerRadius: 0.16),
            materials: [glassMaterial]
        )
        cabin.position = [0, 1.16, -0.15]

        root.addChild(body)
        root.addChild(cabin)

        let tyreMaterial = SimpleMaterial(color: .init(red: 0.08, green: 0.08, blue: 0.09, alpha: 1), isMetallic: false)
        let rimMaterial = SimpleMaterial(color: .init(red: 0.7, green: 0.72, blue: 0.75, alpha: 1), isMetallic: true)
        for (dx, dz) in [(0.82 as Float, 1.45 as Float), (-0.82, 1.45), (0.82, -1.45), (-0.82, -1.45)] {
            let tyre = ModelEntity(
                mesh: .generateCylinder(height: 0.22, radius: 0.34),
                materials: [tyreMaterial]
            )
            tyre.position = [dx, 0.34, dz]
            tyre.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            root.addChild(tyre)

            let rim = ModelEntity(
                mesh: .generateCylinder(height: 0.23, radius: 0.18),
                materials: [rimMaterial]
            )
            rim.position = [dx, 0.34, dz]
            rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            root.addChild(rim)
        }

        root.position = position
        return root
    }

    /// Ptaki: proste skrzydła, krążą nad domem (animacja w pętli).
    static func birds(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "birds"
        for i in 0..<options.birds {
            let bird = Entity()
            let bodyMaterial = SimpleMaterial(color: .init(red: 0.12, green: 0.12, blue: 0.14, alpha: 1), isMetallic: false)

            let body = ModelEntity(mesh: .generateBox(width: 0.18, height: 0.12, depth: 0.5), materials: [bodyMaterial])
            bird.addChild(body)

            let wingLeft = ModelEntity(mesh: .generateBox(width: 0.55, height: 0.04, depth: 0.16), materials: [bodyMaterial])
            wingLeft.position = [0.33, 0, 0]
            let wingRight = ModelEntity(mesh: .generateBox(width: 0.55, height: 0.04, depth: 0.16), materials: [bodyMaterial])
            wingRight.position = [-0.33, 0, 0]
            bird.addChild(wingLeft)
            bird.addChild(wingRight)

            let radius = rng.range(22, 55)
            let height = rng.range(14, 26)
            let startAngle = rng.range(0, .pi * 2)
            bird.position = [cos(startAngle) * radius, height, sin(startAngle) * radius]
            bird.scale = .one * rng.range(0.9, 1.6)
            bird.name = "bird-\(i)"
            root.addChild(bird)

            // lot po okręgu: 8 odcinków w pętli (każdy osobna animacja)
            Task { @MainActor in
                var angle = startAngle
                while !Task.isCancelled {
                    angle += .pi / 4
                    let next = SIMD3<Float>(cos(angle) * radius, height, sin(angle) * radius)
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    await bird.move(to: Transform(translation: next), relativeTo: bird.parent, duration: 3.5, timingFunction: .linear)
                }
            }

            // skrzydła: machanie przez skalowanie w pionie
            var flap = wingLeft.transform
            flap.scale = [1, 1.8, 1]
            let flapUp = FromToByAnimation<Transform>(from: wingLeft.transform, to: flap, duration: 0.32, timing: .linear, isAdditive: false)
            if let resource = try? AnimationResource.generate(with: flapUp) {
                wingLeft.playAnimation(resource.repeat(count: 0))
                wingRight.playAnimation(resource.repeat(count: 0))
            }
        }
        return root
    }
}
