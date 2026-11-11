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
        public var forestTrees: Int = 260       // gęsty las; z bliska pełne drzewa, z daleka proxy (LOD)
        public var forestBackdrop: Bool = true  // uproszczone tło lasu (pierścień)
        public var grassTufts: Int = 700
        public var undergrowth: Int = 30    // krzaki w lesie (podszycie)
        public var boulders: Int = 24        // głazy i kamienie
        public var understoryPlants: Int = 40   // paprocie/pokrzywy/krzewy
        public var fogBanks: Int = 6            // mgła w dolinach
        public var mountains: Int = 26
        public var birds: Int = 6
        public var clouds: Int = 10
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
        /// Liczba z zakresu ±v — do odchyłek i przechyłów.
        mutating func signed(_ v: Float) -> Float { (next() * 2 - 1) * v }
    }

    // MARK: - scena

    /// Całe otoczenie domu: dom stoi w środku, wjazd od strony +Z.
    public static func makeEntity(room: Room, options: Options = Options()) -> Entity {
        let root = Entity()
        root.name = "environment"
        var rng = RNG(options.seed)

        // Nieba NIE stawiamy jako kuli: promień 24 km leżał poza far plane
        // kamery, a jej „mgielna" kula zasłaniała niebo na szaro. Tło nieba
        // daje skybox środowiska z SceneView.
        root.addChild(ground(radius: options.radius))
        root.addChild(farMeadow(inner: options.radius - 2, outer: 6000))
        // Bieszczady: pasma w warstwach, za nimi uproszczone tło lasu,
        // a między nimi mgła w dolinach. Kolejność = kolejność malowania pleneru.
        // Tło: PRAWDZIWE zdjęcie Bieszczad na walcu, zszyte bez szwu
        // (obraz + odbicie lustrzane), z pasami mgły przed nim.
        // Zdjęcie jako płaska karta wyglądało jak wklejka (widać krawędzie
        // i perspektywę). Wracamy do malowanego tła; pełne wykorzystanie
        // zdjęcia wymaga panoramy 360° (equirect) — to osobny krok.
        // mgła PRZED panoramą, ale niska i delikatna — wcześniej stała tuż
        // przed zdjęciem i zalewała je na biało
        // PASMA WZGÓRZ: bez nich horyzont był płaską linią i cała okolica
        // wyglądała jak boisko. Trzy warstwy — od ciemnej, bliskiej po bladą.
        root.addChild(hillBackdrop(radius: options.radius * 2.6,
                                   heightRange: 18...54,
                                   tint: (0.30, 0.40, 0.30)))
        root.addChild(hillBackdrop(radius: options.radius * 4.0,
                                   heightRange: 34...92,
                                   tint: (0.38, 0.47, 0.50)))
        root.addChild(hillBackdrop(radius: options.radius * 6.2,
                                   heightRange: 60...150,
                                   tint: (0.50, 0.58, 0.64)))
        root.addChild(mountainRange(options: options, rng: &rng))
        root.addChild(clouds(options: options, rng: &rng))
        root.addChild(forest(options: options, rng: &rng, room: room))
        root.addChild(rocks(options: options, rng: &rng, room: room))
        root.addChild(understory(options: options, rng: &rng, room: room))
        root.addChild(grassTufts(options: options, rng: &rng, room: room))
        root.addChild(fence(room: room))
        root.addChild(sidewalk(room: room))
        root.addChild(ditch(room: room))
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
            // Niebo jak na zdjęciu połoniny: błękit u góry, biel przy horyzoncie
            CGColor(red: 0.36, green: 0.55, blue: 0.78, alpha: 1),
            CGColor(red: 0.55, green: 0.70, blue: 0.86, alpha: 1),
            CGColor(red: 0.79, green: 0.86, blue: 0.91, alpha: 1),
            CGColor(red: 0.93, green: 0.94, blue: 0.92, alpha: 1),
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

    /// Wysokość terenu (m). Płaski plac wokół domu (34 m), dalej nieregularne
    /// pagórki — suma trzech sinusów o różnych okresach daje teren „krzywy",
    /// ale bez losowego szumu (ten sam krajobraz przy każdym uruchomieniu).
    /// Tej samej funkcji używają drzewa i trawa, żeby nic nie wisiało w powietrzu.
    public static func terrainHeight(_ x: Float, _ z: Float) -> Float {
        let distance = (x * x + z * z).squareRoot()

        // Płaski plac pod domem i ogrodem.
        let flatUntil: Float = 26
        var mask: Float = distance > flatUntil ? Swift.min(1, (distance - flatUntil) / 60) : 0

        // Korytarz drogi (pas w poprzek, z = 34) i podjazdu (wzdłuż +Z).
        // Bez tego droga i kostka „wchodzą" w pagórki albo wiszą nad nimi.
        func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
            let t = Swift.max(0, Swift.min(1, (value - edge0) / Swift.max(0.001, edge1 - edge0)))
            return t * t * (3 - 2 * t)
        }
        let roadClear = smoothstep(10, 22, abs(z - 34))
        let driveClear = (z < 0 || abs(x) > 18) ? 1 : smoothstep(7, 16, abs(x))
        mask *= roadClear * driveClear

        guard mask > 0.001 else { return 0 }

        // Trzy skale: długie zbocza, średnie garby, drobne nierówności.
        // Dodatkowo składnik „skośny", żeby wzgórza nie były symetryczne.
        let h1 = sin(x * 0.013 + 0.6) * cos(z * 0.010 - 0.4) * 4.2
        let h2 = sin((x * 0.9 + z * 0.45) * 0.031 + 1.7) * cos((z - x * 0.3) * 0.026) * 1.6
        let h3 = sin(x * 0.085 + 3.1) * sin(z * 0.071 + 2.2) * 0.38
        let h4 = cos((x + z) * 0.15 + 0.9) * 0.12
        return (h1 + h2 + h3 + h4) * mask
    }

    static func ground(radius: Float) -> Entity {
        var material = PhysicallyBasedMaterial()
        if let grass = EnvironmentArt.grass() {
            // Bieszczady: połonina to jasna, żółto-zielona trawa — sam szum
            // tekstury daje ciemną zieleń, więc podbijamy tint w stronę słońca
            material.baseColor = .init(tint: PlatformColor(red: 0.78, green: 0.98, blue: 0.50, alpha: 1),
                                       texture: .init(grass))
        } else {
            material.baseColor = .init(tint: PlatformColor(red: 0.42, green: 0.52, blue: 0.26, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.95)
        material.metallic = .init(floatLiteral: 0)
        if let normal = EnvironmentArt.photoTexture("grass_nor", semantic: .normal) {
            material.normal = .init(texture: .init(normal))
        }

        // Siatka terenu z wysokościami: płaski plac pod domem, dalej pagórki.
        // UV w metrach — trawa nie jest rozmazana.
        let tile: Float = 6
        let cells = 120
        let step = radius * 2 / Float(cells)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for iz in 0...cells {
            for ix in 0...cells {
                let x = -radius + Float(ix) * step
                let z = -radius + Float(iz) * step
                let y = terrainHeight(x, z)
                positions.append(SIMD3(x, y, z))
                // normalna z różnic skończonych
                let dx = terrainHeight(x + 1, z) - terrainHeight(x - 1, z)
                let dz = terrainHeight(x, z + 1) - terrainHeight(x, z - 1)
                normals.append(normalize(SIMD3(-dx, 2, -dz)))
                uvs.append(SIMD2(x / tile, z / tile))
            }
        }
        for iz in 0..<cells {
            for ix in 0..<cells {
                let i0 = UInt32(iz * (cells + 1) + ix)
                let i1 = i0 + 1
                let i2 = UInt32((iz + 1) * (cells + 1) + ix)
                let i3 = i2 + 1
                indices += [i0, i2, i1, i1, i2, i3]
            }
        }

        var desc = MeshDescriptor(name: "ground")
        desc.positions = MeshBuffer(positions)
        desc.normals = MeshBuffer(normals)
        desc.textureCoordinates = MeshBuffer(uvs)
        desc.primitives = .triangles(indices)

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
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(red: 0.30, green: 0.38, blue: 0.22, alpha: 1))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0)

        // Pierścień z wielu segmentów, nie jedna wielka tarcza: przy blendowaniu
        // mgły wielka płaszczyzna łapała jasny odcień i wyglądała jak jezioro.
        let root = Entity()
        root.name = "far-meadow"
        let segments = 96
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * .pi * 2
            let length = outer - inner
            let mid = (inner + outer) / 2
            let slab = ModelEntity(
                mesh: .generateBox(width: length, height: 0.2, depth: .pi * 2 * mid / Float(segments) * 1.05),
                materials: [material]
            )
            slab.position = [cos(angle) * mid, -0.35, sin(angle) * mid]
            slab.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            slab.name = "meadow-\(i)"
            root.addChild(slab)
        }
        return root
    }

    static func mountainRange(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "mountains"

        // Trzy plany jak w plenerze: bliski las → ciemne pasmo → blade pasmo w mgle.
        // Wcześniej pasma stały na 8–12 km i przy far plane 9 km były ucinane,
        // więc nieba nie przesłaniało nic — horyzont był pusty.
        let layers: [(radius: Float, minH: Float, maxH: Float, tint: (Float, Float, Float))] = [
            (5200, 340, 820, (0.44, 0.53, 0.58)),   // najdalsze: Niebiesko-szare
            (3300, 180, 460, (0.26, 0.38, 0.36)),   // średnie: ciemna zieleń buczyny
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

    /// Wzgórza z lasem w tle: pierścień z poszarpaną górną krawędzią
    /// (ząbki = korony drzew) i pasem mgły przed nim.
    ///
    /// PO CO: pojedyncze drzewa kończą się w pewnej odległości i horyzont robi
    /// się pusty. Zamiast sadzić tysiące dodatkowych modeli, stawiamy taflę
    /// w kolorze lasu z nierównym grzbietem — z dystansu nie do odróżnienia.
    static func hillBackdrop(
        radius: Float,
        heightRange: ClosedRange<Float>,
        tint: (Float, Float, Float),
        texture: TextureResource? = nil,
        uvRepeat: Float = 1,
        jitter: Bool = true
    ) -> Entity {
        let root = Entity()
        root.name = "forest-backdrop"

        let segments = 220
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // Grzbiet: kilka sinusów o różnych okresach (bez szumu pseudolosowego).
        // Wysoki okres = pojedyncze korony drzew, niski = łagodne wzgórze.
        func ridge(_ i: Int) -> Float {
            let a = Float(i) / Float(segments) * .pi * 2
            let hills = 0.5 + 0.5 * sin(a * 3.0 + 0.7)
            let woods = 0.5 + 0.5 * sin(a * 19.0 + 2.1)
            let crowns = 0.5 + 0.5 * sin(a * 61.0 + 4.3)
            let blend = hills * 0.60 + woods * 0.25 + (jitter ? crowns * 0.15 : 0)
            return heightRange.lowerBound + blend * (heightRange.upperBound - heightRange.lowerBound)
        }

        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * .pi * 2
            let a1 = Float(i + 1) / Float(segments) * .pi * 2
            let x0 = cos(a0) * radius, z0 = sin(a0) * radius
            let x1 = cos(a1) * radius, z1 = sin(a1) * radius
            let h0 = ridge(i), h1 = ridge(i + 1)

            let base = UInt32(positions.count)
            positions += [
                SIMD3(x0, -3, z0), SIMD3(x1, -3, z1),
                SIMD3(x1, h1, z1), SIMD3(x0, h0, z0),
            ]
            let inward = normalize(SIMD3<Float>(-(x0 + x1) / 2, 0, -(z0 + z1) / 2))
            normals += [inward, inward, inward, inward]
            let u0 = Float(i) / Float(segments) * uvRepeat
            let u1 = Float(i + 1) / Float(segments) * uvRepeat
            uvs += [SIMD2(u0, 0), SIMD2(u1, 0), SIMD2(u1, 1), SIMD2(u0, 1)]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        var descriptor = MeshDescriptor(name: "hillBackdrop")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return root }

        var material = UnlitMaterial()
        if let texture {
            // korony lasu z tekstury — tło przestaje być jednolitą ścianą
            material.color = .init(tint: PlatformColor(
                red: CGFloat(tint.0), green: CGFloat(tint.1), blue: CGFloat(tint.2), alpha: 1
            ), texture: .init(texture))
        } else {
            material.color = .init(tint: PlatformColor(
                red: CGFloat(tint.0), green: CGFloat(tint.1), blue: CGFloat(tint.2), alpha: 1
            ))
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "hills-silhouette"
        root.addChild(entity)
        return root
    }

    /// Tło z prawdziwego zdjęcia: WYCINEK panoramy (łuk), nie pełny walec.
    ///
    /// Dlaczego łuk: zdjęcie ma pole widzenia ~90°, a owinięte na 360° rozciąga
    /// się 4-5 razy i wygląda jak morze. Łuk 150° za domem daje naturalne
    /// proporcje grzbietów.
    static func photoBackdrop(
        name: String,
        radius: Float,
        bottom: Float,
        top: Float,
        arcDegrees: Float = 150,
        centerAzimuthDegrees: Float = 180
    ) -> Entity {
        let root = Entity()
        root.name = "photo-backdrop"

        // BILLBOARD, nie walec: zwykła płaszczyzna z wbudowanej siatki.
        // Własna siatka łuku nie renderowała się wcale (TextureResource i mesh
        // były w porządku — problem leżał w geometrii), a płaszczyzna działa.
        let aspect: Float = 2.6
        let height = top - bottom
        let width = height * aspect
        let plane = MeshResource.generatePlane(width: width, height: height)

        var material = UnlitMaterial()
        if let texture = EnvironmentArt.panorama(fromImageNamed: name) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: PlatformColor(red: 0.8, green: 0.15, blue: 0.6, alpha: 1))
        }
        material.faceCulling = .none

        let entity = ModelEntity(mesh: plane, materials: [material])
        entity.position = [0, (bottom + top) / 2, -radius]
        // płaszczyzna domyślnie patrzy w +Z; kamera jest po +Z, więc nie obracamy
        entity.name = "panorama"
        root.addChild(entity)
        return root
    }

    /// Pas mgły przed wzgórzami: pionowe karty z gradientem, ustawione w krąg.
    /// Mgła między planami to połowa efektu Bieszczadów — bez niej wzgórza
    /// wyglądają jak wycinanki.
    static func fogRings(radius: Float, count: Int, height: Float, opacity: Float) -> Entity {
        let root = Entity()
        root.name = "fog-ring"
        guard let texture = EnvironmentArt.hazeGradient() else { return root }

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none

        let plane = MeshResource.generatePlane(width: 1, height: 1)
        for i in 0..<count {
            let angle = Float(i) / Float(count) * .pi * 2
            let card = ModelEntity(mesh: plane, materials: [material])
            let span = 2 * .pi * radius / Float(count) * 1.6
            card.scale = [span, height, 1]
            card.position = [cos(angle) * radius, height * 0.35, sin(angle) * radius]
            // karta patrzy w środek sceny
            card.orientation = simd_quatf(angle: angle + .pi / 2, axis: [0, 1, 0])
            card.name = "fog-card-\(i)"
            root.addChild(card)
        }
        return root
    }

    /// Mgła w dolinach: płaskie, rozmyte karty nisko nad terenem.
    /// Bieszczady bez mgły to tylko pagórki — ona daje głębię planów.
    static func fogBanks(options: Options, rng: inout RNG) -> Entity {
        let root = Entity()
        root.name = "fog"
        guard let texture = EnvironmentArt.cloud() else { return root }

        var material = UnlitMaterial()
        material.color = .init(tint: PlatformColor(red: 0.93, green: 0.95, blue: 0.96, alpha: 1),
                               texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        material.faceCulling = .none

        let mesh = MeshFactory.ground(size: 1, tile: 1) ?? .generatePlane(width: 1, depth: 1)
        for i in 0..<options.fogBanks {
            let bank = ModelEntity(mesh: mesh, materials: [material])
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(100, 520)
            let size = rng.range(90, 260)
            bank.scale = [size, 1, size * rng.range(0.5, 0.8)]
            bank.position = [cos(angle) * distance, rng.range(1.5, 10), sin(angle) * distance]
            bank.orientation = simd_quatf(angle: rng.range(0, .pi), axis: [0, 1, 0])
            bank.name = "fog-\(i)"
            root.addChild(bank)
        }
        return root
    }

    /// Gęsta trawa: kępy z dwóch skrzyżowanych billboardów.
    ///
    /// Rozstawiamy je tylko w pasie do ~45 m od domu — dalej i tak zlewają się
    /// w jednolitą zieleń, a kosztowałoby to tysiące encji.
    static func grassTufts(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "grass-tufts"

        let patches = GrassFactory.patches()
        guard !patches.isEmpty else { return root }

        // Te same wymiary co ogrodzenie — pas roślin rośnie dokładnie wzdłuż płotu.
        let halfW = Float(room.width / 2000) + 7
        let halfD = Float(room.depth / 2000) + 9
        let houseHalfX = Float(room.width / 2000) + 1.5
        let houseHalfZ = Float(room.depth / 2000) + 1.5

        var placed = 0
        var guardCount = 0
        let target = options.grassTufts
        let limit = target * 6

        func tuft(_ x: Float, _ z: Float, _ scale: Float = 1) {
            let flowers = patches.count > 1 && rng.next() < 0.20
            let plainCount = max(1, patches.count - 1)
            let index = flowers ? patches.count - 1 : Int(rng.next() * Float(plainCount))
            let patch = patches[min(index, patches.count - 1)]
            let entity = ModelEntity(mesh: patch.mesh, materials: [patch.material])
            entity.scale = SIMD3(rng.range(1.8, 3.4) * scale,
                                 rng.range(1.8, 3.6) * scale,
                                 rng.range(1.8, 3.4) * scale)
            entity.orientation = simd_quatf(angle: rng.range(0, .pi * 2), axis: [0, 1, 0])
            entity.position = [x, terrainHeight(x, z), z]
            entity.name = "grass-\(placed)"
            root.addChild(entity)
            placed += 1
        }

        // 1) GĘSTY PAS WZDŁUŻ PŁOTU — 55% kęp, ±3,5 m od linii ogrodzenia.
        let bandCount = Int(Float(target) * 0.55)
        let perimeter = 4 * (halfW + halfD)
        while placed < bandCount && guardCount < limit {
            guardCount += 1
            var t = rng.range(0, perimeter)
            var x: Float = 0
            var z: Float = 0
            if t < halfW * 2 {
                x = -halfW + t; z = -halfD
            } else if t < halfW * 2 + halfD * 2 {
                t -= halfW * 2; x = halfW; z = -halfD + t
            } else if t < halfW * 4 + halfD * 2 {
                t -= halfW * 2 + halfD * 2; x = halfW - t; z = halfD
            } else {
                t -= halfW * 4 + halfD * 2; x = -halfW; z = halfD - t
            }
            x += rng.range(-1.2, 1.2)
            z += rng.range(-3.5, 3.5)
            if abs(x) < houseHalfX && abs(z) < houseHalfZ { continue }
            if z > 0 && abs(x) < 16 { continue }
            tuft(x, z, 1.25)
        }

        // 2) CAŁY TRAWNIK W ŚRODKU PŁOTU
        while placed < target && guardCount < limit {
            guardCount += 1
            let x = rng.range(-halfW, halfW)
            let z = rng.range(-halfD, halfD)
            if abs(x) < houseHalfX && abs(z) < houseHalfZ { continue }
            if z > 0 && abs(x) < 16 { continue }
            tuft(x, z, 1.1)
        }

        // 3) DZICZ ZA PŁOTEM — rzadziej, ale bez łysych plam
        var extra = 0
        let extraTarget = Int(Float(target) * 0.25)
        while extra < extraTarget && guardCount < limit * 2 {
            guardCount += 1
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(28, 62)
            let x = cos(angle) * distance
            let z = sin(angle) * distance
            if abs(x) < halfW + 2 && abs(z) < halfD + 2 { continue }
            tuft(x, z, 0.95)
            extra += 1
        }
        return root
    }

    /// Las w skupiskach + podszycie + miękkie cienie kontaktowe pod drzewami.
    static func forest(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "forest"

        let variants = TreeFactory.variants()
        guard !variants.isEmpty else { return root }

        let houseRadius = max(Float(room.width), Float(room.depth)) / 2000 + 12
        var shadowSpots: [(SIMD3<Float>, Float)] = []

        struct Grove { let x: Float; let z: Float; let radius: Float }
        var groves: [Grove] = []
        for _ in 0..<16 {
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(houseRadius + 20, options.radius * 0.72)
            groves.append(Grove(x: cos(angle) * distance,
                                z: sin(angle) * distance,
                                radius: rng.range(12, 34)))
        }

        var placed = 0
        var guardCount = 0
        while placed < options.forestTrees && guardCount < options.forestTrees * 10 {
            guardCount += 1

            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(houseRadius + 4, options.radius * 0.82)
            var x = cos(angle) * distance
            var z = sin(angle) * distance

            if rng.next() < 0.65, !groves.isEmpty {
                let grove = groves[Int(rng.next() * Float(groves.count)) % groves.count]
                let a = rng.range(0, .pi * 2)
                let r = rng.range(0, grove.radius)
                x = grove.x + cos(a) * r
                z = grove.z + sin(a) * r
                if (x * x + z * z).squareRoot() < houseRadius + 6 { continue }
            }

            // strefa kamery: nic nie staje między obiektywem a domem
            if abs(x) < 46 && z > -12 && z < 96 { continue }

            let sawView = 3 * Float.pi / 2
            var dAngle = abs(atan2(z, x) - sawView)
            if dAngle > Float.pi { dAngle = 2 * Float.pi - dAngle }
            if z < 0, abs(x) < 20 { continue }
            if (x * x + z * z).squareRoot() < 260, dAngle < 0.45 { continue }

            let behind = z < 0
            let height = behind ? rng.range(13.0, 30.0) : rng.range(8.0, 21.0)

            let variant = variants[Int(rng.next() * Float(variants.count)) % variants.count]
            let rotation = rng.range(0, .pi * 2)
            let squash = rng.range(0.78, 1.22)
            let tilt = rng.signed(0.12)

            // LOD: pełne drzewo z bliska, uproszczone (pień + 3 karty) z oddali
            let tree = Entity()
            tree.name = "lod-tree-\(placed)"
            tree.position = [x, terrainHeight(x, z), z]

            let full = TreeFactory.instance(variant, height: height, rotation: rotation, squash: squash, tilt: tilt)
            full.name = "lod0"
            tree.addChild(full)

            let proxy = TreeFactory.proxy(variant, height: height, rotation: rotation, squash: squash, tilt: tilt)
            proxy.name = "lod1"
            proxy.isEnabled = false
            tree.addChild(proxy)

            root.addChild(tree)
            shadowSpots.append((SIMD3(x, terrainHeight(x, z) + 0.03, z), height * 0.24))
            placed += 1
        }

        var undergrowth = PhysicallyBasedMaterial()
        undergrowth.baseColor = .init(tint: PlatformColor(red: 0.20, green: 0.33, blue: 0.18, alpha: 1))
        undergrowth.roughness = .init(floatLiteral: 1.0)
        for i in 0..<options.undergrowth {
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(houseRadius + 10, options.radius * 0.8)
            let x = cos(angle) * distance
            let z = sin(angle) * distance
            if abs(x) < 40 && z > -8 && z < 90 { continue }
            let size = rng.range(0.45, 1.3)
            let bush = ModelEntity(mesh: .generateSphere(radius: size * 0.5), materials: [undergrowth])
            bush.scale = [1.3, rng.range(0.5, 0.9), 1.3]
            bush.position = [x, terrainHeight(x, z) + size * 0.18, z]
            bush.name = "undergrowth-\(i)"
            root.addChild(bush)
            shadowSpots.append((SIMD3(x, terrainHeight(x, z) + 0.03, z), size * 0.6))
        }

        root.addChild(contactShadows(shadowSpots))
        return root
    }

    /// Jedna scalona siatka miękkich cieni pod obiektami (AO kontaktowe).
    static func contactShadows(_ spots: [(SIMD3<Float>, Float)]) -> Entity {
        let root = Entity()
        root.name = "contact-shadows"
        guard !spots.isEmpty, let texture = EnvironmentArt.softShadow() else { return root }

        var builder = TreeFactory.MeshBuilder()
        for (center, radius) in spots {
            let r = max(0.35, radius)
            builder.addQuad(center: center, right: SIMD3(r, 0, 0), up: SIMD3(0, 0, r))
        }
        guard let descriptor = builder.descriptor("contact-shadow"),
              let mesh = try? MeshResource.generate(from: [descriptor]) else { return root }

        var material = UnlitMaterial()
        material.color = .init(tint: PlatformColor(white: 1, alpha: 1), texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        material.faceCulling = .none

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "shadow-decals"
        root.addChild(entity)
        return root
    }

    /// OGRODZENIE WILLI: murowane słupki + czarne metalowe pręty, pełna brama
    /// dwuskrzydłowa w osi podjazdu. Wcześniej był tu płot drewniany — wyglądał
    /// jak zagroda na konie, nie jak ogrodzenie willi.
    /// SKAŁY: głazy i kamienie — w lesie, wzdłuż rowu i pojedyncze na łące.
    /// Wcześniej teren był idealnie gładki, bez żadnego „twardego" elementu.
    static func rocks(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "rocks"

        let houseRadius = max(Float(room.width), Float(room.depth)) / 2000 + 12
        let boulders = max(0, options.boulders)

        for i in 0..<boulders {
            let angle = rng.range(0, .pi * 2)
            let near = rng.next() < 0.6
            let distance = near ? rng.range(houseRadius + 4, 70) : rng.range(70, options.radius * 0.85)
            let x = cos(angle) * distance
            let z = sin(angle) * distance

            // strefa kamery i podjazd — tam skały tylko psują widok
            if abs(x) < 46 && z > -12 && z < 96 { continue }
            if z > 30 && abs(x) < 16 { continue }

            let big = rng.next() < 0.6
            let name = big ? "boulder_01" : "stone_01"
            let size = big ? rng.range(0.5, 1.9) : rng.range(0.2, 0.7)
            guard let rock = ModelLibrary.entity(named: name, targetSize: size) else { continue }
            rock.position = [x, terrainHeight(x, z), z]
            rock.orientation = simd_quatf(angle: rng.range(0, .pi * 2), axis: [0, 1, 0])
            rock.name = "rock-\(i)"
            root.addChild(rock)
        }

        // pojedyncze kamienie przy rowie i wzdłuż płotu (detal blisko domu)
        for i in 0..<10 {
            let side = i % 2 == 0 ? Float(1) : Float(-1)
            let x = side * rng.range(4, 18)
            let z = Float(room.depth / 2000) + 9 + rng.range(1.2, 2.6)
            guard let stone = ModelLibrary.entity(named: "stone_01", targetSize: rng.range(0.25, 0.6)) else { continue }
            stone.position = [x, terrainHeight(x, z), z]
            stone.orientation = simd_quatf(angle: rng.range(0, .pi * 2), axis: [0, 1, 0])
            root.addChild(stone)
        }
        return root
    }

    /// ROŚLINY MIĘDZY DRZEWAMI: paprocie, pokrzywy, krzewy — runo leśne.
    /// Bez tego las to same pnie na równej trawie.
    static func understory(options: Options, rng: inout RNG, room: Room) -> Entity {
        let root = Entity()
        root.name = "understory"

        let houseRadius = max(Float(room.width), Float(room.depth)) / 2000 + 12
        let kinds: [(String, ClosedRange<Float>)] = [
            ("fern_02", 0.35...0.85),
            ("nettle_plant", 0.4...0.9),
            ("shrub_01", 0.5...1.4),
            ("grass_medium_01", 0.4...0.8),
        ]

        for i in 0..<options.understoryPlants {
            let angle = rng.range(0, .pi * 2)
            let near = rng.next() < 0.5
            let distance = near ? rng.range(houseRadius + 5, 55) : rng.range(55, options.radius * 0.7)
            let x = cos(angle) * distance
            let z = sin(angle) * distance

            if abs(x) < 44 && z > -12 && z < 92 { continue }

            let kind = kinds[Int(rng.next() * Float(kinds.count)) % kinds.count]
            guard let plant = ModelLibrary.entity(named: kind.0, targetSize: rng.range(kind.1.lowerBound, kind.1.upperBound)) else { continue }
            plant.position = [x, terrainHeight(x, z), z]
            plant.orientation = simd_quatf(angle: rng.range(0, .pi * 2), axis: [0, 1, 0])
            plant.name = "understory-\(i)"
            root.addChild(plant)
        }
        return root
    }

    static func fence(room: Room) -> Entity {
        let root = Entity()
        root.name = "fence"

        let halfW = Float(room.width / 2000) + 7
        let halfD = Float(room.depth / 2000) + 9
        let pillarHeight: Float = 1.85
        let railHeight: Float = 1.45
        let spacing: Float = 3.2
        let gateHalf: Float = 2.9          // brama 5,8 m

        var stone = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("concrete_diff") {
            stone.baseColor = .init(tint: PlatformColor(white: 0.92, alpha: 1), texture: .init(texture))
            stone.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(1.6, 1.6))
        } else {
            stone.baseColor = .init(tint: PlatformColor(red: 0.86, green: 0.85, blue: 0.82, alpha: 1))
        }
        stone.roughness = .init(floatLiteral: 0.85)

        var metal = PhysicallyBasedMaterial()
        metal.baseColor = .init(tint: PlatformColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1))
        metal.roughness = .init(floatLiteral: 0.45)
        metal.metallic = .init(floatLiteral: 0.85)

        func pillar(_ x: Float, _ z: Float) {
            let entity = ModelEntity(
                mesh: .generateBox(width: 0.42, height: pillarHeight, depth: 0.42, cornerRadius: 0.02),
                materials: [stone]
            )
            entity.position = [x, terrainHeight(x, z) + pillarHeight / 2, z]
            entity.name = "fence-pillar"
            root.addChild(entity)

            let cap = ModelEntity(
                mesh: .generateBox(width: 0.52, height: 0.08, depth: 0.52, cornerRadius: 0.02),
                materials: [stone]
            )
            cap.position = [x, terrainHeight(x, z) + pillarHeight + 0.04, z]
            root.addChild(cap)
        }

        /// Przęsło: pręty pionowe + dwie belki poziome.
        func bay(from a: SIMD2<Float>, to b: SIMD2<Float>) {
            let delta = b - a
            let length = simd_length(delta)
            guard length > 0.3 else { return }
            let angle = atan2(delta.x, delta.y)
            let midX = (a.x + b.x) / 2
            let midZ = (a.y + b.y) / 2
            let base = terrainHeight(midX, midZ)

            for y: Float in [railHeight, 0.35] {
                let rail = ModelEntity(
                    mesh: .generateBox(width: 0.05, height: 0.06, depth: length - 0.42),
                    materials: [metal]
                )
                rail.position = [midX, base + y, midZ]
                rail.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                root.addChild(rail)
            }

            let bars = max(2, Int(length / 0.16))
            for i in 0...bars {
                let t = Float(i) / Float(bars)
                let x = a.x + delta.x * t
                let z = a.y + delta.y * t
                let bar = ModelEntity(
                    mesh: .generateBox(width: 0.025, height: railHeight - 0.32, depth: 0.025),
                    materials: [metal]
                )
                bar.position = [x, base + (railHeight - 0.32) / 2 + 0.32, z]
                root.addChild(bar)
            }
        }

        let runs: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(-halfW, -halfD), SIMD2(halfW, -halfD)),
            (SIMD2(-halfW, -halfD), SIMD2(-halfW, halfD)),
            (SIMD2(halfW, -halfD), SIMD2(halfW, halfD)),
            (SIMD2(-halfW, halfD), SIMD2(-gateHalf, halfD)),
            (SIMD2(gateHalf, halfD), SIMD2(halfW, halfD)),
        ]

        for (a, b) in runs {
            let delta = b - a
            let length = simd_length(delta)
            let count = max(1, Int((length / spacing).rounded()))
            for i in 0...count {
                let t = Float(i) / Float(count)
                pillar(a.x + delta.x * t, a.y + delta.y * t)
            }
            for i in 0..<count {
                let t0 = Float(i) / Float(count)
                let t1 = Float(i + 1) / Float(count)
                bay(from: SIMD2(a.x + delta.x * t0, a.y + delta.y * t0),
                    to: SIMD2(a.x + delta.x * t1, a.y + delta.y * t1))
            }
        }

        // BRAMA: dwa skrzydła otwarte na posesję, zawiasy na słupkach.
        for side in [Float(-1), Float(1)] {
            let leaf = Entity()
            leaf.name = "gate-leaf"
            let width = gateHalf
            for y: Float in [0.4, 1.35] {
                let rail = ModelEntity(
                    mesh: .generateBox(width: width, height: 0.07, depth: 0.06),
                    materials: [metal]
                )
                rail.transform.translation = SIMD3(side * (width / 2), y, 0)
                leaf.addChild(rail)
            }
            let bars = Int(width / 0.16)
            for i in 0...bars {
                let x = side * (Float(i) / Float(bars)) * width
                let bar = ModelEntity(
                    mesh: .generateBox(width: 0.03, height: 1.0, depth: 0.03),
                    materials: [metal]
                )
                bar.transform.translation = SIMD3(x, 0.88, 0)
                leaf.addChild(bar)
            }
            leaf.transform.translation = SIMD3(side * gateHalf, terrainHeight(side * gateHalf, halfD), halfD)
            leaf.transform.rotation = simd_quatf(angle: side * .pi * 0.55, axis: [0, 1, 0])
            root.addChild(leaf)
        }
        return root
    }

    /// CHODNIK wzdłuż drogi — płyty betonowe, 2 m szerokości.
    static func sidewalk(room: Room) -> Entity {
        let root = Entity()
        root.name = "sidewalk"
        let halfD = Float(room.depth / 2000) + 9
        let z = halfD + 6.2

        var material = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("paving_diff") {
            material.baseColor = .init(tint: PlatformColor(white: 0.95, alpha: 1), texture: .init(texture))
            material.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(24, 1.2))
        } else {
            material.baseColor = .init(tint: PlatformColor(red: 0.72, green: 0.71, blue: 0.68, alpha: 1))
        }
        material.roughness = .init(floatLiteral: 0.8)

        let slab = ModelEntity(mesh: .generateBox(width: 160, height: 0.14, depth: 2.0), materials: [material])
        slab.position = [0, 0.07, z]
        slab.name = "sidewalk-slab"
        root.addChild(slab)

        // krawężnik
        var kerb = PhysicallyBasedMaterial()
        kerb.baseColor = .init(tint: PlatformColor(red: 0.62, green: 0.62, blue: 0.60, alpha: 1))
        kerb.roughness = .init(floatLiteral: 0.9)
        let edge = ModelEntity(mesh: .generateBox(width: 160, height: 0.18, depth: 0.18), materials: [kerb])
        edge.position = [0, 0.09, z - 1.05]
        root.addChild(edge)
        return root
    }

    /// RÓW odwadniający między chodnikiem a ogrodzeniem (skarpy + dno).
    static func ditch(room: Room) -> Entity {
        let root = Entity()
        root.name = "ditch"
        let halfD = Float(room.depth / 2000) + 9
        let z = halfD + 3.8

        var soil = PhysicallyBasedMaterial()
        soil.baseColor = .init(tint: PlatformColor(red: 0.30, green: 0.27, blue: 0.20, alpha: 1))
        soil.roughness = .init(floatLiteral: 1.0)

        var gravel = PhysicallyBasedMaterial()
        gravel.baseColor = .init(tint: PlatformColor(red: 0.46, green: 0.45, blue: 0.42, alpha: 1))
        gravel.roughness = .init(floatLiteral: 1.0)

        // dwie skarpy pod kątem — od terenu do dna rowu
        for side in [Float(-1), Float(1)] {
            let slope = ModelEntity(
                mesh: .generateBox(width: 150, height: 0.1, depth: 1.3),
                materials: [soil]
            )
            slope.position = [0, -0.18, z + side * 0.55]
            slope.orientation = simd_quatf(angle: side * .pi * 0.16, axis: [1, 0, 0])
            root.addChild(slope)
        }
        let bottom = ModelEntity(mesh: .generateBox(width: 150, height: 0.06, depth: 0.9), materials: [gravel])
        bottom.position = [0, -0.36, z]
        root.addChild(bottom)
        return root
    }

    static func road(room: Room) -> Entity {
        let root = Entity()
        root.name = "road"
        let z = Float(room.depth / 2000) + 34
        let length: Float = 300
        let width: Float = 7

        var material = PhysicallyBasedMaterial()
        if let asphalt = EnvironmentArt.photoTexture("asphalt_diff") ?? EnvironmentArt.asphalt() {
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
        if let cobble = EnvironmentArt.photoTexture("paving_diff") ?? EnvironmentArt.cobble() {
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

    /// Samochód na podjeździe: model Tesla Model 3 (CC-BY-4.0, Ameer Studio),
    /// a gdy pliku nie ma — bryła proceduralna.
    ///
    /// UWAGA LICENCYJNA: CC-BY wymaga podania autora w aplikacji (stopka/„o
    /// programie”). Model jest fanowski, nie pochodzi od Tesli.
    static func tesla(position: SIMD3<Float>) -> Entity {
        if let model = ModelLibrary.entity(named: "TeslaModel3", targetLength: 4.7, axis: 2) {
            let root = Entity()
            root.name = "tesla"
            root.addChild(model)
            root.position = position
            return root
        }
        return teslaProcedural(position: position)
    }

    /// Zapas, gdy modelu nie da się wczytać: bryła czytelna z 20 m.
    static func teslaProcedural(position: SIMD3<Float>) -> Entity {
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
        material.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        material.faceCulling = .none

        let mesh = MeshFactory.ground(size: 1, tile: 1) ?? .generatePlane(width: 1, depth: 1)
        for i in 0..<options.clouds {
            let cloud = ModelEntity(mesh: mesh, materials: [material])
            let angle = rng.range(0, .pi * 2)
            let distance = rng.range(180, 900)
            let size = rng.range(90, 220)
            cloud.scale = [size, 1, size * rng.range(0.45, 0.7)]
            cloud.position = [cos(angle) * distance, rng.range(110, 260), sin(angle) * distance]
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