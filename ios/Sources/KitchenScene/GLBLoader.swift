import Foundation
import RealityKit
import CoreGraphics
import ImageIO
import simd

/// Minimalny loader GLB (glTF 2.0 w jednym pliku).
///
/// RealityKit nie czyta GLB — a właśnie w tym formacie są darmowe modele
/// (Poly Haven, Kenney, Khronos). Loader obsługuje to, co potrzebne do scen:
/// pozycje, normalne, UV, indeksy, kolor bazowy + teksturę bazową i transformacje węzłów.
/// Układ atrybutów w buforze wierzchołków.
/// UWAGA: `SIMD3<Float>` ma `stride` 16 B (wyrównanie), a w buforze piszemy
/// 12 B — używanie `MemoryLayout` dawało przesunięte offsety i „rozsypaną" siatkę.
enum GLBLayout {
    static let vec3 = 12
    static let vec2 = 8
    static let vertex = 12 * 2 + 8   // position + normal + uv
}

public enum GLBLoader {

    public struct Loaded {
        public let entity: Entity
        public let meshCount: Int
    }

    public enum LoadError: Error, CustomStringConvertible {
        case badHeader
        case noBinaryChunk
        case badJSON
        case noMeshes

        public var description: String {
            switch self {
            case .badHeader: "to nie jest plik GLB"
            case .noBinaryChunk: "brak chunku binarnego"
            case .badJSON: "uszkodzony JSON w GLB"
            case .noMeshes: "model nie ma siatek"
            }
        }
    }

    // MARK: - trójkąty (dla detektorów geometrii, bez RealityKit)

    /// Wszystkie trójkąty modelu w **przestrzeni świata** (metry).
    ///
    /// Potrzebne modułom, które liczą na geometrii (np. `ScanKitchen`),
    /// a nie chcą budować encji ani tekstur.
    public static func triangles(url: URL) throws -> [SIMD3<Float>] {
        let data = try Data(contentsOf: url)
        return try triangles(data: data)
    }

    public static func triangles(data: Data) throws -> [SIMD3<Float>] {
        let (json, bin) = try splitChunks(data)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw LoadError.badJSON
        }
        let accessors = root["accessors"] as? [[String: Any]] ?? []
        let bufferViews = root["bufferViews"] as? [[String: Any]] ?? []
        let meshes = root["meshes"] as? [[String: Any]] ?? []
        let nodes = root["nodes"] as? [[String: Any]] ?? []
        let scenes = root["scenes"] as? [[String: Any]] ?? []

        var out: [SIMD3<Float>] = []

        func nodeMatrix(_ node: [String: Any]) -> float4x4 {
            if let m = node["matrix"] as? [Double], m.count == 16 {
                return float4x4(columnMajor: m.map(Float.init))
            }
            var t = matrix_identity_float4x4
            if let tr = node["translation"] as? [Double], tr.count == 3 {
                t.columns.3 = SIMD4<Float>(Float(tr[0]), Float(tr[1]), Float(tr[2]), 1)
            }
            var r = matrix_identity_float4x4
            if let q = node["rotation"] as? [Double], q.count == 4 {
                r = float4x4(simd_quatf(ix: Float(q[0]), iy: Float(q[1]), iz: Float(q[2]), r: Float(q[3])))
            }
            var s = matrix_identity_float4x4
            if let sc = node["scale"] as? [Double], sc.count == 3 {
                s.columns.0.x = Float(sc[0])
                s.columns.1.y = Float(sc[1])
                s.columns.2.z = Float(sc[2])
            }
            return t * r * s
        }

        func walk(_ index: Int, _ parent: float4x4, _ depth: Int) {
            guard nodes.indices.contains(index), depth < 12 else { return }
            let node = nodes[index]
            let world = parent * nodeMatrix(node)
            if let meshIndex = node["mesh"] as? Int, meshes.indices.contains(meshIndex),
               let primitives = meshes[meshIndex]["primitives"] as? [[String: Any]] {
                for prim in primitives {
                    guard let attributes = prim["attributes"] as? [String: Int],
                          let positionAccessor = attributes["POSITION"],
                          let positions = readVec3(accessor: positionAccessor, accessors: accessors,
                                                   views: bufferViews, bin: bin) else { continue }
                    let indices: [UInt32]
                    if let ia = prim["indices"] as? Int,
                       let read = readIndices(accessor: ia, accessors: accessors, views: bufferViews, bin: bin) {
                        indices = read
                    } else {
                        indices = Array(0..<UInt32(positions.count))
                    }
                    guard indices.count >= 3 else { continue }
                    var i = 0
                    while i + 2 < indices.count {
                        let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
                        i += 3
                        guard ia < positions.count, ib < positions.count, ic < positions.count else { continue }
                        for p in [positions[ia], positions[ib], positions[ic]] {
                            let v = world * SIMD4<Float>(p, 1)
                            out.append(SIMD3(v.x, v.y, v.z))
                        }
                    }
                }
            }
            for child in (node["children"] as? [Int] ?? []) {
                walk(child, world, depth + 1)
            }
        }

        for scene in scenes.prefix(1) {
            for rootIndex in (scene["nodes"] as? [Int] ?? []) {
                walk(rootIndex, matrix_identity_float4x4, 0)
            }
        }
        return out
    }

    // MARK: - wejście

    @MainActor
    public static func load(url: URL) throws -> Loaded {
        let data = try Data(contentsOf: url)
        return try load(data: data)
    }

    @MainActor
    public static func load(data: Data) throws -> Loaded {
        let (json, bin) = try splitChunks(data)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw LoadError.badJSON
        }

        let accessors = root["accessors"] as? [[String: Any]] ?? []
        let bufferViews = root["bufferViews"] as? [[String: Any]] ?? []
        let meshes = root["meshes"] as? [[String: Any]] ?? []
        let nodes = root["nodes"] as? [[String: Any]] ?? []
        let materials = root["materials"] as? [[String: Any]] ?? []
        let textures = root["textures"] as? [[String: Any]] ?? []
        let images = root["images"] as? [[String: Any]] ?? []
        let scenes = root["scenes"] as? [[String: Any]] ?? []

        guard !meshes.isEmpty else { throw LoadError.noMeshes }

        var cache: [Int: [ModelEntity]] = [:]
        var meshCount = 0

        func material(for index: Int?) -> PhysicallyBasedMaterial {
            guard let index, materials.indices.contains(index) else {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: .white)
                m.roughness = .init(floatLiteral: 0.8)
                return m
            }
            let json = materials[index]
            var m = PhysicallyBasedMaterial()
            let pbr = json["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            if let factor = pbr["baseColorFactor"] as? [Double], factor.count >= 3 {
                m.baseColor = .init(tint: PlatformColor(
                    red: CGFloat(factor[0]), green: CGFloat(factor[1]), blue: CGFloat(factor[2]), alpha: 1
                ))
            }
            if let texInfo = pbr["baseColorTexture"] as? [String: Any],
               let texIndex = texInfo["index"] as? Int,
               textures.indices.contains(texIndex),
               let source = textures[texIndex]["source"] as? Int,
               images.indices.contains(source),
               let view = images[source]["bufferView"] as? Int,
               bufferViews.indices.contains(view),
               let texture = imageTexture(bufferViews[view], bin: bin) {
                m.baseColor = .init(tint: .white, texture: .init(texture))
            }
            // liście w modelach roślin to alphaMask — bez tego renderują się jako białe kwadraty
            if let alphaMode = json["alphaMode"] as? String {
                switch alphaMode {
                case "MASK":
                    let cutoff = (json["alphaCutoff"] as? Double) ?? 0.5
                    m.opacityThreshold = Float(cutoff)
                    m.blending = .opaque
                case "BLEND":
                    m.blending = .transparent(opacity: .init(floatLiteral: 0.85))
                default:
                    m.blending = .opaque
                }
            }
            if json["doubleSided"] as? Bool == true {
                m.faceCulling = .none
            }
            if let rough = pbr["roughnessFactor"] as? Double { m.roughness = .init(floatLiteral: Float(rough)) }
            if let metal = pbr["metallicFactor"] as? Double { m.metallic = .init(floatLiteral: Float(metal)) }
            return m
        }

        func meshEntities(for meshIndex: Int) -> [ModelEntity] {
            if let cached = cache[meshIndex] { return cached }
            guard meshes.indices.contains(meshIndex) else { return [] }
            let mesh = meshes[meshIndex]
            guard let primitives = mesh["primitives"] as? [[String: Any]] else { return [] }

            // najpierw policz obrysy prymitywów, żeby odrzucić odstające
            var diagonals: [Float] = []
            var loadedPrimitives: [(dict: [String: Any], positions: [SIMD3<Float>], normals: [SIMD3<Float>]?, uvs: [SIMD2<Float>]?, indices: [UInt32], diagonal: Float)] = []

            for first in primitives {
                guard let attributes = first["attributes"] as? [String: Int],
                      let positionAccessor = attributes["POSITION"],
                      let positions = readVec3(accessor: positionAccessor, accessors: accessors, views: bufferViews, bin: bin)
                else { continue }
                let normals = attributes["NORMAL"].flatMap { readVec3(accessor: $0, accessors: accessors, views: bufferViews, bin: bin) }
                let uvs = attributes["TEXCOORD_0"].flatMap { readVec2(accessor: $0, accessors: accessors, views: bufferViews, bin: bin) }
                let indices: [UInt32]
                if let indexAccessor = first["indices"] as? Int,
                   let read = readIndices(accessor: indexAccessor, accessors: accessors, views: bufferViews, bin: bin) {
                    indices = read
                } else {
                    indices = (0..<UInt32(positions.count)).map { $0 }
                }
                guard !indices.isEmpty, (indices.max() ?? 0) < UInt32(positions.count) else { continue }

                var lo = positions[0], hi = positions[0]
                for p in positions {
                    lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                    hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
                }
                let diagonal = length(hi - lo)
                diagonals.append(diagonal)
                loadedPrimitives.append((first, positions, normals, uvs, indices, diagonal))
            }

            // mediana obrysu: prymitywy >3× większe to zwykle płaszczyzny cienia
            // albo artefakty trackingu, które psują cały model
            let median: Float = {
                guard !diagonals.isEmpty else { return 0 }
                let sorted = diagonals.sorted()
                return sorted[sorted.count / 2]
            }()

            var entities: [ModelEntity] = []
            for item in loadedPrimitives {
                if median > 0.001, item.diagonal > median * 3.2 { continue }
                let first = item.dict
                let positions = item.positions
                let normals = item.normals
                let uvs = item.uvs
                let indices = item.indices
                _ = first
                guard let resource = try? makeMesh(
                    positions: positions,
                    normals: normals ?? defaultNormals(positions: positions, indices: indices),
                    uvs: uvs,
                    indices: indices
                ) else { continue }

                entities.append(ModelEntity(mesh: resource, materials: [material(for: first["material"] as? Int)]))
            }
            cache[meshIndex] = entities
            return entities
        }

        func buildNode(_ index: Int, depth: Int = 0) -> Entity? {
            guard nodes.indices.contains(index), depth < 8 else { return nil }
            let node = nodes[index]
            let entity = Entity()
            entity.name = (node["name"] as? String) ?? "node-\(index)"

            if let matrix = node["matrix"] as? [Double], matrix.count == 16 {
                entity.transform.matrix = float4x4(columnMajor: matrix.map(Float.init))
            } else {
                if let t = node["translation"] as? [Double], t.count == 3 {
                    entity.position = [Float(t[0]), Float(t[1]), Float(t[2])]
                }
                if let r = node["rotation"] as? [Double], r.count == 4 {
                    entity.orientation = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
                }
                if let s = node["scale"] as? [Double], s.count == 3 {
                    entity.scale = [Float(s[0]), Float(s[1]), Float(s[2])]
                }
            }

            if let meshIndex = node["mesh"] as? Int {
                for model in meshEntities(for: meshIndex) {
                    entity.addChild(model)
                    meshCount += 1
                }
            }

            for child in (node["children"] as? [Int] ?? []) {
                if let childEntity = buildNode(child, depth: depth + 1) {
                    entity.addChild(childEntity)
                }
            }
            return entity
        }

        let rootEntity = Entity()
        rootEntity.name = "glb"
        let sceneNodes = (scenes.first?["nodes"] as? [Int]) ?? Array(0..<nodes.count)
        for nodeIndex in sceneNodes {
            if let e = buildNode(nodeIndex) { rootEntity.addChild(e) }
        }

        guard meshCount > 0 else { throw LoadError.noMeshes }
        return Loaded(entity: rootEntity, meshCount: meshCount)
    }

    // MARK: - GLB / glTF

    static func splitChunks(_ data: Data) throws -> (json: Data, bin: Data) {
        guard data.count > 20,
              data[0] == 0x67, data[1] == 0x6C, data[2] == 0x54, data[3] == 0x46 // "glTF"
        else { throw LoadError.badHeader }

        var offset = 12
        var json = Data()
        var bin = Data()
        while offset + 8 <= data.count {
            let length = Int(readUInt32(data, offset))
            let type = readUInt32(data, offset + 4)
            let start = offset + 8
            let end = min(start + length, data.count)
            guard start < end else { break }
            // UWAGA: plasterki Data zachowują indeksy rodzica — trzeba je zerować,
            // inaczej odczyty offsetów glTF wychodzą poza zakres.
            if type == 0x4E4F534A { json = Data(data[start..<end]) }      // JSON
            else if type == 0x004E4942 { bin = Data(data[start..<end]) }  // BIN
            offset = end
        }
        guard !bin.isEmpty else { throw LoadError.noBinaryChunk }
        return (json, bin)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    static func accessorInfo(_ index: Int, accessors: [[String: Any]], views: [[String: Any]]) -> (offset: Int, count: Int, stride: Int, componentType: Int, type: String, normalized: Bool)? {
        guard accessors.indices.contains(index) else { return nil }
        let a = accessors[index]
        guard let count = a["count"] as? Int,
              let viewIndex = a["bufferView"] as? Int,
              views.indices.contains(viewIndex)
        else { return nil }
        let view = views[viewIndex]
        let viewOffset = (view["byteOffset"] as? Int) ?? 0
        let accessorOffset = (a["byteOffset"] as? Int) ?? 0
        let componentType = (a["componentType"] as? Int) ?? 5126
        let type = (a["type"] as? String) ?? "VEC3"
        let components = type == "VEC3" ? 3 : (type == "VEC2" ? 2 : 1)
        let stride = (view["byteStride"] as? Int) ?? (components * componentSize(componentType))
        let normalized = (a["normalized"] as? Bool) ?? false
        return (viewOffset + accessorOffset, count, stride, componentType, type, normalized)
    }

    static func readVec3(accessor: Int, accessors: [[String: Any]], views: [[String: Any]], bin: Data) -> [SIMD3<Float>]? {
        guard let info = accessorInfo(accessor, accessors: accessors, views: views) else { return nil }
        let bytes = componentSize(info.componentType)
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(info.count)
        for i in 0..<info.count {
            let base = info.offset + i * info.stride
            guard base + bytes * 3 <= bin.count else { break }
            // KHR_mesh_quantization: pozycje/normalne bywają w short/int8 (normalized)
            let x = readComponent(bin, base, info.componentType, info.normalized)
            let y = readComponent(bin, base + bytes, info.componentType, info.normalized)
            let z = readComponent(bin, base + bytes * 2, info.componentType, info.normalized)
            out.append(SIMD3(x, y, z))
        }
        return out.isEmpty ? nil : out
    }

    static func componentSize(_ type: Int) -> Int {
        switch type {
        case 5120, 5121: return 1
        case 5122, 5123: return 2
        default: return 4
        }
    }

    /// Odczyt pojedynczej składowej w formacie glTF (z obsługą `normalized`).
    static func readComponent(_ data: Data, _ offset: Int, _ type: Int, _ normalized: Bool) -> Float {
        switch type {
        case 5126:
            return readFloat(data, offset)
        case 5125:
            var v: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
            return normalized ? Float(v) / Float(UInt32.max) : Float(v)
        case 5123:
            var v: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
            return normalized ? Float(v) / 65535.0 : Float(v)
        case 5122:
            var v: Int16 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
            return normalized ? max(Float(v) / 32767.0, -1) : Float(v)
        case 5121:
            return normalized ? Float(data[offset]) / 255.0 : Float(data[offset])
        case 5120:
            let raw = Int8(bitPattern: data[offset])
            return normalized ? max(Float(raw) / 127.0, -1) : Float(raw)
        default:
            return readFloat(data, offset)
        }
    }

    static func readVec2(accessor: Int, accessors: [[String: Any]], views: [[String: Any]], bin: Data) -> [SIMD2<Float>]? {
        guard let info = accessorInfo(accessor, accessors: accessors, views: views), info.componentType == 5126 else { return nil }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(info.count)
        for i in 0..<info.count {
            let base = info.offset + i * info.stride
            guard base + 8 <= bin.count else { break }
            out.append(SIMD2(readFloat(bin, base), readFloat(bin, base + 4)))
        }
        return out.isEmpty ? nil : out
    }

    static func readIndices(accessor: Int, accessors: [[String: Any]], views: [[String: Any]], bin: Data) -> [UInt32]? {
        guard let info = accessorInfo(accessor, accessors: accessors, views: views) else { return nil }
        var out: [UInt32] = []
        out.reserveCapacity(info.count)
        for i in 0..<info.count {
            switch info.componentType {
            case 5125:
                let base = info.offset + i * info.stride
                guard base + 4 <= bin.count else { return out }
                out.append(readUInt32(bin, base))
            case 5123:
                let base = info.offset + i * info.stride
                guard base + 2 <= bin.count else { return out }
                out.append(UInt32(bin[base]) | UInt32(bin[base + 1]) << 8)
            case 5121:
                let base = info.offset + i * info.stride
                guard base < bin.count else { return out }
                out.append(UInt32(bin[base]))
            default:
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    static func readFloat(_ data: Data, _ offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, offset))
    }

    @MainActor
    static func imageTexture(_ view: [String: Any], bin: Data) -> TextureResource? {
        let offset = (view["byteOffset"] as? Int) ?? 0
        let length = (view["byteLength"] as? Int) ?? 0
        guard length > 0, offset + length <= bin.count else { return nil }
        let imageData = bin[offset..<(offset + length)]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    static func defaultNormals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = positions[Int(indices[i])], b = positions[Int(indices[i + 1])], c = positions[Int(indices[i + 2])]
            let n = cross(b - a, c - a)
            normals[Int(indices[i])] += n
            normals[Int(indices[i + 1])] += n
            normals[Int(indices[i + 2])] += n
            i += 3
        }
        for k in 0..<normals.count {
            let len = length(normals[k])
            normals[k] = len > 1e-9 ? normals[k] / len : SIMD3(0, 1, 0)
        }
        return normals
    }

    @MainActor
    static func makeMesh(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>]?,
        indices: [UInt32]
    ) throws -> MeshResource {
        guard !positions.isEmpty, !indices.isEmpty else { throw LoadError.noMeshes }
        guard normals.count == positions.count else { throw LoadError.noMeshes }
        var hasUV = uvs != nil && uvs!.count == positions.count
        if uvs != nil && !hasUV { hasUV = false }

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = positions.count
        descriptor.indexCapacity = indices.count
        var attributes: [LowLevelMesh.Attribute] = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0, offset: GLBLayout.vec3),
        ]
        if hasUV {
            attributes.append(.init(semantic: .uv0, format: .float2, layoutIndex: 0, offset: GLBLayout.vec3 * 2))
        }
        descriptor.vertexAttributes = attributes
        let stride = GLBLayout.vec3 * 2 + (hasUV ? MemoryLayout<SIMD2<Float>>.stride : 0)
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: stride)]

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let floats = raw.bindMemory(to: Float.self)
            var index = 0
            for i in 0..<positions.count {
                floats[index] = positions[i].x; floats[index + 1] = positions[i].y; floats[index + 2] = positions[i].z
                index += 3
                floats[index] = normals[i].x; floats[index + 1] = normals[i].y; floats[index + 2] = normals[i].z
                index += 3
                if hasUV, let uvs {
                    floats[index] = uvs[i].x; floats[index + 1] = uvs[i].y
                    index += 2
                }
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

extension float4x4 {
    /// macierz z glTF jest kolumnowa
    init(columnMajor values: [Float]) {
        precondition(values.count == 16, "macierz musi mieć 16 wartości")
        self.init(
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        )
    }
}
