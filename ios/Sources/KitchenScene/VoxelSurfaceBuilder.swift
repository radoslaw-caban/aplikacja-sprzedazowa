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
        public var cell: Float = 0.025
        /// ile bitów na kanał koloru (2 → 64 kubełki materiałów)
        public var colorBits: Int = 2
        public var maxPoints: Int = 600_000
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
        var result = Geometry(buckets: [], voxelCount: 0)
        let source = cloud.decimated(maxPoints: options.maxPoints)
        guard !source.positions.isEmpty else { return result }

        let toMeters = cloud.unitScaleToMeters
        let cellSize = max(0.01, options.cell)

        // 1) woksele: suma kolorów i liczba punktów
        var sums: [Cell: SIMD3<Float>] = [:]
        var counts: [Cell: Float] = [:]
        sums.reserveCapacity(source.positions.count / 6)
        counts.reserveCapacity(source.positions.count / 6)

        for (i, raw) in source.positions.enumerated() {
            let p = transform.apply(raw * toMeters)
            let key = Cell(
                x: Int32(floor(p.x / cellSize)),
                y: Int32(floor(p.y / cellSize)),
                z: Int32(floor(p.z / cellSize))
            )
            let c = source.colors.map { SIMD3(Float($0[i].x), Float($0[i].y), Float($0[i].z)) } ?? SIMD3(200, 200, 200)
            sums[key, default: .zero] += c
            counts[key, default: 0] += 1
        }
        guard !sums.isEmpty else { return result }

        // 2) widoczne ścianki: tylko tam, gdzie sąsiad jest pusty
        let maxBucket = (1 << (options.colorBits * 3)) - 1
        var buckets: [Int: (pos: [SIMD3<Float>], idx: [UInt32], sum: SIMD3<Float>, n: Float)] = [:]

        // szablony ścianek: (normalna, 4 narożniki)
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3(1, 0, 0), [SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(1, 1, 1), SIMD3(1, 0, 1)]),
            (SIMD3(-1, 0, 0), [SIMD3(0, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 1), SIMD3(0, 1, 0)]),
            (SIMD3(0, 1, 0), [SIMD3(0, 1, 0), SIMD3(0, 1, 1), SIMD3(1, 1, 1), SIMD3(1, 1, 0)]),
            (SIMD3(0, -1, 0), [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1), SIMD3(0, 0, 1)]),
            (SIMD3(0, 0, 1), [SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1)]),
            (SIMD3(0, 0, -1), [SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0), SIMD3(1, 0, 0)]),
        ]

        for (cell, sum) in sums {
            let n = counts[cell] ?? 1
            let color = sum / max(1, n)
            let bucket = quantizedBucket(color, bits: options.colorBits, maxBucket: maxBucket)
            var entry = buckets[bucket] ?? ([], [], .zero, 0)

            for (normal, corners) in faces {
                let neighbor = Cell(x: cell.x + Int32(normal.x), y: cell.y + Int32(normal.y), z: cell.z + Int32(normal.z))
                if sums[neighbor] != nil { continue } // sąsiad zajęty → ścianka niewidoczna

                let base = UInt32(entry.pos.count)
                for corner in corners {
                    let v = SIMD3(
                        (Float(cell.x) + corner.x) * cellSize,
                        (Float(cell.y) + corner.y) * cellSize,
                        (Float(cell.z) + corner.z) * cellSize
                    )
                    entry.pos.append(v)
                }
                entry.idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }

            if !entry.pos.isEmpty {
                entry.sum += color * Float(entry.pos.count)
                entry.n += Float(entry.pos.count)
                buckets[bucket] = entry
            }
        }

        var out: [Bucket] = []
        for (_, entry) in buckets where !entry.idx.isEmpty {
            let avg = entry.sum / max(1, entry.n)
            out.append(Bucket(color: avg, positions: entry.pos, indices: entry.idx))
        }
        result.buckets = out
        result.voxelCount = sums.count
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
            .init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)
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
