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
