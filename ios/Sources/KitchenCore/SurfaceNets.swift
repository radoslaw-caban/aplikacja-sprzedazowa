import Foundation
import simd

/// Gładka powierzchnia skanu z chmury punktów — algorytm surface nets
/// (odmiana dual contouring bez dużych tablic przypadków).
///
/// Chmura → pole gęstości na siatce → izopowierzchnia → siatka z normalnymi.
/// W przeciwieństwie do wokselizacji nie daje schodków: wierzchołki siatki
/// siedzą w środkach komórek, a łączone są krawędziami pola.
public enum SurfaceNets {

    public struct Options: Sendable {
        /// bok komórki siatki (m); 0.03 = 3 cm
        public var cell: Float = 0.03
        /// wygładzenie pola: liczba przebiegów blura 3×3×3
        public var smoothingPasses: Int = 1
        /// ile punktów bierzemy (decymacja przed liczeniem)
        public var maxPoints: Int = 200_000
        /// próg izopowierzchni (0…1)
        public var isoLevel: Float = 0.35
        /// obrys bez punktów odstających; nil = z wszystkich punktów
        public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
        public init() {}
    }

    public struct Mesh: Sendable {
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        /// kolor wierzchołka (0…255) uśredniony z punktów w komórce
        public var colors: [SIMD3<Float>]
        public var indices: [UInt32]
        public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
        public var isEmpty: Bool { indices.isEmpty }
    }

    /// Siatka z chmury punktów (w metrach, po transformacji).
    public static func build(
        points source: [SIMD3<Float>],
        colors sourceColors: [SIMD3<UInt8>]? = nil,
        options: Options = Options()
    ) -> Mesh {
        let empty = Mesh(positions: [], normals: [], colors: [], indices: [], bounds: (.zero, .zero))
        guard source.count > 32 else { return empty }

        var cell = max(0.01, options.cell)

        // 1) zakres siatki — z odpornego obrysu, jeśli podany (bez punktów odstających)
        var lo: SIMD3<Float>
        var hi: SIMD3<Float>
        if let b = options.bounds {
            lo = b.min
            hi = b.max
        } else {
            lo = source[0]
            hi = source[0]
            for p in source {
                lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
        }
        // dobór komórki: siatka nie może przekroczyć limitu pamięci
        let maxCells = 24_000_000
        let spanX = hi.x - lo.x, spanY = hi.y - lo.y, spanZ = hi.z - lo.z
        while Int((spanX / cell) + 3) * Int((spanY / cell) + 3) * Int((spanZ / cell) + 3) > maxCells {
            cell *= 1.25
        }

        let origin = SIMD3<Float>(
            (lo.x / cell).rounded(.down) * cell - cell,
            (lo.y / cell).rounded(.down) * cell - cell,
            (lo.z / cell).rounded(.down) * cell - cell
        )
        let dims = SIMD3<Int32>(
            Int32((hi.x - origin.x) / cell) + 3,
            Int32((hi.y - origin.y) / cell) + 3,
            Int32((hi.z - origin.z) / cell) + 3
        )
        guard dims.x > 3, dims.y > 3, dims.z > 3 else { return empty }
        let total = Int(dims.x) * Int(dims.y) * Int(dims.z)
        guard total < 40_000_000 else { return empty } // zabezpieczenie pamięci

        // 2) pole gęstości: punkty rozłożone w komórkach (z rozmyciem na sąsiadów)
        var field = [Float](repeating: 0, count: total)
        var colorSum = [SIMD3<Float>](repeating: .zero, count: total)
        var colorN = [Float](repeating: 0, count: total)
        func index(_ x: Int32, _ y: Int32, _ z: Int32) -> Int {
            Int(x) + Int(dims.x) * (Int(y) + Int(dims.y) * Int(z))
        }

        for (pointIndex, p) in source.enumerated() {
            let fx = (p.x - origin.x) / cell
            let fy = (p.y - origin.y) / cell
            let fz = (p.z - origin.z) / cell
            guard fx >= 0, fy >= 0, fz >= 0 else { continue }
            let cx = Int32(fx), cy = Int32(fy), cz = Int32(fz)
            guard cx < dims.x, cy < dims.y, cz < dims.z else { continue }
            // rozkład trójliniowy = naturalne wygładzenie bez osobnego blura
            let tx = fx - Float(cx), ty = fy - Float(cy), tz = fz - Float(cz)
            for dz in 0...1 {
                let wz = dz == 0 ? 1 - tz : tz
                guard cz + Int32(dz) < dims.z else { continue }
                for dy in 0...1 {
                    let wy = dy == 0 ? 1 - ty : ty
                    guard cy + Int32(dy) < dims.y else { continue }
                    for dx in 0...1 {
                        let wx = dx == 0 ? 1 - tx : tx
                        guard cx + Int32(dx) < dims.x else { continue }
                        let ii = index(cx + Int32(dx), cy + Int32(dy), cz + Int32(dz))
                        field[ii] += wx * wy * wz
                        if let sourceColors, pointIndex < sourceColors.count {
                            let c = sourceColors[pointIndex]
                            colorSum[ii] += SIMD3(Float(c.x), Float(c.y), Float(c.z))
                            colorN[ii] += 1
                        }
                    }
                }
            }
        }

        // 3) dodatkowe wygładzenie pola (opcjonalne)
        if options.smoothingPasses > 0 {
            var tmp = field
            for _ in 0..<options.smoothingPasses {
                for z in 1..<(Int(dims.z) - 1) {
                    for y in 1..<(Int(dims.y) - 1) {
                        for x in 1..<(Int(dims.x) - 1) {
                            let i = index(Int32(x), Int32(y), Int32(z))
                            var sum: Float = 0
                            for dz in -1...1 {
                                for dy in -1...1 {
                                    for dx in -1...1 {
                                        sum += field[index(Int32(x + dx), Int32(y + dy), Int32(z + dz))]
                                    }
                                }
                            }
                            tmp[i] = sum / 27
                        }
                    }
                }
                swap(&field, &tmp)
            }
        }

        // 3b) normalizacja pola do 0…1 — próg izo nie może zależeć od gęstości chmury
        // Próbka niezerowych wartości → 90. percentyl jako odniesienie.
        // Max brać nie można: jeden gęsty hot-spot zaniża całą powierzchnię.
        var sample: [Float] = []
        let stride = Swift.max(1, field.count / 120_000)
        var cursor = 0
        while cursor < field.count {
            let v = field[cursor]
            if v > 1e-6 { sample.append(v) }
            cursor += stride
        }
        if !sample.isEmpty {
            sample.sort()
            let ref = sample[Int(Double(sample.count - 1) * 0.90)]
            if ref > 1e-6 {
                let inv = 1 / ref
                for k in 0..<field.count { field[k] *= inv }
            }
        }

        // 4) surface nets: jeden wierzchołek na komórkę z przejściem przez izopoziom
        let iso = options.isoLevel
        var cellVertex = [Int32](repeating: -1, count: total)
        var positions: [SIMD3<Float>] = []
        var vertexColors: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let cubeCorners: [SIMD3<Int32>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0),
            SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(0, 1, 1), SIMD3(1, 1, 1),
        ]
        let cubeEdges: [(Int, Int)] = [
            (0, 1), (2, 3), (4, 5), (6, 7),
            (0, 2), (1, 3), (4, 6), (5, 7),
            (0, 4), (1, 5), (2, 6), (3, 7),
        ]

        for z in 0..<(Int(dims.z) - 1) {
            for y in 0..<(Int(dims.y) - 1) {
                for x in 0..<(Int(dims.x) - 1) {
                    var cornerValues = [Float](repeating: 0, count: 8)
                    var inside = 0
                    for (c, off) in cubeCorners.enumerated() {
                        let v = field[index(Int32(x) + off.x, Int32(y) + off.y, Int32(z) + off.z)]
                        cornerValues[c] = v
                        if v >= iso { inside += 1 }
                    }
                    guard inside > 0 && inside < 8 else { continue }

                    // pozycja wierzchołka: średnia przecięć krawędzi
                    var sum = SIMD3<Float>.zero
                    var n: Float = 0
                    for (a, b) in cubeEdges {
                        let va = cornerValues[a], vb = cornerValues[b]
                        if (va >= iso) == (vb >= iso) { continue }
                        let t = (iso - va) / (vb - va)
                        let pa = SIMD3<Float>(Float(cubeCorners[a].x), Float(cubeCorners[a].y), Float(cubeCorners[a].z))
                        let pb = SIMD3<Float>(Float(cubeCorners[b].x), Float(cubeCorners[b].y), Float(cubeCorners[b].z))
                        sum += pa + (pb - pa) * t
                        n += 1
                    }
                    guard n > 0 else { continue }
                    let local = sum / n
                    let world = origin + SIMD3(
                        (Float(x) + local.x) * cell,
                        (Float(y) + local.y) * cell,
                        (Float(z) + local.z) * cell
                    )
                    let ii = index(Int32(x), Int32(y), Int32(z))
                    cellVertex[ii] = Int32(positions.count)
                    positions.append(world)
                    if colorN[ii] > 0 {
                        vertexColors.append(colorSum[ii] / colorN[ii])
                    } else {
                        vertexColors.append(SIMD3(190, 190, 185))
                    }
                }
            }
        }
        guard positions.count > 3 else { return empty }

        // 5) połącz wierzchołki sąsiednich komórek w quady (po krawędziach pola)
        func vertex(_ x: Int, _ y: Int, _ z: Int) -> UInt32? {
            guard x >= 0, y >= 0, z >= 0, x < Int(dims.x), y < Int(dims.y), z < Int(dims.z) else { return nil }
            let v = cellVertex[index(Int32(x), Int32(y), Int32(z))]
            return v >= 0 ? UInt32(v) : nil
        }

        for z in 0..<(Int(dims.z) - 1) {
            for y in 0..<(Int(dims.y) - 1) {
                for x in 0..<(Int(dims.x) - 1) {
                    let here = field[index(Int32(x), Int32(y), Int32(z))] >= iso
                    // krawędź w X
                    if here != (field[index(Int32(x + 1), Int32(y), Int32(z))] >= iso) {
                        if let a = vertex(x, y - 1, z - 1), let b = vertex(x, y, z - 1),
                           let c = vertex(x, y, z), let d = vertex(x, y - 1, z) {
                            appendQuad(&indices, a, b, c, d, here)
                        }
                    }
                    // krawędź w Y
                    if here != (field[index(Int32(x), Int32(y + 1), Int32(z))] >= iso) {
                        if let a = vertex(x - 1, y, z - 1), let b = vertex(x, y, z - 1),
                           let c = vertex(x, y, z), let d = vertex(x - 1, y, z) {
                            appendQuad(&indices, a, b, c, d, here)
                        }
                    }
                    // krawędź w Z
                    if here != (field[index(Int32(x), Int32(y), Int32(z + 1))] >= iso) {
                        if let a = vertex(x - 1, y - 1, z), let b = vertex(x, y - 1, z),
                           let c = vertex(x, y, z), let d = vertex(x - 1, y, z) {
                            appendQuad(&indices, a, b, c, d, here)
                        }
                    }
                }
            }
        }
        guard !indices.isEmpty else { return empty }

        orientConsistently(&indices)

        // 6) normalne: średnia z trójkątów
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            let n = cross(positions[ib] - positions[ia], positions[ic] - positions[ia])
            normals[ia] += n
            normals[ib] += n
            normals[ic] += n
            i += 3
        }
        for k in 0..<normals.count {
            let len = length(normals[k])
            normals[k] = len > 1e-9 ? normals[k] / len : SIMD3(0, 1, 0)
        }

        var mn = positions[0], mx = positions[0]
        for p in positions {
            mn = SIMD3(Swift.min(mn.x, p.x), Swift.min(mn.y, p.y), Swift.min(mn.z, p.z))
            mx = SIMD3(Swift.max(mx.x, p.x), Swift.max(mx.y, p.y), Swift.max(mx.z, p.z))
        }
        return Mesh(positions: positions, normals: normals, colors: vertexColors, indices: indices, bounds: (mn, mx))
    }

    /// Spójna orientacja trójkątów: BFS po sąsiedztwie przez wspólne krawędzie.
    /// Dwa trójkąty dzielące krawędź muszą przechodzić ją w przeciwnych kierunkach —
    /// to usuwa pomieszane nawijanie między osiami siatki.
    static func orientConsistently(_ indices: inout [UInt32]) {
        let triangleCount = indices.count / 3
        guard triangleCount > 1 else { return }

        func edgeKeys(_ t: Int) -> [(UInt32, UInt32, Bool)] {
            let a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2]
            return [(a, b, a < b), (b, c, b < c), (c, a, c < a)]
        }

        // krawędź (min,max) → trójkąty
        var edgeToTriangles: [UInt64: [Int]] = [:]
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = UInt64(Swift.min(a, b)), hi = UInt64(Swift.max(a, b))
            return lo << 32 | hi
        }
        for t in 0..<triangleCount {
            for (a, b, _) in edgeKeys(t) {
                edgeToTriangles[key(a, b), default: []].append(t)
            }
        }

        var visited = [Bool](repeating: false, count: triangleCount)
        var queue = [0]
        visited[0] = true

        func traverse(_ t: Int, _ a: UInt32, _ b: UInt32) -> (UInt32, UInt32) {
            // kierunek krawędzi (a→b) w trójkącie t
            let x = indices[t * 3], y = indices[t * 3 + 1], z = indices[t * 3 + 2]
            if (x == a && y == b) || (y == a && z == b) || (z == a && x == b) { return (a, b) }
            return (b, a)
        }

        while let t = queue.popLast() {
            for (a, b, _) in edgeKeys(t) {
                guard let neighbors = edgeToTriangles[key(a, b)] else { continue }
                for n in neighbors where n != t && !visited[n] {
                    // orientacja krawędzi w sąsiedzie
                    let (na, nb) = traverse(n, a, b)
                    let (ta, tb) = traverse(t, a, b)
                    if na == ta && nb == tb {
                        // ta sama orientacja → odwróć sąsiada
                        indices.swapAt(n * 3 + 1, n * 3 + 2)
                    }
                    visited[n] = true
                    queue.append(n)
                }
            }
        }
    }

    /// Dwie trójkąty z czworokąta, z orientacją zależną od strony przejścia.
    private static func appendQuad(_ indices: inout [UInt32], _ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ flip: Bool) {
        if flip {
            indices.append(contentsOf: [a, b, c, a, c, d])
        } else {
            indices.append(contentsOf: [a, c, b, a, d, c])
        }
    }
}
