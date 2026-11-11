import Foundation
import RealityKit
import KitchenCore
import simd

/// Zamiana siatki surface nets na encje RealityKit.
/// Kolor jest per wierzchołek, a materiały wbudowane go nie czytają —
/// dlatego trójkąty grupujemy po kolorze (2 bity na kanał = 64 materiały).
@MainActor
public enum SurfaceMeshBuilder {

    public struct Options: Sendable {
        public var colorBits: Int = 2
        public init() {}
    }

    public static func makeEntity(_ mesh: SurfaceNets.Mesh, options: Options = Options()) -> Entity {
        let root = Entity()
        root.name = "scan-surface"
        guard !mesh.isEmpty, mesh.positions.count == mesh.normals.count else { return root }

        let bucketCount = 1 << (options.colorBits * 3)
        let levels = (1 << options.colorBits) - 1
        let step = 255 / Swift.max(1, levels)

        var bucketPos = [[SIMD3<Float>]](repeating: [], count: bucketCount)
        var bucketNrm = [[SIMD3<Float>]](repeating: [], count: bucketCount)
        var bucketIdx = [[UInt32]](repeating: [], count: bucketCount)
        var bucketSum = [SIMD3<Float>](repeating: .zero, count: bucketCount)
        var bucketN = [Float](repeating: 0, count: bucketCount)

        var t = 0
        while t + 2 < mesh.indices.count {
            let ia = Int(mesh.indices[t]), ib = Int(mesh.indices[t + 1]), ic = Int(mesh.indices[t + 2])
            let color = (mesh.colors[ia] + mesh.colors[ib] + mesh.colors[ic]) / 3
            let r = Int(color.x) / Swift.max(1, step)
            let g = Int(color.y) / Swift.max(1, step)
            let b = Int(color.z) / Swift.max(1, step)
            let bucket = Swift.min(bucketCount - 1, r * (1 << (options.colorBits * 2)) + g * (1 << options.colorBits) + b)

            let base = UInt32(bucketPos[bucket].count)
            for v in [ia, ib, ic] {
                bucketPos[bucket].append(mesh.positions[v])
                bucketNrm[bucket].append(mesh.normals[v])
            }
            bucketIdx[bucket].append(contentsOf: [base, base + 1, base + 2])
            bucketSum[bucket] += color
            bucketN[bucket] += 1
            t += 3
        }

        for b in 0..<bucketCount where !bucketIdx[b].isEmpty {
            guard let m = try? meshResource(positions: bucketPos[b], normals: bucketNrm[b], indices: bucketIdx[b]) else { continue }
            // lekko przyciemniamy: skan jest prześwietlony przez słońce
            let avg = bucketSum[b] / Swift.max(1, bucketN[b]) / 255 * 0.82
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: PlatformColor(
                red: CGFloat(avg.x), green: CGFloat(avg.y), blue: CGFloat(avg.z), alpha: 1
            ))
            material.roughness = .init(floatLiteral: 0.9)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: 0.1)
            let entity = ModelEntity(mesh: m, materials: [material])
            entity.name = "surface-\(b)"
            root.addChild(entity)
        }
        return root
    }

    static func meshResource(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) throws -> MeshResource {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = positions.count
        descriptor.indexCapacity = indices.count
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0, offset: GLBLayout.vec3),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: GLBLayout.vec3 * 2)
        ]

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let bound = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<positions.count {
                bound[i * 2] = positions[i]
                bound[i * 2 + 1] = normals[i]
            }
        }
        mesh.withUnsafeMutableIndices { raw in
            let idx = raw.bindMemory(to: UInt32.self)
            for i in 0..<indices.count { idx[i] = indices[i] }
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
