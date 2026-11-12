// Diagnostyka detekcji pomieszczenia.
//   swift run RoomDiag                 → pokoje syntetyczne (znane wymiary)
//   swift run RoomDiag <plik.ply>      → REALNY skan (np. Trimble X9)
import Foundation
import simd
import KitchenCore

// MARK: - wczytywanie PLY (tylko do diagnostyki)

/// Wczytuje PLY binary_little_endian z polami x, y, z.
///
/// Parser jest celowo prosty: czyta nagłówek, liczy rozmiar rekordu z typów
/// właściwości (float = 4 B, uchar = 1 B) i skacze po rekordach. Kolejność
/// właściwości w pliku nie ma znaczenia — bierzemy tylko pierwsze trzy floaty.
func loadPLY(_ path: String) -> [RoomModel.Sample] {
    guard let data = FileManager.default.contents(atPath: path) else { return [] }
    guard let endRange = data.range(of: Data("end_header".utf8)) else { return [] }
    var bodyStart = endRange.upperBound
    while bodyStart < data.count, data[bodyStart] == 0x0A || data[bodyStart] == 0x0D {
        bodyStart += 1
    }
    let header = String(decoding: data[0..<endRange.lowerBound], as: UTF8.self)

    var count = 0
    var recordSize = 0
    var floatOffset = 0
    var floatSeen = 0
    var xyzOffsets: [Int] = []

    for rawLine in header.split(separator: "\n") {
        let parts = rawLine.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.count >= 3, parts[0] == "element", parts[1] == "vertex" {
            count = Int(parts[2]) ?? 0
        }
        guard parts.count == 3, parts[0] == "property" else { continue }
        let type = String(parts[1])
        let name = String(parts[2])
        let size = type == "uchar" || type == "char" ? 1
            : (type == "double" ? 8 : 4)
        if ["x", "y", "z"].contains(name), floatSeen < 3 {
            xyzOffsets.append(recordSize)
            floatSeen += 1
        }
        recordSize += size
    }
    _ = floatOffset

    guard count > 0, recordSize > 0, xyzOffsets.count == 3,
          bodyStart + count * recordSize <= data.count else { return [] }

    var out: [RoomModel.Sample] = []
    out.reserveCapacity(count)
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let base = raw.baseAddress!.advanced(by: bodyStart)
        for i in 0..<count {
            let p = base.advanced(by: i * recordSize)
            let x = p.loadUnaligned(fromByteOffset: xyzOffsets[0], as: Float.self)
            let y = p.loadUnaligned(fromByteOffset: xyzOffsets[1], as: Float.self)
            let z = p.loadUnaligned(fromByteOffset: xyzOffsets[2], as: Float.self)
            guard x.isFinite, y.isFinite, z.isFinite else { continue }
            out.append(RoomModel.Sample(position: SIMD3(x, y, z), sigma: 0.002))
        }
    }
    return out
}

// MARK: - pokoje syntetyczne

func makeCloud(width: Float, depth: Float, height: Float, seed: UInt64 = 7,
               bow: Float = 0, withWindow: Bool = false, withDoor: Bool = false,
               density: Float = 1200) -> [RoomModel.Sample] {
    var state = seed
    func rnd() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xFFFFFF) / Float(0x1000000) - 0.5
    }
    var cloud: [RoomModel.Sample] = []
    let halfW = width / 2, halfD = depth / 2
    for _ in 0..<Int(width * depth * density) {
        cloud.append(.init(position: SIMD3((rnd() + 0.5) * width - halfW, 0,
                                           (rnd() + 0.5) * depth - halfD), sigma: 0.002))
    }
    func wall(axis: Int, pos: Float, from: Float, to: Float) {
        let len = to - from
        for _ in 0..<Int(len * height * density) {
            let t = from + (rnd() + 0.5) * len
            let y = (rnd() + 0.5) * height
            let u = (t - from) / Swift.max(0.001, len)
            let bowValue = bow * (1 - pow(2 * u - 1, 2))
            let p = axis == 0 ? SIMD3(pos + bowValue + rnd() * 0.002, y, t)
                              : SIMD3(t, y, pos + bowValue + rnd() * 0.002)
            if withDoor, axis == 1, pos < 0, t > -0.45, t < 0.45, y < 2.05 { continue }
            if withWindow, axis == 1, pos < 0, t > 0.5, t < 1.7, y > 0.9, y < 2.1 { continue }
            cloud.append(.init(position: p, sigma: 0.004))
        }
    }
    wall(axis: 1, pos: -halfD, from: -halfW, to: halfW)
    wall(axis: 1, pos: halfD, from: -halfW, to: halfW)
    wall(axis: 0, pos: -halfW, from: -halfD, to: halfD)
    wall(axis: 0, pos: halfW, from: -halfD, to: halfD)
    return cloud
}

func report(_ label: String, _ model: RoomModel.Result?) {
    guard let m = model else { print("\n\(label): NIL"); return }
    print("\n\(label)")
    print(String(format: "  narożniki %d, ściany %d, otwory %d",
                 m.corners.count, m.walls.count, m.openings.count))
    print(String(format: "  wysokość %.2f m, pole %.2f m²", m.height, m.area))
    let lengths = m.walls.map(\.length).sorted()
    print("  długości: " + lengths.map { String(format: "%.2f", $0) }.joined(separator: ", "))
    for p in m.corners { print(String(format: "    (%.3f, %.3f)", p.x, p.z)) }
}

// MARK: - tryb realnego skanu

func analyseRealScan(_ path: String) {
    let cloud = loadPLY(path)
    print("wczytano \(cloud.count.formatted()) pkt z \(path)")
    guard !cloud.isEmpty else { print("PLY pusty lub nieobsługiwany"); exit(1) }

    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    for s in cloud { lo = simd_min(lo, s.position); hi = simd_max(hi, s.position) }
    print(String(format: "obrys: %.2f × %.2f × %.2f m", (hi - lo).x, (hi - lo).y, (hi - lo).z))
    print(String(format: "  X %.2f…%.2f   Y %.2f…%.2f   Z %.2f…%.2f",
                 lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))

    // UKŁAD WSPÓŁRZĘDNYCH: Trimble X9 trzyma pion w Z, a `RoomModel` oczekuje
    // pionu w Y (tak jak ARKit). Zamieniamy więc Y↔Z. Bez tego „podłoga"
    // wypada na ścianie i detekcja zwraca śmieci.
    let swapped = cloud.map {
        RoomModel.Sample(position: SIMD3($0.position.x, $0.position.z, $0.position.y),
                         sigma: $0.sigma)
    }

    // ETAP PO ETAPIE — bez tego nie wiadomo, gdzie detekcja odpada
    guard let floorY = RoomModel.detectFloor(samples: swapped) else {
        print("ETAP 1: detectFloor = nil"); exit(2)
    }
    print(String(format: "ETAP 1 podłoga: y = %.3f m", floorY))
    let ceilY = RoomModel.detectCeiling(samples: swapped, floorY: floorY)
    print(String(format: "ETAP 2 sufit: %@", ceilY.map { String(format: "%.3f m", $0) } ?? "nil"))
    let top = ceilY ?? RoomModel.wallTop(samples: swapped, floorY: floorY)
    print(String(format: "        poziom konturu: %.3f m", top))

    let bandPts = swapped.filter { $0.position.y >= top - 0.4 && $0.position.y <= top - 0.02 }
    print("ETAP 3 pasmo konturu: \(bandPts.count.formatted()) pkt")
    let plan = bandPts.map { SIMD2($0.position.x, $0.position.z) }
    // ETAP 4 z diagnostyką: co daje każda kombinacja (cell, radius)
    for (cell, radius) in [(Float(0.03), 1), (0.04, 2), (0.05, 2), (0.05, 3), (0.06, 4)] {
        let g = RoomModel.OccupancyGrid(points: plan, cell: cell, sealRadius: radius)
        let frac = g.interiorFraction
        let outline = RoomModel.roomOutline(points: plan, cell: cell, radius: radius,
                                            options: RoomModel.Options())
        print(String(format: "  cell %.2f r=%d: wnętrze %.1f%% siatki %dx%d → kontur %@",
                     cell, radius, frac * 100, g.width, g.height,
                     outline.map { "\($0.count) narożników" } ?? "nil"))
        if let o = outline, o.count >= 3 {
            for q in o { print(String(format: "     (%8.3f, %8.3f)", q.x, q.y)) }
            break
        }
    }
    let finalOutline = RoomModel.roomOutline(points: plan, options: RoomModel.Options())
    print("ETAP 4 wynik: \(finalOutline?.count ?? 0) narożników")

    // NOWA ŚCIEŻKA: ściany z normalnych (skaner w środku pomieszczenia)
    let tp = Date()
    let wallResult = ScanWalls.detect(points: swapped.map(\.position))
    if let wr = wallResult {
        print(String(format: "\nŚCIANY Z NORMALNYCH: %d płaszczyzn, czas %.1f s",
                     wr.planes.count, Date().timeIntervalSince(tp)))
        print(String(format: "  podłoga %.3f m, sufit %.3f m, pole ścian %.1f m²",
                     wr.floorY, wr.ceilingY, wr.wallArea))
        for (i, pl) in wr.planes.enumerated() {
            let angle = atan2(pl.normal.z, pl.normal.x) * 180 / .pi
            print(String(format: "  %d: %5.1f°  szer %5.2f × wys %5.2f m  pole %6.2f m²  "
                         + "pkt %7d  med %4.1f mm  p95 %4.1f mm",
                         i, angle, pl.width, pl.height, pl.area, pl.support,
                         pl.residualMedian * 1000, pl.residualP95 * 1000))
        }
    } else {
        print("\nŚCIANY Z NORMALNYCH: nil")
    }

    let t0 = Date()
    guard let model = RoomModel.build(from: swapped) else {
        print("MODEL: nil — detekcja nie dała wyniku")
        exit(2)
    }
    print(String(format: "czas detekcji: %.2f s", Date().timeIntervalSince(t0)))
    print("\nNAROŻNIKI: \(model.corners.count)")
    for c in model.corners { print(String(format: "  (%8.3f, %8.3f)", c.x, c.z)) }
    print(String(format: "\nwysokość %.3f m, pole %.2f m²", model.height, model.area))
    print("ŚCIANY: \(model.walls.count)")
    for (i, w) in model.walls.enumerated() {
        print(String(format: "  %d: dł %6.3f m  med %5.1f mm  p95 %5.1f mm  pion %6.1f mm/m  pkt %d",
                     i, w.length, w.residualMedian * 1000, w.residualP95 * 1000,
                     w.plumbMmPerM, w.samples))
    }
    print("OTWORY: \(model.openings.count)")
    for o in model.openings {
        print(String(format: "  %@ ściana %d: offset %.2f  szer %.2f  próg %.2f  wys %.2f",
                     o.kind.rawValue, o.wallIndex, o.offset, o.width, o.sill, o.height))
    }
}

// MARK: - start

let args = CommandLine.arguments
if args.count > 1 {
    analyseRealScan(args[1])
} else {
    report("prostokąt 4×3", RoomModel.build(from: makeCloud(width: 4, depth: 3, height: 2.6)))
    report("prostokąt 4,2×3,4 wygięta ściana 3 cm",
           RoomModel.build(from: makeCloud(width: 4.2, depth: 3.4, height: 2.6, bow: 0.03)))
    report("prostokąt 5×4 z oknem i drzwiami",
           RoomModel.build(from: makeCloud(width: 5, depth: 4, height: 2.7,
                                           withWindow: true, withDoor: true)))
}
