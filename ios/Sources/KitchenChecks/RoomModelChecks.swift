// Testy modułu RoomModel na syntetycznych pomieszczeniach o znanych wymiarach.
// Uruchomienie: swift run KitchenChecks  (sekcja „Model pomieszczenia")
import Foundation
import simd
import KitchenCore

/// Buduje chmurę pomieszczenia: 4 ściany + podłoga, z szumem, opcjonalnym
/// wygięciem ściany i otworami (okno, drzwi). Wymiary znane → testy sprawdzają
/// odtworzenie, a nie „czy coś się policzyło".
func syntheticRoom(
    width: Float, depth: Float, height: Float,
    noise: Float = 0.002,
    bow: Float = 0,
    withWindow: Bool = false,
    withDoor: Bool = false,
    seed: UInt64 = 7,
    samplesPerSqm: Float = 1200
) -> [RoomModel.Sample] {
    var state = seed
    func rnd() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xFFFFFF) / Float(0x1000000) - 0.5
    }

    var out: [RoomModel.Sample] = []
    let halfW = width / 2, halfD = depth / 2

    // podłoga
    let floorN = Int(width * depth * samplesPerSqm)
    for _ in 0..<floorN {
        let x = (rnd() + 0.5) * width - halfW
        let z = (rnd() + 0.5) * depth - halfD
        out.append(.init(position: SIMD3(x, rnd() * noise, z), sigma: 0.002))
    }

    func wall(axis: Int, pos: Float, from: Float, to: Float, bowAmount: Float) {
        let len = to - from
        let n = Int(len * height * samplesPerSqm)
        for _ in 0..<n {
            let t = from + (rnd() + 0.5) * len
            let y = (rnd() + 0.5) * height
            let u = (t - from) / Swift.max(0.001, len)
            let bowValue = bowAmount * (1 - pow(2 * u - 1, 2))
            var p: SIMD3<Float>
            if axis == 0 {
                p = SIMD3(pos + bowValue + rnd() * noise, y, t)
            } else {
                p = SIMD3(t, y, pos + bowValue + rnd() * noise)
            }
            // otwory: usuń punkty w prostokącie (ściana północna z=-halfD)
            if withDoor, axis == 1, pos < 0, t > -0.45, t < 0.45, y < 2.05 { continue }
            if withWindow, axis == 1, pos < 0, t > 0.5, t < 1.7, y > 0.9, y < 2.1 { continue }
            out.append(.init(position: p, sigma: 0.004))
        }
    }

    wall(axis: 1, pos: -halfD, from: -halfW, to: halfW, bowAmount: bow)
    wall(axis: 1, pos: halfD, from: -halfW, to: halfW, bowAmount: 0)
    wall(axis: 0, pos: -halfW, from: -halfD, to: halfD, bowAmount: 0)
    wall(axis: 0, pos: halfW, from: -halfD, to: halfD, bowAmount: 0)

    return out
}

/// Chmura pomieszczenia o dowolnym konturze (np. L-kształt) — podłoga
/// odrzucana testem przynależności do wielokąta.
func syntheticPolygonRoom(poly: [SIMD2<Float>], height: Float,
                          samplesPerSqm: Float = 900, seed: UInt64 = 42)
    -> [RoomModel.Sample] {
    var state = seed
    func rnd() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xFFFFFF) / Float(0x1000000)
    }
    func inside(_ p: SIMD2<Float>) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let t = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < t { c.toggle() }
            }
            j = i
        }
        return c
    }

    var lo = poly[0], hi = poly[0]
    for p in poly { lo = simd_min(lo, p); hi = simd_max(hi, p) }
    let span = hi - lo

    var out: [RoomModel.Sample] = []
    let target = Int(span.x * span.y * samplesPerSqm * 2)
    var attempts = 0
    while out.count < target, attempts < target * 40 {
        attempts += 1
        let p = SIMD2(lo.x + rnd() * span.x, lo.y + rnd() * span.y)
        guard inside(p) else { continue }
        out.append(.init(position: SIMD3(p.x, 0, p.y), sigma: 0.002))
    }

    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        let len = simd_length(b - a)
        for _ in 0..<Int(len * height * samplesPerSqm) {
            let t = rnd()
            let p = a + (b - a) * t
            out.append(.init(position: SIMD3(p.x, rnd() * height, p.y), sigma: 0.004))
        }
    }
    return out
}

func runRoomModelChecks(_ r: Reporter) {
    print("\nModel pomieszczenia — narożniki, kontur, ściany")

    // 1) prostokąt 4 × 3 m, wysokość 2,6 m
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("prostokąt 4×3: model powstał", false, "nil")
            return
        }
        r.check("prostokąt 4×3: 4 narożniki", model.corners.count == 4, "= \(model.corners.count)")
        r.check("prostokąt 4×3: 4 ściany", model.walls.count == 4, "= \(model.walls.count)")
        r.check("prostokąt 4×3: pole ≈ 12 m²", abs(model.area - 12) < 0.1,
                String(format: "%.2f m²", model.area))
        r.check("prostokąt 4×3: wysokość ≈ 2,6 m", abs(model.height - 2.6) < 0.15,
                String(format: "%.2f m", model.height))

        let lengths = model.walls.map(\.length).sorted()
        r.check("prostokąt: 2 ściany 3 m ±2 cm",
                abs(lengths[0] - 3) < 0.02 && abs(lengths[1] - 3) < 0.02,
                String(format: "%.3f, %.3f", lengths[0], lengths[1]))
        r.check("prostokąt: 2 ściany 4 m ±2 cm",
                abs(lengths[2] - 4) < 0.02 && abs(lengths[3] - 4) < 0.02,
                String(format: "%.3f, %.3f", lengths[2], lengths[3]))
    }

    // 2) narożniki w prawidłowych miejscach
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("narożniki: model powstał", false, "nil")
            return
        }
        let expected: [SIMD2<Float>] = [
            SIMD2(-2, -1.5), SIMD2(2, -1.5), SIMD2(2, 1.5), SIMD2(-2, 1.5),
        ]
        var maxErr: Float = 0
        for e in expected {
            let nearest = model.corners.map { simd_length($0.plan - e) }.min() ?? 99
            maxErr = Swift.max(maxErr, nearest)
        }
        r.check("narożniki: każdy w promieniu 2 cm od prawdziwego", maxErr < 0.02,
                String(format: "maks. odchyłka %.0f mm", maxErr * 1000))
    }

    // 3) pomieszczenie L-kształtne (kontur niewypukły)
    do {
        // kontur L: pole = 4·2 + 2·2 = 12 m², 6 narożników
        let poly: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 2), SIMD2(2, 2), SIMD2(2, 4), SIMD2(0, 4),
        ]
        let cloud = syntheticPolygonRoom(poly: poly, height: 2.6)
        if let model = RoomModel.build(from: cloud) {
            r.check("L-kształt: 6 narożników", model.corners.count == 6, "= \(model.corners.count)")
            r.check("L-kształt: 6 ścian", model.walls.count == 6, "= \(model.walls.count)")
            r.check("L-kształt: pole ≈ 12 m²", abs(model.area - 12) < 0.3,
                    String(format: "%.2f m²", model.area))
            let shortest = model.walls.map(\.length).min() ?? 0
            r.check("L-kształt: najkrótsza ściana ≈ 2 m", abs(shortest - 2) < 0.1,
                    String(format: "%.2f m", shortest))
        } else {
            r.check("L-kształt: model powstał", false, "nil")
        }
    }

    // 4) wygięta ściana — model MUSI to pokazać, a nie wyprostować
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6, bow: 0.03)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("wygięcie: model powstał", false, "nil")
            return
        }
        let bowed = model.walls.max { $0.residualP95 < $1.residualP95 }
        r.check("wygięcie: ściana z wybrzuszeniem wykryta (p95 > 15 mm)",
                (bowed?.residualP95 ?? 0) > 0.015,
                String(format: "p95 = %.1f mm", (bowed?.residualP95 ?? 0) * 1000))
        let flat = model.walls.min { $0.residualP95 < $1.residualP95 }
        r.check("wygięcie: ściana prosta ma małą odchyłkę (p95 < 15 mm)",
                (flat?.residualP95 ?? 99) < 0.015,
                String(format: "p95 = %.1f mm", (flat?.residualP95 ?? 0) * 1000))
    }

    // 5) otwory: okno i drzwi
    do {
        let cloud = syntheticRoom(width: 5, depth: 4, height: 2.7,
                                  withWindow: true, withDoor: true)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("otwory: model powstał", false, "nil")
            return
        }
        r.check("otwory: kontur bez rozdarć (4 narożniki)", model.corners.count == 4,
                "= \(model.corners.count)")
        r.check("otwory: wykryto 2", model.openings.count == 2, "= \(model.openings.count)")
        let doors = model.openings.filter { $0.kind == .door }
        let windows = model.openings.filter { $0.kind == .window }
        r.check("otwory: 1 drzwi", doors.count == 1, "= \(doors.count)")
        r.check("otwory: 1 okno", windows.count == 1, "= \(windows.count)")
        if let d = doors.first {
            r.check("drzwi: sięgają podłogi (próg ≈ 0)", d.sill < 0.1,
                    String(format: "próg %.2f m", d.sill))
            r.check("drzwi: szerokość ≈ 0,9 m", abs(d.width - 0.9) < 0.25,
                    String(format: "%.2f m", d.width))
            r.check("drzwi: wysokość ≈ 2,05 m", abs(d.height - 2.05) < 0.3,
                    String(format: "%.2f m", d.height))
        }
        if let w = windows.first {
            r.check("okno: nie sięga podłogi (próg ≈ 0,9 m)", abs(w.sill - 0.9) < 0.25,
                    String(format: "próg %.2f m", w.sill))
            r.check("okno: szerokość ≈ 1,2 m", abs(w.width - 1.2) < 0.3,
                    String(format: "%.2f m", w.width))
        }
    }

    // 6) geometria pomocnicza
    do {
        let corners = [
            RoomModel.Corner(x: 0, z: 0), RoomModel.Corner(x: 2, z: 0),
            RoomModel.Corner(x: 2, z: 1), RoomModel.Corner(x: 0, z: 1),
        ]
        r.check("pole: prostokąt 2×1 = 2 m²",
                abs(RoomModel.polygonArea(corners) - 2) < 0.001,
                String(format: "%.3f", RoomModel.polygonArea(corners)))

        var pts: [SIMD2<Float>] = []
        for i in 0..<200 {
            let t = Float(i) / 100
            pts.append(SIMD2(t, 0.003 * sin(t * 10)))
        }
        if let line = RoomModel.fitLine(pts) {
            r.check("fitLine: kierunek poziomy", abs(line.direction.y) < 0.05,
                    String(format: "dy = %.3f", line.direction.y))
            r.check("fitLine: zakres ~0…2 m",
                    abs(line.tMin) < 0.05 && abs(line.tMax - 2) < 0.05,
                    String(format: "%.2f…%.2f", line.tMin, line.tMax))
        } else {
            r.check("fitLine: zwraca linię", false, "nil")
        }

        // Douglas–Peucker na otwartej linii
        let zig: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.5, 0.001),
                                   SIMD2(1, 0), SIMD2(1.5, 0.001), SIMD2(2, 0)]
        let simplified = RoomModel.douglasPeuckerOpen(zig, tolerance: 0.01)
        r.check("DP: usuwa punkty współliniowe", simplified.count == 2,
                "= \(simplified.count)")
    }

    // 7) odporność
    do {
        r.check("za mało punktów → nil", RoomModel.build(from: []) == nil)
        var wallOnly: [RoomModel.Sample] = []
        for i in 0..<3000 {
            wallOnly.append(.init(position: SIMD3(Float(i % 100) * 0.01,
                                                  Float(i / 100) * 0.01, 0), sigma: 0.01))
        }
        r.check("chmura bez podłogi → nil albo model bez ścian",
                RoomModel.build(from: wallOnly)?.walls.count ?? 0 < 3)
    }
}
