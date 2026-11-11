import Foundation
import RealityKit
import KitchenCore

#if os(iOS)
import UIKit
#endif

/// Render chmury punktów w RealityKit.
///
/// Punkty idą do jednej siatki „point" (LowLevelMesh), ale kolor musi być
/// rozbity na pasma wysokości — RealityKit nie czyta koloru wierzchołka
/// w materiałach wbudowanych, więc dzielimy chmurę na N poziomów i każdy
/// dostaje własny materiał. Przy 500 tys. punktów to 8 encji, nie 500 tys.
@MainActor
public enum PointCloudRenderer {

    public struct Options {
        public var maxPoints: Int = 400_000
        public var bands: Int = 8
        public var pointScale: Float = 1.0
        public init() {}
    }

    /// Encja z chmurą, wyśrodkowana na własnym obrysie i ustawiona na podłodze.
    public static func makeEntity(
        _ source: PointCloud,
        transform: ScanTransform = ScanTransform(),
        options: Options = Options()
    ) -> ModelEntity {
        let cloud = source.decimated(maxPoints: options.maxPoints)
        let root = ModelEntity()
        root.name = "point-cloud"

        guard !cloud.positions.isEmpty else { return root }

        // centrowanie: X/Z na środku, Y od podłogi
        let b = cloud.robustBounds()
        let center = SIMD3<Float>((b.min.x + b.max.x) / 2, b.min.y, (b.min.z + b.max.z) / 2)
        let toMeters = cloud.unitScaleToMeters
        let height = max(0.001, (b.max.y - b.min.y) * toMeters)

        // Kolor: jeśli skan ma RGB, grupujemy punkty po kolorze (64 kubełki),
        // bo RealityKit nie czyta koloru wierzchołka w materiałach wbudowanych.
        // Bez RGB — pasma wysokości.
        if let colors = cloud.colors, colors.count == cloud.positions.count {
            var buckets = Array(repeating: [SIMD3<Float>](), count: 64)
            var sums = Array(repeating: SIMD3<Float>(0, 0, 0), count: 64)
            for (i, p) in cloud.positions.enumerated() {
                let c = colors[i]
                let key = Int(c.x >> 6) * 16 + Int(c.y >> 6) * 4 + Int(c.z >> 6)
                buckets[key].append(transform.apply(p * toMeters))
                sums[key] += SIMD3(Float(c.x), Float(c.y), Float(c.z))
            }
            for key in 0..<64 where !buckets[key].isEmpty {
                guard let mesh = try? pointMesh(buckets[key]) else { continue }
                let avg = sums[key] / Float(buckets[key].count) / 255
                let material = UnlitMaterial(color: PlatformColor(
                    red: CGFloat(avg.x), green: CGFloat(avg.y), blue: CGFloat(avg.z), alpha: 1
                ))
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = "scan-color-\(key)"
                root.addChild(entity)
            }
            return root
        }

        let bands = max(1, options.bands)
        var buckets = Array(repeating: [SIMD3<Float>](), count: bands)
        for p in cloud.positions {
            let t = (p.y - b.min.y) / max(0.001, b.max.y - b.min.y)
            let idx = Swift.min(bands - 1, Swift.max(0, Int(t * Float(bands))))
            buckets[idx].append(transform.apply(p * toMeters))
        }
        for (i, points) in buckets.enumerated() where !points.isEmpty {
            guard let mesh = try? pointMesh(points) else { continue }
            let material = UnlitMaterial(color: bandColor(Float(i) / Float(max(1, bands - 1))))
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "scan-band-\(i)"
            root.addChild(entity)
        }
        return root
    }

    /// Siatka typu „point": pozycje w metrach, bez indeksów.
    static func pointMesh(_ points: [SIMD3<Float>]) throws -> MeshResource {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = points.count
        descriptor.indexCapacity = points.count
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: GLBLayout.vec3)
        ]

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let bound = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<points.count { bound[i] = points[i] }
        }
        mesh.withUnsafeMutableIndices { raw in
            let idx = raw.bindMemory(to: UInt32.self)
            for i in 0..<points.count { idx[i] = UInt32(i) }
        }

        var lo = points[0], hi = points[0]
        for p in points {
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexOffset: 0,
                indexCount: points.count,
                topology: .point,
                materialIndex: 0,
                bounds: BoundingBox(min: lo, max: hi)
            )
        ])
        return try MeshResource(from: mesh)
    }

    /// Kolor pasma: od ciemnego grafitu (podłoga) do jasnego piasku (sufit).
    static func bandColor(_ t: Float) -> PlatformColor {
        let base = (0.28 + 0.55 * t, 0.30 + 0.52 * t, 0.33 + 0.45 * t)
        return PlatformColor(red: CGFloat(base.0), green: CGFloat(base.1), blue: CGFloat(base.2), alpha: 1)
    }
}
