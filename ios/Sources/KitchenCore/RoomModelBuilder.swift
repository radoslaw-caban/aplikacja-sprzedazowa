import Foundation
import simd

/// Detekcja modelu pomieszczenia z chmury punktów.
///
/// METODA (i dlaczego nie inne — sprawdzone na testach):
///  - **obrys z bounding boxa** obejmuje meble i punkty odstające: w tym
///    projekcie dawał 10,35 × 9,02 m przy realnej podłodze 8,94 × 6,22 m,
///  - **profil promieniowy od środka** (odległość ściany w funkcji kąta) nie
///    działa: dla ściany promień nie jest kawałkami liniowy, więc uproszczenie
///    konturu łapie fałszywe załamania — prostokąt 4×3 m rozpadł się na
///    8 narożników o bokach 0,35 / 0,48 / 1,31 / 1,48 m,
///  - **PCA lokalnych normalnych → linie → przecięcia** (ta implementacja):
///    1. dzielimy pas przy podłodze na komórki 10 cm i w każdej liczymy
///       kierunek PCA — na ścianie punkty układają się wzdłuż ściany,
///    2. histogram (kąt, przesunięcie) z tych komórek daje linie ścian,
///    3. każdą linię dopasowujemy ponownie do WSZYSTKICH punktów w pasie
///       (najmniejsze kwadraty), więc dokładność nie zależy od siatki komórek,
///    4. narożniki = przecięcia linii o RÓŻNYCH kierunkach, których przecięcie
///       leży w zakresie obu odcinków. Pary równoległe odpadają same — dlatego
///       Hough z przecięć „sąsiednich pików kątowych" gubił narożniki,
///    5. narożniki łączymy w kontur przez graf (wspólna linia) i przechodzimy
///       cykl — to działa też dla pomieszczeń niewypukłych (L, T), gdzie
///       sortowanie kątowe względem środka daje zły porządek.
///
/// Cała matematyka jest czysta (tablice + simd), więc testuje się bez iPada.
public extension RoomModel {

    // MARK: - budowa modelu

    /// Buduje model pomieszczenia z punktów pomiarowych.
    ///
    /// - Parameters:
    ///   - samples: punkty w metrach (układ ARKit: Y w górę, podłoga ≈ y=0)
    ///   - options: parametry detekcji
    /// - Returns: model albo `nil`, gdy chmura nie ma sensownej podłogi
    static func build(from samples: [Sample], options: Options = Options()) -> Result? {
        guard samples.count > 500 else { return nil }

        // 1) poziom podłogi — najgęstszy pik wysokości (LiDAR zawsze widzi podłogę)
        guard let floorY = detectFloor(samples: samples) else { return nil }
        // 2) poziom sufitu — najgęstszy pik powyżej 1,8 m nad podłogą
        let ceilingY = detectCeiling(samples: samples, floorY: floorY) ?? (floorY + 2.6)
        let height = Swift.max(1.8, ceilingY - floorY)

        // 3) punkty przy podłodze → kontur w planie
        let floorBand = samples.filter {
            $0.position.y >= floorY - 0.03 && $0.position.y <= floorY + options.floorBand
        }
        guard floorBand.count > 200 else { return nil }

        // 4) linie ścian z PCA lokalnych normalnych
        let plan = floorBand.map { SIMD2($0.position.x, $0.position.z) }
        guard let outline = roomOutline(points: plan, options: options),
              outline.count >= 3 else { return nil }

        let corners = outline.map {
            Corner(x: $0.x, z: $0.y, yMin: floorY, yMax: ceilingY, confidence: 1)
        }

        // 5) ściany: każda krawędź konturu + dopasowanie płaszczyzny
        let walls = fitWalls(corners: corners, samples: samples, options: options)
        guard walls.count >= 3 else { return nil }

        // 6) otwory (okna/drzwi) — po dopasowaniu ścian, bo potrzebują normalnej
        let openings = detectOpenings(walls: walls, samples: samples, floorY: floorY,
                                      height: height, options: options)

        // 7) pole powierzchni i jakość narożników
        let area = polygonArea(corners)
        let cornerSigma: Float = options.wallTolerance / 4

        return Result(corners: corners, walls: walls, openings: openings,
                      height: height, area: area, cornerSigma: cornerSigma)
    }

    // MARK: - poziomy podłogi i sufitu

    /// Najgęstszy pik histogramu wysokości w dolnej części skanu.
    static func detectFloor(samples: [Sample], bin: Float = 0.02) -> Float? {
        let ys = samples.map(\.position.y).filter { $0.isFinite }
        guard ys.count > 100 else { return nil }
        let lo = ys.min()!, hi = ys.max()!
        guard hi - lo > 0.5 else { return nil }

        var hist: [Int: Int] = [:]
        for y in ys {
            let b = Int(((y - lo) / bin).rounded())
            hist[b, default: 0] += 1
        }
        // podłoga to najgęstszy pik w dolnych 40% wysokości
        let limit = Int((hi - lo) * 0.4 / bin)
        let best = hist.filter { $0.key <= limit }.max { $0.value < $1.value }
        guard let b = best?.key else { return nil }
        return lo + Float(b) * bin
    }

    /// Najgęstszy pik powyżej 1,8 m nad podłogą (sufit).
    static func detectCeiling(samples: [Sample], floorY: Float, bin: Float = 0.02) -> Float? {
        let ys = samples.map(\.position.y).filter { $0.isFinite && $0 > floorY + 1.8 }
        guard ys.count > 100 else { return nil }
        let lo = ys.min()!

        var hist: [Int: Int] = [:]
        for y in ys {
            let b = Int(((y - lo) / bin).rounded())
            hist[b, default: 0] += 1
        }
        guard let best = hist.max(by: { $0.value < $1.value }) else { return nil }
        let y = lo + Float(best.key) * bin
        // sensowna wysokość pomieszczenia: 2,0–4,5 m
        return (y - floorY > 2.0 && y - floorY < 4.5) ? y : nil
    }

    // MARK: - linie ścian

    /// Linia ściany w planie (metry).
    struct WallLine: Sendable {
        /// punkt na linii
        public var point: SIMD2<Float>
        /// kierunek jednostkowy (wzdłuż ściany)
        public var direction: SIMD2<Float>
        /// zakres wzdłuż ściany (od `point`, w metrach)
        public var tMin: Float
        public var tMax: Float
        /// liczba punktów wspierających
        public var support: Int

        public init(point: SIMD2<Float>, direction: SIMD2<Float>,
                    tMin: Float, tMax: Float, support: Int) {
            self.point = point
            self.direction = direction
            self.tMin = tMin
            self.tMax = tMax
            self.support = support
        }

        /// normalna w planie
        public var normal: SIMD2<Float> { SIMD2(-direction.y, direction.x) }
        /// przesunięcie normalne od początku układu
        public var offset: Float { simd_dot(point, normal) }
        public var length: Float { tMax - tMin }
        /// kąt w stopniach 0…180
        public var angleDeg: Double {
            // zwrot kanoniczny (dir.x ≥ 0) → kąt w [-90°, 90°] → sprowadzony do [0°, 180°)
            normalizeAngle180(Double(atan2(direction.y, direction.x)) * 180 / .pi)
        }
    }

    /// Wyznacza kontur pomieszczenia: linie ścian → narożniki → cykl.
    static func roomOutline(points: [SIMD2<Float>], options: Options) -> [SIMD2<Float>]? {
        guard points.count > 100 else { return nil }

        // 1) linie z histogramu (kąt, przesunięcie) lokalnych normalnych
        var lines = detectWallLines(points: points, options: options)
        guard lines.count >= 3 else { return nil }

        // 2) scal linie opisujące tę samą ścianę (bliski kąt i przesunięcie)
        lines = mergeLines(lines, options: options)

        // 3) narożniki = przecięcia linii o różnych kierunkach, w zakresach
        guard let corners = intersect(lines: lines, options: options),
              corners.count >= 3 else { return nil }

        // 4) uporządkuj w kontur (graf: narożniki na wspólnej linii)
        return orderContour(corners: corners, lines: lines)
    }

    /// Wykrywa linie ścian jako piki histogramu (kąt, przesunięcie).
    ///
    /// Pomysł: w komórce 10 cm leżącej na ścianie punkty tworzą odcinek wzdłuż
    /// ściany, więc PCA takiej komórki daje kierunek ściany. Histogram par
    /// (kierunek normalnej, przesunięcie normalne) ma ostre piki na ścianach.
    ///
    /// Sam histogram nie wystarcza — „cięciwa" przez środek pomieszczenia też
    /// zbiera wsparcie, bo wpadają w nią punkty podłogi (zmierzone: 750–820
    /// punktów przy 1175–1900 na prawdziwych ścianach). Dlatego każdy kandydat
    /// przechodzi test „ściana ma pokój po jednej stronie, pustkę po drugiej".
    static func detectWallLines(points: [SIMD2<Float>], options: Options) -> [WallLine] {
        let cell: Float = 0.10
        var buckets: [SIMD2<Int32>: [SIMD2<Float>]] = [:]
        for p in points {
            let key = SIMD2(Int32((p.x / cell).rounded()), Int32((p.y / cell).rounded()))
            buckets[key, default: []].append(p)
        }

        // siatka zajętości podłogi (do testu „pusto po jednej stronie")
        let grid = OccupancyGrid(points: points, cell: 0.05)

        // histogram: kąt normalnej co 2°, przesunięcie co 2 cm
        let angleBins = 180
        let offsetBin: Float = 0.02
        var hist: [SIMD2<Int32>: Int] = [:]
        var usedCells = 0
        for (_, pts) in buckets where pts.count >= 5 {
            guard let theta = pcaAngle(pts) else { continue }
            // odrzucamy komórki bez kierunku (podłoga w środku pomieszczenia)
            guard let spread = pcaSpread(pts), spread < 0.25 else { continue }
            usedCells += 1

            // ta sama kanonizacja co w fitLine — inaczej jedna ściana trafia
            // do dwóch koszy (normalna + normalna przeciwna)
            let dir = canonicalDirection(SIMD2<Float>(Float(cos(theta)), Float(sin(theta))))
            let normal = SIMD2<Float>(-dir.y, dir.x)
            let cx = pts.reduce(Float(0)) { $0 + $1.x } / Float(pts.count)
            let cy = pts.reduce(Float(0)) { $0 + $1.y } / Float(pts.count)
            let d = simd_dot(SIMD2(cx, cy), normal)

            // tolerancyjne zawijanie — patrz normalizeAngle180
            let angDeg = normalizeAngle180(Double(atan2(normal.y, normal.x)) * 180 / .pi)
            let aBin = Int32(angDeg.rounded()) % Int32(angleBins)
            let oBin = Int32((d / offsetBin).rounded())
            hist[SIMD2(aBin, oBin), default: 0] += pts.count
        }
        guard !hist.isEmpty, usedCells >= 3 else { return [] }

        let maxSupport = hist.values.max() ?? 0
        let threshold = Swift.max(options.minCornerSamples, maxSupport / 6)

        var candidates: [(a: Double, off: Float, support: Int)] = []
        for (key, support) in hist where support >= threshold {
            candidates.append((Double(key.x), Float(key.y) * offsetBin, support))
        }
        guard !candidates.isEmpty else { return [] }
        candidates.sort { $0.support > $1.support }

        var peaks: [(a: Double, off: Float)] = []
        for c in candidates {
            let tooClose = peaks.contains {
                angleDiff180($0.a, c.a) < options.mergeAngleDeg && abs($0.off - c.off) < 0.10
            }
            if !tooClose { peaks.append((c.a, c.off)) }
        }

        let debug = ProcessInfo.processInfo.environment["ROOM_DEBUG"] != nil
        if debug {
            for pk in peaks {
                FileHandle.standardError.write(Data(String(format:
                    "    PIK kąt %6.1f° off %7.3f\n", pk.a, pk.off).utf8))
            }
        }

        var lines: [WallLine] = []
        for peak in peaks {
            let normal = SIMD2<Float>(Float(cos(peak.a * .pi / 180)), Float(sin(peak.a * .pi / 180)))
            var inliers: [SIMD2<Float>] = []
            for p in points where abs(simd_dot(p, normal) - peak.off) <= options.wallTolerance {
                inliers.append(p)
            }
            guard inliers.count >= options.minCornerSamples else { continue }
            guard var fitted = fitLine(inliers) else { continue }

            // DOPASOWANIE ITERACYJNE: pierwsze pasmo wybieramy normalną z kosza
            // histogramu (dokładność 1°), a taka normalna obcina końce długiej
            // ściany — zmierzone: ściana 4 m przekrzywiła się o 0,9°, przez co
            // zakres skrócił się o 0,87 m i narożnik wypadł poza linię.
            // Po dopasowaniu normalna jest dokładna, więc wybieramy pasmo ponownie.
            for _ in 0..<2 {
                let current = fitted
                var refined: [SIMD2<Float>] = []
                for p in points
                where abs(simd_dot(p - current.point, current.normal)) <= options.wallTolerance {
                    refined.append(p)
                }
                guard refined.count >= options.minCornerSamples,
                      let next = fitLine(refined) else { break }
                fitted = next
            }

            let ok = isBoundaryLine(fitted, grid: grid)
            if debug {
                FileHandle.standardError.write(Data(String(format:
                    "    LINIA kąt %6.1f° off %7.3f wsp %d granica %@\n",
                    fitted.angleDeg, fitted.offset, inliers.count, ok ? "TAK" : "nie").utf8))
            }
            guard ok else { continue }
            lines.append(fitted)
        }
        return lines
    }

    /// Siatka zajętości w planie — do testów przestrzennych bez O(n²).
    struct OccupancyGrid {
        var cell: Float
        var origin: SIMD2<Float>
        var width: Int
        var height: Int
        var occupied: [Bool]

        init(points: [SIMD2<Float>], cell: Float) {
            guard !points.isEmpty else {
                self.cell = cell; self.origin = .zero
                self.width = 0; self.height = 0; self.occupied = []
                return
            }
            var lo = points[0], hi = points[0]
            for p in points {
                lo = simd_min(lo, p); hi = simd_max(hi, p)
            }
            // margines 0,5 m, żeby test „na zewnątrz" miał gdzie pytać
            self.origin = lo - SIMD2(repeating: 0.5)
            self.cell = cell
            let span = hi - lo + SIMD2(repeating: 1.0)
            self.width = Swift.max(1, Int(span.x / cell) + 1)
            self.height = Swift.max(1, Int(span.y / cell) + 1)
            self.occupied = [Bool](repeating: false, count: width * height)

            for p in points {
                let g = (p - origin) / cell
                let ix = Int(g.x.rounded()), iy = Int(g.y.rounded())
                // zapalamy komórkę i sąsiadów — zamyka dziury w chmurze
                for dx in -1...1 {
                    for dy in -1...1 {
                        let x = ix + dx, y = iy + dy
                        guard x >= 0, x < width, y >= 0, y < height else { continue }
                        occupied[y * width + x] = true
                    }
                }
            }
        }

        func isOccupied(_ world: SIMD2<Float>) -> Bool {
            guard width > 0 else { return false }
            let g = (world - origin) / cell
            let ix = Int(g.x.rounded()), iy = Int(g.y.rounded())
            guard ix >= 0, ix < width, iy >= 0, iy < height else { return false }
            return occupied[iy * width + ix]
        }

        /// Ile komórek jest zajętych w odległościach `from…to` po stronie `side`
        /// (1 = zgodnie z normalną, -1 = przeciwnie).
        func occupancy(on side: Float, at point: SIMD2<Float>, normal: SIMD2<Float>,
                       from: Float = 0.14, to: Float = 0.45) -> Int {
            var count = 0
            var d = from
            while d <= to {
                if isOccupied(point + normal * (d * side)) { count += 1 }
                d += 0.05
            }
            return count
        }
    }

    /// Test: czy linia jest granicą pomieszczenia (a nie cięciwą przez środek).
    ///
    /// Ściana ma punkty po jednej stronie (wnętrze) i pustkę po drugiej.
    /// Cięciwa przez podłogę ma punkty po obu stronach — dlatego sama liczba
    /// punktów przy linii nie wystarcza do rozpoznania ściany.
    static func isBoundaryLine(_ line: WallLine, grid: OccupancyGrid) -> Bool {
        let steps = 20
        let normal = line.normal
        var inside = 0
        var outside = 0
        let debug = ProcessInfo.processInfo.environment["ROOM_DEBUG"] != nil
        for k in 0...steps {
            let t = line.tMin + (line.tMax - line.tMin) * Float(k) / Float(steps)
            let p = line.point + line.direction * t
            let a = grid.occupancy(on: 1, at: p, normal: normal)
            let b = grid.occupancy(on: -1, at: p, normal: normal)
            inside += Swift.max(a, b)
            outside += Swift.min(a, b)
        }
        if debug {
            FileHandle.standardError.write(Data(String(format:
                "       t %.2f…%.2f p(%.2f,%.2f) dir(%.2f,%.2f) n(%.2f,%.2f) in %d out %d → %@\n",
                line.tMin, line.tMax, line.point.x, line.point.y,
                line.direction.x, line.direction.y, normal.x, normal.y,
                inside, outside,
                (inside >= steps / 3 && Float(outside) / Float(Swift.max(1, inside)) < 0.15)
                    ? "TAK" : "nie").utf8))
        }
        // musi być wnętrze po jednej stronie i prawie nic po drugiej
        guard inside >= steps / 3 else { return false }
        return Float(outside) / Float(Swift.max(1, inside)) < 0.15
    }

    /// Dopasowuje linię do zbioru punktów (najmniejsze kwadraty, PCA).
    ///
    /// Zwraca kierunek, punkt (centroid) i zakres wzdłuż linii.
    static func fitLine(_ pts: [SIMD2<Float>]) -> WallLine? {
        guard pts.count >= 3 else { return nil }
        let n = Float(pts.count)
        let cx = pts.reduce(Float(0)) { $0 + $1.x } / n
        let cy = pts.reduce(Float(0)) { $0 + $1.y } / n
        let centroid = SIMD2(cx, cy)

        var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        // zwrot kanoniczny — patrz canonicalDirection (bez tego scalały się
        // naprzeciwległe ściany: zmierzone 4 ściany → 2)
        let dir = canonicalDirection(SIMD2<Float>(Float(cos(theta)), Float(sin(theta))))

        var tMin = Float.greatestFiniteMagnitude
        var tMax = -Float.greatestFiniteMagnitude
        for p in pts {
            let t = simd_dot(p - centroid, dir)
            tMin = Swift.min(tMin, t)
            tMax = Swift.max(tMax, t)
        }
        return WallLine(point: centroid, direction: dir,
                        tMin: tMin, tMax: tMax, support: pts.count)
    }

    /// Sprowadza kąt do zakresu [0°, 180°) — z tolerancją.
    ///
    /// Musi być tolerancyjna: `atan2(ε, -1)` daje 179,99999°, a nie 180°, więc
    /// naiwne `if d >= 180 { d -= 180 }` NIE zawija takiego kąta. Skutek:
    /// jedna i ta sama ściana trafia do dwóch koszy histogramu (179,99999° i 0°)
    /// i pojawia się dwa razy w wyniku.
    static func normalizeAngle180(_ d: Double) -> Double {
        var a = d.truncatingRemainder(dividingBy: 180)
        if a < 0 { a += 180 }
        if a >= 179.9 { a -= 180 }
        if a < 0 { a = 0 }
        return a
    }

    /// Kanonizuje zwrot kierunku linii: zawsze `dir.x ≥ 0`.
    ///
    /// Musi być stosowana WSZĘDZIE, gdzie liczymy linię — i w histogramie, i w
    /// dopasowaniu. Bez tego jedna ściana trafia do dwóch koszy histogramu
    /// (normalna i normalna przeciwna), więc ta sama ściana pojawia się dwa
    /// razy, a naprzeciwległa ściana wypada z detekcji. Zmierzone na prostokącie
    /// 4×3: 4 ściany → 2 kosze, kontur się nie domykał.
    static func canonicalDirection(_ dir: SIMD2<Float>) -> SIMD2<Float> {
        (dir.x < -1e-6 || (abs(dir.x) <= 1e-6 && dir.y < 0)) ? -dir : dir
    }

    /// Kąt dominujący (radiany) z PCA punktów w planie.
    static func pcaAngle(_ pts: [SIMD2<Float>]) -> Double? {
        guard pts.count >= 3 else { return nil }
        let n = Float(pts.count)
        let cx = pts.reduce(Float(0)) { $0 + $1.x } / n
        let cy = pts.reduce(Float(0)) { $0 + $1.y } / n
        var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        return Double(0.5 * atan2(2 * sxy, sxx - syy))
    }

    /// Rozrzut punktów wokół kierunku dominującego (pierwiastek stosunku wariancji).
    ///
    /// Na ścianie punkty leżą wzdłuż linii → wynik blisko 0.
    /// Na podłodze są rozrzucone w obu kierunkach → wynik blisko 1.
    /// To pozwala odsiać komórki, w których PCA nie ma sensownego kierunku.
    static func pcaSpread(_ pts: [SIMD2<Float>]) -> Float? {
        guard pts.count >= 3 else { return nil }
        let n = Float(pts.count)
        let cx = pts.reduce(Float(0)) { $0 + $1.x } / n
        let cy = pts.reduce(Float(0)) { $0 + $1.y } / n
        var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        // wartości własne macierzy kowariancji 2×2 (wzór jawny)
        let tr = sxx + syy
        let det = sxx * syy - sxy * sxy
        let disc = Swift.max(0, tr * tr / 4 - det)
        let root = disc.squareRoot()
        let l1 = tr / 2 + root
        let l2 = tr / 2 - root
        guard l1 > 1e-9 else { return nil }
        return (Swift.max(0, l2) / l1).squareRoot()
    }

    /// Różnica kątów z zawijaniem na 180°.
    static func angleDiff180(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 180)
        if d > 90 { d = 180 - d }
        return d
    }

    /// Scala linie opisujące tę samą ścianę.
    ///
    /// Ta sama ściana wykryta z dwóch fragmentów chmury ma ten sam kąt i
    /// przesunięcie, ale inny zakres. Scalamy, wydłużając zakres — inaczej
    /// powstałyby dwa równoległe odcinki i fałszywy „narożnik" między nimi.
    static func mergeLines(_ lines: [WallLine], options: Options) -> [WallLine] {
        var out: [WallLine] = []
        for line in lines.sorted(by: { $0.support > $1.support }) {
            var merged = false
            for i in 0..<out.count {
                let a = out[i]
                // Porównujemy ODLEGŁOŚĆ PROSTOPADŁĄ między liniami, a nie
                // różnicę offsetów: offset zależy od zwrotu normalnej, więc
                // naprzeciwległe ściany (x=+2 i x=-2) potrafią mieć ten sam
                // offset i zostać scalone w jedną (zmierzone: 4 ściany → 3,
                // a potem → 2). Odległość punktu jednej prostej od drugiej jest
                // nieujemna i niezależna od znaku.
                let perpendicularGap = abs(simd_dot(line.point - a.point, a.normal))
                if angleDiff180(a.angleDeg, line.angleDeg) < options.mergeAngleDeg,
                   perpendicularGap < 0.06 {
                    // przedłuź zakres obu odcinków do wspólnej osi
                    let dir = a.direction
                    var lo = Float.greatestFiniteMagnitude
                    var hi = -Float.greatestFiniteMagnitude
                    for probe in [a.point + dir * a.tMin, a.point + dir * a.tMax,
                                  line.point + dir * line.tMin, line.point + dir * line.tMax] {
                        let t = simd_dot(probe - a.point, dir)
                        lo = Swift.min(lo, t); hi = Swift.max(hi, t)
                    }
                    out[i] = WallLine(point: a.point, direction: dir,
                                      tMin: lo, tMax: hi,
                                      support: a.support + line.support)
                    merged = true
                    break
                }
            }
            if !merged { out.append(line) }
        }
        return out
    }

    /// Narożniki: przecięcia linii o różnych kierunkach, mieszczące się w zakresach.
    static func intersect(lines: [WallLine], options: Options) -> [SIMD2<Float>]? {
        guard lines.count >= 3 else { return nil }
        var out: [SIMD2<Float>] = []
        // ile razy dany punkt już dodano (zbieżność 3 linii w jednym narożniku)
        func alreadyThere(_ p: SIMD2<Float>) -> Bool {
            out.contains { simd_length($0 - p) < 0.05 }
        }

        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                let a = lines[i], b = lines[j]
                let det = a.direction.x * b.direction.y - a.direction.y * b.direction.x
                // równoległe (albo prawie) — brak narożnika
                guard abs(det) > 0.15 else { continue }

                let ab = b.point - a.point
                let t = (ab.x * b.direction.y - ab.y * b.direction.x) / det
                let p = a.point + a.direction * t

                // Przecięcie musi leżeć w zakresie OBIE linii, ale z dużym
                // marginesem: wykryty zakres linii bywa krótszy od ściany
                // (punkty przy narożniku trafiają do sąsiedniej ściany), a wtedy
                // prawdziwy narożnik wypada poza zakres i znika — zmierzone:
                // narożnik (2, -1,47) leżał 0,64 m poza końcem wykrytej linii.
                let margin: Float = 0.7
                let tb = simd_dot(p - b.point, b.direction)
                if ProcessInfo.processInfo.environment["ROOM_DEBUG"] != nil {
                    FileHandle.standardError.write(Data(String(format:
                        "      %5.1f x %5.1f → (%.3f, %.3f) t=%.2f [%.2f,%.2f] tb=%.2f [%.2f,%.2f] %@\n",
                        a.angleDeg, b.angleDeg, p.x, p.y, t, a.tMin, a.tMax, tb, b.tMin, b.tMax,
                        (t >= a.tMin - margin && t <= a.tMax + margin
                         && tb >= b.tMin - margin && tb <= b.tMax + margin) ? "OK" : "poza").utf8))
                }
                guard t >= a.tMin - margin, t <= a.tMax + margin,
                      tb >= b.tMin - margin, tb <= b.tMax + margin else { continue }
                guard !alreadyThere(p) else { continue }
                out.append(p)
            }
        }
        return out.count >= 3 ? out : nil
    }

    /// Porządkuje narożniki w zamknięty kontur.
    ///
    /// Kolejność bierzemy z grafu: dwa narożniki sąsiadują, gdy leżą na tej
    /// samej linii i nic nie stoi między nimi. Sortowanie kątowe względem środka
    /// odpada — dla pomieszczeń niewypukłych (L, T) daje przestawiony obrys.
    static func orderContour(corners: [SIMD2<Float>], lines: [WallLine]) -> [SIMD2<Float>]? {
        guard corners.count >= 3 else { return nil }

        // zbuduj listę sąsiadów: dla każdej linii weź narożniki leżące NA niej
        // (w tolerancji), posortuj wzdłuż i połącz kolejne.
        //
        // Wcześniej filtrowałem po zakresie t, ale narożnik jest przecięciem
        // dwóch linii, więc może wypaść kilka cm poza wykryty zakres jednej
        // z nich — dlatego decyduje odległość od linii, nie zakres.
        let onLineTolerance: Float = 0.08
        var adjacency: [[Int]] = Array(repeating: [], count: corners.count)
        for line in lines {
            let members = (0..<corners.count)
                .map { (idx: $0, t: simd_dot(corners[$0] - line.point, line.direction),
                        d: abs(simd_dot(corners[$0] - line.point, line.normal))) }
                .filter { $0.d <= onLineTolerance }
                .sorted { $0.t < $1.t }
            guard members.count >= 2 else { continue }
            for k in 0..<(members.count - 1) {
                let i = members[k].idx, j = members[k + 1].idx
                if !adjacency[i].contains(j) { adjacency[i].append(j) }
                if !adjacency[j].contains(i) { adjacency[j].append(i) }
            }
        }

        // przejdź cykl grafowy, zaczynając od narożnika o najmniejszym indeksie
        var visited = [Bool](repeating: false, count: corners.count)
        var order: [Int] = []
        var current = 0
        visited[0] = true
        order.append(0)
        while true {
            let next = adjacency[current].first { !visited[$0] }
            guard let n = next else { break }
            visited[n] = true
            order.append(n)
            current = n
        }
        // kontur musi objąć wszystkie narożniki — inaczej wykrycie jest niespójne
        guard order.count == corners.count else { return nil }
        return order.map { corners[$0] }
    }

    // MARK: - ściany z dopasowaniem płaszczyzny

    /// Dopasowuje płaszczyznę do punktów każdej krawędzi konturu.
    ///
    /// Płaszczyzna jest **pionowa** (normalna pozioma) — tak wygląda ściana.
    /// Wyznaczamy średnie przesunięcie normalne punktów w pasie odcinka,
    /// a potem liczymy odchyłki: medianę (typowe wygięcie) i p95 (najgorsze
    /// miejsce) oraz pion z porównania dolnej i górnej połowy punktów.
    ///
    /// To jest odpowiedź na „ściana nie jest płaszczyzną": model nie wygładza
    /// wybrzuszenia, tylko je raportuje (`residualP95`) i pokazuje nachylenie
    /// (`plumbMmPerM`).
    static func fitWalls(corners: [Corner], samples: [Sample], options: Options) -> [Wall] {
        guard corners.count >= 3 else { return [] }
        var walls: [Wall] = []

        for i in 0..<corners.count {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            let start = a.plan
            let end = b.plan
            let dir = end - start
            let len = simd_length(dir)
            guard len >= options.minWallLength else { continue }
            let unit = dir / len
            let normal2 = SIMD2<Float>(-unit.y, unit.x)

            var inBand: [SIMD3<Float>] = []
            inBand.reserveCapacity(2048)
            for s in samples {
                let p2 = SIMD2(s.position.x, s.position.z)
                let t = simd_dot(p2 - start, unit)
                guard t >= -0.02, t <= len + 0.02 else { continue }
                let d = simd_dot(p2 - start, normal2)
                guard abs(d) <= options.wallTolerance else { continue }
                guard s.position.y >= a.yMin - 0.02, s.position.y <= a.yMax + 0.02 else { continue }
                inBand.append(s.position)
            }
            guard inBand.count >= options.minCornerSamples else { continue }

            let meanD = inBand.reduce(Float(0)) { $0 + simd_dot(SIMD2($1.x, $1.z) - start, normal2) }
                / Float(inBand.count)
            let planePoint = SIMD3<Float>(start.x + normal2.x * meanD, a.yMin, start.y + normal2.y * meanD)
            let planeNormal = SIMD3<Float>(normal2.x, 0, normal2.y)

            var residuals: [Float] = []
            residuals.reserveCapacity(inBand.count)
            for p in inBand {
                residuals.append(abs(simd_dot(p - planePoint, planeNormal)))
            }
            residuals.sort()
            let median = residuals[residuals.count / 2]
            let p95 = residuals[Swift.min(residuals.count - 1, Int(Double(residuals.count) * 0.95))]

            // pion: porównanie średniego przesunięcia dolnej i górnej połowy
            let midY = (a.yMin + a.yMax) / 2
            var lowSum: Float = 0, lowN: Float = 0
            var highSum: Float = 0, highN: Float = 0
            for p in inBand {
                let d = simd_dot(p - planePoint, planeNormal)
                if p.y < midY { lowSum += d; lowN += 1 } else { highSum += d; highN += 1 }
            }
            var plumb: Float = 0
            if lowN > 5, highN > 5 {
                let delta = (highSum / highN) - (lowSum / lowN)
                let halfHeight = (a.yMax - a.yMin) / 2
                if halfHeight > 0.1 { plumb = delta / halfHeight * 1000 }
            }

            walls.append(Wall(start: start, end: end,
                              planePoint: planePoint, planeNormal: planeNormal,
                              residualMedian: median, residualP95: p95,
                              plumbMmPerM: plumb, samples: inBand.count))
        }
        return walls
    }

    // MARK: - otwory

    /// Wykrywa okna i drzwi jako przerwy w pokryciu ściany punktami.
    ///
    /// Ściana bez otworu ma punkty na całej wysokości. Okno i drzwi to obszar,
    /// gdzie punktów NIE MA — i to jest cała detekcja: skanujemy siatkę
    /// „wysokość × długość" ściany i szukamy dziur o prostokątnym kształcie.
    /// Rozróżnienie: drzwi sięgają podłogi (sill ≈ 0), okno nie.
    static func detectOpenings(walls: [Wall], samples: [Sample], floorY: Float,
                               height: Float, options: Options) -> [Opening] {
        var out: [Opening] = []
        let cellU: Float = 0.10
        let cellV: Float = 0.10

        for (wi, wall) in walls.enumerated() {
            let len = wall.length
            guard len > 0.5 else { continue }
            let unit = wall.direction
            let cols = Int(len / cellU)
            let rows = Int(height / cellV)
            guard cols > 3, rows > 3 else { continue }

            var grid = [Bool](repeating: false, count: cols * rows)
            for s in samples {
                let p2 = SIMD2(s.position.x, s.position.z)
                let t = simd_dot(p2 - wall.start, unit)
                guard t >= 0, t < len else { continue }
                let d = wall.signedDistance(s.position)
                guard abs(d) <= options.wallTolerance else { continue }
                let relY = s.position.y - floorY
                guard relY >= 0, relY < height else { continue }
                let c = Swift.min(cols - 1, Int(t / cellU))
                let r = Swift.min(rows - 1, Int(relY / cellV))
                grid[r * cols + c] = true
            }

            // kolumny CAŁKOWICIE puste w pionie = prawdziwe otwory
            // (pojedyncze dziury to szum i meble)
            var emptyRuns: [(start: Int, end: Int)] = []
            var runStart: Int? = nil
            for c in 0..<cols {
                var filled = 0
                for r in 0..<rows where grid[r * cols + c] { filled += 1 }
                let isEmpty = filled <= 1
                if isEmpty, runStart == nil { runStart = c }
                if !isEmpty, let s = runStart { emptyRuns.append((s, c - 1)); runStart = nil }
            }
            if let s = runStart { emptyRuns.append((s, cols - 1)) }

            for run in emptyRuns {
                let width = Float(run.end - run.start + 1) * cellU
                guard width >= 0.4, width <= len * 0.95 else { continue }

                var lowestEmpty = rows
                var highestEmpty = -1
                for c in run.start...run.end {
                    for r in 0..<rows where !grid[r * cols + c] {
                        lowestEmpty = Swift.min(lowestEmpty, r)
                        highestEmpty = Swift.max(highestEmpty, r)
                    }
                }
                guard highestEmpty >= lowestEmpty else { continue }
                let sill = Float(lowestEmpty) * cellV
                let top = Float(highestEmpty + 1) * cellV
                let h = top - sill
                guard h >= 0.4 else { continue }

                let kind: Opening.Kind = sill <= 0.15 ? .door : .window
                out.append(Opening(wallIndex: wi, kind: kind,
                                   offset: Float(run.start) * cellU,
                                   width: width, sill: sill, height: h))
            }
        }
        return out
    }

    // MARK: - geometria planu

    /// Pole powierzchni wielokąta (wzór sznurowadła).
    static func polygonArea(_ corners: [Corner]) -> Float {
        guard corners.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in 0..<corners.count {
            let a = corners[i].plan
            let b = corners[(i + 1) % corners.count].plan
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
