import Foundation
import CoreGraphics
import RealityKit
import KitchenCore
import simd

#if os(iOS)
import UIKit
typealias TreeColor = UIColor
#else
import AppKit
typealias TreeColor = NSColor
#endif

/// Drzewa i trawa z prawdziwej geometrii: gałęzie to zwężające się rury,
/// liście to karty z teksturą kępy liści (z przezroczystością).
///
/// DLACZEGO TAK, A NIE STOŻKI I KULE:
/// stożek i kula są czytelne tylko z daleka i wyglądają jak w grze. Realistyczne
/// drzewo poznaje się po trzech rzeczach: pniu, który się rozgałęzia, koronie
/// złożonej z wielu drobnych kęp liści i prześwitach między nimi. Dlatego
/// generujemy rozgałęzienia rekurencyjnie, a liście rozrzucamy na końcach gałęzi.
///
/// KLUCZOWE DLA WYDAJNOŚCI: całe drzewo to JEDNA scalona siatka (pień + gałęzie
/// w jednej części, liście w drugiej). 900 drzew = 900 encji, a nie 60 tys.
/// Siata i materiały są wspólne dla wszystkich instancji danego wariantu.
enum TreeFactory {

    // MARK: - budowa siatek

    public struct MeshBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        /// Karta (quad) — dla liści; `twoSided` dokłada odwrotną stronę.
        public mutating func addQuad(center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, twoSided: Bool = true) {
            let n = normalize(cross(right, up))
            let halfR = right * 0.5
            let halfU = up * 0.5
            let a = center - halfR - halfU
            let b = center + halfR - halfU
            let c = center + halfR + halfU
            let d = center - halfR + halfU
            let base = UInt32(positions.count)
            positions += [a, b, c, d]
            normals += [n, n, n, n]
            uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            if twoSided {
                let base2 = UInt32(positions.count)
                positions += [d, c, b, a]
                normals += [-n, -n, -n, -n]
                uvs += [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
                indices += [base2, base2 + 1, base2 + 2, base2, base2 + 2, base2 + 3]
            }
        }

        /// Stożek (uproszczone igliwie / korona) — wierzchołek do góry.
        public mutating func addCone(center: SIMD3<Float>, height: Float, radius: Float, sides: Int = 6) {
            let apex = center + SIMD3<Float>(0, height / 2, 0)
            let baseY = center.y - height / 2
            for i in 0..<sides {
                let a0 = Float(i) / Float(sides) * .pi * 2
                let a1 = Float(i + 1) / Float(sides) * .pi * 2
                let p0 = SIMD3<Float>(center.x + cos(a0) * radius, baseY, center.z + sin(a0) * radius)
                let p1 = SIMD3<Float>(center.x + cos(a1) * radius, baseY, center.z + sin(a1) * radius)
                let n = normalize(cross(p1 - p0, apex - p0))
                let base = UInt32(positions.count)
                positions += [p0, p1, apex]
                normals += [n, n, n]
                uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)]
                indices += [base, base + 1, base + 2]
            }
        }

        /// Zwężająca się rura (gałąź) między dwoma punktami.
        mutating func addTube(a: SIMD3<Float>, b: SIMD3<Float>, radiusA: Float, radiusB: Float, sides: Int = 5) {
            let axis = b - a
            let len = simd_length(axis)
            guard len > 1e-4 else { return }
            let dir = axis / len
            // dowolny wektor prostopadły
            let helper: SIMD3<Float> = abs(dir.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let right = normalize(cross(helper, dir))
            let up = normalize(cross(dir, right))

            let base = UInt32(positions.count)
            for i in 0..<sides {
                let angle = Float(i) / Float(sides) * .pi * 2
                let offset = right * cos(angle) + up * sin(angle)
                positions.append(a + offset * radiusA)
                positions.append(b + offset * radiusB)
                let n = normalize(offset)
                normals.append(n)
                normals.append(n)
                let u = Float(i) / Float(sides)
                uvs.append(SIMD2(u, 0))
                uvs.append(SIMD2(u, 1))
            }
            for i in 0..<sides {
                let i0 = UInt32(i * 2)
                let i1 = UInt32((i + 1) % sides * 2)
                indices += [base + i0, base + i1, base + i1 + 1,
                            base + i0, base + i1 + 1, base + i0 + 1]
            }
        }

        public func descriptor(_ name: String) -> MeshDescriptor? {
            guard !positions.isEmpty else { return nil }
            var d = MeshDescriptor(name: name)
            d.positions = MeshBuffer(positions)
            d.normals = MeshBuffer(normals)
            d.textureCoordinates = MeshBuffer(uvs)
            d.primitives = .triangles(indices)
            return d
        }
    }

    // MARK: - wariant drzewa

    struct Variant {
        let name: String
        /// pień i gałęzie — jedna siatka, materiał kory
        let trunkMesh: MeshResource
        let trunkMaterial: PhysicallyBasedMaterial
        /// liście/igliwie — karty z alfą, osobna encja (materiał nie miesza się z korą)
        let leafMesh: MeshResource?
        let leafMaterial: PhysicallyBasedMaterial?
        /// wysokość, dla której zbudowano siatkę — instancje skalują się względem niej
        let baseHeight: Float
    }

    struct RNG {
        var state: UInt64
        init(_ seed: UInt64) { state = seed == 0 ? 1 : seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
        mutating func signed(_ v: Float) -> Float { (next() * 2 - 1) * v }
    }

    // MARK: - materiały

    private static func barkMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let tex = EnvironmentArt.bark() {
            m.baseColor = .init(tint: TreeColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1), texture: .init(tex))
        } else {
            m.baseColor = .init(tint: TreeColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1))
        }
        m.roughness = .init(floatLiteral: 0.95)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    private static func leafMaterial(_ texture: TextureResource?, tint: TreeColor, roughness: Float = 0.85) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let texture {
            m.baseColor = .init(tint: tint, texture: .init(texture))
        } else {
            m.baseColor = .init(tint: tint)
        }
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        m.opacityThreshold = 0.35
        m.faceCulling = .none
        return m
    }

    // MARK: - warianty

    /// Cztery warianty: trzy liściaste (buk, dąb, brzoza) i dwa iglaste.
    /// Leniwe, budowane raz na proces.
    @MainActor private static var cache: [Variant] = []

    @MainActor static func variants() -> [Variant] {
        if !cache.isEmpty { return cache }
        let leaves = EnvironmentArt.leafCluster()
        let needles = EnvironmentArt.needleCluster()

        var built: [Variant] = []
        built.append(deciduous(seed: 11, baseHeight: 16, spread: 1.00,
                               tint: TreeColor(red: 0.55, green: 0.72, blue: 0.34, alpha: 1),
                               leaves: leaves, name: "beech"))
        built.append(deciduous(seed: 29, baseHeight: 20, spread: 1.25,
                               tint: TreeColor(red: 0.40, green: 0.60, blue: 0.28, alpha: 1),
                               leaves: leaves, name: "oak"))
        built.append(birch(seed: 47, baseHeight: 18, leaves: leaves))
        built.append(conifer(seed: 61, baseHeight: 22, needles: needles,
                             tint: TreeColor(red: 0.24, green: 0.40, blue: 0.26, alpha: 1), name: "spruce"))
        built.append(conifer(seed: 83, baseHeight: 26, needles: needles,
                             tint: TreeColor(red: 0.29, green: 0.44, blue: 0.30, alpha: 1), name: "fir"))

        cache = built
        return cache
    }

    /// Drzewo liściaste: pień rozwidla się rekurencyjnie, na końcach gałęzi
    /// siedzą kępy liści.
    private static func deciduous(
        seed: UInt64,
        baseHeight: Float,
        spread: Float,
        tint: TreeColor,
        leaves: TextureResource?,
        name: String
    ) -> Variant {
        var rng = RNG(seed)
        var trunk = MeshBuilder()
        var foliage = MeshBuilder()

        let trunkHeight = baseHeight * 0.42
        let trunkRadius = baseHeight * 0.022

        func grow(
            from start: SIMD3<Float>,
            direction: SIMD3<Float>,
            length: Float,
            radius: Float,
            depth: Int
        ) {
            let end = start + direction * length
            trunk.addTube(a: start, b: end, radiusA: radius, radiusB: radius * 0.68, sides: depth == 0 ? 7 : 5)

            // LIŚCIE WZDŁUŻ GAŁĘZI, nie tylko na czubkach — inaczej korona
            // to kilka kęp na końcach i drzewo wygląda jak palma.
            if depth >= 2 {
                let alongCount = 2 + Int(rng.range(0, 3))
                for _ in 0..<alongCount {
                    let t = rng.range(0.3, 0.85)
                    let at = start + direction * (length * t)
                    let size = baseHeight * rng.range(0.055, 0.115) * spread
                    let up = normalize(SIMD3(rng.signed(0.9), 1, rng.signed(0.9)))
                    let right = normalize(cross(up, SIMD3(rng.signed(1), rng.signed(0.4), rng.signed(1))))
                    foliage.addQuad(center: at + SIMD3(rng.signed(size), rng.signed(size), rng.signed(size)),
                                    right: right * size, up: up * size)
                }
            }

            if depth >= 3 || radius < baseHeight * 0.0022 {
                // koniec gałęzi: kępa liści z kilku kart
                let count = 6 + Int(rng.range(0, 4))
                for _ in 0..<count {
                    let size = baseHeight * rng.range(0.070, 0.130) * spread
                    let up = normalize(SIMD3(
                        rng.signed(0.5), 1, rng.signed(0.5)
                    ))
                    let right = normalize(cross(up, SIMD3(rng.signed(1), 0.2, rng.signed(1))))
                    let center = end + SIMD3(rng.signed(size * 0.6), rng.signed(size * 0.5), rng.signed(size * 0.6))
                    foliage.addQuad(center: center, right: right * size, up: up * size)
                }
                return
            }

            let children = 2 + (rng.next() > 0.55 ? 1 : 0)
            for i in 0..<children {
                let angle = Float(i) / Float(children) * .pi * 2 + rng.signed(0.7)
                // odchylenie od osi rodzica: im wyżej, tym szerzej
                let tilt = rng.range(0.35, 0.75) + Float(depth) * 0.06
                var dir = normalize(direction + SIMD3(cos(angle) * tilt, rng.range(0.05, 0.35), sin(angle) * tilt))
                if dir.y < 0.05 { dir.y = 0.05 }
                dir = normalize(dir)
                grow(
                    from: end,
                    direction: dir,
                    length: length * rng.range(0.60, 0.78),
                    radius: radius * rng.range(0.52, 0.68),
                    depth: depth + 1
                )
            }
        }

        grow(
            from: SIMD3(0, 0, 0),
            direction: SIMD3(rng.signed(0.06), 1, rng.signed(0.06)),
            length: trunkHeight,
            radius: trunkRadius,
            depth: 0
        )

        guard let trunkDesc = trunk.descriptor("\(name)-trunk"),
              let trunkMesh = try? MeshResource.generate(from: [trunkDesc]) else {
            return Variant(name: name, trunkMesh: MeshResource.generateSphere(radius: 1),
                           trunkMaterial: barkMaterial(), leafMesh: nil, leafMaterial: nil,
                           baseHeight: baseHeight)
        }
        let leafDesc = foliage.descriptor("\(name)-leaves")
        let leafMesh = leafDesc.flatMap { try? MeshResource.generate(from: [$0]) }
        return Variant(name: name, trunkMesh: trunkMesh, trunkMaterial: barkMaterial(),
                       leafMesh: leafMesh, leafMaterial: leafMaterial(leaves, tint: tint),
                       baseHeight: baseHeight)
    }

    /// Brzoza: biały pień, cienkie gałęzie, jasna korona.
    private static func birch(seed: UInt64, baseHeight: Float, leaves: TextureResource?) -> Variant {
        var rng = RNG(seed)
        var trunk = MeshBuilder()
        var foliage = MeshBuilder()

        let trunkHeight = baseHeight * 0.55
        trunk.addTube(a: .zero, b: SIMD3(0, trunkHeight, 0),
                      radiusA: baseHeight * 0.016, radiusB: baseHeight * 0.010, sides: 6)

        let branches = 7
        for i in 0..<branches {
            let t = 0.35 + Float(i) / Float(branches) * 0.6
            let start = SIMD3(rng.signed(0.1), trunkHeight * t, rng.signed(0.1))
            let angle = rng.range(0, .pi * 2)
            let dir = normalize(SIMD3(cos(angle) * 0.75, 0.85, sin(angle) * 0.75))
            let len = baseHeight * rng.range(0.15, 0.26)
            let end = start + dir * len
            trunk.addTube(a: start, b: end, radiusA: baseHeight * 0.006, radiusB: baseHeight * 0.003, sides: 4)
            for _ in 0..<7 {
                let size = baseHeight * rng.range(0.07, 0.12)
                let up = normalize(SIMD3(rng.signed(0.6), 1, rng.signed(0.6)))
                let right = normalize(cross(up, SIMD3(rng.signed(1), 0.2, rng.signed(1))))
                foliage.addQuad(
                    center: end + SIMD3(rng.signed(size), rng.signed(size), rng.signed(size)),
                    right: right * size,
                    up: up * size
                )
            }
        }

        guard let trunkDesc = trunk.descriptor("birch-trunk"),
              let trunkMesh = try? MeshResource.generate(from: [trunkDesc]) else {
            return Variant(name: "birch", trunkMesh: MeshResource.generateSphere(radius: 1),
                           trunkMaterial: barkMaterial(), leafMesh: nil, leafMaterial: nil,
                           baseHeight: baseHeight)
        }
        var white = barkMaterial()
        white.baseColor = .init(tint: TreeColor(red: 0.80, green: 0.78, blue: 0.72, alpha: 1))
        let leafDesc = foliage.descriptor("birch-leaves")
        let leafMesh = leafDesc.flatMap { try? MeshResource.generate(from: [$0]) }
        return Variant(name: "birch", trunkMesh: trunkMesh, trunkMaterial: white,
                       leafMesh: leafMesh,
                       leafMaterial: leafMaterial(leaves, tint: TreeColor(red: 0.62, green: 0.78, blue: 0.40, alpha: 1)),
                       baseHeight: baseHeight)
    }

    /// Iglaste: pień + okółki gałęzi, na nich kępy igliwia.
    private static func conifer(
        seed: UInt64,
        baseHeight: Float,
        needles: TextureResource?,
        tint: TreeColor,
        name: String
    ) -> Variant {
        var rng = RNG(seed)
        var trunk = MeshBuilder()
        var foliage = MeshBuilder()

        trunk.addTube(a: .zero, b: SIMD3(0, baseHeight, 0),
                      radiusA: baseHeight * 0.020, radiusB: baseHeight * 0.004, sides: 7)

        let whorls = 9
        for w in 0..<whorls {
            let t = 0.22 + Float(w) / Float(whorls) * 0.72
            let y = baseHeight * t
            let radius = baseHeight * (0.24 * (1 - t) + 0.03)
            let branches = 5 + Int(rng.range(0, 3))
            for b in 0..<branches {
                let angle = Float(b) / Float(branches) * .pi * 2 + rng.signed(0.4)
                let dir = normalize(SIMD3(cos(angle), rng.range(0.02, 0.18), sin(angle)))
                let len = radius * rng.range(0.85, 1.15)
                let start = SIMD3(0, y, 0)
                let end = start + dir * len
                trunk.addTube(a: start, b: end,
                              radiusA: baseHeight * 0.005, radiusB: baseHeight * 0.002, sides: 4)
                // igliwie: 8 kart na gałęzi — korona gęsta, bez prześwitów
                for _ in 0..<8 {
                    let size = baseHeight * rng.range(0.060, 0.105)
                    let up = normalize(SIMD3(rng.signed(0.5), 1, rng.signed(0.5)))
                    let right = normalize(cross(up, dir))
                    let center = start + dir * len * rng.range(0.35, 0.95) + SIMD3(0, -size * 0.15, 0)
                    foliage.addQuad(center: center, right: right * size * 1.6, up: up * size)
                }
            }
        }

        guard let trunkDesc = trunk.descriptor("\(name)-trunk"),
              let trunkMesh = try? MeshResource.generate(from: [trunkDesc]) else {
            return Variant(name: name, trunkMesh: MeshResource.generateSphere(radius: 1),
                           trunkMaterial: barkMaterial(), leafMesh: nil, leafMaterial: nil,
                           baseHeight: baseHeight)
        }
        let leafDesc = foliage.descriptor("\(name)-needles")
        let leafMesh = leafDesc.flatMap { try? MeshResource.generate(from: [$0]) }
        return Variant(name: name, trunkMesh: trunkMesh, trunkMaterial: barkMaterial(),
                       leafMesh: leafMesh,
                       leafMaterial: leafMaterial(needles, tint: tint, roughness: 0.95),
                       baseHeight: baseHeight)
    }

    // MARK: - instancje

    /// Instancja wariantu: skala = docelowa wysokość, losowy obrót.
    /// Siatka i materiały są wspólne — to jedno pole i jedna encja na drzewo.
    @MainActor
    /// Uproszczony zamiennik drzewa dla oddali: pień + kilka dużych kart liści.
    /// Pełne drzewo to tysiące kart; z 60 m widać tylko sylwetkę.
    static func proxy(
        _ variant: Variant,
        height: Float,
        rotation: Float,
        squash: Float = 1,
        tilt: Float = 0
    ) -> Entity {
        let root = Entity()
        let scale = height / variant.baseHeight

        let trunk = ModelEntity(
            mesh: .generateCylinder(height: height * 0.62, radius: max(0.06, height * 0.018)),
            materials: [variant.trunkMaterial]
        )
        trunk.position = [0, height * 0.31, 0]
        trunk.name = "\(variant.name)-proxy-trunk"
        root.addChild(trunk)

        if let leafMaterial = variant.leafMaterial {
            var builder = MeshBuilder()
            let conifer = variant.name.contains("spruce") || variant.name.contains("fir")

            if conifer {
                // iglaste: stożki z igliwia — z 60 m czytają się jak świerk
                for tier in 0..<4 {
                    let t = Float(tier) / 4
                    let segHeight = height * (0.34 - t * 0.05)
                    let segRadius = height * (0.20 - t * 0.04)
                    let y = height * (0.34 + t * 0.19)
                    builder.addCone(center: [0, y, 0], height: segHeight, radius: segRadius, sides: 7)
                }
            } else {
                // liściaste: kula z 5 kart — pełna sylwetka, 10 trójkątów
                let canopyY = height * 0.66
                let radius = height * 0.30
                for i in 0..<5 {
                    let angle = Float(i) / 5 * .pi
                    let right = SIMD3<Float>(cos(angle), 0, sin(angle)) * (radius * 2)
                    let up = SIMD3<Float>(0, radius * 1.5, 0)
                    builder.addQuad(center: [0, canopyY, 0], right: right, up: up, twoSided: false)
                }
                // dodatkowa karta pozioma — korona nie jest płaska z góry
                builder.addQuad(center: [0, canopyY + radius * 0.35, 0],
                                right: SIMD3(radius * 2, 0, 0), up: SIMD3(0, 0, radius * 2), twoSided: false)
            }

            let canopyDesc = builder.descriptor("canopy-proxy")
            if let canopyDesc, let mesh = try? MeshResource.generate(from: [canopyDesc]) {
                let canopy = ModelEntity(mesh: mesh, materials: [leafMaterial])
                canopy.name = "\(variant.name)-proxy-leaves"
                root.addChild(canopy)
            }
        }

        root.scale = [scale * squash, scale, scale * squash]
        root.orientation = simd_quatf(angle: rotation, axis: [0, 1, 0])
        if tilt != 0 {
            root.orientation = root.orientation * simd_quatf(angle: tilt, axis: [1, 0, 0])
        }
        return root
    }

    static func instance(
        _ variant: Variant,
        height: Float,
        rotation: Float,
        squash: Float = 1,
        tilt: Float = 0
    ) -> Entity {
        let root = Entity()
        let scale = height / variant.baseHeight

        let trunk = ModelEntity(mesh: variant.trunkMesh, materials: [variant.trunkMaterial])
        trunk.name = "\(variant.name)-trunk"
        root.addChild(trunk)

        if let leafMesh = variant.leafMesh, let leafMat = variant.leafMaterial {
            let leaves = ModelEntity(mesh: leafMesh, materials: [leafMat])
            leaves.name = "\(variant.name)-leaves"
            root.addChild(leaves)
        }

        // Każda instancja inaczej „wyciągnięta" w planie i lekko przechylona —
        // inaczej widać, że to ten sam model kopiowany setki razy.
        root.scale = SIMD3(scale * squash, scale, scale * (1 / max(0.4, squash)))
        let yaw = simd_quatf(angle: rotation, axis: [0, 1, 0])
        let lean = simd_quatf(angle: tilt, axis: normalize(SIMD3<Float>(1, 0, 0.6)))
        root.orientation = yaw * lean
        return root
    }
}

/// Trawa i kwiaty jako scalone siatki: kilka kart w jednej siatce = jedna encja
/// na kępę. Dzięki temu 3000 kęp to 3000 encji, a nie 12 tysięcy.
enum GrassFactory {

    struct Patch {
        let mesh: MeshResource
        let material: any Material
    }

    @MainActor private static var cache: [Patch] = []

    @MainActor static func patches() -> [Patch] {
        if !cache.isEmpty { return cache }
        guard let blades = EnvironmentArt.grassBlades(),
              let flowers = EnvironmentArt.flowerCluster() else { return [] }

        var built: [Patch] = []

        // Trawnik strzyżony na 5 cm: niskie, szerokie kępy
        for seed in [UInt64(3), 8, 15] {
            if let patch = makePatch(seed: seed, texture: blades,
                                     minHeight: 0.05, maxHeight: 0.09,
                                     minWidth: 0.55, maxWidth: 0.95,
                                     cards: 4, name: "grass-patch") {
                built.append(patch)
            }
        }
        // Kwiaty wyższe od trawnika (12-22 cm) — inaczej znikają w trawie
        if let patch = makePatch(seed: 21, texture: flowers,
                                 minHeight: 0.12, maxHeight: 0.22,
                                 minWidth: 0.32, maxWidth: 0.55,
                                 cards: 3, name: "flower-patch") {
            built.append(patch)
        }

        cache = built
        return cache
    }

    private static func makePatch(
        seed: UInt64,
        texture: TextureResource,
        minHeight: Float,
        maxHeight: Float,
        minWidth: Float,
        maxWidth: Float,
        cards: Int,
        name: String
    ) -> Patch? {
        var rng = TreeFactory.RNG(seed)
        var builder = TreeFactory.MeshBuilder()

        // karty w wachlarzu — kępa widziana z każdej strony
        for i in 0..<cards {
            let angle = Float(i) / Float(cards) * .pi
            let width = rng.range(minWidth, maxWidth)
            let height = rng.range(minHeight, maxHeight)
            let right = SIMD3<Float>(cos(angle) * width, 0, sin(angle) * width)
            let up = SIMD3<Float>(0, height, 0)
            builder.addQuad(center: SIMD3(rng.signed(0.12), height / 2, rng.signed(0.12)),
                            right: right, up: up)
        }

        guard let desc = builder.descriptor(name),
              let mesh = try? MeshResource.generate(from: [desc]) else { return nil }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0)
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        material.opacityThreshold = .init(0.40)
        material.faceCulling = .none

        return Patch(mesh: mesh, material: material)
    }
}
