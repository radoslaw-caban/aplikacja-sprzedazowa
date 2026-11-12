import Foundation
import simd

/// Odczyt zabudowy kuchennej **ze skanu** (chmura/siatka) i zamiana na projekt
/// z szafek parametrycznych.
///
/// Wejście: trójkąty w metrach (świat sceny). Wyjście: biegi szafek w mm,
/// z podziałem na moduły — gotowe do wstawienia jako `Cabinet`.
///
/// Moduł jest celowo **niepodpięty** do UI: liczy się tylko geometria i liczby,
/// więc da się go testować bez sceny i bez RealityKit.
///
/// Metoda (kolejność ma znaczenie):
/// 1. szukamy **poziomych powierzchni skierowanych w górę** w pasie wysokości blatu
///    (0,72–1,05 m) — to są blaty, a nie „meble" czy ściany;
/// 2. obracamy punkty do układu blatu (minimalna obwiednia, krok 0,5°) —
///    kuchnie w skanach rzadko stoją idealnie na osiach;
/// 3. rasteryzujemy blat na siatce 5 cm i wydzielamy **spójne wyspy**;
/// 4. z każdej wyspy wycinamy **biegi**: pasy głębokości 0,45–0,75 m o pokryciu
///    co najmniej 55%, najdłuższy pierwszy, i usuwamy zajęte komórki;
/// 5. dzielimy bieg na moduły o szerokości najbliższej 600 mm (300–1000 mm).
public enum ScanKitchen {

    // MARK: - Wejście / wyjście

    public struct Options {
        /// bok komórki rastra [m]
        public var cell: Float = 0.05
        /// dolna/górna granica wysokości blatu [m]
        public var counterLow: Float = 0.72
        public var counterHigh: Float = 1.05
        /// dopuszczalna głębokość biegu [m]
        public var runDepthMin: Float = 0.48
        public var runDepthMax: Float = 0.70
        /// minimalna długość i powierzchnia biegu
        public var minRunLength: Float = 0.45
        public var minRunArea: Float = 0.25
        /// docelowa szerokość modułu [mm]
        public var moduleTarget: Float = 600
        public var moduleMin: Float = 300
        public var moduleMax: Float = 1000
        /// gęstość próbkowania powierzchni [punktów/m²]
        public var samplesPerM2: Float = 3000
        /// minimalne wypełnienie pasa (odsiewa pasy grubsze niż blat i skrawki)
        public var minStripFill: Float = 0.85
        /// bieg musi stać przy pionowej powierzchni (ścianie/słupku);
        /// odsiewa stoły, wyspy i blaty kuchenek wolnostojących
        public var requireWall: Bool = true
        /// biegi liczone wzdłuż ścian (eksperymentalne: w skanie z wieloma
        /// pomieszczeniami kierunki ścian są mylące — domyślnie wyłączone)
        public var useWallRuns: Bool = false
        /// jak blisko ściany musi być tył biegu [m]
        public var wallProximity: Float = 0.40

        public init() {}
    }

    public enum ModuleKind: String {
        case base        // szafka z frontem
        case drawers     // szuflady (do ustalenia przy wyposażeniu)
        case tall        // słupek
    }

    public struct Module {
        /// szerokość w mm (pełne mm)
        public let width: Float
        public let kind: ModuleKind
        public init(width: Float, kind: ModuleKind = .base) {
            self.width = width
            self.kind = kind
        }
    }

    /// Jeden bieg zabudowy: początek, długość, głębokość, kąt i moduły.
    public struct Run {
        /// początek biegu w mm (x, z) w układzie świata, y = 0
        public let startX: Float
        public let startZ: Float
        /// kierunek biegu w stopniach (0° = +X)
        public let angleDeg: Float
        public let lengthMM: Float
        public let depthMM: Float
        /// wysokość blatu nad podłogą w mm (0, jeśli nie wykryto)
        public let worktopMM: Float
        public let modules: [Module]

        public var lengthM: Float { lengthMM / 1000 }
        public var depthM: Float { depthMM / 1000 }
    }

    public struct Proposal {
        public var runs: [Run]
        /// kąt, o który obrócona jest kuchnia względem osi sceny
        public var rotationDeg: Float
        /// wykryta wysokość blatu [mm]
        public var worktopHeightMM: Float
        /// powierzchnia blatów, z której policzono biegi [m²]
        public var counterAreaM2: Float
        /// co wykryto, a czego nie — bez zgadywania
        public var notes: [String]

        public var totalLengthMM: Float { runs.reduce(0) { $0 + $1.lengthMM } }
        public var moduleCount: Int { runs.reduce(0) { $0 + $1.modules.count } }
        public var isEmpty: Bool { runs.isEmpty }
    }

    // MARK: - Detekcja

    public static func detect(triangles: [SIMD3<Float>], options: Options = Options()) -> Proposal {
        var notes: [String] = []
        guard triangles.count >= 3 else {
            return Proposal(runs: [], rotationDeg: 0, worktopHeightMM: 0, counterAreaM2: 0,
                            notes: ["brak geometrii"])
        }

        // 1. trójkąty blatu: poziome i skierowane w górę, w pasie wysokości
        var counterTris: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float)] = []
        var counterArea: Float = 0
        var heightWeighted: [(Float, Float)] = []

        var i = 0
        while i + 2 < triangles.count {
            let a = triangles[i], b = triangles[i + 1], c = triangles[i + 2]
            i += 3
            let n = simd_cross(b - a, c - a)
            let len = simd_length(n)
            guard len > 1e-9 else { continue }
            let unit = n / len
            let area = len / 2
            let centroid = (a + b + c) / 3
            guard abs(unit.y) > 0.85, centroid.y > options.counterLow, centroid.y < options.counterHigh else { continue }
            counterTris.append((a, b, c, area))
            counterArea += area
            heightWeighted.append((centroid.y, area))
        }

        guard !counterTris.isEmpty else {
            return Proposal(runs: [], rotationDeg: 0, worktopHeightMM: 0, counterAreaM2: 0,
                            notes: ["nie znaleziono poziomych blatów w pasie \(Int(options.counterLow * 1000))–\(Int(options.counterHigh * 1000)) mm"])
        }

        let worktop = weightedMedian(heightWeighted)

        // 2. orientacja: minimalna obwiednia punktów blatu
        var samples: [SIMD2<Float>] = []
        samples.reserveCapacity(counterTris.count * 8)
        var rng = LCG(seed: 0x5EED_1234)
        for (a, b, c, area) in counterTris {
            let count = max(1, Int(area * options.samplesPerM2))
            for _ in 0..<count {
                var u = rng.nextFloat(), v = rng.nextFloat()
                if u + v > 1 { u = 1 - u; v = 1 - v }
                let p = a + u * (b - a) + v * (c - a)
                samples.append(SIMD2(p.x, p.z))
            }
        }
        guard !samples.isEmpty else {
            return Proposal(runs: [], rotationDeg: 0, worktopHeightMM: worktop * 1000, counterAreaM2: counterArea,
                            notes: ["brak próbek powierzchni blatu"])
        }

        // Orientacja z **krawędzi blatów**: blaty to prostokąty, więc ich boki
        // leżą dokładnie wzdłuż biegu. Obwiednia dla kuchni w L bywa kwadratowa
        // i dawała 60° zamiast 30° — krawędzie nie mają tej niejednoznaczności.
        let rot = estimateRotation(samples)

        // 3. rasteryzacja w układzie blatu
        let local = samples.map { rotate($0, by: -rot) }
        let lo = local.reduce(SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let hi = local.reduce(SIMD2<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        let cell = options.cell
        let nx = max(1, Int(((hi.x - lo.x) / cell).rounded(.up)) + 1)
        let nz = max(1, Int(((hi.y - lo.y) / cell).rounded(.up)) + 1)
        guard nx * nz < 4_000_000 else {
            return Proposal(runs: [], rotationDeg: degrees(rot), worktopHeightMM: worktop * 1000,
                            counterAreaM2: counterArea, notes: ["obszar blatu za duży do rastrowania"])
        }

        var grid = [Int32](repeating: 0, count: nx * nz)
        for p in local {
            let ix = min(nx - 1, max(0, Int((p.x - lo.x) / cell)))
            let iz = min(nz - 1, max(0, Int((p.y - lo.y) / cell)))
            grid[iz * nx + ix] += 1
        }
        var mask = grid.map { $0 >= 2 }

        // pionowe powierzchnie o wysokości >1,2 m = ściany (dla testu przylegania)
        var wallPoints: [SIMD2<Float>] = []
        if options.requireWall {
            var k = 0
            while k + 2 < triangles.count {
                let a = triangles[k], b = triangles[k + 1], c = triangles[k + 2]
                k += 3
                let n = simd_cross(b - a, c - a)
                let len = simd_length(n)
                guard len > 1e-9 else { continue }
                let unit = n / len
                guard abs(unit.y) < 0.35 else { continue }
                let yLo = Swift.min(a.y, Swift.min(b.y, c.y))
                let yHi = Swift.max(a.y, Swift.max(b.y, c.y))
                guard yHi - yLo > 1.2, yLo < 0.4 else { continue }
                let centroid = (a + b + c) / 3
                wallPoints.append(rotate(SIMD2(centroid.x, centroid.z), by: -rot))
            }
        }

        // 4. wyspy → pasy zabudowy
        //    Nie „zjemy" komórek po pierwszym pasie: róg kuchni w L należy do
        //    obu blatów, a po zużyciu powstawały ogony 2,5 m + 1,65 m.
        var runs: [Run] = []
        let comps = components(mask: &mask, nx: nx, nz: nz)
        for component in comps {
            // tylko pasy wypełnione w ≥85% — to odsiewa pasy „grubsze" od blatu
            // (600 mm zamiast 750 mm) i skrawki po rogu
            var strips = maximalStrips(cells: component, nx: nx, nz: nz, options: options)
                .filter { $0.fill >= options.minStripFill }
            strips.sort { $0.areaCells > $1.areaCells }
            var kept: [Strip] = []
            for strip in strips {
                let overlaps = kept.contains { $0.overlapFraction(with: strip) > 0.45 }
                if overlaps { continue }
                kept.append(strip)
            }
            for strip in kept {
                let lengthM = Float(strip.count) * cell
                guard lengthM >= options.minRunLength else { continue }
                if options.requireWall,
                   !hasWallBehind(strip, walls: wallPoints, origin: lo, cell: cell,
                                  proximity: options.wallProximity) {
                    continue
                }
                let depthM = Float(strip.depth) * cell
                let lengthMM = (lengthM * 1000).rounded()
                let depthMM = (depthM * 1000).rounded()
                let originLocal = SIMD2(lo.x + Float(strip.colRange.lowerBound) * cell,
                                        lo.y + Float(strip.rowRange.lowerBound) * cell)
                let origin = rotate(originLocal, by: rot)
                let modules = split(lengthMM: lengthMM, options: options)
                let runAngle = rot + (strip.alongX ? 0 : .pi / 2)
                runs.append(Run(startX: origin.x * 1000,
                                startZ: origin.y * 1000,
                                angleDeg: degrees(runAngle),
                                lengthMM: lengthMM,
                                depthMM: depthMM,
                                worktopMM: (worktop * 1000).rounded(),
                                modules: modules))
            }
        }

        // 5. biegi „przy ścianie" są pewniejsze niż pasy z rastra: ściana daje
        //    prostą, do której wystarczy przypiąć punkty blatu — dzięki temu
        //    przerwy w blacie i dwa „pasy" tej samej ściany nie robią trzech biegnów
        if options.useWallRuns, options.requireWall, !wallPoints.isEmpty {
            let along = runsAlongWalls(samples: local, walls: wallPoints, rotation: rot, options: options)
            if !along.isEmpty { runs = along }
        }

        // 6. scalanie współliniowych odcinków (przerwy zlewu/płyty dzielą blat)
        runs = mergeCollinear(runs, options: options)
        runs.sort { $0.lengthMM > $1.lengthMM }

        if runs.isEmpty {
            notes.append("blat wykryty (\(String(format: "%.2f", counterArea)) m²), ale nie udało się wydzielić biegu o szerokości 0,45–0,78 m")
        } else {
            notes.append("blat \(String(format: "%.2f", counterArea)) m², biegi: \(runs.count), moduły: \(runs.reduce(0) { $0 + $1.modules.count })")
        }
        notes.append("fronty, zlew i sprzęt nie są rozpoznawane z geometrii — do uzupełnienia w projekcie")

        return Proposal(runs: runs, rotationDeg: degrees(rot), worktopHeightMM: (worktop * 1000).rounded(),
                        counterAreaM2: counterArea, notes: notes)
    }

    // MARK: - Biegi po ścianach

    /// Biegi wyznaczone **wzdłuż ścian**: dla każdej wykrytej linii ściany bierzemy
    /// punkty blatu w odległości ≤ 0,75 m i liczymy przedziały pokrycia.
    /// Przerwy do 300 mm (zlew, płyta) nie dzielą biegu.
    private static func runsAlongWalls(samples: [SIMD2<Float>], walls: [SIMD2<Float>],
                                       rotation: Float, options: Options) -> [Run] {
        guard samples.count > 50, walls.count > 20 else { return [] }

        // tylko ściany **przy blacie** (≤1 m): w skanie jest cały budynek,
        // a kierunki ścian z innych pomieszczeń psuły orientację biegnów
        let gridCell: Float = 0.5
        var occupied = Set<Int64>()
        func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) &* 100_000 &+ Int64(y) }
        for p in samples {
            occupied.insert(key(Int((p.x / gridCell).rounded(.down)), Int((p.y / gridCell).rounded(.down))))
        }
        let nearWalls = walls.filter { w in
            let cx = Int((w.x / gridCell).rounded(.down))
            let cy = Int((w.y / gridCell).rounded(.down))
            for dx in -2...2 {
                for dy in -2...2 where occupied.contains(key(cx + dx, cy + dy)) {
                    return true
                }
            }
            return false
        }
        guard nearWalls.count > 20 else { return [] }

        // 1. dominujące kierunki ścian (mod 180°), max dwa, min 30° różnicy
        let bins = 90                                  // koszyk 2°
        var weight = [Float](repeating: 0, count: bins)
        for i in 1..<nearWalls.count {
            let d = nearWalls[i] - nearWalls[i - 1]
            let len = simd_length(d)
            guard len > 0.2 else { continue }
            var ang = atan2(d.y, d.x) * 180 / .pi
            ang = ang.truncatingRemainder(dividingBy: 180)
            if ang < 0 { ang += 180 }
            weight[Swift.min(bins - 1, Int(ang / 2))] += len
        }
        var directions: [Float] = []
        for _ in 0..<2 {
            guard let peak = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[peak] > 0 else { break }
            directions.append(Float(peak) * 2 * .pi / 180)
            let center = peak
            for d in -8...8 {
                let idx = center + d
                if idx >= 0 && idx < bins { weight[idx] = 0 }
            }
        }
        guard !directions.isEmpty else { return [] }

        var runs: [Run] = []
        for direction in directions {
            let u = SIMD2<Float>(cos(direction), sin(direction))
            let n = SIMD2<Float>(-u.y, u.x)

            // 2. linie ścian: klastrowanie po odległości od początku układu
            var lineBuckets: [Int: [(t: Float, s: Float)]] = [:]
            for w in nearWalls {
                let t = simd_dot(w, u)
                let sv = simd_dot(w, n)
                lineBuckets[Int((sv / 0.08).rounded()), default: []].append((t, sv))
            }

            for (_, points) in lineBuckets {
                guard points.count >= 12 else { continue }
                let ts = points.map { $0.t }
                guard let minT = ts.min(), let maxT = ts.max(), maxT - minT > 1.0 else { continue }
                let sLine = points.map { $0.s }.sorted()[points.count / 2]

                // 3. punkty blatu przy tej ścianie
                var along: [Float] = []
                var depthSum: Float = 0
                for p in samples {
                    let sv = simd_dot(p, n)
                    let dist = abs(sv - sLine)
                    guard dist <= 0.75 else { continue }
                    along.append(simd_dot(p, u))
                    depthSum += dist
                }
                guard along.count > 60 else { continue }
                along.sort()

                // 4. przedziały z tolerancją przerwy 300 mm
                var intervals: [(Float, Float)] = []
                var start = along[0], prev = along[0]
                for value in along.dropFirst() {
                    if value - prev > 0.30 {
                        intervals.append((start, prev))
                        start = value
                    }
                    prev = value
                }
                intervals.append((start, prev))

                for (a, b) in intervals {
                    let lengthMM = ((b - a) * 1000).rounded()
                    guard lengthMM >= options.minRunLength * 1000 else { continue }
                    // głębokość: mediana odległości (przybliżenie średnią), w granicach
                    let depthMM = Swift.min(options.runDepthMax * 1000,
                                            Swift.max(options.runDepthMin * 1000,
                                                      (depthSum / Float(along.count)) * 1000 * 1.6)).rounded()
                    let originLocal = u * a + n * sLine
                    let originWorld = rotate(originLocal, by: rotation)
                    runs.append(Run(startX: originWorld.x * 1000,
                                    startZ: originWorld.y * 1000,
                                    angleDeg: degrees(rotation + direction),
                                    lengthMM: lengthMM,
                                    depthMM: depthMM,
                                    worktopMM: 0,
                                    modules: split(lengthMM: lengthMM, options: options)))
                }
            }
        }
        return runs
    }

    // MARK: - Scalanie biegnów

    /// Łączy odcinki leżące na jednej linii, jeśli przerwa jest mniejsza niż `maxGapMM`.
    ///
    /// Blat w skanie bywa przerwany zlewem, płytą albo okapem — bez scalania
    /// jeden bieg rozjeżdża się na 2,5 + 2,3 + 1,2 m zamiast 3,9 m.
    /// Odcinki **nakładające się** też są scalane (detektor może dwa razy
    /// złapać ten sam fragment pod różnym kątem siatki).
    static func mergeCollinear(_ runs: [Run], options: Options,
                               maxGapMM: Float = 400, maxAngleDiff: Float = 4,
                               maxLineOffsetMM: Float = 260) -> [Run] {
        guard runs.count > 1 else { return runs }
        var pending = runs.sorted { $0.lengthMM > $1.lengthMM }
        var merged: [Run] = []

        while let base = pending.first {
            pending.removeFirst()
            var dir = SIMD2<Float>(cos(base.angleDeg * .pi / 180), sin(base.angleDeg * .pi / 180))
            var origin = SIMD2<Float>(base.startX, base.startZ)
            var end = origin + dir * base.lengthMM
            var depth = base.depthMM
            var worktop = base.worktopMM

            var didMerge = true
            while didMerge {
                didMerge = false
                for (index, other) in pending.enumerated() {
                    let otherDir = SIMD2<Float>(cos(other.angleDeg * .pi / 180), sin(other.angleDeg * .pi / 180))
                    // kąt (mod 180°, biegi są odcinkami, nie wektorami)
                    var dot = abs(simd_dot(dir, otherDir))
                    dot = Swift.min(1, dot)
                    let angleDiff = acos(dot) * 180 / .pi
                    guard angleDiff <= maxAngleDiff else { continue }

                    // odległość linii: rzut prostopadły początku drugiego odcinka
                    let normal = SIMD2<Float>(-dir.y, dir.x)
                    let offset = abs(simd_dot(SIMD2(other.startX, other.startZ) - origin, normal))
                    guard offset <= maxLineOffsetMM else { continue }

                    // przedziały wzdłuż kierunku
                    let oStart = simd_dot(SIMD2(other.startX, other.startZ) - origin, dir)
                    let oEnd = oStart + other.lengthMM
                    let bStart: Float = 0
                    let bEnd = simd_length(end - origin)
                    let overlaps = oStart <= bEnd + maxGapMM && oEnd >= bStart - maxGapMM
                    guard overlaps else { continue }

                    // scal: nowy zakres
                    let newStart = Swift.min(bStart, oStart)
                    let newEnd = Swift.max(bEnd, oEnd)
                    let newOrigin = origin + dir * newStart
                    origin = newOrigin
                    end = origin + dir * (newEnd - newStart)
                    depth = Swift.max(depth, other.depthMM)
                    if worktop == 0 { worktop = other.worktopMM }
                    pending.remove(at: index)
                    didMerge = true
                    break
                }
            }

            let length = simd_length(end - origin)
            guard length >= options.minRunLength * 1000 else { continue }
            let angle = atan2(dir.y, dir.x) * 180 / .pi
            merged.append(Run(startX: origin.x,
                              startZ: origin.y,
                              angleDeg: angle,
                              lengthMM: length.rounded(),
                              depthMM: depth,
                              worktopMM: worktop,
                              modules: split(lengthMM: length.rounded(), options: options)))
        }
        return merged
    }

    // MARK: - Podział na moduły

    /// Dzieli długość na równe moduły najbliższe `moduleTarget`, w granicach min/max.
    /// Suma modułów = długość biegu co do 1 mm — ostatni moduł bierze resztę.
    static func split(lengthMM: Float, options: Options) -> [Module] {
        guard lengthMM > 0 else { return [] }
        var count = max(1, Int((lengthMM / options.moduleTarget).rounded()))
        let maxCount = max(1, Int((lengthMM / options.moduleMin).rounded(.down)))
        count = min(count, maxCount)
        while count > 1 && lengthMM / Float(count) < options.moduleMin { count -= 1 }
        while count < 60 && lengthMM / Float(count) > options.moduleMax { count += 1 }

        let width = (lengthMM / Float(count)).rounded()
        var modules = [Module](repeating: Module(width: width), count: count)
        let drift = lengthMM - width * Float(count)   // ≤ 0,5 mm na moduł
        if drift != 0, !modules.isEmpty {
            modules[modules.count - 1] = Module(width: width + drift)
        }
        return modules
    }

    // MARK: - Pas (bieg)

    /// Pas zabudowy. `colRange` zawsze idzie po X, `rowRange` po Z;
    /// `alongX` mówi, w której osi leży **długość** pasa.
    private struct Strip {
        var rowRange: ClosedRange<Int>
        var colRange: ClosedRange<Int>
        var alongX: Bool
        /// pokrycie pasa zajętymi komórkami (0…1)
        var fill: Float = 0
        var count: Int { alongX ? colRange.count : rowRange.count }
        var depth: Int { alongX ? rowRange.count : colRange.count }
        var areaCells: Int { count * depth }

        func overlapFraction(with other: Strip) -> Float {
            let cols = max(0, min(colRange.upperBound, other.colRange.upperBound)
                              - max(colRange.lowerBound, other.colRange.lowerBound) + 1)
            let rows = max(0, min(rowRange.upperBound, other.rowRange.upperBound)
                              - max(rowRange.lowerBound, other.rowRange.lowerBound) + 1)
            let inter = cols * rows
            let smaller = min(areaCells, other.areaCells)
            return smaller > 0 ? Float(inter) / Float(smaller) : 0
        }
    }

    /// Wszystkie pasy o głębokości 0,45–0,78 m i pokryciu ≥ 75%.
    ///
    /// Dla każdej linii startowej testujemy kilka głębokości i wybieramy tę,
    /// która daje najlepsze wypełnienie — dzięki temu blat 600 mm nie rozjeżdża się
    /// na pas 800 mm ani na „resztki" po rogu.
    private static func maximalStrips(cells: Set<Int>, nx: Int, nz: Int,
                                      options: Options) -> [Strip] {
        guard !cells.isEmpty else { return [] }
        let cell = options.cell
        let minDepth = max(1, Int((options.runDepthMin / cell).rounded()))
        let maxDepth = max(minDepth, Int((options.runDepthMax / cell).rounded()))

        func strips(alongX: Bool) -> [Strip] {
            var found: [Strip] = []
            let outer = alongX ? nz : nx     // oś głębokości
            let inner = alongX ? nx : nz     // oś długości
            for start in 0..<outer {
                for depth in minDepth...maxDepth {
                    guard start + depth <= outer else { continue }
                    var perLine = [Int](repeating: 0, count: inner)
                    var occupied = 0
                    for d in 0..<depth {
                        for i in 0..<inner {
                            let idx = alongX ? (start + d) * nx + i : i * nx + (start + d)
                            if cells.contains(idx) {
                                perLine[i] += 1
                                occupied += 1
                            }
                        }
                    }
                    guard occupied > 0 else { continue }
                    let threshold = max(1, Int(Float(depth) * 0.75))
                    var runStart: Int?
                    var runEnd = 0
                    func close(_ a: Int, _ b: Int) {
                        let length = b - a + 1
                        guard length >= 4 else { return }
                        var inside = 0
                        for i in a...b { inside += perLine[i] }
                        let fill = Float(inside) / Float(length * depth)
                        guard fill >= 0.75 else { return }
                        let band = start...(start + depth - 1)
                        let span = a...b
                        found.append(alongX
                            ? Strip(rowRange: band, colRange: span, alongX: true, fill: fill)
                            : Strip(rowRange: span, colRange: band, alongX: false, fill: fill))
                    }
                    for i in 0..<inner {
                        if perLine[i] >= threshold {
                            if runStart == nil { runStart = i }
                            runEnd = i
                        } else if let a = runStart {
                            close(a, runEnd)
                            runStart = nil
                        }
                    }
                    if let a = runStart { close(a, runEnd) }
                }
            }
            return found
        }

        // odsiewamy pasy, które są tylko fragmentem dłuższego w tym samym kierunku
        // Najpierw pasy **najlepiej wypełnione** (600 mm wygrywa z 750 mm),
        // dopiero potem większe — inaczej pas 750 mm „połykał" właściwy 600 mm.
        func dedupe(_ items: [Strip]) -> [Strip] {
            let sorted = items.sorted {
                if abs($0.fill - $1.fill) > 0.02 { return $0.fill > $1.fill }
                return $0.areaCells > $1.areaCells
            }
            var keep: [Strip] = []
            for s in sorted {
                if keep.contains(where: { $0.overlapFraction(with: s) > 0.7 }) { continue }
                keep.append(s)
            }
            return keep
        }

        let hx = dedupe(strips(alongX: true))
        let vz = dedupe(strips(alongX: false))
        return hx + vz
    }

    /// Czy za pasem (po jednej z jego długich krawędzi) stoi pionowa powierzchnia.
    /// Blaty kuchenne przylegają do ściany; stół w środku pokoju nie.
    private static func hasWallBehind(_ strip: Strip, walls: [SIMD2<Float>],
                                      origin: SIMD2<Float>, cell: Float, proximity: Float) -> Bool {
        guard !walls.isEmpty else { return true }   // brak ścian w modelu = nie karzemy
        // wszystko w **indeksach siatki**: krawędź pasa i pozycja ściany
        let tol = proximity / cell + 1
        let edges: [(ClosedRange<Int>, Float)] = strip.alongX
            ? [(strip.colRange, Float(strip.rowRange.lowerBound)),
               (strip.colRange, Float(strip.rowRange.upperBound))]
            : [(strip.rowRange, Float(strip.colRange.lowerBound)),
               (strip.rowRange, Float(strip.colRange.upperBound))]

        for (span, edgeCoord) in edges {
            var hits = 0
            for w in walls {
                // współrzędne siatki: (punkt − początek obwiedni) / bok komórki
                let alongIdx = Int((((strip.alongX ? w.x : w.y) - (strip.alongX ? origin.x : origin.y)) / cell).rounded())
                let acrossIdx = ((strip.alongX ? w.y : w.x) - (strip.alongX ? origin.y : origin.x)) / cell
                guard span.contains(alongIdx) else { continue }
                if abs(acrossIdx - edgeCoord) <= tol { hits += 1 }
            }
            if hits >= max(2, span.count / 20) { return true }
        }
        return false
    }

    // MARK: - Wyspy

    private static func components(mask: inout [Bool], nx: Int, nz: Int) -> [Set<Int>] {
        var result: [Set<Int>] = []
        var visited = [Bool](repeating: false, count: mask.count)
        for start in 0..<mask.count where mask[start] && !visited[start] {
            var comp = Set<Int>()
            var stack = [start]
            visited[start] = true
            while let idx = stack.popLast() {
                comp.insert(idx)
                let r = idx / nx, c = idx % nx
                for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let rr = r + dr, cc = c + dc
                    guard rr >= 0, rr < nz, cc >= 0, cc < nx else { continue }
                    let ni = rr * nx + cc
                    if mask[ni] && !visited[ni] {
                        visited[ni] = true
                        stack.append(ni)
                    }
                }
            }
            if comp.count > 40 { result.append(comp) }
        }
        return result
    }

    // MARK: - Geometria pomocnicza

    private static func rotate(_ p: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle), s = sin(angle)
        return SIMD2(p.x * c - p.y * s, p.x * s + p.y * c)
    }

    /// Orientacja blatu: kąt, przy którym punkty układają się w **proste pasy**
    /// (najostrzejszy histogram rzutów). Obwiednia zawodziła na L-kach
    /// (kwadratowa → 60° zamiast 30°), a krawędzie trójkątów mają przekątne.
    private static func estimateRotation(_ samples: [SIMD2<Float>]) -> Float {
        guard samples.count > 20 else { return 0 }
        let step = max(1, samples.count / 6000)          // do ~6 tys. punktów wystarczy
        let subset = stride(from: 0, to: samples.count, by: step).map { samples[$0] }
        let bin: Float = 0.05                             // 5 cm

        func score(_ angle: Float) -> Float {
            let c = cos(-angle), s = sin(-angle)
            var binsX: [Float: Int] = [:]
            var binsZ: [Float: Int] = [:]
            for p in subset {
                let x = p.x * c - p.y * s
                let z = p.x * s + p.y * c
                binsX[((x / bin).rounded()), default: 0] += 1
                binsZ[((z / bin).rounded()), default: 0] += 1
            }
            var total: Float = 0
            for v in binsX.values { total += Float(v * v) }
            for v in binsZ.values { total += Float(v * v) }
            return total
        }

        var bestAngle: Float = 0
        var bestScore: Float = -1
        var deg: Float = 0
        while deg < 90 {
            let sc = score(deg * .pi / 180)
            if sc > bestScore { bestScore = sc; bestAngle = deg * .pi / 180 }
            deg += 1
        }
        // doprecyzowanie wokół najlepszego kąta
        var fine = bestAngle - .pi / 180
        let limit = bestAngle + .pi / 180
        while fine <= limit {
            let sc = score(fine)
            if sc > bestScore { bestScore = sc; bestAngle = fine }
            fine += .pi / 360
        }
        return bestAngle
    }

    private static func boundingBoxArea(_ pts: [SIMD2<Float>], rotation: Float) -> Float {
        var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var hi = SIMD2<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        let c = cos(rotation), s = sin(rotation)
        for p in pts {
            let x = p.x * c - p.y * s
            let y = p.x * s + p.y * c
            lo = simd_min(lo, SIMD2(x, y))
            hi = simd_max(hi, SIMD2(x, y))
        }
        return (hi.x - lo.x) * (hi.y - lo.y)
    }

    private static func weightedMedian(_ values: [(Float, Float)]) -> Float {
        let sorted = values.sorted { $0.0 < $1.0 }
        let total = sorted.reduce(0) { $0 + $1.1 }
        var acc: Float = 0
        for (v, w) in sorted {
            acc += w
            if acc >= total / 2 { return v }
        }
        return sorted.last?.0 ?? 0
    }

    private static func degrees(_ rad: Float) -> Float { rad * 180 / .pi }

    /// Deterministyczny generator — ten sam skan musi dawać ten sam projekt.
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func nextFloat() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24)
        }
    }
}
