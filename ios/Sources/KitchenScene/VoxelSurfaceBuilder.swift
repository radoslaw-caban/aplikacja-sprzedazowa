import Foundation
import RealityKit
import KitchenCore

/// Alias, żeby warstwa UI nie musiała importować RealityKit (konflikt nazw `Scene`).
public typealias ScanSurface = Entity

/// Powierzchnia ze skanu: wokselizacja chmury i siatka tylko z widocznych ścianek.
///
/// Dlaczego nie „większe punkty": pojedynczy punkt ma 1 px niezależnie od materiału,
/// a rozdmuchiwanie go wymaga shadera. Woksel 4 cm daje czytelną ścianę, podłogę
/// i sufit przy kilkudziesięciu tysiącach trójkątów — i nie zależy od kamerowania.
@MainActor
public enum VoxelSurfaceBuilder {

    public struct Options {
        /// bok woksela w metrach
        public var cell: Float = 0.04
        /// ile bitów na kanał koloru (2 → 64 kubełki materiałów)
        public var colorBits: Int = 2
        public var maxPoints: Int = 200_000
        public init() {}
    }

    public struct Bucket: Sendable {
        public var color: SIMD3<Float>
        public var positions: [SIMD3<Float>]
        public var indices: [UInt32]
    }

    public struct Geometry: Sendable {
        public var buckets: [Bucket]
        public var voxelCount: Int
        public var pickCells: Set<SIMD3<Int32>>
        public var empty: Bool { buckets.isEmpty }
    }

    struct Cell: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }

    /// Encja z gotowej geometrii — jedyne miejsce dotykające RealityKit.
    @MainActor
    public static func makeEntity(_ geometry: Geometry) -> Entity {
        let root = Entity()
        root.name = "scan-surface"
        for (i, bucket) in geometry.buckets.enumerated() {
            guard !bucket.indices.isEmpty, let mesh = try? triangleMesh(bucket.positions, bucket.indices) else { continue }
            var material = PhysicallyBasedMaterial()
            let c = bucket.color / 255
            material.baseColor = .init(tint: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
            material.roughness = .init(floatLiteral: 0.92)
            material.metallic = .init(floatLiteral: 0)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "scan-surface-\(i)"
            root.addChild(entity)
        }
        return root
    }

    /// Wokselizacja — czysta funkcja, można liczyć w tle (bez RealityKit).
    public nonisolated static func geometry(
        _ cloud: PointCloud,
        transform: ScanTransform = ScanTransform(),
        options: Options = Options()
    ) -> Geometry {
        var result = Geometry(buckets: [], voxelCount: 0, pickCells: [])
        let source = cloud.decimated(maxPoints: options.maxPoints)
        guard !source.positions.isEmpty else { return result }

        let toMeters = cloud.unitScaleToMeters
        let cellSize = max(0.01, options.cell)

        // 1) woksele: suma kolorów i liczba punktów
        var sums: [Cell: SIMD3<Float>] = [:]
        var counts: [Cell: Float] = [:]
        sums.reserveCapacity(source.positions.count / 6)
        counts.reserveCapacity(source.positions.count / 6)

        let positions = source.positions
        let colors = source.colors
        var pickCells = Set<SIMD3<Int32>>(minimumCapacity: positions.count / 4)

        for i in 0..<positions.count {
            let p = transform.apply(positions[i] * toMeters)
            let key = Cell(
                x: Int32((p.x / cellSize).rounded(.down)),
                y: Int32((p.y / cellSize).rounded(.down)),
                z: Int32((p.z / cellSize).rounded(.down))
            )
            var c = SIMD3<Float>(200, 200, 200)
            if let colors {
                let cc = colors[i]
                c = SIMD3(Float(cc.x), Float(cc.y), Float(cc.z))
            }
            if var existing = sums[key] {
                sums[key] = existing + c
                counts[key] = (counts[key] ?? 0) + 1
            } else {
                sums[key] = c
                counts[key] = 1
                // siatka do klikania: komórki 5 cm
                pickCells.insert(SIMD3(
                    Int32((p.x / 0.05).rounded(.down)),
                    Int32((p.y / 0.05).rounded(.down)),
                    Int32((p.z / 0.05).rounded(.down))
                ))
            }
        }
        _ = pickCells
        guard !sums.isEmpty else { return result }

        // 2) widoczne ścianki: tylko tam, gdzie sąsiad jest pusty.
        // Bufory per kubełek — bez alokacji tablicy na każdą ściankę i bez
        // wielokrotnego zapisu do słownika (to było 2,5 s z 2,6 s całości).
        let bucketCount = 1 << (options.colorBits * 3)
        var bucketPos = [[SIMD3<Float>]](repeating: [], count: bucketCount)
        var bucketIdx = [[UInt32]](repeating: [], count: bucketCount)
        var bucketSum = [SIMD3<Float>](repeating: .zero, count: bucketCount)
        var bucketN = [Float](repeating: 0, count: bucketCount)

        // szablony ścianek: 4 narożniki (w jednostkach woksela)
        let faceOffsets: [[SIMD3<Float>]] = [
            [SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(1, 1, 1), SIMD3(1, 0, 1)],
            [SIMD3(0, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 1), SIMD3(0, 1, 0)],
            [SIMD3(0, 1, 0), SIMD3(0, 1, 1), SIMD3(1, 1, 1), SIMD3(1, 1, 0)],
            [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1), SIMD3(0, 0, 1)],
            [SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1)],
            [SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0), SIMD3(1, 0, 0)],
        ]
        let neighborOffsets: [SIMD3<Int32>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1),
        ]

        for (cell, sum) in sums {
            let n = counts[cell] ?? 1
            let color = sum / Swift.max(1, n)
            let bucket = quantizedBucket(color, bits: options.colorBits, maxBucket: bucketCount - 1)
            var pos = bucketPos[bucket]
            var idx = bucketIdx[bucket]

            for f in 0..<6 {
                let off = neighborOffsets[f]
                let key = Cell(x: cell.x + off.x, y: cell.y + off.y, z: cell.z + off.z)
                if sums[key] != nil { continue }

                let base = UInt32(pos.count)
                for corner in faceOffsets[f] {
                    pos.append(SIMD3(
                        (Float(cell.x) + corner.x) * cellSize,
                        (Float(cell.y) + corner.y) * cellSize,
                        (Float(cell.z) + corner.z) * cellSize
                    ))
                }
                idx.append(base)
                idx.append(base + 1)
                idx.append(base + 2)
                idx.append(base)
                idx.append(base + 2)
                idx.append(base + 3)
            }

            bucketPos[bucket] = pos
            bucketIdx[bucket] = idx
            bucketSum[bucket] += color
            bucketN[bucket] += 1
        }

        var out: [Bucket] = []
        for b in 0..<bucketCount where !bucketIdx[b].isEmpty {
            let avg = bucketSum[b] / Swift.max(1, bucketN[b])
            out.append(Bucket(color: avg, positions: bucketPos[b], indices: bucketIdx[b]))
        }
        result.buckets = out
        result.voxelCount = sums.count
        result.pickCells = pickCells
        return result
    }

    public nonisolated static func quantizedBucket(_ c: SIMD3<Float>, bits: Int, maxBucket: Int) -> Int {
        let levels = (1 << bits) - 1
        let step = 255 / max(1, levels)
        let r = Int(c.x) / max(1, step)
        let g = Int(c.y) / max(1, step)
        let b = Int(c.z) / max(1, step)
        return Swift.min(maxBucket, r * (1 << (bits * 2)) + g * (1 << bits) + b)
    }

    @MainActor static func triangleMesh(_ positions: [SIMD3<Float>], _ indices: [UInt32]) throws -> MeshResource {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = positions.count
        descriptor.indexCapacity = indices.count
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: GLBLayout.vec3)
        ]

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let bound = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<positions.count { bound[i] = positions[i] }
        }
        mesh.withUnsafeMutableIndices { raw in
            let bound = raw.bindMemory(to: UInt32.self)
            for i in 0..<indices.count { bound[i] = indices[i] }
        }

        var lo = positions[0], hi = positions[0]
        for p in positions {
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexOffset: 0,
                indexCount: indices.count,
                topology: .triangle,
                materialIndex: 0,
                bounds: BoundingBox(min: lo, max: hi)
            )
        ])
        return try MeshResource(from: mesh)
    }
}
