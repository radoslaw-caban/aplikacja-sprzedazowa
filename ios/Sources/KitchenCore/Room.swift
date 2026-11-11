import Foundation

/// Pomieszczenie w milimetrach — punkt odniesienia dla zabudowy i dla skanu.
public struct Room: Codable, Sendable, Equatable {
    public var name: String
    public var width: Double   // X
    public var depth: Double   // Z
    public var height: Double  // Y

    public init(name: String = "Pomieszczenie", width: Double = 5000, depth: Double = 5000, height: Double = 2600) {
        self.name = name
        self.width = width
        self.depth = depth
        self.height = height
    }

    public var area: Double { width * depth / 1_000_000 } // m²

    /// Ściany: 0 = północ (−Z), 1 = południe (+Z), 2 = zachód (−X), 3 = wschód (+X)
    public func wallPosition(_ index: Int, thickness: Double = 100) -> SIMD3<Double> {
        switch index {
        case 0: SIMD3(0, height / 2, -depth / 2 - thickness / 2)
        case 1: SIMD3(0, height / 2, depth / 2 + thickness / 2)
        case 2: SIMD3(-width / 2 - thickness / 2, height / 2, 0)
        default: SIMD3(width / 2 + thickness / 2, height / 2, 0)
        }
    }

    public func wallSize(_ index: Int, thickness: Double = 100) -> SIMD3<Double> {
        switch index {
        case 0, 1: SIMD3(width + thickness * 2, height, thickness)
        default: SIMD3(thickness, height, depth)
        }
    }
}

/// Transformacja chmury punktów do układu projektu.
///
/// Skan jest w swoim własnym układzie (kamera skanera) — dopiero ta transformacja
/// przenosi go do pokoju. Kolejność: skala → obrót wokół Y → przesunięcie (w metrach).
public struct ScanTransform: Codable, Sendable, Equatable {
    public var scale: Double          // 1.0 = bez zmiany
    public var rotationDeg: Double    // 0/90/180/270 i dowolne pośrednie
    public var offset: SIMD3<Double>  // metry (X, Y, Z)

    public init(scale: Double = 1, rotationDeg: Double = 0, offset: SIMD3<Double> = .zero) {
        self.scale = scale
        self.rotationDeg = rotationDeg
        self.offset = offset
    }

    /// Przekształcenie punktu chmury (w metrach) na współrzędne sceny (metry).
    public func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let a = rotationDeg * .pi / 180
        let c = cos(a), s = sin(a)
        let x = Double(p.x) * scale
        let z = Double(p.z) * scale
        let rx = x * c + z * s
        let rz = -x * s + z * c
        return SIMD3(Float(rx + offset.x), Float(Double(p.y) * scale + offset.y), Float(rz + offset.z))
    }

    /// Odwrotność `apply`: ze współrzędnych sceny do współrzędnych chmury.
    public func inverseApply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let a = rotationDeg * .pi / 180
        let c = cos(a), s = sin(a)
        let wx = Double(p.x) - offset.x
        let wz = Double(p.z) - offset.z
        // odwrotny obrót
        let x = wx * c - wz * s
        let z = wx * s + wz * c
        let inv = scale == 0 ? 1 : 1 / scale
        return SIMD3(Float(x * inv), Float((Double(p.y) - offset.y) * inv), Float(z * inv))
    }

    /// Automatyczne dopasowanie: skala z obrytu, środek na środku pokoju, podłoga na y = 0.
    public static func autoFit(
        cloudMin: SIMD3<Float>,
        cloudMax: SIMD3<Float>,
        room: Room,
        rotationDeg: Double = 0
    ) -> ScanTransform {
        let w = Double(cloudMax.x - cloudMin.x)
        let d = Double(cloudMax.z - cloudMin.z)
        guard w > 0.001, d > 0.001 else { return ScanTransform() }

        let roomW = room.width / 1000
        let roomD = room.depth / 1000

        // skala: chmura ma zmieścić się w pokoju (z 2% luzem)
        let scale = min((roomW * 0.98) / w, (roomD * 0.98) / d)

        // obrót zmienia wymiary w rzucie — po obrocie liczymy obrys ponownie
        let a = rotationDeg * .pi / 180
        let swap = abs(sin(a)) > 0.5
        let spanX = (swap ? d : w) * scale
        let spanZ = (swap ? w : d) * scale

        // środek chmury po obrocie (obrót wokół początku układu chmury)
        let cx = Double(cloudMin.x + cloudMax.x) / 2 * scale
        let cz = Double(cloudMin.z + cloudMax.z) / 2 * scale
        let c = cos(a), s = sin(a)
        let rcx = cx * c + cz * s
        let rcz = -cx * s + cz * c

        return ScanTransform(
            scale: scale,
            rotationDeg: rotationDeg,
            offset: SIMD3(
                -rcx,                                   // środek X na 0
                -Double(cloudMin.y) * scale,            // podłoga na 0
                -rcz
            )
        )
    }

    /// Obrys chmury po transformacji (metry) — do kadrowania kamery.
    public func transformedBounds(min: SIMD3<Float>, max: SIMD3<Float>) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = apply(min), hi = apply(min)
        let corners: [SIMD3<Float>] = [
            min,
            SIMD3(max.x, min.y, min.z),
            SIMD3(min.x, max.y, min.z),
            SIMD3(min.x, min.y, max.z),
            SIMD3(max.x, max.y, min.z),
            SIMD3(max.x, min.y, max.z),
            SIMD3(min.x, max.y, max.z),
            max,
        ]
        for c in corners {
            let p = apply(c)
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }

}
