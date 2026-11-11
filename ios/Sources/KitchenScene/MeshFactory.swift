import Foundation
import RealityKit
import simd

/// Siatki z UV w metrach — potrzebne, żeby tekstury (stucco, dach, trawa) miały
/// realną skalę. `MeshResource.generateBox` daje UV 0…1 na każdą ścianę, więc
/// jedna tekstura rozciąga się na cały dom i wygląda jak plakat.
enum MeshFactory {

    /// Pudełko z UV liczonym w metrach: `tile` = rozmiar jednej kafelki (m).
    @MainActor
    static func texturedBox(
        width: Float,
        height: Float,
        depth: Float,
        tile: Float,
        cornerRadius: Float = 0
    ) -> MeshResource? {
        let hx = width / 2, hy = height / 2, hz = depth / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // (normalna, cztery narożniki, rozmiar kafla w osi U i V)
        func face(_ n: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                  _ sizeU: Float, _ sizeV: Float) {
            let base = UInt32(positions.count)
            let u = sizeU / tile, v = sizeV / tile
            positions += [a, b, c, d]
            normals += [n, n, n, n]
            uvs += [SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, v), SIMD2(0, v)]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        let w = width, d = depth, h = height
        // +Z (front)
        face([0, 0, 1], [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz], w, h)
        // -Z (tył)
        face([0, 0, -1], [hx, -hy, -hz], [-hx, -hy, -hz], [-hx, hy, -hz], [hx, hy, -hz], w, h)
        // +X
        face([1, 0, 0], [hx, -hy, hz], [hx, -hy, -hz], [hx, hy, -hz], [hx, hy, hz], d, h)
        // -X
        face([-1, 0, 0], [-hx, -hy, -hz], [-hx, -hy, hz], [-hx, hy, hz], [-hx, hy, -hz], d, h)
        // +Y (góra)
        face([0, 1, 0], [-hx, hy, hz], [hx, hy, hz], [hx, hy, -hz], [-hx, hy, -hz], w, d)
        // -Y (dół)
        face([0, -1, 0], [-hx, -hy, -hz], [hx, -hy, -hz], [hx, -hy, hz], [-hx, -hy, hz], w, d)

        var descriptor = MeshDescriptor(name: "texturedBox")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        _ = cornerRadius
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Dach dwuspadowy: dwie połacie + okap. Kalenica wzdłuż osi X.
    /// Zwraca siatkę dachu (bez szczytów — te robi `gableEnds`).
    @MainActor
    static func gabledRoof(
        width: Float,
        depth: Float,
        rise: Float,
        eaveOverhang: Float,
        gableOverhang: Float,
        tile: Float
    ) -> MeshResource? {
        let halfW = width / 2 + gableOverhang
        let halfD = depth / 2 + eaveOverhang
        let slope = sqrt(halfD * halfD + rise * rise)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // połowa +Z: od okapu (y=0) do kalenicy (y=rise)
        // normalna nachylona w stronę +Z i +Y
        let n1 = normalize(SIMD3<Float>(0, halfD, rise))
        let n2 = normalize(SIMD3<Float>(0, halfD, -rise))

        func quad(_ n: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
            let base = UInt32(positions.count)
            let u = (halfW * 2) / tile
            let v = slope / tile
            positions += [a, b, c, d]
            normals += [n, n, n, n]
            uvs += [SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, v), SIMD2(0, v)]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        quad(n1,
              [-halfW, 0, halfD], [halfW, 0, halfD], [halfW, rise, 0], [-halfW, rise, 0])
        quad(n2,
              [halfW, 0, -halfD], [-halfW, 0, -halfD], [-halfW, rise, 0], [halfW, rise, 0])

        var descriptor = MeshDescriptor(name: "gabledRoof")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Trójkąty szczytowe (wypełnienie między połaciami) — materiał ściany.
    @MainActor
    static func gableEnds(width: Float, rise: Float, depth: Float) -> MeshResource? {
        let halfW = width / 2
        let halfD = depth / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        func tri(_ n: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions += [a, b, c]
            normals += [n, n, n]
            uvs += [SIMD2(0, 0), SIMD2(depth / 2.5, 0), SIMD2(depth / 5, rise / 2.5)]
            indices += [base, base + 1, base + 2]
        }

        tri([1, 0, 0], [halfW, 0, -halfD], [halfW, 0, halfD], [halfW, rise, 0])
        tri([-1, 0, 0], [-halfW, 0, halfD], [-halfW, 0, -halfD], [-halfW, rise, 0])

        var descriptor = MeshDescriptor(name: "gableEnds")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Płaszczyzna pozioma z UV w metrach (trawa, kostka, taras).
    @MainActor
    static func ground(size: Float, tile: Float) -> MeshResource? {
        let r = size / 2
        var descriptor = MeshDescriptor(name: "ground")
        descriptor.positions = MeshBuffer([
            SIMD3<Float>(-r, 0, -r), SIMD3(r, 0, -r), SIMD3(r, 0, r), SIMD3(-r, 0, r),
        ])
        descriptor.normals = MeshBuffer([
            SIMD3<Float>(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 0),
        ])
        let u = size / tile
        descriptor.textureCoordinates = MeshBuffer([
            SIMD2<Float>(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u),
        ])
        descriptor.primitives = .triangles([0, 2, 1, 0, 3, 2])
        return try? MeshResource.generate(from: [descriptor])
    }
}
