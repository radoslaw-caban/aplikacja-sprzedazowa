import Foundation
import simd

/// Detekcja modelu pomieszczenia z chmury punktów.
///
/// METODA (i dlaczego nie inne — każda odrzucona na podstawie pomiarów):
///
///  - **obrys z bounding boxa** — obejmuje meble i punkty odstające: dawał
///    10,35 × 9,02 m przy realnej podłodze 8,94 × 6,22 m.
///  - **profil promieniowy od środka** (odległość ściany w funkcji kąta) —
///    dla ściany promień nie jest kawałkami liniowy, więc uproszczenie konturu
///    łapie fałszywe załamania: prostokąt 4×3 m rozpadł się na 8 narożników.
///  - **Hough / histogram (kąt normalnej, przesunięcie)** — wymaga spójnego
///    zwrotu normalnej. PCA zwraca zwrot losowo, więc ta sama ściana trafiała
///    do dwóch koszy, a naprzeciwległe ściany bywały scalane (zmierzone:
///    4 ściany → 2 lub 3). Da się to łatać, ale każda łata psuła inny
///    przypadek — to nie jest metoda, którą chce się utrzymywać.
///  - **siatka zajętości + śledzenie konturu** (ta implementacja) — działa na
///    zbiorze, nie na parametrach, więc nie ma problemu ze znakami:
///    1. punkty przy podłodze → siatka 3 cm,
///    2. komórki zajęte pogrubiamy o jedną komórkę i zalewamy z zewnątrz:
///       wszystko, czego zalewanie nie dosięgło, to wnętrze pomieszczenia
///       (dziury w chmurze zostają wypełnione automatycznie),
///    3. śledzimy kontur brzegu (Moore) i upraszczamy go (Douglas–Peucker) →
///       przybliżone narożniki,
///    4. **dopracowanie**: każdą krawędź dopasowujemy do SUROWYCH punktów
///       w jej pobliżu (najmniejsze kwadraty), a narożniki liczymy jako
///       przecięcia sąsiednich dopasowanych linii. Bez tego kontur byłby
///       przesunięty o grubość pogrubienia siatki.
///
/// Metoda z kroku 2–4 jest niezależna od kształtu, więc obsługuje też
/// pomieszczenia niewypukłe (L, T, wnęka na pion).
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

        // 3) kontur: pasmo pod sufitem (poziom nadproży), nie przy podłodze.
        //
        // DLACZEGO NIE PRZY PODŁODZE: drzwi sięgają podłogi, więc ściana jest
        // przy podłodze PRZERWANA. Zalewanie z zewnątrz wpływa wtedy przez
        // otwór, wnętrze łączy się z zewnętrzem i kontur się rozrywa —
        // zmierzone na pokoju 5×4 z drzwiami: 7 narożników i bok 0,37 m.
        // Nadproże (nad drzwiami i oknami) jest ciągłe, więc pasmo pod sufitem
        // daje zamknięty obrys. Poniżej, dla porównania, pasmo przy podłodze.
        let top = ceilingY > floorY ? ceilingY : wallTop(samples: samples, floorY: floorY)
        var outlinePoints = samples.filter {
            $0.position.y >= top - 0.4 && $0.position.y <= top - 0.02
        }
        // gdy skan nie ma sufitu, pasmo nadproży może być zbyt ubogie —
        // wtedy wracamy do pasma przy podłodze
        if outlinePoints.count < 80 {
            outlinePoints = samples.filter {
                $0.position.y >= floorY - 0.03 && $0.position.y <= floorY + options.floorBand
            }
        }
        guard outlinePoints.count > 80 else { return nil }

        let plan = outlinePoints.map { SIMD2($0.position.x, $0.position.z) }
        guard let outline = roomOutline(points: plan, options: options),
              outline.count >= 3 else { return nil }

        let corners = outline.map {
            Corner(x: $0.x, z: $0.y, yMin: floorY, yMax: ceilingY, confidence: 1)
        }

        // 4) ściany: każda krawędź konturu + dopasowanie płaszczyzny
        let walls = fitWalls(corners: corners, samples: samples, options: options)
        guard walls.count >= 3 else { return nil }

        // 5) otwory (okna/drzwi)
        let openings = detectOpenings(walls: walls, samples: samples, floorY: floorY,
                                      height: height, options: options)

        let area = polygonArea(corners)

        return Result(corners: corners, walls: walls, openings: openings,
                      height: height, area: area, cornerSigma: 0.003)
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
        let limit = Int((hi - lo) * 0.4 / bin)
        let best = hist.filter { $0.key <= limit }.max { $0.value < $1.value }
        guard let b = best?.key else { return nil }
        return lo + Float(b) * bin
    }

    /// Górna krawędź ścian, gdy w skanie nie ma sufitu.
    ///
    /// Bierzemy 95 percentyl wysokości: pasmo przy samej górnej krawędzi
    /// mogłoby wypaść poza chmurę, a percentyl zostaje na ścianie.
    static func wallTop(samples: [Sample], floorY: Float) -> Float {
        let ys = samples.map(\.position.y).filter { $0.isFinite && $0 > floorY + 1.0 }.sorted()
        guard !ys.isEmpty else { return floorY + 2.6 }
        return ys[Swift.min(ys.count - 1, Int(Double(ys.count) * 0.97))]
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
        return (y - floorY > 2.0 && y - floorY < 4.5) ? y : nil
    }

    // MARK: - kontur pomieszczenia

    /// Kontur pomieszczenia: siatka zajętości → śledzenie brzegu → dopracowanie.
    static func roomOutline(points: [SIMD2<Float>], options: Options) -> [SIMD2<Float>]? {
        guard points.count > 100 else { return nil }

        let cell: Float = 0.03
        let grid = OccupancyGrid(points: points, cell: cell, sealRadius: 1)
        guard let coarse = grid.outline(sealRadius: 1) else { return nil }

        // uproszczenie: kontur siatki ma schodki 3 cm, więc tolerancja 5 cm
        var poly = douglasPeucker(coarse, tolerance: 0.05, closed: true)
        guard poly.count >= 3 else { return nil }

        // dopracowanie na surowych punktach (usuwa obciążenie od pogrubienia siatki)
        poly = refinePolygon(poly, points: points, tolerance: 0.10, iterations: 2)
        poly = removeShortEdges(poly, minLength: options.minWallLength)
        return poly.count >= 3 ? poly : nil
    }

    /// Siatka zajętości w planie z wypełnianiem wnętrza.
    ///
    /// „Wnętrze" to obszar, do którego nie dotarło zalewanie z zewnątrz siatki.
    /// Dzięki temu dziury w chmurze (ciemny kąt, zasłonięty fragment) zostają
    /// wypełnione i nie rozrywają konturu.
    struct OccupancyGrid {
        var cell: Float
        var origin: SIMD2<Float>
        var width: Int
        var height: Int
        /// komórki z punktami
        var raw: [Bool]
        /// komórki z punktami po pogrubieniu (do zamknięcia szczelin w ścianach)
        var sealed: [Bool]
        /// wnętrze pomieszczenia (nieosiągalne zalewaniem z zewnątrz)
        var interior: [Bool]

        init(points: [SIMD2<Float>], cell: Float, sealRadius: Int) {
            self.cell = cell
            guard !points.isEmpty else {
                origin = .zero; width = 0; height = 0
                raw = []; sealed = []; interior = []
                return
            }
            var lo = points[0], hi = points[0]
            for p in points {
                lo = simd_min(lo, p); hi = simd_max(hi, p)
            }
            // margines na zalewanie z zewnątrz
            origin = lo - SIMD2(repeating: cell * 4)
            let span = hi - lo + SIMD2(repeating: cell * 8)
            width = Swift.max(1, Int(span.x / cell) + 1)
            height = Swift.max(1, Int(span.y / cell) + 1)
            raw = [Bool](repeating: false, count: width * height)
            // inicjalizujemy WSZYSTKIE pola przed użyciem domknięć, bo Swift
            // nie pozwala użyć `self` dopóki wszystkie właściwości nie są gotowe
            sealed = raw
            interior = raw

            func index(_ p: SIMD2<Float>) -> (Int, Int) {
                let g = (p - origin) / cell
                return (Int(g.x.rounded()), Int(g.y.rounded()))
            }
            for p in points {
                let (ix, iy) = index(p)
                guard ix >= 0, ix < width, iy >= 0, iy < height else { continue }
                raw[iy * width + ix] = true
            }

            // pogrubienie: 3×3 (radius 1) wystarcza, żeby zamknąć szczeliny
            sealed = raw
            if sealRadius > 0 {
                sealed = [Bool](repeating: false, count: width * height)
                for y in 0..<height {
                    for x in 0..<width where raw[y * width + x] {
                        for dy in -sealRadius...sealRadius {
                            for dx in -sealRadius...sealRadius {
                                let nx = x + dx, ny = y + dy
                                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                                sealed[ny * width + nx] = true
                            }
                        }
                    }
                }
            }

            // zalewanie z zewnątrz po komórkach NIEzajętych (4-spójnie, żeby nie
            // przeciekało po przekątnej przez szczelinę w ścianie)
            var outside = [Bool](repeating: false, count: width * height)
            var stack: [(Int, Int)] = []
            func push(_ x: Int, _ y: Int) {
                guard x >= 0, x < width, y >= 0, y < height else { return }
                let i = y * width + x
                guard !sealed[i], !outside[i] else { return }
                outside[i] = true
                stack.append((x, y))
            }
            for x in 0..<width { push(x, 0); push(x, height - 1) }
            for y in 0..<height { push(0, y); push(width - 1, y) }
            while let (x, y) = stack.popLast() {
                push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1)
            }

            // wnętrze = komórki nie-zajęte i nie-osiągnięte z zewnątrz
            interior = [Bool](repeating: false, count: width * height)
            for i in 0..<(width * height) where !sealed[i] && !outside[i] {
                interior[i] = true
            }
        }

        /// Bryła pomieszczenia: wnętrze + punkty (bez pogrubienia — kontur ma
        /// leżeć na rzeczywistych punktach, nie na pogrubieniu).
        func solid() -> [Bool] {
            var s = raw
            for i in 0..<(width * height) where interior[i] { s[i] = true }
            return s
        }

        /// Kontur bryły pomieszczenia w metrach (zamknięty, bez powtórzenia).
        func outline(sealRadius: Int) -> [SIMD2<Float>]? {
            let solidMask = solid()
            let cells = traceBoundary(solid: solidMask, width: width, height: height)
            guard cells.count >= 8 else { return nil }
            return cells.map { c in
                origin + SIMD2(Float(c.x), Float(c.y)) * cell
            }
        }
    }

    /// Śledzenie brzegu (Moore, z kryterium zatrzymania) — zwraca komórki konturu.
    static func traceBoundary(solid: [Bool], width: Int, height: Int) -> [SIMD2<Int>] {
        guard width > 0, height > 0 else { return [] }

        // start: pierwsza zajęta komórka w skanie wierszami
        var start = SIMD2(-1, -1)
        outer: for y in 0..<height {
            for x in 0..<width where solid[y * width + x] {
                start = SIMD2(x, y)
                break outer
            }
        }
        guard start.x >= 0 else { return [] }

        // sąsiedzi w kolejności zgodnej z ruchem wskazówek zegara (E, NE, N, …)
        let nbr = [SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1), SIMD2(-1, 1),
                   SIMD2(-1, 0), SIMD2(-1, -1), SIMD2(0, -1), SIMD2(1, -1)]

        func occupied(_ c: SIMD2<Int>) -> Bool {
            guard c.x >= 0, c.x < width, c.y >= 0, c.y < height else { return false }
            return solid[c.y * width + c.x]
        }

        var contour: [SIMD2<Int>] = [start]
        var current = start
        var backtrack = SIMD2(start.x - 1, start.y)
        var steps = 0
        let limit = Swift.max(64, width * height / 2)

        while steps < limit {
            steps += 1
            let delta = SIMD2(backtrack.x - current.x, backtrack.y - current.y)
            var idx = nbr.firstIndex(of: delta) ?? 0
            var next: SIMD2<Int>? = nil

            for k in 1...8 {
                let i = (idx + k) % 8
                let cand = SIMD2(current.x + nbr[i].x, current.y + nbr[i].y)
                if occupied(cand) {
                    next = cand
                    // cofnięcie: sąsiad przed bieżącym w kolejności przeszukiwania
                    idx = (i + 7) % 8
                    backtrack = SIMD2(current.x + nbr[idx].x, current.y + nbr[idx].y)
                    break
                }
            }
            guard let n = next else { break }
            // zamknięcie konturu: wróciliśmy do startu
            if n == start && contour.count > 2 { break }
            current = n
            contour.append(n)
        }
        return contour
    }

    /// Dopracowuje wielokąt: krawędzie dopasowuje do surowych punktów, a
    /// narożniki liczy jako przecięcia sąsiednich dopasowanych linii.
    ///
    /// To jest krok, który usuwa obciążenie od siatki: kontur z siatki jest
    /// przesunięty o grubość pogrubienia i „schodkowy", a dopasowanie
    /// najmniejszych kwadratów do prawdziwych punktów daje dokładną pozycję
    /// ściany. Powtarzamy dwa razy, bo po pierwszym kroku segmenty są już
    /// blisko ścian, więc zbierają lepsze punkty.
    static func refinePolygon(_ poly: [SIMD2<Float>], points: [SIMD2<Float>],
                              tolerance: Float, iterations: Int) -> [SIMD2<Float>] {
        guard poly.count >= 3 else { return poly }
        var current = poly

        for _ in 0..<iterations {
            let n = current.count
            var lines: [(point: SIMD2<Float>, direction: SIMD2<Float>)] = []

            for i in 0..<n {
                let a = current[i]
                let b = current[(i + 1) % n]
                let length = simd_length(b - a)
                guard length > 1e-4 else {
                    lines.append((a, SIMD2(1, 0)))
                    continue
                }
                let unit = (b - a) / length

                // punkty w pobliżu krawędzi, ale nie na jej końcach (żeby nie
                // złapać punktów ze ściany prostopadłej)
                var near: [SIMD2<Float>] = []
                for p in points {
                    let t = simd_dot(p - a, unit)
                    guard t >= length * 0.15, t <= length * 0.85 else { continue }
                    let lateral = abs(simd_dot(p - a, SIMD2(-unit.y, unit.x)))
                    guard lateral <= tolerance else { continue }
                    near.append(p)
                }
                if near.count >= 20, let fitted = fitLine(near) {
                    lines.append((fitted.point, fitted.direction))
                } else {
                    lines.append((a, unit))
                }
            }

            var refined: [SIMD2<Float>] = []
            for i in 0..<n {
                let l1 = lines[(i + n - 1) % n]  // krawędź kończąca się w narożniku i
                let l2 = lines[i]                // krawędź zaczynająca się w narożniku i
                let det = l1.direction.x * l2.direction.y - l1.direction.y * l2.direction.x
                if abs(det) > 0.05 {
                    let ab = l2.point - l1.point
                    let t = (ab.x * l2.direction.y - ab.y * l2.direction.x) / det
                    refined.append(l1.point + l1.direction * t)
                } else {
                    refined.append(current[i])  // równoległe — zostaw stary narożnik
                }
            }
            current = refined
        }
        return current
    }

    /// Uproszczenie linii: Douglas–Peucker.
    ///
    /// `closed` = true dla konturu zamkniętego: wtedy dzielimy go na dwa łuki
    /// i upraszczamy każdy osobno, bo algorytm dla linii nie obsługuje pętli.
    static func douglasPeucker(_ points: [SIMD2<Float>], tolerance: Float,
                               closed: Bool) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        guard closed else { return douglasPeuckerOpen(points, tolerance: tolerance) }

        // dla pętli: rozbij na dwa łuki (najdalsza para punktów) i złóż
        var farIndex = 0
        var farDist: Float = -1
        for i in 1..<points.count {
            let d = simd_length(points[i] - points[0])
            if d > farDist { farDist = d; farIndex = i }
        }
        let arc1 = Array(points[0...farIndex])
        let arc2 = Array(points[farIndex...] + [points[0]])
        let s1 = douglasPeuckerOpen(arc1, tolerance: tolerance)
        let s2 = douglasPeuckerOpen(arc2, tolerance: tolerance)
        // s1 kończy się punktem farIndex, s2 zaczyna się nim — łączymy bez dubli
        var out = s1
        for p in s2.dropFirst() where !(p == s1.last && out.last == p) {
            out.append(p)
        }
        if out.count > 1, simd_length(out.first! - out.last!) < 1e-6 {
            out.removeLast()
        }
        return out
    }

    /// Douglas–Peucker dla otwartej linii (iteracyjnie — bez rekurencji).
    static func douglasPeuckerOpen(_ points: [SIMD2<Float>], tolerance: Float) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            var maxDist: Float = 0
            var index = lo
            let a = points[lo], b = points[hi]
            for i in (lo + 1)..<hi {
                let d = perpendicularDistance(points[i], a, b)
                if d > maxDist { maxDist = d; index = i }
            }
            if maxDist > tolerance {
                keep[index] = true
                stack.append((lo, index))
                stack.append((index, hi))
            }
        }
        return (0..<points.count).filter { keep[$0] }.map { points[$0] }
    }

    /// Odległość punktu od odcinka (a–b).
    static func perpendicularDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let len = simd_length(ab)
        guard len > 1e-6 else { return simd_length(p - a) }
        let t = Swift.max(0, Swift.min(1, simd_dot(p - a, ab) / (len * len)))
        return simd_length(p - (a + ab * t))
    }

    /// Usuwa wierzchołki tworzące krawędzie krótsze niż `minLength`.
    static func removeShortEdges(_ poly: [SIMD2<Float>], minLength: Float) -> [SIMD2<Float>] {
        guard poly.count > 3 else { return poly }
        var out = poly
        var changed = true
        while changed && out.count > 3 {
            changed = false
            for i in 0..<out.count {
                let a = out[i]
                let b = out[(i + 1) % out.count]
                if simd_length(b - a) < minLength {
                    out.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return out
    }

    /// Linia w planie (metry) — wynik dopasowania.
    struct WallLine: Sendable {
        public var point: SIMD2<Float>
        public var direction: SIMD2<Float>
        public var tMin: Float
        public var tMax: Float

        public init(point: SIMD2<Float>, direction: SIMD2<Float>,
                    tMin: Float, tMax: Float) {
            self.point = point
            self.direction = direction
            self.tMin = tMin
            self.tMax = tMax
        }

        public var normal: SIMD2<Float> { SIMD2(-direction.y, direction.x) }
        public var length: Float { tMax - tMin }
    }

    /// Dopasowuje linię do zbioru punktów (najmniejsze kwadraty, PCA).
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
        // Zwrot jest tu dowolny — wszystkie użycia liczą wielkości niezależne od
        // znaku (odległości prostopadłe, przecięcia par), więc kanonizacja nie
        // jest potrzebna i nie wprowadza sprzeczności z histogramem.
        let dir = SIMD2<Float>(Float(cos(theta)), Float(sin(theta)))

        var tMin = Float.greatestFiniteMagnitude
        var tMax = -Float.greatestFiniteMagnitude
        for p in pts {
            let t = simd_dot(p - centroid, dir)
            tMin = Swift.min(tMin, t)
            tMax = Swift.max(tMax, t)
        }
        return WallLine(point: centroid, direction: dir, tMin: tMin, tMax: tMax)
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

            // Otwór to SPÓJNY OBSZAR bez punktów, nie „pusta kolumna".
            //
            // Wcześniej szukałem kolumn pustych na całej wysokości. To nie
            // działa, gdy otwór ma nadproże: nad drzwiami jest ściana, więc
            // kolumna jest częściowo wypełniona i otwór znikał (zmierzone:
            // drzwi 0,9 m i okno 1,2 m → 0 otworów). Teraz szukamy plam:
            // łączenie pustych komórek 4-spójnie, a potem prostokąt otaczający.
            let skipBottom = Swift.max(1, Int(0.20 / cellV))
            var visited = [Bool](repeating: false, count: cols * rows)
            var regions: [(c0: Int, c1: Int, r0: Int, r1: Int)] = []

            for c0 in 0..<cols {
                for r0 in skipBottom..<rows where !grid[r0 * cols + c0] {
                    guard !visited[r0 * cols + c0] else { continue }
                    // zalewanie plamy pustych komórek
                    var stack = [(c0, r0)]
                    visited[r0 * cols + c0] = true
                    var minC = c0, maxC = c0, minR = r0, maxR = r0
                    while let (c, r) = stack.popLast() {
                        minC = Swift.min(minC, c); maxC = Swift.max(maxC, c)
                        minR = Swift.min(minR, r); maxR = Swift.max(maxR, r)
                        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let nc = c + dc, nr = r + dr
                            guard nc >= 0, nc < cols, nr >= skipBottom, nr < rows else { continue }
                            guard !grid[nr * cols + nc], !visited[nr * cols + nc] else { continue }
                            visited[nr * cols + nc] = true
                            stack.append((nc, nr))
                        }
                    }
                    regions.append((minC, maxC, minR, maxR))
                }
            }

            for region in regions {
                let width = Float(region.c1 - region.c0 + 1) * cellU
                let h = Float(region.r1 - region.r0 + 1) * cellV
                // otwór sensowny: ≥ 40 cm szerokości, ≥ 40 cm wysokości,
                // i nie cała ściana (to byłby brak pokrycia, nie otwór)
                guard width >= 0.4, width <= len * 0.95 else { continue }
                guard h >= 0.4 else { continue }
                // plama przyklejona do dolnego pasa = sięga podłogi → drzwi
                let reachesFloor = region.r0 <= skipBottom + 1
                let sill = reachesFloor ? 0 : Float(region.r0) * cellV
                let kind: Opening.Kind = sill <= 0.15 ? .door : .window
                out.append(Opening(wallIndex: wi, kind: kind,
                                   offset: Float(region.c0) * cellU,
                                   width: width, sill: sill, height: h))
            }
        }
        return out
    }

    // MARK: - geometria planu

    /// Pole powierzchni wielokąta w planie (wzór sznurowadła).
    static func polygonArea(_ poly: [SIMD2<Float>]) -> Float {
        guard poly.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Pole powierzchni wielokąta (wzór sznurowadła) — wariant dla narożników.
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
