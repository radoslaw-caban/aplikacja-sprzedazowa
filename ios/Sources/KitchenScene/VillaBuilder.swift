import Foundation
import RealityKit
import KitchenCore
import simd

/// Nowoczesna willa: dwie białe bryły, płaskie dachy z ciemną attyką,
/// przeszklenia z ciepłym światłem, grafitowe panele, drewniane lamele,
/// taras z pergolą i basen przed domem.
///
/// DLACZEGO OSOBNY BUILDER: dotychczasowy dom był „pudełkiem z dachem
/// dwuspadowym". Współczesna willa to kilka prostopadłościanów o różnych
/// głębokościach, płaskie dachy i duże przeszklenia — geometrycznie inny
/// zestaw elementów, który nie pasuje do starej funkcji.
@MainActor
public enum VillaBuilder {

    /// Skorupa willi: elewacja, dachy, przeszklenia, taras, basen.
    /// Geometria wewnętrzna (ściany, podłoga) zostaje w `SceneBuilder`.
    public static func shell(room: Room, plan: FloorPlan? = nil) -> Entity {
        _ = plan
        let root = Entity()
        root.name = "villa"

        let w = Float(room.width / 1000)
        let d = Float(room.depth / 1000)
        let h = Float(room.height / 1000)

        // MARK: materiały

        var white = PhysicallyBasedMaterial()
        if let stucco = EnvironmentArt.photoTexture("stucco_diff") {
            white.baseColor = .init(tint: PlatformColor(white: 0.98, alpha: 1), texture: .init(stucco))
        } else {
            white.baseColor = .init(tint: PlatformColor(white: 0.95, alpha: 1))
        }
        white.roughness = .init(floatLiteral: 0.75)

        var graphite = PhysicallyBasedMaterial()
        graphite.baseColor = .init(tint: PlatformColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1))
        graphite.roughness = .init(floatLiteral: 0.55)
        graphite.metallic = .init(floatLiteral: 0.05)

        var frame = PhysicallyBasedMaterial()
        frame.baseColor = .init(tint: PlatformColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1))
        frame.roughness = .init(floatLiteral: 0.4)

        // SZYBY PRZEŹROCZYSTE: widać przez nie wnętrze, a nie lustrzaną taflę.
        // Lekki chłód i odbicie zostają — szyba ma być szkłem, nie dziurą.
        var warmGlass = PhysicallyBasedMaterial()
        warmGlass.baseColor = .init(tint: PlatformColor(red: 0.80, green: 0.88, blue: 0.92, alpha: 0.15))
        warmGlass.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        warmGlass.roughness = .init(floatLiteral: 0.04)
        warmGlass.metallic = .init(floatLiteral: 0.05)

        var wood = PhysicallyBasedMaterial()
        if let texture = EnvironmentArt.photoTexture("wood_diff") {
            wood.baseColor = .init(tint: PlatformColor(white: 0.95, alpha: 1), texture: .init(texture))
            wood.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(1, 2))
        } else {
            wood.baseColor = .init(tint: PlatformColor(red: 0.62, green: 0.44, blue: 0.28, alpha: 1))
        }
        wood.roughness = .init(floatLiteral: 0.8)

        var concrete = PhysicallyBasedMaterial()
        if let tex = EnvironmentArt.photoTexture("concrete_diff") {
            // tekstura 2k z Poly Haven (CC0) — beton wygląda jak beton
            concrete.baseColor = .init(tint: PlatformColor(white: 0.95, alpha: 1), texture: .init(tex))
            concrete.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(3, 3))
        } else if let tex = EnvironmentArt.concrete() {
            concrete.baseColor = .init(tint: PlatformColor(white: 0.92, alpha: 1), texture: .init(tex))
        } else {
            concrete.baseColor = .init(tint: PlatformColor(white: 0.78, alpha: 1))
        }
        concrete.roughness = .init(floatLiteral: 0.85)

        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: PlatformColor(red: 0.16, green: 0.52, blue: 0.82, alpha: 1))
        water.roughness = .init(floatLiteral: 0.05)
        water.metallic = .init(floatLiteral: 0.1)
        water.blending = .transparent(opacity: .init(floatLiteral: 0.88))

        var planting = PhysicallyBasedMaterial()
        planting.baseColor = .init(tint: PlatformColor(red: 0.22, green: 0.38, blue: 0.20, alpha: 1))
        planting.roughness = .init(floatLiteral: 1.0)

        // MARK: 1) parter — biała bryła
        let ground = ModelEntity(
            mesh: MeshFactory.texturedBox(width: w + 0.4, height: h, depth: d + 0.4, tile: 2.6) ?? .generateBox(width: w, height: h, depth: d),
            materials: [white]
        )
        ground.position = [0, h / 2, 0]
        ground.name = "villa-ground"
        root.addChild(ground)

        // MARK: 2) piętro — bryła przesunięta i wyższa o 15 cm
        let upperH = h * 0.92
        let upperW = w * 0.74
        let upperD = d * 0.9
        let upper = ModelEntity(
            mesh: MeshFactory.texturedBox(width: upperW, height: upperH, depth: upperD, tile: 2.6) ?? .generateBox(width: upperW, height: upperH, depth: upperD),
            materials: [white]
        )
        upper.position = [-w * 0.08, h + upperH / 2, d * 0.04]
        upper.name = "villa-upper"
        root.addChild(upper)

        // MARK: 3) płaskie dachy z ciemną attyką
        func flatRoof(width: Float, depth: Float, center: SIMD3<Float>, bodyHeight: Float) {
            // płyta dachu
            let slab = ModelEntity(
                mesh: .generateBox(width: width + 0.5, height: 0.22, depth: depth + 0.5, cornerRadius: 0.01),
                materials: [concrete]
            )
            slab.position = [center.x, bodyHeight + 0.11, center.z]
            root.addChild(slab)

            // attyka: ciemna opaska dookoła (czytelna linia dachu)
            let fasciaHeight: Float = 0.42
            let fasciaThickness: Float = 0.16
            for side in [Float(-1), Float(1)] {
                let front = ModelEntity(
                    mesh: .generateBox(width: width + 0.5, height: fasciaHeight, depth: fasciaThickness, cornerRadius: 0.01),
                    materials: [graphite]
                )
                front.position = [center.x, bodyHeight + 0.22 + fasciaHeight / 2, center.z + side * (depth / 2 + 0.25)]
                root.addChild(front)

                let flank = ModelEntity(
                    mesh: .generateBox(width: fasciaThickness, height: fasciaHeight, depth: depth + 0.5, cornerRadius: 0.01),
                    materials: [graphite]
                )
                flank.position = [center.x + side * (width / 2 + 0.25), bodyHeight + 0.22 + fasciaHeight / 2, center.z]
                root.addChild(flank)
            }
        }

        flatRoof(width: w + 0.4, depth: d + 0.4, center: SIMD3(0, 0, 0), bodyHeight: h)
        flatRoof(width: upperW, depth: upperD, center: SIMD3(-w * 0.08, 0, d * 0.04), bodyHeight: h + upperH)

        // MARK: 4) przeszklenia

        /// Tafla szkła z ramą: rama to ciemna płyta pod spodem, szkło 6 cm przed nią.
        func glazing(
            width: Float,
            height: Float,
            center: SIMD3<Float>,
            mullions: Int,
            material: PhysicallyBasedMaterial
        ) {
            // RAMA, nie płyta: wcześniej w tym miejscu była pełna ciemna płyta,
            // która zasłaniała wnętrze — szyba pokazywała „czarną dziurę".
            let bar: Float = 0.07
            let horizontal = ModelEntity(
                mesh: .generateBox(width: width + bar * 2, height: bar, depth: 0.10),
                materials: [frame]
            )
            for side in [Float(-1), Float(1)] {
                let copy = horizontal.clone(recursive: true)
                copy.position = [center.x, center.y + side * (height / 2 + bar / 2), center.z]
                root.addChild(copy)
            }
            let vertical = ModelEntity(
                mesh: .generateBox(width: bar, height: height, depth: 0.10),
                materials: [frame]
            )
            for side in [Float(-1), Float(1)] {
                let copy = vertical.clone(recursive: true)
                copy.position = [center.x + side * (width / 2 + bar / 2), center.y, center.z]
                root.addChild(copy)
            }

            let pane = ModelEntity(
                mesh: .generateBox(width: width, height: height, depth: 0.08, cornerRadius: 0.005),
                materials: [material]
            )
            pane.position = [center.x, center.y, center.z + 0.04]
            root.addChild(pane)

            // słupki między szybami
            if mullions > 1 {
                let step = width / Float(mullions)
                for i in 1..<mullions {
                    let post = ModelEntity(
                        mesh: .generateBox(width: 0.06, height: height, depth: 0.10, cornerRadius: 0.005),
                        materials: [frame]
                    )
                    post.position = [center.x - width / 2 + step * Float(i), center.y, center.z + 0.06]
                    root.addChild(post)
                }
            }
        }

        let facadeZ = d / 2 + 0.22

        // parter: szeroka przeszklenia salonu
        glazing(width: w * 0.52, height: h * 0.62, center: SIMD3(-w * 0.16, h * 0.36, facadeZ), mullions: 4, material: warmGlass)
        // parter: ciemny panel garażowy / wejściowy
        let garagePanel = ModelEntity(
            mesh: .generateBox(width: w * 0.26, height: h * 0.55, depth: 0.08, cornerRadius: 0.01),
            materials: [graphite]
        )
        garagePanel.position = [w * 0.3, h * 0.30, facadeZ]
        root.addChild(garagePanel)

        // piętro: duża szyba + grafitowy panel
        glazing(width: upperW * 0.55, height: upperH * 0.55,
                center: SIMD3(-w * 0.08 - upperW * 0.18, h + upperH * 0.5, d * 0.04 + upperD / 2 + 0.22),
                mullions: 3, material: warmGlass)
        let upperPanel = ModelEntity(
            mesh: .generateBox(width: upperW * 0.34, height: upperH * 0.72, depth: 0.08, cornerRadius: 0.01),
            materials: [graphite]
        )
        upperPanel.position = [w * 0.14, h + upperH * 0.5, d * 0.04 + upperD / 2 + 0.22]
        root.addChild(upperPanel)

        // MARK: 4b) wnętrze widoczne przez szyby
        var interiorFloor = PhysicallyBasedMaterial()
        if let wood = EnvironmentArt.photoTexture("wood_diff") {
            interiorFloor.baseColor = .init(tint: PlatformColor(white: 0.92, alpha: 1), texture: .init(wood))
        } else {
            interiorFloor.baseColor = .init(tint: PlatformColor(red: 0.62, green: 0.50, blue: 0.36, alpha: 1))
        }
        interiorFloor.roughness = .init(floatLiteral: 0.6)

        let floorInner = ModelEntity(
            mesh: MeshFactory.texturedBox(width: w - 0.5, height: 0.04, depth: d - 0.5, tile: 2)
                ?? .generateBox(width: w - 0.5, height: 0.04, depth: d - 0.5),
            materials: [interiorFloor]
        )
        floorInner.position = [0, 0.02, 0]
        root.addChild(floorInner)

        // ściana tylna i wyspa kuchenna — dają głębię za szybą
        let backWall = ModelEntity(
            mesh: .generateBox(width: w - 0.6, height: h * 0.92, depth: 0.12),
            materials: [white]
        )
        backWall.position = [0, h * 0.46, -d / 2 + 0.2]
        root.addChild(backWall)

        var islandMaterial = PhysicallyBasedMaterial()
        islandMaterial.baseColor = .init(tint: PlatformColor(red: 0.90, green: 0.89, blue: 0.87, alpha: 1))
        islandMaterial.roughness = .init(floatLiteral: 0.35)
        let island = ModelEntity(
            mesh: .generateBox(width: min(4.2, w * 0.5), height: 0.92, depth: 0.8, cornerRadius: 0.03),
            materials: [islandMaterial]
        )
        island.position = [0, 0.46, -d * 0.12]
        island.name = "kitchen-island"
        root.addChild(island)

        // ciepła "poświata" wnętrza: bez niej szyba pokazuje ciemną dziurę
        var glowMaterial = PhysicallyBasedMaterial()
        glowMaterial.baseColor = .init(tint: PlatformColor(red: 0.55, green: 0.45, blue: 0.34, alpha: 1))
        glowMaterial.emissiveColor = .init(color: PlatformColor(red: 0.95, green: 0.78, blue: 0.55, alpha: 1))
        glowMaterial.emissiveIntensity = 0.45
        glowMaterial.roughness = .init(floatLiteral: 0.9)
        let glowPanel = ModelEntity(
            mesh: .generateBox(width: w * 0.92, height: h * 0.66, depth: 0.06),
            materials: [glowMaterial]
        )
        glowPanel.position = [0, h * 0.40, -d / 2 + 0.45]
        glowPanel.name = "interior-glow"
        root.addChild(glowPanel)

        // ciepłe światło wnętrza (punktowe kule pod stropem)
        for i in 0..<4 {
            var lamp = UnlitMaterial(color: PlatformColor(red: 1.0, green: 0.88, blue: 0.68, alpha: 1))
            lamp.faceCulling = .none
            let bulb = ModelEntity(mesh: .generateSphere(radius: 0.10), materials: [lamp])
            bulb.position = [-w * 0.3 + Float(i) * (w * 0.2), h * 0.82, 0]
            root.addChild(bulb)
        }

        // MARK: 5) drewniane lamele przy wejściu
        let slatCount = 14
        for i in 0..<slatCount {
            let slat = ModelEntity(
                mesh: .generateBox(width: 0.08, height: h * 0.8, depth: 0.16, cornerRadius: 0.005),
                materials: [wood]
            )
            slat.position = [w * 0.5 + 0.28, h * 0.45, -d * 0.28 + Float(i) * 0.22]
            root.addChild(slat)
        }

        // MARK: 6) taras z pergolą
        let terraceDepth: Float = 4.2
        let terrace = ModelEntity(
            mesh: MeshFactory.texturedBox(width: w * 0.86, height: 0.18, depth: terraceDepth, tile: 1.2)
                ?? .generateBox(width: w * 0.86, height: 0.18, depth: terraceDepth),
            materials: [concrete]
        )
        terrace.position = [-w * 0.04, 0.09, facadeZ + terraceDepth / 2]
        terrace.name = "terrace"
        root.addChild(terrace)

        // pergola: 4 słupy + belki
        let pergolaZ = facadeZ + terraceDepth - 0.3
        let pergolaW = w * 0.5
        for sx in [Float(-1), Float(1)] {
            for sz in [Float(0), Float(1)] {
                let post = ModelEntity(mesh: .generateBox(width: 0.14, height: 2.6, depth: 0.14), materials: [frame])
                post.position = [sx * pergolaW / 2, 1.3, sz == 0 ? facadeZ + 0.4 : pergolaZ]
                root.addChild(post)
            }
            let beam = ModelEntity(
                mesh: .generateBox(width: 0.12, height: 0.16, depth: terraceDepth - 0.7),
                materials: [frame]
            )
            beam.position = [sx * pergolaW / 2, 2.62, facadeZ + terraceDepth / 2]
            root.addChild(beam)
        }
        let crossBar = ModelEntity(mesh: .generateBox(width: pergolaW, height: 0.14, depth: 0.12), materials: [frame])
        crossBar.position = [0, 2.62, pergolaZ]
        root.addChild(crossBar)

        // MARK: 7) basen
        let poolW: Float = min(9, w * 0.7)
        let poolD: Float = 4.2
        let poolZ = facadeZ + terraceDepth + 1.6 + poolD / 2

        // niecka: jasna opaska
        let coping = ModelEntity(
            mesh: .generateBox(width: poolW + 0.7, height: 0.16, depth: poolD + 0.7, cornerRadius: 0.02),
            materials: [concrete]
        )
        coping.position = [0, 0.08, poolZ]
        root.addChild(coping)

        // lustro wody (lekko wpuszczone w opaskę)
        let waterSurface = ModelEntity(
            mesh: .generateBox(width: poolW, height: 0.06, depth: poolD, cornerRadius: 0.01),
            materials: [water]
        )
        waterSurface.position = [0, 0.13, poolZ]
        waterSurface.name = "pool-water"
        root.addChild(waterSurface)

        // MARK: 8) meble i rośliny — modele z paczki (Poly Haven, CC0)
        if let sofa = ModelLibrary.entity(named: "TerraceSofa", targetSize: 2.4) {
            sofa.position = [-w * 0.14, 0.18, facadeZ + terraceDepth - 1.1]
            sofa.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            sofa.name = "terrace-sofa"
            root.addChild(sofa)
        }
        let plantSpots: [SIMD3<Float>] = [
            SIMD3(-w * 0.36, 0.18, facadeZ + 0.5),
            SIMD3(w * 0.06, 0.18, facadeZ + 0.45),
            SIMD3(poolW / 2 + 1.0, 0.16, poolZ + poolD / 2 - 1.0),
        ]
        for (i, spot) in plantSpots.enumerated() {
            if let plant = ModelLibrary.entity(named: "TerracePlant", targetSize: 1.0) {
                plant.position = spot
                plant.name = "terrace-plant-\(i)"
                root.addChild(plant)
            }
        }

        // więcej zieleni: krzewy wzdłuż tarasu i basenu, różne rozmiary
        var bushSpots: [SIMD3<Float>] = []
        for i in 0..<9 {
            let t = Float(i) / 8
            bushSpots.append(SIMD3(-w * 0.42 + t * w * 0.84, 0.22 + Float(i % 3) * 0.06, facadeZ + 0.55))
        }
        for i in 0..<5 {
            let t = Float(i) / 4
            bushSpots.append(SIMD3(-poolW / 2 - 0.9 + t * 0.4, 0.24, poolZ - poolD / 2 + 0.5 + t * poolD))
            bushSpots.append(SIMD3(poolW / 2 + 0.9, 0.24, poolZ - poolD / 2 + 0.5 + t * poolD))
        }
        for (i, spot) in bushSpots.enumerated() {
            // najpierw prawdziwy model rośliny, kula tylko jako zapas
            if let plant = ModelLibrary.entity(named: "TerracePlant", targetSize: 0.6 + Float(i % 3) * 0.18) {
                plant.orientation = simd_quatf(angle: Float(i) * 1.1, axis: [0, 1, 0])
                plant.position = spot
                plant.name = "bush-\(i)"
                root.addChild(plant)
            } else {
                let radius = 0.34 + Float(i % 4) * 0.07
                let bush = ModelEntity(mesh: .generateSphere(radius: radius), materials: [planting])
                bush.scale = [1.35, 0.72, 1.35]
                bush.position = spot
                bush.name = "bush-\(i)"
                root.addChild(bush)
            }
        }

        // MARK: 9) oświetlenie elewacji (małe punkty nad tarasem)
        for i in 0..<5 {
            var lamp = UnlitMaterial(color: PlatformColor(red: 1.0, green: 0.92, blue: 0.76, alpha: 1))
            lamp.faceCulling = .none
            let light = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [lamp])
            light.position = [-w * 0.3 + Float(i) * (w * 0.15), h - 0.25, facadeZ + 0.12]
            root.addChild(light)
        }

        return root
    }
}
