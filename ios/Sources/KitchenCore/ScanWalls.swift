import Foundation
import simd

/// Detekcja ścian ze skanu typu „skaner w środku pomieszczenia" (Trimble X9).
///
/// DLACZEGO OSOBNA METODA:
/// `RoomModelBuilder` liczy kontur z obrysu bryły (siatka zajętości + zalewanie
/// z zewnątrz). To działa, gdy chodzisz po pomieszczeniu i widzisz je z zewnątrz
/// (iPad). Skaner stojący w środku daje inny obraz: w rzucie od góry wypełniony
/// wielokąt bez wyróżnionych ścian, a pasmo pod sufitem widzi tylko te ściany,
/// których nie zasłania sufit. Zmierzone na realnym skanie X9: wnętrze 0,0%
/// siatki w KAŻDYM paśmie wysokości — zalewanie zawsze przecieka.
///
/// METODA (ta implementacja): ściany z NORMALNYCH, nie z obrysu.
///  1. dzielimy chmurę na komórki 15 cm (3D) i w każdej liczymy płaszczyznę PCA,
///  2. komórki, których punkty są współpłaszczyznowe (mały rozrzut w trzecim
///     kierunku), dają kandydatów na fragment ściany z normalną,
///  3. grupujemy kandydatów po (normalna, przesunięcie) — to samo co Hough,
///     ale na płatach, nie na pojedynczych punktach, więc jest odporne na szum,
///  4. dla każdej grupy dopasowujemy płaszczyznę do WSZYSTKICH jej punktów
///     i wyznaczamy zasięg (prostokąt na płaszczyźnie),
///  5. zostają płaszczyzny pionowe (normalna pozioma) o sensownym rozmiarze —
///     to ściany. Sufit i podłoga odpadają przez normalną pionową.
///
/// Metoda nie wymaga zamkniętego obrysu, więc działa na skanach częściowych,
/// na rzutach mieszkań i na pomieszczeniach z otworami.
public enum ScanWalls {

    /// Płaszczyzna znaleziona w chmurze.
    public struct Plane: Sendable, Identifiable {
        public var id = UUID()
        /// punkt na płaszczyźnie (metry)
        public var point: SIMD3<Float>
        /// normalna jednostkowa, zwrócona „do wewnątrz" pomieszczenia
        public var normal: SIMD3<Float>
        /// zasięg na płaszczyźnie: dwie osie i półprzekątne (metry)
        public var uAxis: SIMD3<Float>
        public var vAxis: SIMD3<Float>
        public var uMin: Float
        public var uMax: Float
        public var vMin: Float
        public var vMax: Float
        /// liczba punktów wspierających
        public var support: Int
        /// odchyłka punktów od płaszczyzny: mediana i 95 percentyl (metry)
        public var residualMedian: Float
        public var residualP95: Float

        public var width: Float { uMax - uMin }
        public var height: Float { vMax - vMin }
        public var area: Float { width * height }

        public init(point: SIMD3<Float>, normal: SIMD3<Float>,
                    uAxis: SIMD3<Float>, vAxis: SIMD3<Float>,
                    uMin: Float, uMax: Float, vMin: Float, vMax: Float,
                    support: Int, residualMedian: Float = 0, residualP95: Float = 0) {
            self.point = point
            self.normal = normal
            self.uAxis = uAxis
            self.vAxis = vAxis
            self.uMin = uMin
            self.uMax = uMax
            self.vMin = vMin
            self.vMax = vMax
            self.support = support
            self.residualMedian = residualMedian
            self.residualP95 = residualP95
        }

        /// Odległość punktu od płaszczyzny (ze znakiem).
        public func signedDistance(_ p: SIMD3<Float>) -> Float {
            simd_dot(p - point, normal)
        }

        /// Rzut punktu na płaszczyznę → współrzędne (u, v).
        public func project(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let d = p - point
            return SIMD2(simd_dot(d, uAxis), simd_dot(d, vAxis))
        }
    }

    public struct Options: Sendable {
        /// bok komórki 3D (metry) — 15 cm to kompromis: mniejsze dają szum,
        /// większe mieszają ściany pod kątem
        public var cell: Float = 0.15
        /// minimalna liczba punktów w komórce, żeby liczyć PCA
        public var minCellPoints: Int = 40
        /// maksymalny rozrzut w trzecim kierunku (względny), żeby uznać płat
        /// za współpłaszczyznowy — 0,15 = „dość płaski"
        public var planarityThreshold: Float = 0.15
        /// tolerancja odległości od płaszczyzny przy dopasowaniu (metry)
        public var tolerance: Float = 0.02
        /// minimalna liczba punktów płaszczyzny
        public var minSupport: Int = 2_000
        /// minimalne wymiary ściany (metry) — odsiewa fragmenty mebli
        public var minWidth: Float = 0.5
        public var minHeight: Float = 0.5
        /// maksymalne nachylenie normalnej od poziomu (stopnie) — ściany pionowe
        public var maxTiltDeg: Float = 20

        public init() {}
    }

    public struct Result: Sendable {
        public var planes: [Plane]
        /// poziom podłogi (metry)
        public var floorY: Float
        /// poziom sufitu (metry)
        public var ceilingY: Float
        /// pole powierzchni ścian (m²)
        public var wallArea: Float
    }

    // MARK: - główna funkcja

    /// Znajduje ściany w chmurze punktów.
    ///
    /// - Parameter points: punkty w metrach (układ dowolny, ale pion musi być w Y)
    public static func detect(points: [SIMD3<Float>],
                              options: Options = Options()) -> Result? {
        guard points.count > 5_000 else { return nil }

        // 1) płaszczyzny z komórek PCA
        var candidates = planarCells(points: points, options: options)
        guard !candidates.isEmpty else { return nil }

        // 2) grupowanie po (normalna, przesunięcie)
        let groups = groupCandidates(candidates, options: options)

        // 3) dopasowanie każdej grupy do wszystkich punktów + zasięg
        var planes: [Plane] = []
        for group in groups {
            guard let plane = fitPlane(group, points: points, options: options) else { continue }
            // tylko ściany: normalna pozioma
            let tilt = abs(plane.normal.y)
            guard tilt <= sin(options.maxTiltDeg * .pi / 180) else { continue }
            guard plane.width >= options.minWidth, plane.height >= options.minHeight else { continue }
            planes.append(plane)
        }
        guard !planes.isEmpty else { return nil }

        // 4) poziomy podłogi i sufitu z histogramu wysokości
        let (floorY, ceilingY) = detectLevels(points: points)

        return Result(planes: planes, floorY: floorY, ceilingY: ceilingY,
                      wallArea: planes.reduce(0) { $0 + $1.area })
    }

    // MARK: - płaszczyzny z komórek

    /// Kandydat na płat płaski: punkt, normalna, liczba punktów.
    struct Candidate {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
        var count: Int
    }

    /// Dzieli chmurę na komórki 3D i w każdej liczy płaszczyznę PCA.
    ///
    /// Płaski płat (ściana) ma w PCA jeden mały rozrzut — trzeci wektor własny
    /// ma wariancję bliską zeru. Meble, rośliny, zasłony dają rozrzut we
    /// wszystkich kierunkach i odpadają.
    static func planarCells(points: [SIMD3<Float>], options: Options) -> [Candidate] {
        var buckets: [SIMD3<Int32>: [SIMD3<Float>]] = [:]
        buckets.reserveCapacity(points.count / 200)
        let cell = options.cell
        for p in points {
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
            let key = SIMD3(Int32((p.x / cell).rounded()),
                            Int32((p.y / cell).rounded()),
                            Int32((p.z / cell).rounded()))
            buckets[key, default: []].append(p)
        }

        var out: [Candidate] = []
        out.reserveCapacity(buckets.count / 4)
        for (_, pts) in buckets where pts.count >= options.minCellPoints {
            guard let (normal, spread) = planeNormal(pts) else { continue }
            guard spread <= options.planarityThreshold else { continue }
            // punkt odniesienia: centroid
            var c = SIMD3<Float>(0, 0, 0)
            for p in pts { c += p }
            c /= Float(pts.count)
            out.append(Candidate(point: c, normal: normal, count: pts.count))
        }
        return out
    }

    /// Normalna i miara płaskości z PCA.
    ///
    /// Zwraca normalną (najmniejszy wektor własny) i stosunek √(λ3/λ1):
    /// 0 = idealnie płaski płat, 1 = izotropowa chmura (meble, szum).
    static func planeNormal(_ pts: [SIMD3<Float>]) -> (SIMD3<Float>, Float)? {
        guard pts.count >= 3 else { return nil }
        var c = SIMD3<Float>(0, 0, 0)
        for p in pts { c += p }
        c /= Float(pts.count)

        // macierz kowariancji 3×3 — liczymy składowe jawnie, bo `simd_outer_product`
        // nie jest dostępne na wszystkich platformach (brakuje go w SDK macOS)
        var sxx: Float = 0, syy: Float = 0, szz: Float = 0
        var sxy: Float = 0, sxz: Float = 0, syz: Float = 0
        for p in pts {
            let d = p - c
            sxx += d.x * d.x; syy += d.y * d.y; szz += d.z * d.z
            sxy += d.x * d.y; sxz += d.x * d.z; syz += d.y * d.z
        }
        let n = Float(pts.count)
        var cov = simd_float3x3(
            SIMD3(sxx / n, sxy / n, sxz / n),
            SIMD3(sxy / n, syy / n, syz / n),
            SIMD3(sxz / n, syz / n, szz / n)
        )

        // wartości własne macierzy symetrycznej 3×3 — metoda Jacobiego
        var a = cov
        var v = matrix_identity_float3x3
        for _ in 0..<12 {
            // znajdź największy element pozadiagonalny
            var maxOff: Float = 0
            var (p, q) = (0, 1)
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    if abs(a[i][j]) > maxOff { maxOff = abs(a[i][j]); (p, q) = (i, j) }
                }
            }
            if maxOff < 1e-9 { break }
            // obrót Jacobiego
            let theta = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p])
            let s = sin(theta), co = cos(theta)
            var r = matrix_identity_float3x3
            r[p][p] = co; r[q][q] = co
            r[p][q] = -s; r[q][p] = s
            a = r.transpose * a * r
            v = v * r
        }
        let lambda = SIMD3(a[0][0], a[1][1], a[2][2])
        // najmniejsza wartość → normalna
        var idx = 0
        if lambda[1] < lambda[idx] { idx = 1 }
        if lambda[2] < lambda[idx] { idx = 2 }
        let normal = simd_normalize(SIMD3(v[0][idx], v[1][idx], v[2][idx]))

        let l1 = Swift.max(lambda[0], lambda[1], lambda[2])
        let l3 = Swift.min(lambda[0], lambda[1], lambda[2])
        guard l1 > 1e-12 else { return nil }
        let spread = sqrt(Swift.max(0, l3) / l1)
        return (normal, spread)
    }

    // MARK: - grupowanie

    /// Grupuje kandydatów o podobnej normalnej i bliskim przesunięciu.
    ///
    /// To odpowiednik Hough, ale na płatach: każdy płat ma już policzoną
    /// normalną, więc nie trzeba głosować pojedynczymi punktami (co dawało
    /// fałszywe piki od szumu).
    static func groupCandidates(_ candidates: [Candidate],
                                options: Options) -> [[Candidate]] {
        var groups: [[Candidate]] = []
        var used = [Bool](repeating: false, count: candidates.count)

        // sortuj od największych płatów — one wyznaczają ściany
        let order = candidates.indices.sorted { candidates[$0].count > candidates[$1].count }

        for i in order {
            guard !used[i] else { continue }
            let seed = candidates[i]
            var group = [seed]
            used[i] = true

            for j in order where !used[j] {
                let c = candidates[j]
                // ta sama normalna (z tolerancją 12°)
                let dotN = simd_dot(seed.normal, c.normal)
                guard abs(dotN) > cos(12 * .pi / 180) else { continue }
                // to samo przesunięcie (odległość płaszczyzn < 5 cm)
                let offsetDiff = abs(simd_dot(c.point - seed.point, seed.normal))
                guard offsetDiff < 0.05 else { continue }
                group.append(c)
                used[j] = true
            }
            if group.count >= 2 { groups.append(group) }
        }
        return groups
    }

    // MARK: - dopasowanie

    /// Dopasowuje płaszczyznę do wszystkich punktów w pobliżu grupy.
    static func fitPlane(_ group: [Candidate], points: [SIMD3<Float>],
                         options: Options) -> Plane? {
        guard !group.isEmpty else { return nil }

        // normalna: średnia z grupy (ważona liczbą punktów)
        var normal = SIMD3<Float>(0, 0, 0)
        var refPoint = SIMD3<Float>(0, 0, 0)
        var total: Float = 0
        for c in group {
            let w = Float(c.count)
            normal += c.normal * w
            refPoint += c.point * w
            total += w
        }
        guard total > 0 else { return nil }
        normal = simd_normalize(normal)
        refPoint /= total

        // zbierz punkty w pasie tolerancji
        var inliers: [SIMD3<Float>] = []
        inliers.reserveCapacity(Int(total))
        for p in points {
            if abs(simd_dot(p - refPoint, normal)) <= options.tolerance {
                inliers.append(p)
            }
        }
        guard inliers.count >= options.minSupport else { return nil }

        // dopasuj normalną do inlierów (PCA), potem przesunięcie
        guard let (refinedNormal, _) = planeNormal(inliers) else { return nil }
        var centroid = SIMD3<Float>(0, 0, 0)
        for p in inliers { centroid += p }
        centroid /= Float(inliers.count)

        // osie na płaszczyźnie: v w pionie (Y), u prostopadłe
        var up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(refinedNormal, up)) > 0.95 {
            up = SIMD3<Float>(1, 0, 0)  // płaszczyzna pozioma — nie powinno tu trafić
        }
        let vAxis = simd_normalize(up - refinedNormal * simd_dot(up, refinedNormal))
        let uAxis = simd_cross(refinedNormal, vAxis)

        var uMin = Float.greatestFiniteMagnitude, uMax = -Float.greatestFiniteMagnitude
        var vMin = Float.greatestFiniteMagnitude, vMax = -Float.greatestFiniteMagnitude
        var residuals: [Float] = []
        residuals.reserveCapacity(inliers.count)
        for p in inliers {
            let d = p - centroid
            let u = simd_dot(d, uAxis), v = simd_dot(d, vAxis)
            uMin = Swift.min(uMin, u); uMax = Swift.max(uMax, u)
            vMin = Swift.min(vMin, v); vMax = Swift.max(vMax, v)
            residuals.append(abs(simd_dot(p - centroid, refinedNormal)))
        }
        residuals.sort()
        let median = residuals[residuals.count / 2]
        let p95 = residuals[Swift.min(residuals.count - 1, Int(Double(residuals.count) * 0.95))]

        return Plane(point: centroid, normal: refinedNormal,
                     uAxis: uAxis, vAxis: vAxis,
                     uMin: uMin, uMax: uMax, vMin: vMin, vMax: vMax,
                     support: inliers.count, residualMedian: median, residualP95: p95)
    }

    // MARK: - poziomy

    /// Poziom podłogi i sufitu z histogramu wysokości.
    static func detectLevels(points: [SIMD3<Float>]) -> (Float, Float) {
        let ys = points.map(\.y).filter { $0.isFinite }
        guard !ys.isEmpty else { return (0, 2.6) }
        let lo = ys.min()!, hi = ys.max()!
        guard hi - lo > 1.0 else { return (lo, hi) }

        let bin: Float = 0.02
        var hist: [Int: Int] = [:]
        for y in ys {
            let b = Int(((y - lo) / bin).rounded())
            hist[b, default: 0] += 1
        }
        // podłoga: najgęstszy pik w dolnych 30%
        let lowLimit = Int((hi - lo) * 0.3 / bin)
        let floorBin = hist.filter { $0.key <= lowLimit }.max { $0.value < $1.value }?.key
        let floorY = floorBin.map { lo + Float($0) * bin } ?? lo

        // sufit: najgęstszy pik powyżej 1,8 m nad podłogą
        let ceilLimit = Int((floorY + 1.8 - lo) / bin)
        let ceilBin = hist.filter { $0.key >= ceilLimit }.max { $0.value < $1.value }?.key
        let ceilingY = ceilBin.map { lo + Float($0) * bin } ?? (floorY + 2.6)

        return (floorY, ceilingY)
    }
}
