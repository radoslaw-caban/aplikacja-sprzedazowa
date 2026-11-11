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
        public var radius: Float = 210          // promień terenu z teksturą (m)
        public var forestTrees: Int = 600       // gęsty las wokół posesji
        public var mountains: Int = 26
        public var birds: Int = 6
        public var clouds: Int = 16
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

        root.addChild(sky(radius: 24000))
        root.addChild(ground(radius: options.radius))
        root.addChild(farMeadow(inner: options.radius - 2, outer: 6000))
        root.addChild(mountainRange(options: options, rng: &rng))
        root.addChild(clouds(options: options, rng: &rng))
        root.addChild(forest(options: options, rng: &rng, room: room))
        root.addChild(road(room: room))
        root.addChild(driveway(room: room))
        root.addChild(tesla(position: SIMD3(-1.3, 0, Float(room.depth / 2000) + 9.5)))
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
        if let grass = EnvironmentArt.grass() {
            material.baseColor = .init(tint: .white, texture: .init(grass))
        } else {
            material.baseColor = .init(tint: PlatformColor(red: 0.36, green: 0.46, blue: 0.26, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.95)
        material.metallic = .init(floatLiteral: 0)
        if let normal = EnvironmentArt.photoTexture("grass_nor", semantic: .normal) {
            material.normal = .init(texture: .init(normal))
        }

        // UV w metrach: kafelka 4 × 4 m, więc trawa nie jest rozmazana przy horyzoncie
        let tile: Float = 6
        let r = radius
        var desc = MeshDescriptor(name: "ground")
        desc.positions = MeshBuffer([SIMD3<Float>(-r, 0, -r), SIMD3(r, 0, -r), SIMD3(r, 0, r), SIMD3(-r, 0, r)])
        desc.normals = MeshBuffer([SIMD3<Float>(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0)])
        let u = r * 2 / tile
        desc.textureCoordinates = MeshBuffer([SIMD2<Float>(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u)])
        desc.primitives = .triangles([0, 2, 1, 0, 3, 2])

        if let mesh = try? MeshResource.generate(from: [desc]) {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "ground"
            return entity
        }
        let fallback = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: radius), materials: [material])
        fallback.position = [0, -0.2, 0]
        fallback.name = "ground"
        return fallback
    }

    /// Daleka łąka: jednolity zielony pierścień za lasem. Tekstura trawy na 6 km
    /// zmieliłaby się do brązu (średnia mipmapy), a tak horyzont zostaje zielony.
    static func farMeadow(inner: Float, outer: Float) -> Entity {
        let segments = 96
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * .pi * 2
            let a1 = Float(i + 1) / Float(segments) * .pi * 2
            let base = UInt32(positions.count)
            positions += [
                SIMD3(cos(a0) * inner, -0.02, sin(a0) * inner),
                SIMD3(cos(a1) * inner, -0.02, sin(a1) * inner),
                SIMD3(cos(a1) * outer, -0.02, sin(a1) * outer),
                SIMD3(cos(a0) * outer, -0.02, sin(a0) * outer),
            ]
            normals += [SIMD3(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0)]
            uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
            indices += [base, base + 2, base + 1, base, base + 3, base + 2]
        }

        var descriptor = MeshDescriptor(name: "farMeadow")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return Entity() }

        // UnlitMaterial: daleka łąka nie może łapać światła, bo robiła się beżowa
        let material = UnlitMaterial(color: PlatformColor(red: 0.34, green: 0.40, blue: 0.22, alpha: 1))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "far-meadow"
        return entity
    }

    /// Grań górska na horyzoncie: pierścień trójkątów z poszarpaną linią.
    /// Stożki wyglądały jak spodki — pierścień czyta się jak prawdziwe pasmo.
    static func mountainRange(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "mountains"

        // dwie warstwy: dalsza bledsza, bliższa ciemniejsza (perspektywa powietrzna)
        let layers: [(radius: Float, minH: Float, maxH: Float, tint: (Float, Float, Float))] = [
            (12000, 700, 1500, (0.74, 0.79, 0.86)),
            (8200, 300, 700, (0.60, 0.67, 0.76)),
        ]

        for layer in layers {
            let segments = 220
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var uvs: [SIMD2<Float>] = []
            var indices: [UInt32] = []

            // wygeneruj wysokości grzbietu (suma kilku sinusów — bez losowego szumu)
            var heights = [Float](repeating: 0, count: segments)
            let phase = rng.range(0, 100)
            for i in 0..<segments {
                let a = Float(i) / Float(segments) * .pi * 2
                let n = 0.5 + 0.5 * sin(a * 3 + phase)
                let n2 = 0.5 + 0.5 * sin(a * 7.3 + phase * 1.7)
                let n3 = 0.5 + 0.5 * sin(a * 13.1 + phase * 0.4)
                let blend = n * 0.55 + n2 * 0.3 + n3 * 0.15
                heights[i] = layer.minH + (layer.maxH - layer.minH) * blend
            }

            for i in 0..<segments {
                let a0 = Float(i) / Float(segments) * .pi * 2
                let a1 = Float(i + 1) / Float(segments) * .pi * 2
                let x0 = cos(a0) * layer.radius, z0 = sin(a0) * layer.radius
                let x1 = cos(a1) * layer.radius, z1 = sin(a1) * layer.radius
                let h0 = heights[i], h1 = heights[(i + 1) % segments]

                let base = UInt32(positions.count)
                positions += [
                    SIMD3(x0, -80, z0),          // podstawa (schowana pod terenem)
                    SIMD3(x1, -80, z1),
                    SIMD3(x1, h1, z1),
                    SIMD3(x0, h0, z0),
                ]
                let inward = normalize(SIMD3<Float>(-(x0 + x1) / 2, 0, -(z0 + z1) / 2))
                normals += [inward, inward, inward, inward]
                uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            }

            var descriptor = MeshDescriptor(name: "ridge")
            descriptor.positions = MeshBuffer(positions)
            descriptor.normals = MeshBuffer(normals)
            descriptor.textureCoordinates = MeshBuffer(uvs)
            descriptor.primitives = .triangles(indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }

            let material = UnlitMaterial(color: PlatformColor(
                red: CGFloat(layer.tint.0), green: CGFloat(layer.tint.1), blue: CGFloat(layer.tint.2), alpha: 1
            ))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "ridge-\(layer.radius)"
            root.addChild(entity)
        }
        return root
    }

    static func forest(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "forest"

        var trunkMaterial = PhysicallyBasedMaterial()
        if let bark = EnvironmentArt.bark() {
            trunkMaterial.baseColor = .init(tint: .white, texture: .init(bark))
        } else {
            trunkMaterial.baseColor = .init(tint: PlatformColor(red: 0.24, green: 0.17, blue: 0.11, alpha: 1))
        }
        trunkMaterial.roughness = .init(floatLiteral: 0.95)

        // trzy odcienie igliwia + dwa liści — las przestaje być jednolitą masą
        let needle: [PhysicallyBasedMaterial] = (0..<3).map { i in
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: PlatformColor(red: 0.07, green: CGFloat(0.20 + Double(i) * 0.05), blue: 0.10, alpha: 1))
            m.roughness = .init(floatLiteral: 1.0)
            return m
        }
        let leaf: [PhysicallyBasedMaterial] = (0..<2).map { i in
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: PlatformColor(red: CGFloat(0.22 + Double(i) * 0.06),
                                                    green: CGFloat(0.36 + Double(i) * 0.06),
                                                    blue: 0.13, alpha: 1))
            m.roughness = .init(floatLiteral: 1.0)
            return m
        }

        let houseRadius = max(Float(room.width), Float(room.depth)) / 2000 + 12
        var placed = 0
        var guardCount = 0
        while placed < options.forestTrees && guardCount < options.forestTrees * 6 {
            guardCount += 1
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(houseRadius + 2, options.radius * 0.82)
            let x = cos(angle) * distance
            let z = sin(angle) * distance
            // nie sadzimy na podjeździe (pas szerokości 6 m wzdłuż +Z)
            if abs(x) < 9 && z > 0 { continue }   // pas podjazdu i trawnika przed domem

            // co któryś model z paczki (współdzielona siatka = jedna pamięć)
            if placed % 4 == 0,
               let model = ModelLibrary.entity(named: "IslandTree", targetSize: rng.range(6, 9)) {
                model.position = [x, 0, z]
                model.orientation = simd_quatf(angle: rng.range(0, .pi * 2), axis: [0, 1, 0])
                model.name = "tree-model-\(placed)"
                root.addChild(model)
                placed += 1
                continue
            }

            // gatunki: 45% świerk, 22% sosna, 20% brzoza, 13% dąb
            let roll = rng.next()
            let species: TreeSpecies = roll < 0.45 ? .spruce : (roll < 0.67 ? .pine : (roll < 0.87 ? .birch : .oak))
            let height = rng.range(5.0, 14.0)
            let tree = treeEntity(
                species: species,
                height: height,
                trunk: trunkMaterial,
                needle: needle,
                leaf: leaf,
                rng: &rng
            )
            tree.position = [x, 0, z]
            tree.name = "tree-\(placed)"
            root.addChild(tree)
            placed += 1
        }
        return root
    }

    enum TreeSpecies { case spruce, pine, birch, oak }

    /// Jedno drzewo z brył — świadomie proceduralne: 420 drzew z plików
    /// zajęłoby gigabajty, a las ma być tłem, nie bohaterem.
    static func treeEntity(
        species: TreeSpecies,
        height: Float,
        trunk: PhysicallyBasedMaterial,
        needle: [PhysicallyBasedMaterial],
        leaf: [PhysicallyBasedMaterial],
        rng: inout RNG
    ) -> Entity {
        let tree = Entity()
        let tint = rng.range(0.88, 1.10)
        let lean = simd_quatf(angle: rng.range(-0.05, 0.05), axis: normalize(SIMD3<Float>(rng.range(-1, 1), 0, rng.range(-1, 1))))

        switch species {
        case .spruce:
            // stożki warstwami, im wyżej tym mniejsze
            let trunkHeight = height * 0.30
            let t = ModelEntity(mesh: .generateCylinder(height: trunkHeight, radius: height * 0.022), materials: [trunk])
            t.position = [0, trunkHeight / 2, 0]
            tree.addChild(t)
            for tier in 0..<6 {
                let tierHeight = height * (0.30 - Float(tier) * 0.035)
                let radius = height * (0.17 - Float(tier) * 0.023)
                let cone = ModelEntity(
                    mesh: .generateCone(height: tierHeight, radius: max(0.30, radius)),
                    materials: [needle[tier % needle.count]]
                )
                cone.position = [0, height * (0.22 + Float(tier) * 0.135), 0]
                tree.addChild(cone)
            }

        case .pine:
            // wysoki, odsłonięty pień; korona jak parasol z boku
            let trunkHeight = height * 0.62
            let t = ModelEntity(mesh: .generateCylinder(height: trunkHeight, radius: height * 0.020), materials: [trunk])
            t.position = [0, trunkHeight / 2, 0]
            tree.addChild(t)
            for i in 0..<2 {
                let crown = ModelEntity(
                    mesh: .generateSphere(radius: height * (0.19 - Float(i) * 0.03)),
                    materials: [needle[2]]
                )
                crown.scale = [1.15, 0.55, 1.15]
                crown.position = [0, height * (0.74 + Float(i) * 0.12), 0]
                tree.addChild(crown)
            }

        case .birch:
            // biały, cienki pień (jaśniejszy materiał) + lekkie, jasne liście
            var white = PhysicallyBasedMaterial()
            white.baseColor = .init(tint: PlatformColor(red: 0.86, green: 0.85, blue: 0.80, alpha: 1))
            white.roughness = .init(floatLiteral: 0.85)
            let trunkHeight = height * 0.55
            let t = ModelEntity(mesh: .generateCylinder(height: trunkHeight, radius: height * 0.013), materials: [white])
            t.position = [0, trunkHeight / 2, 0]
            tree.addChild(t)
            for i in 0..<3 {
                let crown = ModelEntity(
                    mesh: .generateSphere(radius: height * (0.13 - Float(i) * 0.02)),
                    materials: [leaf[1]]
                )
                crown.scale = [1.0, 1.35, 1.0]
                crown.position = [rng.range(-0.5, 0.5), height * (0.62 + Float(i) * 0.14), rng.range(-0.5, 0.5)]
                tree.addChild(crown)
            }

        case .oak:
            // gruby, krótki pień i szeroka, ciemna korona
            let trunkHeight = height * 0.36
            let t = ModelEntity(mesh: .generateCylinder(height: trunkHeight, radius: height * 0.038), materials: [trunk])
            t.position = [0, trunkHeight / 2, 0]
            tree.addChild(t)
            let crown = ModelEntity(mesh: .generateSphere(radius: height * 0.26), materials: [leaf[0]])
            crown.scale = [1.25, 0.85, 1.25]
            crown.position = [0, height * 0.60, 0]
            tree.addChild(crown)
            for i in 0..<3 {
                let lobe = ModelEntity(mesh: .generateSphere(radius: height * 0.15), materials: [leaf[0]])
                lobe.position = [cos(Float(i) * 2.1) * height * 0.16, height * (0.66 + Float(i) * 0.05),
                                 sin(Float(i) * 2.1) * height * 0.16]
                tree.addChild(lobe)
            }
        }

        tree.orientation = lean
        tree.scale = .one * tint
        return tree
    }

    /// Droga gminna przed posesją — asfalt z linią i krawężnikami.
    /// Bez niej podjazd kończył się w trawie i dom wyglądał na odludziu.
    static func road(room: Room) -> Entity {
        let root = Entity()
        root.name = "road"
        let z = Float(room.depth / 2000) + 34
        let length: Float = 300
        let width: Float = 7

        var material = PhysicallyBasedMaterial()
        if let asphalt = EnvironmentArt.asphalt() {
            material.baseColor = .init(tint: .white, texture: .init(asphalt))
        } else {
            material.baseColor = .init(tint: PlatformColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.92)

        if let mesh = MeshFactory.texturedBox(width: length, height: 0.10, depth: width, tile: 4) {
            let surface = ModelEntity(mesh: mesh, materials: [material])
            surface.position = [0, 0.03, z]
            surface.name = "road-surface"
            root.addChild(surface)
        }

        // linia przerywana
        var paint = UnlitMaterial(color: PlatformColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 1))
        paint.faceCulling = .none
        var x = -length / 2 + 4
        while x < length / 2 - 4 {
            let dash = ModelEntity(mesh: .generateBox(width: 3, height: 0.01, depth: 0.16), materials: [paint])
            dash.position = [x, 0.085, z]
            root.addChild(dash)
            x += 9
        }

        // krawężniki po obu stronach jezdni
        let kerbMaterial = SimpleMaterial(color: .init(red: 0.58, green: 0.57, blue: 0.54, alpha: 1), isMetallic: false)
        for side in [Float(-1), Float(1)] {
            let kerb = ModelEntity(
                mesh: .generateBox(width: length, height: 0.14, depth: 0.3, cornerRadius: 0.01),
                materials: [kerbMaterial]
            )
            kerb.position = [0, 0.07, z + side * (width / 2 + 0.15)]
            root.addChild(kerb)
        }
        return root
    }

    static func driveway(room: Room) -> Entity {
        let root = Entity()
        root.name = "driveway"
        let halfDepth = Float(room.depth / 2000)
        let roadZ = halfDepth + 34
        let length = roadZ - halfDepth - 3.6     // do krawędzi jezdni

        var material = PhysicallyBasedMaterial()
        if let cobble = EnvironmentArt.cobble() {
            material.baseColor = .init(tint: .white, texture: .init(cobble))
        } else {
            material.baseColor = .init(tint: PlatformColor(red: 0.44, green: 0.43, blue: 0.41, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.85)
        // UV w metrach: kafel 1,6 m = 8 kostek po 20 cm — inaczej kostka jest plakatem
        let tile: Float = 1.6

        // 1) podjazd od domu do drogi
        if let mesh = MeshFactory.texturedBox(width: 5.6, height: 0.12, depth: length, tile: tile) {
            let slab = ModelEntity(mesh: mesh, materials: [material])
            slab.position = [0, 0.04, halfDepth + length / 2]
            slab.name = "driveway-slab"
            root.addChild(slab)
        }

        // 2) plac przed domem (miejsca postojowe, szersza płyta)
        if let mesh = MeshFactory.texturedBox(width: 11, height: 0.12, depth: 6.5, tile: tile) {
            let apron = ModelEntity(mesh: mesh, materials: [material])
            apron.position = [0, 0.04, halfDepth + 3.25]
            apron.name = "driveway-apron"
            root.addChild(apron)
        }

        // 3) zjazd na drogę: łagodne rozszerzenie przy krawędzi jezdni
        for side in [Float(-1), Float(1)] {
            if let mesh = MeshFactory.texturedBox(width: 2.4, height: 0.12, depth: 3.6, tile: tile) {
                let flare = ModelEntity(mesh: mesh, materials: [material])
                flare.position = [side * (5.6 / 2 + 0.7), 0.04, roadZ - 1.8]
                flare.orientation = simd_quatf(angle: side * 0.42, axis: [0, 1, 0])
                flare.name = "driveway-flare"
                root.addChild(flare)
            }
        }

        // krawężniki podjazdu
        let kerbMaterial = SimpleMaterial(color: .init(red: 0.55, green: 0.54, blue: 0.52, alpha: 1), isMetallic: false)
        for side in [Float(-1), Float(1)] {
            let kerb = ModelEntity(
                mesh: .generateBox(width: 0.22, height: 0.16, depth: length, cornerRadius: 0.01),
                materials: [kerbMaterial]
            )
            kerb.position = [side * 2.9, 0.08, halfDepth + length / 2]
            root.addChild(kerb)
        }
        return root
    }

    /// Tesla Model Y (bryła): niski, gładki nadwozie bez grilla, duże koła.
    ///
    /// Świadomie bez pliku GLB: model z paczki był „zabawką" i ważył 40 MB,
    /// a z 20 metrów liczy się sylwetka, nie detale.
    static func tesla(position: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.name = "tesla"

        var paint = PhysicallyBasedMaterial()
        paint.baseColor = .init(tint: PlatformColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1))
        paint.roughness = .init(floatLiteral: 0.22)
        paint.metallic = .init(floatLiteral: 0.35)

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: PlatformColor(red: 0.08, green: 0.11, blue: 0.14, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.05)
        glass.metallic = .init(floatLiteral: 0.1)

        var black = PhysicallyBasedMaterial()
        black.baseColor = .init(tint: PlatformColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))
        black.roughness = .init(floatLiteral: 0.55)

        // dolna część nadwozia (progi, zderzaki)
        let lower = ModelEntity(
            mesh: .generateBox(width: 1.92, height: 0.46, depth: 4.75, cornerRadius: 0.16),
            materials: [paint]
        )
        lower.position = [0, 0.62, 0]
        root.addChild(lower)

        // maska + tył (lekko zwężone, żeby nie był to prostopadłościan)
        let hood = ModelEntity(
            mesh: .generateBox(width: 1.80, height: 0.16, depth: 1.5, cornerRadius: 0.10),
            materials: [paint]
        )
        hood.position = [0, 0.90, 1.55]
        root.addChild(hood)

        // kabina: szyby dookoła + dach
        let cabin = ModelEntity(
            mesh: .generateBox(width: 1.70, height: 0.52, depth: 2.55, cornerRadius: 0.20),
            materials: [glass]
        )
        cabin.position = [0, 1.11, -0.25]
        root.addChild(cabin)

        let roof = ModelEntity(
            mesh: .generateBox(width: 1.62, height: 0.06, depth: 2.1, cornerRadius: 0.03),
            materials: [paint]
        )
        roof.position = [0, 1.38, -0.30]
        root.addChild(roof)

        // koła: czarna opona + jasna felga
        let rimMaterial = SimpleMaterial(color: .init(red: 0.68, green: 0.70, blue: 0.73, alpha: 1), isMetallic: true)
        for (dx, dz) in [(0.86 as Float, 1.48 as Float), (-0.86, 1.48), (0.86, -1.48), (-0.86, -1.48)] {
            let tyre = ModelEntity(mesh: .generateCylinder(height: 0.26, radius: 0.36), materials: [black])
            tyre.position = [dx, 0.36, dz]
            tyre.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            root.addChild(tyre)

            let rim = ModelEntity(mesh: .generateCylinder(height: 0.27, radius: 0.21), materials: [rimMaterial])
            rim.position = [dx, 0.36, dz]
            rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            root.addChild(rim)

            // nadkole: ciemna listwa nad kołem
            let arch = ModelEntity(
                mesh: .generateBox(width: 0.10, height: 0.34, depth: 0.86, cornerRadius: 0.04),
                materials: [black]
            )
            arch.position = [dx > 0 ? 0.92 : -0.92, 0.62, dz]
            root.addChild(arch)
        }

        // listwy progowe i lusterka — czytelne detale z 10 m
        for side in [Float(-1), Float(1)] {
            let sill = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.10, depth: 2.6), materials: [black])
            sill.position = [side * 0.97, 0.40, 0]
            root.addChild(sill)

            let mirror = ModelEntity(mesh: .generateBox(width: 0.22, height: 0.11, depth: 0.16, cornerRadius: 0.03), materials: [black])
            mirror.position = [side * 0.94, 1.02, 0.75]
            root.addChild(mirror)
        }

        root.position = position
        return root
    }

    /// Chmury: kłębiaste karty z teksturą alfa, wysoko nad posesją.
    /// Powolny dryf przez animację — bez ruchu niebo wygląda na zdjęcie.
    static func clouds(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "clouds"
        guard let texture = EnvironmentArt.cloud() else { return root }

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        material.faceCulling = .none

        let mesh = MeshFactory.ground(size: 1, tile: 1) ?? .generatePlane(width: 1, depth: 1)
        for i in 0..<options.clouds {
            let cloud = ModelEntity(mesh: mesh, materials: [material])
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(180, 900)
            let size = rng.range(70, 190)
            cloud.scale = [size, 1, size * rng.range(0.45, 0.7)]
            cloud.position = [cos(angle) * distance, rng.range(85, 190), sin(angle) * distance]
            cloud.orientation = simd_quatf(angle: rng.range(0, .pi), axis: [0, 1, 0])
            cloud.name = "cloud-\(i)"
            root.addChild(cloud)

            // dryf: ten sam kierunek, różne prędkości
            let speed = rng.range(6, 16)
            Task { @MainActor in
                var travelled: Float = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    travelled += speed * 0.06
                    cloud.position.x += speed * 0.06
                    if travelled > 1400 || cloud.position.x > 900 {
                        cloud.position.x = -900
                        travelled = 0
                    }
                }
            }
        }
        return root
    }

    /// Ptaki: proste skrzydła, krążą nad domem (animacja w pętli).
    static func birds(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "birds"
        for i in 0..<options.birds {
            if let model = ModelLibrary.entity(named: i % 2 == 0 ? "Stork" : "Flamingo", targetSize: 1.1) {
                let bird = Entity()
                bird.addChild(model)
                let radius = rng.range(22, 55)
                let height = rng.range(14, 26)
                let startAngle = rng.range(0, .pi * 2)
                bird.position = [cos(startAngle) * radius, height, sin(startAngle) * radius]
                bird.scale = .one * rng.range(0.9, 1.6)
                bird.name = "bird-\(i)"
                root.addChild(bird)

                Task { @MainActor in
                    var angle = startAngle
                    while !Task.isCancelled {
                        angle += .pi / 4
                        let next = SIMD3<Float>(cos(angle) * radius, height, sin(angle) * radius)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        await bird.move(to: Transform(translation: next), relativeTo: bird.parent, duration: 3.5, timingFunction: .linear)
                    }
                }
                continue
            }
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
