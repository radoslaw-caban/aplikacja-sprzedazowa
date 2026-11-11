import Foundation
import simd

/// Dopasowanie skanu do pokoju na podstawie geometrii, nie obrysu:
/// znajduje płaszczyznę podłogi i dwie prostopadłe ściany, a potem liczy
/// transformację, która stawia je w układzie projektu.
///
/// Dlaczego nie obrys: w realnym skanie obrys wyznaczają meble i rzeczy poza
/// pomieszczeniem — bounding box kłamie. Ściany to najgęstsze, cienkie skupiska
/// punktów w rzucie, a podłoga to najgęstsza pozioma warstwa.
public enum ScanFit {

    public struct Result: Sendable {
        /// wysokość podłogi w układzie chmury (metry)
        public var floorY: Float
        /// obrót, po którym ściany są równoległe do osi (stopnie)
        public var wallAngleDeg: Double
        /// przesunięcie ściany nr 1 (wzdłuż normalnej, po obrocie) — do wyrównania
        public var wall1Offset: Float
        /// przesunięcie ściany nr 2
        public var wall2Offset: Float
        /// udział punktów przy podłodze (0…1) — miara pewności
        public var floorCoverage: Float
        /// gęstość najlepszej ściany (punkty na metr bieżący) — miara pewności
        public var wallStrength: Float
        public var isValid: Bool { floorCoverage > 0.02 && wallStrength > 20 }
        /// Podłoga wystarcza do ustawienia poziomu i obrotu (ściany są WIP).
        public var hasFloor: Bool { floorCoverage > 0.004 }
    }

    /// Wykrycie podłogi i ścian. Punkty w metrach, w układzie chmury.
    public static func detect(points: [SIMD3<Float>], bin: Float = 0.04) -> Result {
        guard points.count > 500 else {
            return Result(floorY: 0, wallAngleDeg: 0, wall1Offset: 0, wall2Offset: 0, floorCoverage: 0, wallStrength: 0)
        }

        // --- 1) podłoga: najgęstsza warstwa w dolnych 45% wysokości ---
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for p in points {
            minY = Swift.min(minY, p.y)
            maxY = Swift.max(maxY, p.y)
        }
        let height = Swift.max(0.1, maxY - minY)
        let floorBins = Int(height / bin) + 2
        var yHist = [Int](repeating: 0, count: floorBins)
        for p in points {
            let i = Int((p.y - minY) / bin)
            if i >= 0 && i < floorBins { yHist[i] += 1 }
        }
        let searchLimit = Int(Float(floorBins) * 0.45)
        var bestBin = 0
        var bestCount = 0
        for i in 0..<Swift.max(1, searchLimit) where yHist[i] > bestCount {
            bestCount = yHist[i]
            bestBin = i
        }
        let floorY = minY + (Float(bestBin) + 0.5) * bin
        // pokrycie: punkty w pasie ±5 cm od podłogi
        var nearFloor = 0
        for p in points where abs(p.y - floorY) < 0.05 { nearFloor += 1 }
        let floorCoverage = Float(nearFloor) / Float(points.count)

        // --- 2) ściany: dla wielu kątów liczymy histogram rzutu na normalną ---
        var bestAngle: Double = 0
        var bestScore: Float = 0
        var bestPeaks: (Float, Float) = (0, 0)
        var bestStrength: Float = 0

        let span = Swift.max(2.0, horizontalSpan(points))
        let histBins = Int(span / bin) + 4

        for step in 0..<36 {                       // co 5°
            let angle = Double(step) * 5.0 * .pi / 180
            let nx = Float(cos(angle)), nz = Float(sin(angle))

            var hist = [Int](repeating: 0, count: histBins)
            var minProj = Float.greatestFiniteMagnitude
            var projValues = [Float]()
            projValues.reserveCapacity(points.count)
            for p in points {
                let proj = p.x * nx + p.z * nz
                projValues.append(proj)
                minProj = Swift.min(minProj, proj)
            }
            for v in projValues {
                let i = Int((v - minProj) / bin)
                if i >= 0 && i < histBins { hist[i] += 1 }
            }

            // dwie najgęstsze, odległe od siebie warstwy = dwie ściany
            var first = 0, second = 0, firstIdx = 0, secondIdx = 0
            for i in 0..<histBins {
                if hist[i] > first {
                    second = first; secondIdx = firstIdx
                    first = hist[i]; firstIdx = i
                } else if hist[i] > second {
                    second = hist[i]; secondIdx = i
                }
            }
            // ściany muszą być oddalone o co najmniej 1 m
            let separation = Float(abs(firstIdx - secondIdx)) * bin
            guard separation > 1.0 else { continue }

            // ocena: suma obu szczytów, karana za „grubość" (rozrzut wokół piku)
            let score = Float(first + second)
            if score > bestScore {
                bestScore = score
                bestAngle = Double(step) * 5.0
                bestPeaks = (
                    minProj + (Float(firstIdx) + 0.5) * bin,
                    minProj + (Float(secondIdx) + 0.5) * bin
                )
                bestStrength = Float(first + second) / Swift.max(1, span)
            }
        }

        // --- 2a) korekta kąta z PCA punktów ścian (jeśli się udało) ---
        if let pcaAngle = wallAnglePCA(points: points, floorY: floorY) {
            // histogram zwracał kąt normalnej; PCA zwraca kierunek ściany (90° różnicy)
            var cand = pcaAngle.truncatingRemainder(dividingBy: 90)
            if cand < 0 { cand += 90 }
            var best = bestAngle.truncatingRemainder(dividingBy: 90)
            if best < 0 { best += 90 }
            let diff = abs(cand - best)
            if Swift.min(diff, 90 - diff) < 20 {
                bestAngle = bestAngle + (cand - best)
            }
        }

        // --- 2b) doprecyzowanie kąta: przeszukanie ±5° co 0,5° ---
        var fineAngle = bestAngle
        var fineScore: Float = bestScore
        var finePeaks = bestPeaks
        if bestScore > 0 {
            var candidate = bestAngle - 5
            while candidate <= bestAngle + 5 {
                let angle = candidate * .pi / 180
                let nx = Float(cos(angle)), nz = Float(sin(angle))
                var hist = [Int](repeating: 0, count: histBins)
                var minProj = Float.greatestFiniteMagnitude
                for p in points {
                    let proj = p.x * nx + p.z * nz
                    minProj = Swift.min(minProj, proj)
                }
                for p in points {
                    let i = Int((p.x * nx + p.z * nz - minProj) / bin)
                    if i >= 0 && i < histBins { hist[i] += 1 }
                }
                var first = 0, second = 0, firstIdx = 0, secondIdx = 0
                for i in 0..<histBins {
                    if hist[i] > first {
                        second = first; secondIdx = firstIdx
                        first = hist[i]; firstIdx = i
                    } else if hist[i] > second {
                        second = hist[i]; secondIdx = i
                    }
                }
                let separation = Float(abs(firstIdx - secondIdx)) * bin
                if separation > 1.0 && Float(first + second) > fineScore {
                    fineScore = Float(first + second)
                    fineAngle = candidate
                    finePeaks = (
                        minProj + (Float(firstIdx) + 0.5) * bin,
                        minProj + (Float(secondIdx) + 0.5) * bin
                    )
                }
                candidate += 0.5
            }
        }

        return Result(
            floorY: floorY,
            wallAngleDeg: fineAngle,
            wall1Offset: finePeaks.0,
            wall2Offset: finePeaks.1,
            floorCoverage: floorCoverage,
            wallStrength: bestStrength
        )
    }

    /// Transformacja ustawiająca wykryte ściany w pokoju.
    /// Po obrocie o -kąt mierzymy empirycznie, gdzie wypadają ściany,
    /// i przesuwamy chmurę tak, żeby stały na x = -W/2 i z = -D/2, a podłoga na 0.
    public static func align(
        points: [SIMD3<Float>],
        result: Result,
        room: Room,
        currentScale: Double
    ) -> ScanTransform {
        let a = -result.wallAngleDeg * .pi / 180
        let c = cos(a), s = sin(a)

        // rzuty po obrocie (bez skali i przesunięcia)
        var xs: [Float] = []
        var zs: [Float] = []
        xs.reserveCapacity(points.count)
        zs.reserveCapacity(points.count)
        for p in points {
            let x = Double(p.x)
            let z = Double(p.z)
            xs.append(Float(x * c + z * s))
            zs.append(Float(-x * s + z * c))
        }

        let wallX = dominantBin(xs, bin: 0.04)
        let wallZ = dominantBin(zs, bin: 0.04)

        let roomW = Double(room.width) / 1000
        let roomD = Double(room.depth) / 1000
        let halfW = roomW / 2
        let halfD = roomD / 2

        let offsetX = -halfW - Double(wallX) * currentScale
        let offsetZ = -halfD - Double(wallZ) * currentScale
        let offsetY = -Double(result.floorY) * currentScale

        return ScanTransform(
            scale: currentScale,
            rotationDeg: -result.wallAngleDeg,
            offset: SIMD3(offsetX, offsetY, offsetZ)
        )
    }

    /// Kąt ścian z PCA punktów w pasie wysokości ścian (od podłogi +30 cm do +230 cm).
    /// Ściany tworzą dwie prostopadłe linie w rzucie — dominująca wariancja daje kierunek.
    public static func wallAnglePCA(points: [SIMD3<Float>], floorY: Float) -> Double? {
        var sx: Double = 0, sz: Double = 0, n: Double = 0
        for p in points where p.y > floorY + 0.3 && p.y < floorY + 2.3 {
            sx += Double(p.x); sz += Double(p.z); n += 1
        }
        guard n > 500 else { return nil }
        let mx = sx / n, mz = sz / n

        var cxx: Double = 0, cxz: Double = 0, czz: Double = 0
        for p in points where p.y > floorY + 0.3 && p.y < floorY + 2.3 {
            let dx = Double(p.x) - mx
            let dz = Double(p.z) - mz
            cxx += dx * dx
            cxz += dx * dz
            czz += dz * dz
        }
        cxx /= n; cxz /= n; czz /= n

        // wektor własny większej wartości własnej macierzy 2×2
        let trace = cxx + czz
        let det = cxx * czz - cxz * cxz
        let lambda = trace / 2 + ((trace * trace / 4 - det) > 0 ? (trace * trace / 4 - det).squareRoot() : 0)
        var vx = cxz, vz = lambda - cxx
        if abs(vx) < 1e-9 && abs(vz) < 1e-9 { vx = lambda - czz; vz = cxz }
        let len = (vx * vx + vz * vz).squareRoot()
        guard len > 1e-9 else { return nil }
        let angle = atan2(vz / len, vx / len) * 180 / .pi
        return angle
    }

    /// Orientacja pomieszczenia z obrysu podłogi: szukamy kąta, przy którym
    /// prostokąt opisujący punkty podłogi ma najmniejsze pole (rotating calipers).
    /// To działa dla pokoi prostokątnych niezależnie od gęstości ścian.
    public static func floorOrientation(points: [SIMD3<Float>], floorY: Float, band: Float = 0.06) -> Double? {
        var floor: [SIMD2<Float>] = []
        floor.reserveCapacity(points.count / 4)
        for p in points where abs(p.y - floorY) < band {
            floor.append(SIMD2(p.x, p.z))
        }
        guard floor.count > 200 else { return nil }

        // krok 0,5° po pełnym obrocie; szukamy minimalnego pola prostokąta
        var bestAngle: Double = 0
        var bestArea = Float.greatestFiniteMagnitude
        var angle: Double = 0
        while angle < 90 {
            let a = angle * .pi / 180
            let c = Float(cos(a)), s = Float(sin(a))
            var minU = Float.greatestFiniteMagnitude, maxU = -Float.greatestFiniteMagnitude
            var minV = Float.greatestFiniteMagnitude, maxV = -Float.greatestFiniteMagnitude
            for p in floor {
                let u = p.x * c + p.y * s
                let v = -p.x * s + p.y * c
                minU = Swift.min(minU, u); maxU = Swift.max(maxU, u)
                minV = Swift.min(minV, v); maxV = Swift.max(maxV, v)
            }
            let area = (maxU - minU) * (maxV - minV)
            if area < bestArea {
                bestArea = area
                bestAngle = angle
            }
            angle += 0.5
        }
        return bestAngle
    }

    /// Pewna część dopasowania: podłoga na y = 0 i środek chmury nad środkiem pokoju.
    /// Obrót ścian robi użytkownik narzędziem dwupunktowym (sprawdzone).
    public static func alignFloorOnly(
        points: [SIMD3<Float>],
        result: Result,
        room: Room,
        currentScale: Double
    ) -> ScanTransform {
        let angle = floorOrientation(points: points, floorY: result.floorY) ?? 0

        // po obrocie wyśrodkuj obrys podłogi na środku pokoju
        // (ta sama konwencja co ScanTransform.apply)
        let a = angle * .pi / 180
        let c = Float(cos(a)), s = Float(sin(a))
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for p in points where abs(p.y - result.floorY) < 0.06 {
            let x = p.x * c + p.z * s
            let z = -p.x * s + p.z * c
            minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
            minZ = Swift.min(minZ, z); maxZ = Swift.max(maxZ, z)
        }
        let cx = (minX + maxX) / 2
        let cz = (minZ + maxZ) / 2

        return ScanTransform(
            scale: currentScale,
            rotationDeg: angle,
            offset: SIMD3(
                -Double(cx) * currentScale,
                -Double(result.floorY) * currentScale,
                -Double(cz) * currentScale
            )
        )
    }

    /// Najgęstsza warstwa w rozkładzie wartości (ściana).
    static func dominantBin(_ values: [Float], bin: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in values {
            lo = Swift.min(lo, v)
            hi = Swift.max(hi, v)
        }
        let bins = Int((hi - lo) / bin) + 2
        guard bins > 0, bins < 2_000_000 else { return 0 }
        var hist = [Int](repeating: 0, count: bins)
        for v in values {
            let i = Int((v - lo) / bin)
            if i >= 0 && i < bins { hist[i] += 1 }
        }
        var bestIdx = 0, best = 0
        for i in 0..<bins where hist[i] > best {
            best = hist[i]
            bestIdx = i
        }
        return lo + (Float(bestIdx) + 0.5) * bin
    }

    private static func horizontalSpan(_ points: [SIMD3<Float>]) -> Float {
        var lo = points[0], hi = points[0]
        for p in points {
            lo = SIMD3(Swift.min(lo.x, p.x), 0, Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), 0, Swift.max(hi.z, p.z))
        }
        return Swift.max(hi.x - lo.x, hi.z - lo.z)
    }
}
