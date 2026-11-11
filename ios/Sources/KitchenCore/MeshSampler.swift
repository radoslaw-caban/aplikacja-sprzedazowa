import Foundation
import simd

/// Trójkąt siatki ARKit w przestrzeni świata (metry) z kolorem.
///
/// Celowo NIE importuje ARKit — dzięki temu próbkowanie siatki da się
/// przetestować na macOS, bez iPada i bez symulatora (`swift run KitchenChecks`).
public struct ScanTriangle: Sendable {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var c: SIMD3<Float>
    public var color: SIMD3<UInt8>

    public init(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, color: SIMD3<UInt8>) {
        self.a = a
        self.b = b
        self.c = c
        self.color = color
    }
}

/// Próbkowanie siatki pomieszczenia (z ARKit) do chmury punktów.
///
/// METODA: iterujemy siatkę ŚWIATOWĄ o boku `step` po obrysie trójkąta
/// i zostawiamy punkty leżące w trójkącie. Zalety względem losowych próbek
/// barycentrycznych:
///  - dokładnie jeden punkt na komórkę siatki → znana, równomierna gęstość,
///  - brak kolizji wewnątrz trójkąta, więc nic nie jest gubione,
///  - determinizm bez generatora pseudolosowego (ten sam skan = ten sam plik),
///  - wspólne krawędzie sąsiednich trójkątów trafiają w te same komórki
///    i są odsiewane globalnym zbiorem `seen` — bez „szwów" z podwójnych punktów.
public enum MeshSampler {

    /// Krok próbkowania w METRACH. 0.02 = punkt co 2 cm.
    /// Dla kuchni 3×3×2,6 m (≈40 m² powierzchni) to ~1 mln punktów.
    public static let defaultStep: Float = 0.02

    /// Próbkuje trójkąty do chmury punktów.
    ///
    /// - Parameters:
    ///   - triangles: trójkąty w metrach (układ ARKit, worldAlignment = .gravity)
    ///   - step: bok komórki siatki w metrach
    ///   - maxPoints: twardy limit, żeby eksport nie zjadł pamięci
    /// - Returns: chmura w METRACH (konwersja na mm należy do wołającego)
    public static func sample(
        triangles: [ScanTriangle],
        step: Float = defaultStep,
        maxPoints: Int = 4_000_000
    ) -> PointCloud {
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<UInt8>] = []
        let cell = Swift.max(step, 0.004)
        var seen = Set<SIMD3<Int64>>()
        seen.reserveCapacity(Swift.min(maxPoints, 1 << 20))
        positions.reserveCapacity(Swift.min(maxPoints, 1 << 20))
        colors.reserveCapacity(Swift.min(maxPoints, 1 << 20))

        for tri in triangles {
            let e1 = tri.b - tri.a
            let e2 = tri.c - tri.a
            let area = simd_length(simd_cross(e1, e2)) * 0.5
            // odrzuć zdegenerowane i niefizyczne
            guard area.isFinite, area > 0 else { continue }

            let lo = simd_min(simd_min(tri.a, tri.b), tri.c)
            let hi = simd_max(simd_max(tri.a, tri.b), tri.c)
            guard lo.x.isFinite, hi.x.isFinite, lo.y.isFinite, hi.y.isFinite,
                  lo.z.isFinite, hi.z.isFinite else { continue }
            // 10 km w każdą stronę — dalej to artefakt trackingu, nie pomieszczenie
            guard abs(lo.x) < 10_000, abs(lo.y) < 10_000, abs(lo.z) < 10_000,
                  abs(hi.x) < 10_000, abs(hi.y) < 10_000, abs(hi.z) < 10_000 else { continue }

            let n = simd_normalize(simd_cross(e1, e2))
            guard n.x.isFinite, n.y.isFinite, n.z.isFinite else { continue }

            // Iterujemy tylko po dwóch osiach — trójkąt jest płaski, więc po osi
            // o największej składowej normalnej ma zerowy zakres. Trzecia
            // współrzędna wynika z równania płaszczyzny n·(p - a) = 0.
            let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
            let dropAxis: Int = ax >= ay && ax >= az ? 0 : (ay >= az ? 1 : 2)

            let i0x = Int64((lo.x / cell).rounded(.down))
            let i1x = Int64((hi.x / cell).rounded(.up))
            let i0y = Int64((lo.y / cell).rounded(.down))
            let i1y = Int64((hi.y / cell).rounded(.up))
            let i0z = Int64((lo.z / cell).rounded(.down))
            let i1z = Int64((hi.z / cell).rounded(.up))

            let uRange: ClosedRange<Int64>
            let vRange: ClosedRange<Int64>
            switch dropAxis {
            case 0: uRange = i0y...i1y; vRange = i0z...i1z
            case 1: uRange = i0x...i1x; vRange = i0z...i1z
            default: uRange = i0x...i1x; vRange = i0y...i1y
            }

            // Siatka rzutu nie może być absurdalnie duża: ARKit przy zerwanym
            // trackingu generuje „płaszczyzny" o boku kilometrów. Limit chroni
            // przed zawieszeniem eksportu na takim artefakcie.
            // Bezpieczne mnożenie: przy artefaktach ARKit zakresy bywają ogromne
            // i `count * count` przelewa Int64 (crash), dlatego dzielimy.
            let uc = uRange.count, vc = vRange.count
            guard uc > 0, vc > 0, uc <= 60_000_000, vc <= 60_000_000, uc <= 60_000_000 / vc else { continue }
            _ = uc * vc   // kontrola przepełnienia wyżej

            let denom: Float = dropAxis == 0 ? n.x : (dropAxis == 1 ? n.y : n.z)
            guard abs(denom) > 1e-9 else { continue }

            for iv in vRange {
                let pv = Float(iv) * cell
                for iu in uRange {
                    let pu = Float(iu) * cell

                    var p: SIMD3<Float>
                    switch dropAxis {
                    case 0:
                        let num = simd_dot(n, tri.a - SIMD3<Float>(0, pu, pv))
                        p = SIMD3<Float>(num / denom, pu, pv)
                    case 1:
                        let num = simd_dot(n, tri.a - SIMD3<Float>(pu, 0, pv))
                        p = SIMD3<Float>(pu, num / denom, pv)
                    default:
                        let num = simd_dot(n, tri.a - SIMD3<Float>(pu, pv, 0))
                        p = SIMD3<Float>(pu, pv, num / denom)
                    }

                    guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
                    guard inside(p, tri, normal: n) else { continue }

                    // klucz woksela z RZECZYWISTEJ pozycji — dwa trójkąty
                    // o różnych orientacjach muszą się zdeduplikować na styku
                    let key = SIMD3<Int64>(
                        Int64((p.x / cell).rounded()),
                        Int64((p.y / cell).rounded()),
                        Int64((p.z / cell).rounded())
                    )
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    positions.append(p)
                    colors.append(tri.color)

                    if positions.count >= maxPoints {
                        return PointCloud(positions: positions, colors: colors)
                    }
                }
            }
        }
        return PointCloud(positions: positions, colors: colors)
    }

    /// Test przynależności punktu do trójkąta w 3D.
    ///
    /// Rzutujemy punkt na płaszczyznę trójkąta i sprawdzamy znaki iloczynów
    /// wektorowych względem każdej krawędzi. Rzutowanie jest konieczne, bo
    /// punkt siatki leży zwykle minimalnie poza płaszczyzną trójkąta.
    static func inside(_ p: SIMD3<Float>, _ t: ScanTriangle, normal: SIMD3<Float>) -> Bool {
        let d = simd_dot(p - t.a, normal)
        let q = p - normal * d

        let eps: Float = 1e-6
        let c1 = simd_dot(simd_cross(t.b - t.a, q - t.a), normal)
        let c2 = simd_dot(simd_cross(t.c - t.b, q - t.b), normal)
        let c3 = simd_dot(simd_cross(t.a - t.c, q - t.c), normal)

        let hasNeg = c1 < -eps || c2 < -eps || c3 < -eps
        let hasPos = c1 > eps || c2 > eps || c3 > eps
        return !(hasNeg && hasPos)
    }

    /// Normalna trójkąta (znormalizowana); `nil` dla zdegenerowanych.
    public static func normal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float>? {
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len.isFinite, len > 1e-9 else { return nil }
        return n / len
    }
}
