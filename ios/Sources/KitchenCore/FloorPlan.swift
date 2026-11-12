import Foundation
import simd

/// Plan domu rysowany kreskami: ciąg punktów w milimetrach (X, Z) i ściany
/// między nimi. Wysokość i grubość ściany są wspólne dla całego planu.
///
/// DLACZEGO PUNKTY, A NIE NIEZALEŻNE ODCINKI:
/// ściany w planie są połączone — przesunięcie narożnika zmienia długość
/// dwóch ścian naraz. Trzymając punkty, „zmiana długości ściany" to przesunięcie
/// jednego punktu wzdłuż kierunku ściany, a sąsiednia ściana dostosowuje się
/// sama. Gdyby każda ściana miała własne końce, plan rozjechałby się w szwach.
public struct FloorPlan: Codable, Sendable, Equatable {

    /// Kolejne wierzchołki planu (mm). Pierwszy = ostatni, gdy `closed`.
    public var points: [SIMD2<Double>]
    /// Czy plan jest zamknięty (dom) czy otwarty (rysunek w trakcie).
    public var closed: Bool
    /// Wysokość pomieszczenia (mm).
    public var height: Double
    /// Grubość ściany (mm) — do geometrii 3D i do wymiarowania.
    public var thickness: Double

    public init(
        points: [SIMD2<Double>] = [],
        closed: Bool = false,
        height: Double = 2900,
        thickness: Double = 120
    ) {
        self.points = points
        self.closed = closed
        self.height = height
        self.thickness = thickness
    }

    /// Dokleja prostokątne pomieszczenie do istniejącego planu.
    ///
    /// ZASADA (wymóg): edycja planu ma DOKLEJAĆ pomieszczenia, a nie zamieniać
    /// całego planu. Wcześniej każde narysowanie prostokąta nadpisywało plan
    /// (`plan = FloorPlan.rectangle(...)`), więc nie dało się złożyć mieszkania
    /// z kilku pomieszczeń.
    ///
    /// REGUŁA DOKLEJANIA: nowy prostokąt jest dosuwany i wyrównywany do
    /// najbliższej krawędzi istniejącego planu, a wynikiem jest obwiednia obu.
    /// Dzięki temu zawsze powstaje JEDEN spójny obrys (dom rośnie), a nie dwa
    /// zachodzące na siebie prostokąty.
    ///
    /// Świadome ograniczenie: jeśli nowe pomieszczenie nie jest wyrównane do
    /// istniejącego, zostaje wyrównane — nie tworzymy kształtu L. Plan obsługuje
    /// jeden zamknięty obrys, więc obwiednia jest jedynym wynikiem, który nie
    /// psuje rysunku (L wymagałoby wielu obrysów w jednym planie).
    public func appending(room rect: FloorPlan) -> FloorPlan {
        guard !points.isEmpty, closed else { return rect }
        let a = bounds
        let b = rect.bounds
        let bSize = b.max - b.min
        guard bSize.x > 0, bSize.y > 0 else { return self }

        // Która krawędź jest najbliżej? Liczymy odległość środków krawędzi.
        let gapEast = b.min.x - a.max.x
        let gapWest = a.min.x - b.max.x
        let gapSouth = b.min.y - a.max.y
        let gapNorth = a.min.y - b.max.y
        let gaps = [("E", gapEast), ("W", gapWest), ("S", gapSouth), ("N", gapNorth)]
        let nearest = gaps.min { abs($0.1) < abs($1.1) }?.0 ?? "E"

        var out = self
        switch nearest {
        case "E", "W":
            // doklejamy w poziomie: obwiednia w X, wspólny zakres w Y
            let x0 = Swift.min(a.min.x, b.min.x)
            let x1 = Swift.max(a.max.x, b.max.x)
            let y0 = Swift.min(a.min.y, b.min.y)
            let y1 = Swift.max(a.max.y, b.max.y)
            out.points = [
                SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1),
            ]
        default:
            // doklejamy w pionie: obwiednia w Y, wspólny zakres w X
            let x0 = Swift.min(a.min.x, b.min.x)
            let x1 = Swift.max(a.max.x, b.max.x)
            let y0 = Swift.min(a.min.y, b.min.y)
            let y1 = Swift.max(a.max.y, b.max.y)
            out.points = [
                SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1),
            ]
        }
        out.closed = true
        out.thickness = thickness
        return out
    }

    /// Startowy plan willi: prostokąt 12,8 × 9,6 m wyśrodkowany w (0, 0).
    public static func rectangle(width: Double = 12800, depth: Double = 9600, height: Double = 2900) -> FloorPlan {
        let hx = width / 2, hz = depth / 2
        return FloorPlan(
            points: [
                SIMD2(-hx, -hz), SIMD2(hx, -hz), SIMD2(hx, hz), SIMD2(-hx, hz),
            ],
            closed: true,
            height: height
        )
    }

    /// Prostokąt o zadanych wymiarach, umieszczony lewym-górnym narożnikiem w (x, z).
    /// To ścieżka „wpisuję wymiary" — bez rysowania.
    public static func rectangle(
        x: Double,
        z: Double,
        width: Double,
        depth: Double,
        height: Double = 2900,
        thickness: Double = 120
    ) -> FloorPlan {
        let w = Swift.max(500, width)
        let d = Swift.max(500, depth)
        return FloorPlan(
            points: [
                SIMD2(x, z), SIMD2(x + w, z), SIMD2(x + w, z + d), SIMD2(x, z + d),
            ],
            closed: true,
            height: height,
            thickness: thickness
        )
    }

    /// Prostokąt z dwóch narożników (przeciągnięcie po planie), zaokrąglony do `snap` mm.
    public static func rectangle(
        from start: SIMD2<Double>,
        to end: SIMD2<Double>,
        snap: Double = 50,
        height: Double = 2900,
        thickness: Double = 120
    ) -> FloorPlan {
        func rounded(_ v: Double) -> Double { snap > 0 ? (v / snap).rounded() * snap : v }
        let x0 = rounded(Swift.min(start.x, end.x))
        let z0 = rounded(Swift.min(start.y, end.y))
        let x1 = rounded(Swift.max(start.x, end.x))
        let z1 = rounded(Swift.max(start.y, end.y))
        return rectangle(x: x0, z: z0,
                         width: Swift.max(500, x1 - x0),
                         depth: Swift.max(500, z1 - z0),
                         height: height, thickness: thickness)
    }

    /// Wymiary obrysu w mm.
    public var size: SIMD2<Double> {
        let b = bounds
        return SIMD2(b.max.x - b.min.x, b.max.y - b.min.y)
    }

    /// Czy plan jest pojedynczym prostokątem (4 ściany, 4 punkty).
    public var isSimpleRectangle: Bool { closed && points.count == 4 }

    /// Zmiana wymiarów istniejącego prostokąta z zachowaniem jego środka.
    /// Wpisanie „szerokość 3600" w formularzu nie przesuwa pomieszczenia.
    public mutating func setSize(width: Double, depth: Double) {
        let b = bounds
        let cx = (b.min.x + b.max.x) / 2
        let cz = (b.min.y + b.max.y) / 2
        let w = Swift.max(500, width) / 2
        let d = Swift.max(500, depth) / 2
        points = [SIMD2(cx - w, cz - d), SIMD2(cx + w, cz - d), SIMD2(cx + w, cz + d), SIMD2(cx - w, cz + d)]
        closed = true
    }

    // MARK: - ściany

    /// Liczba odcinków: dla zamkniętego planu tyle, ile punktów.
    public var wallCount: Int {
        guard points.count >= 2 else { return 0 }
        return closed ? points.count : points.count - 1
    }

    /// Ściana i: początek, koniec, długość, kąt (stopnie).
    public func wall(_ index: Int) -> (a: SIMD2<Double>, b: SIMD2<Double>, length: Double, angleDeg: Double)? {
        guard index >= 0, index < wallCount else { return nil }
        let a = points[index]
        let b = points[(index + 1) % points.count]
        let d = b - a
        let length = simd_length(d)
        let angle = atan2(d.y, d.x) * 180 / .pi
        return (a, b, length, angle)
    }

    /// Przesunięcie ściany prostopadle do niej (mm). Sąsiednie ściany same się
    /// wydłużają/skracają, bo plan jest zamknięty — tak działa „ciągnięcie ściany palcem".
    public mutating func moveWall(_ index: Int, by distance: Double) {
        guard let wall = wall(index), distance != 0 else { return }
        let d = wall.b - wall.a
        let length = simd_length(d)
        guard length > 1e-6 else { return }
        let normal = SIMD2<Double>(-d.y / length, d.x / length)
        let shift = normal * distance
        for i in [index, (index + 1) % points.count] {
            points[i] = SIMD2(Units.quantize(points[i].x + shift.x),
                              Units.quantize(points[i].y + shift.y))
        }
    }

    /// Przesunięcie narożnika (wierzchołka) planu.
    public mutating func moveVertex(_ index: Int, to point: SIMD2<Double>) {
        guard points.indices.contains(index) else { return }
        points[index] = SIMD2(Units.quantize(point.x), Units.quantize(point.y))
    }

    /// Wszystkie długości ścian (mm) — do tabeli wymiarów.
    public var wallLengths: [Double] {
        (0..<wallCount).compactMap { wall($0)?.length }
    }

    public var perimeter: Double { wallLengths.reduce(0, +) }

    /// Powierzchnia (mm²) ze wzoru sznurowadłowego — tylko dla zamkniętego planu.
    public var area: Double {
        guard closed, points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    public var areaM2: Double { area / 1_000_000 }

    /// Obrys planu (mm).
    public var bounds: (min: SIMD2<Double>, max: SIMD2<Double>) {
        guard let first = points.first else { return (SIMD2(0, 0), SIMD2(0, 0)) }
        var lo = first, hi = first
        for p in points {
            lo = SIMD2(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y))
            hi = SIMD2(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y))
        }
        return (lo, hi)
    }

    // MARK: - edycja

    /// Dokłada punkt (rysowanie kreskami). Punkt bliższy niż `snapRadius`
    /// do pierwszego zamyka plan — tak działa „klik w start", bez osobnego guzika.
    public mutating func append(_ point: SIMD2<Double>, snapRadius: Double = 250) {
        if closed { return }
        if points.count >= 3, let first = points.first, simd_length(point - first) <= snapRadius {
            closed = true
            return
        }
        points.append(point)
    }

    /// Zmienia długość ściany `index`, przesuwając jej KOŃCOWY punkt wzdłuż
    /// kierunku ściany. Sąsiednia ściana (i zamknięcie) dostosowuje się sama.
    ///
    /// `length` w mm, minimalna długość 100 mm.
    @discardableResult
    public mutating func setWallLength(_ index: Int, to length: Double) -> Bool {
        guard let w = wall(index), w.length > 1e-6 else { return false }
        let target = Swift.max(100, length)
        let dir = (w.b - w.a) / w.length
        let newB = w.a + dir * target
        let endIndex = (index + 1) % points.count
        points[endIndex] = newB
        return true
    }

    /// Przesuwa punkt planu (przeciąganie narożnika).
    public mutating func movePoint(_ index: Int, to point: SIMD2<Double>) {
        guard index >= 0, index < points.count else { return }
        points[index] = point
    }

    public mutating func removeLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        if points.count < 3 { closed = false }
    }

    public mutating func open() { closed = false }

    /// Najbliższa ściana do punktu — do zaznaczania klikiem w planie.
    /// Zwraca indeks i odległość (mm).
    public func nearestWall(to point: SIMD2<Double>) -> (index: Int, distance: Double)? {
        var best: (index: Int, distance: Double)?
        for i in 0..<wallCount {
            guard let w = wall(i) else { continue }
            let d = Self.distanceToSegment(point, w.a, w.b)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        return best
    }

    static func distanceToSegment(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let len2 = simd_length_squared(ab)
        guard len2 > 1e-9 else { return simd_length(p - a) }
        let t = Swift.max(0, Swift.min(1, simd_dot(p - a, ab) / len2))
        let projection = a + ab * t
        return simd_length(p - projection)
    }

    // MARK: - zgodność z pokojem

    /// Obrys planu jako pokój (mm) — plan jest źródłem prawdy dla 3D.
    public func room(name: String = "Pomieszczenie") -> Room {
        let b = bounds
        return Room(
            name: name,
            width: Swift.max(1000, b.max.x - b.min.x),
            depth: Swift.max(1000, b.max.y - b.min.y),
            height: Swift.max(2000, height)
        )
    }
}
