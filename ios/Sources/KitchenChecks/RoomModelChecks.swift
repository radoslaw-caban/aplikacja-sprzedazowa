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
        r.check("prostokąt 4×3: pole ≈ 12 m²", abs(model.area - 12) < 0.6,
                String(format: "%.2f m²", model.area))
        r.check("prostokąt 4×3: wysokość ≈ 2,6 m", abs(model.height - 2.6) < 0.15,
                String(format: "%.2f m", model.height))

        // długości ścian: dwie po 4 m, dwie po 3 m
        let lengths = model.walls.map(\.length).sorted()
        r.check("prostokąt: dwie ściany ~3 m",
                abs(lengths[0] - 3) < 0.15 && abs(lengths[1] - 3) < 0.15,
                String(format: "%.2f, %.2f", lengths[0], lengths[1]))
        r.check("prostokąt: dwie ściany ~4 m",
                abs(lengths[2] - 4) < 0.15 && abs(lengths[3] - 4) < 0.15,
                String(format: "%.2f, %.2f", lengths[2], lengths[3]))
    }

    // 2) narożniki w prawidłowych miejscach (nie tylko ich liczba)
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
        r.check("narożniki: każdy w promieniu 8 cm od prawdziwego", maxErr < 0.08,
                String(format: "maks. odchyłka %.0f mm", maxErr * 1000))
    }

    // 3) pomieszczenie L-kształtne (dowolny kontur, nie tylko prostokąt)
    do {
        var cloud: [RoomModel.Sample] = []
        // kontur L: (0,0) (4,0) (4,2) (2,2) (2,4) (0,4)
        let poly: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 2), SIMD2(2, 2), SIMD2(2, 4), SIMD2(0, 4),
        ]
        var state: UInt64 = 42
        func rnd() -> Float {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(state & 0xFFFFFF) / Float(0x1000000)
        }
        // podłoga: odrzucamy punkty spoza wielokąta
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
        for _ in 0..<60_000 {
            let p = SIMD2(rnd() * 4.2 - 0.1, rnd() * 4.2 - 0.1)
            guard inside(p) else { continue }
            cloud.append(.init(position: SIMD3(p.x, 0, p.y), sigma: 0.002))
        }
        // ściany
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let len = simd_length(b - a)
            let n = Int(len * 2.6 * 900)
            for _ in 0..<n {
                let t = rnd()
                let p = a + (b - a) * t
                let y = rnd() * 2.6
                cloud.append(.init(position: SIMD3(p.x, y, p.y), sigma: 0.004))
            }
        }

        if let model = RoomModel.build(from: cloud) {
            r.check("L-kształt: 6 narożników", model.corners.count == 6, "= \(model.corners.count)")
            r.check("L-kształt: 6 ścian", model.walls.count == 6, "= \(model.walls.count)")
            // pole L = 4*2 + 2*2 = 12 m²
            r.check("L-kształt: pole ≈ 12 m²", abs(model.area - 12) < 1.0,
                    String(format: "%.2f m²", model.area))
        } else {
            r.check("L-kształt: model powstał", false, "nil")
        }
    }

    // 4) wygięta ściana — model MUSI to pokazać, a nie wyprostować
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6, bow: 0.03)  // 3 cm wybrzuszenia
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
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6,
                                  withWindow: true, withDoor: true)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("otwory: model powstał", false, "nil")
            return
        }
        r.check("otwory: wykryto 2", model.openings.count == 2, "= \(model.openings.count)")
        let doors = model.openings.filter { $0.kind == .door }
        let windows = model.openings.filter { $0.kind == .window }
        r.check("otwory: 1 drzwi", doors.count == 1, "= \(doors.count)")
        r.check("otwory: 1 okno", windows.count == 1, "= \(windows.count)")
        if let d = doors.first {
            r.check("drzwi: sięgają podłogi", d.sill < 0.2, String(format: "sill %.2f m", d.sill))
            r.check("drzwi: szerokość ≈ 0,9 m", abs(d.width - 0.9) < 0.25,
                    String(format: "%.2f m", d.width))
        }
        if let w = windows.first {
            r.check("okno: nie sięga podłogi", w.sill > 0.6, String(format: "sill %.2f m", w.sill))
            r.check("okno: szerokość ≈ 1,2 m", abs(w.width - 1.2) < 0.3,
                    String(format: "%.2f m", w.width))
        }
    }

    // 6) geometria pomocnicza: pole powierzchni
    do {
        let corners = [
            RoomModel.Corner(x: 0, z: 0), RoomModel.Corner(x: 2, z: 0),
            RoomModel.Corner(x: 2, z: 1), RoomModel.Corner(x: 0, z: 1),
        ]
        r.check("pole: prostokąt 2×1 = 2 m²",
                abs(RoomModel.polygonArea(corners) - 2) < 0.001,
                String(format: "%.3f", RoomModel.polygonArea(corners)))

        // linia dopasowana do punktów na osi X: kierunek poziomy, zakres 0…2 m
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
    }

    // 7) odporność: za mało punktów, brak podłogi
    do {
        r.check("za mało punktów → nil", RoomModel.build(from: []) == nil)
        // chmura bez podłogi (tylko pionowa płaszczyzna)
        var wallOnly: [RoomModel.Sample] = []
        for i in 0..<3000 {
            wallOnly.append(.init(position: SIMD3(Float(i % 100) * 0.01, Float(i / 100) * 0.01, 0),
                                  sigma: 0.01))
        }
        r.check("chmura bez podłogi → nil albo model bez ścian",
                RoomModel.build(from: wallOnly)?.walls.count ?? 0 < 3)
    }
}
