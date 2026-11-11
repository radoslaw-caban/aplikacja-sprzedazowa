import Foundation
import simd

/// Siatka wokseli skanu — do klikania w chmurę (promień → pierwszy trafiony woksel).
///
/// Trzymamy tylko zajęte komórki (Set), więc pamięć jest proporcjonalna do powierzchni,
/// a nie do objętości. Przejście promienia to DDA (Amanatides & Woo) — O(liczba komórek
/// na promieniu), bez skanowania całej siatki.
public struct VoxelGrid: Sendable {
    public let cellSize: Float
    public let cells: Set<SIMD3<Int32>>

    public init(cellSize: Float, cells: Set<SIMD3<Int32>>) {
        self.cellSize = cellSize
        self.cells = cells
    }

    public var isEmpty: Bool { cells.isEmpty }

    /// Buduje siatkę z punktów w metrach (po transformacji).
    public init(points: [SIMD3<Float>], cellSize: Float) {
        var set = Set<SIMD3<Int32>>()
        set.reserveCapacity(points.count / 4)
        for p in points {
            set.insert(SIMD3(
                Int32((p.x / cellSize).rounded(.down)),
                Int32((p.y / cellSize).rounded(.down)),
                Int32((p.z / cellSize).rounded(.down))
            ))
        }
        self.cellSize = cellSize
        self.cells = set
    }

    /// Pierwsze trafienie promienia w zajętą komórkę (metry). Zwraca środek trafionego woksela.
    public func firstHit(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 60) -> SIMD3<Float>? {
        guard !cells.isEmpty else { return nil }
        let dir = normalize(direction)
        guard dir.x.isFinite, dir.y.isFinite, dir.z.isFinite else { return nil }

        let cs = cellSize
        var cell = SIMD3<Int32>(
            Int32((origin.x / cs).rounded(.down)),
            Int32((origin.y / cs).rounded(.down)),
            Int32((origin.z / cs).rounded(.down))
        )

        let step = SIMD3<Int32>(dir.x > 0 ? 1 : -1, dir.y > 0 ? 1 : -1, dir.z > 0 ? 1 : -1)

        func axisT(_ axis: Int) -> Float {
            let (o, d, c, s): (Float, Float, Int32, Int32) = axis == 0
                ? (origin.x, dir.x, cell.x, step.x)
                : (axis == 1 ? (origin.y, dir.y, cell.y, step.y) : (origin.z, dir.z, cell.z, step.z))
            if abs(d) < 1e-9 { return .infinity }
            let cellMin = Float(c) * cs
            let target = s > 0 ? cellMin + cs : cellMin
            return (target - o) / d
        }

        var tMax = SIMD3<Float>(axisT(0), axisT(1), axisT(2))
        let tDelta = SIMD3<Float>(
            abs(dir.x) < 1e-9 ? .infinity : abs(cs / dir.x),
            abs(dir.y) < 1e-9 ? .infinity : abs(cs / dir.y),
            abs(dir.z) < 1e-9 ? .infinity : abs(cs / dir.z)
        )

        var travelled: Float = 0
        while travelled <= maxDistance {
            if cells.contains(cell) {
                return SIMD3(
                    (Float(cell.x) + 0.5) * cs,
                    (Float(cell.y) + 0.5) * cs,
                    (Float(cell.z) + 0.5) * cs
                )
            }
            // krok w osi o najmniejszym tMax
            var t = Swift.min(tMax.x, Swift.min(tMax.y, tMax.z))
            guard t.isFinite else { break }
            // start dokładnie na granicy komórki daje t = 0 — to nie koniec promienia
            if t <= 0 { t = 1e-6 }
            travelled = t
            if tMax.x <= tMax.y && tMax.x <= tMax.z {
                cell.x += step.x
                tMax.x += tDelta.x
            } else if tMax.y <= tMax.z {
                cell.y += step.y
                tMax.y += tDelta.y
            } else {
                cell.z += step.z
                tMax.z += tDelta.z
            }
        }
        return nil
    }

    /// Promień z kamery przez punkt ekranu (współrzędne znormalizowane 0…1).
    public static func ray(
        cameraPosition: SIMD3<Float>,
        lookAt target: SIMD3<Float>,
        verticalFOVDegrees: Float,
        aspect: Float,
        normalizedPoint p: CGPoint
    ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let forward = normalize(target - cameraPosition)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = cross(forward, worldUp)
        if length(right) < 1e-5 { right = SIMD3(1, 0, 0) }
        right = normalize(right)
        let up = normalize(cross(right, forward))

        let tanHalf = tan(verticalFOVDegrees * .pi / 180 / 2)
        let ndcX = (Float(p.x) * 2 - 1) * tanHalf * aspect
        let ndcY = (1 - Float(p.y) * 2) * tanHalf
        let direction = normalize(forward + right * ndcX + up * ndcY)
        return (cameraPosition, direction)
    }
}
