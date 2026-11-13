import Foundation
import simd

/// Siatka w pamięci: pozycje + indeksy, wszystko w metrach.
public struct TriMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>], indices: [UInt32]) {
        self.positions = positions
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { positions.isEmpty || indices.isEmpty }

    public struct Bounds: Sendable, Equatable {
        public var min: SIMD3<Float>
        public var max: SIMD3<Float>
        public var size: SIMD3<Float> { max - min }
        public var center: SIMD3<Float> { (min + max) / 2 }
        /// wymiary w mm (zaokrąglone) — do karty produktu
        public var sizeMM: (width: Double, depth: Double, height: Double) {
            (Double(size.x) * 1000, Double(size.z) * 1000, Double(size.y) * 1000)
        }
    }

    public var bounds: Bounds? {
        guard let first = positions.first else { return nil }
        var lo = first, hi = first
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return Bounds(min: lo, max: hi)
    }

    /// Skaluje model tak, aby miał zadany wymiar w mm w najdłuższej osi.
    public func scaled(toLongestMM target: Double) -> TriMesh {
        guard let b = bounds else { return self }
        let longest = max(b.size.x, max(b.size.y, b.size.z))
        guard longest > 0.0001 else { return self }
        let factor = Float(target / 1000) / longest
        return TriMesh(positions: positions.map { $0 * factor }, indices: indices)
    }
}

public enum MeshFormat: String, CaseIterable, Sendable {
    case glb, gltf, obj, stl, usdz, ply

    public static func detect(_ url: URL) -> MeshFormat? {
        MeshFormat(rawValue: url.pathExtension.lowercased())
    }
}

public enum MeshError: Error, CustomStringConvertible {
    case unsupported(String)
    case corrupt(String)

    public var description: String {
        switch self {
        case .unsupported(let ext): "Nieobsługiwany format: \(ext)"
        case .corrupt(let detail): "Uszkodzony plik: \(detail)"
        }
    }
}

/// Czytnik i konwerter modeli — bez RealityKit, działa w CLI i w testach.
public enum MeshIO {

    // MARK: - wejście

    public static func load(url: URL) throws -> TriMesh {
        guard let format = MeshFormat.detect(url) else {
            throw MeshError.unsupported(url.pathExtension)
        }
        let data = try Data(contentsOf: url)
        switch format {
        case .glb: return try readGLB(data)
        case .gltf: throw MeshError.unsupported("gltf (JSON) — zapisz jako GLB")
        case .obj: return try readOBJ(String(decoding: data, as: UTF8.self))
        case .stl: return try readSTL(data)
        case .usdz: throw MeshError.unsupported("usdz — wyeksportuj GLB z Reality Composer/Blender")
        case .ply: throw MeshError.unsupported("ply (chmura punktów) — to nie model produktu")
        }
    }

    // MARK: - GLB

    public static func readGLB(_ data: Data) throws -> TriMesh {
        guard data.count > 20 else { throw MeshError.corrupt("za krótki") }
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == 0x46546C67 else { throw MeshError.corrupt("zły nagłówek GLB") }
        var offset = 12
        var jsonData: Data?
        var binData: Data?
        while offset + 8 <= data.count {
            let length = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) })
            let type = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self) }
            let start = offset + 8
            guard start + length <= data.count else { break }
            let chunk = Data(data[start..<start + length])
            if type == 0x4E4F534A { jsonData = chunk }
            if type == 0x004E4942 { binData = chunk }
            offset = start + length
        }
        guard let jsonData, let binData,
              let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw MeshError.corrupt("brak JSON/BIN w GLB")
        }
        let accessors = root["accessors"] as? [[String: Any]] ?? []
        let views = root["bufferViews"] as? [[String: Any]] ?? []
        let meshes = root["meshes"] as? [[String: Any]] ?? []
        let nodes = root["nodes"] as? [[String: Any]] ?? []
        let scenes = root["scenes"] as? [[String: Any]] ?? []

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func matrix(_ node: [String: Any]) -> float4x4 {
            if let m = node["matrix"] as? [Double], m.count == 16 {
                return float4x4(
                SIMD4(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3])),
                SIMD4(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7])),
                SIMD4(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11])),
                SIMD4(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))
            )
            }
            var t = matrix_identity_float4x4
            if let tr = node["translation"] as? [Double], tr.count == 3 {
                t.columns.3 = SIMD4(Float(tr[0]), Float(tr[1]), Float(tr[2]), 1)
            }
            var r = matrix_identity_float4x4
            if let q = node["rotation"] as? [Double], q.count == 4 {
                r = float4x4(simd_quatf(ix: Float(q[0]), iy: Float(q[1]), iz: Float(q[2]), r: Float(q[3])))
            }
            var s = matrix_identity_float4x4
            if let sc = node["scale"] as? [Double], sc.count == 3 {
                s.columns.0.x = Float(sc[0]); s.columns.1.y = Float(sc[1]); s.columns.2.z = Float(sc[2])
            }
            return t * r * s
        }

        func vec3(_ accessor: Int) -> [SIMD3<Float>] {
            guard accessors.indices.contains(accessor) else { return [] }
            let a = accessors[accessor]
            guard let viewIndex = a["bufferView"] as? Int, views.indices.contains(viewIndex) else { return [] }
            let view = views[viewIndex]
            let start = (view["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let count = a["count"] as? Int ?? 0
            let stride = view["byteStride"] as? Int ?? 12
            var out: [SIMD3<Float>] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let base = start + i * stride
                guard base + 12 <= binData.count else { break }
                let x = binData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base, as: Float.self) }
                let y = binData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 4, as: Float.self) }
                let z = binData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: base + 8, as: Float.self) }
                out.append(SIMD3(x, y, z))
            }
            return out
        }

        func indexList(_ accessor: Int) -> [UInt32] {
            guard accessors.indices.contains(accessor) else { return [] }
            let a = accessors[accessor]
            guard let viewIndex = a["bufferView"] as? Int, views.indices.contains(viewIndex) else { return [] }
            let view = views[viewIndex]
            let start = (view["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let count = a["count"] as? Int ?? 0
            let component = a["componentType"] as? Int ?? 5125
            let size = component == 5123 ? 2 : (component == 5121 ? 1 : 4)
            var out: [UInt32] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let base = start + i * size
                guard base + size <= binData.count else { break }
                switch size {
                case 1: out.append(UInt32(binData[base]))
                case 2: out.append(UInt32(binData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: base, as: UInt16.self) }))
                default: out.append(binData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: base, as: UInt32.self) })
                }
            }
            return out
        }

        func walk(_ index: Int, _ parent: float4x4, _ depth: Int) {
            guard nodes.indices.contains(index), depth < 16 else { return }
            let node = nodes[index]
            let world = parent * matrix(node)
            if let meshIndex = node["mesh"] as? Int, meshes.indices.contains(meshIndex),
               let primitives = meshes[meshIndex]["primitives"] as? [[String: Any]] {
                for prim in primitives {
                    guard let attributes = prim["attributes"] as? [String: Int],
                          let positionAccessor = attributes["POSITION"] else { continue }
                    let local = vec3(positionAccessor)
                    guard !local.isEmpty else { continue }
                    let base = UInt32(positions.count)
                    for p in local {
                        let v = world * SIMD4<Float>(p, 1)
                        positions.append(SIMD3(v.x, v.y, v.z))
                    }
                    if let ia = prim["indices"] as? Int {
                        for idx in indexList(ia) { indices.append(base + idx) }
                    } else {
                        for i in 0..<UInt32(local.count) { indices.append(base + i) }
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
        guard !positions.isEmpty else { throw MeshError.corrupt("brak geometrii") }
        return TriMesh(positions: positions, indices: indices)
    }

    // MARK: - OBJ

    public static func readOBJ(_ text: String) throws -> TriMesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("v ") {
                let parts = line.dropFirst(2).split(separator: " ")
                guard parts.count >= 3,
                      let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]) else { continue }
                positions.append(SIMD3(x, y, z))
            } else if line.hasPrefix("f ") {
                let parts = line.dropFirst(2).split(separator: " ")
                var face: [UInt32] = []
                for token in parts {
                    let first = token.split(separator: "/").first.map(String.init) ?? ""
                    guard let raw = Int(first) else { continue }
                    let idx = raw > 0 ? raw - 1 : positions.count + raw
                    if idx >= 0 && idx < positions.count { face.append(UInt32(idx)) }
                }
                // triangulacja wachlarzem (OBJ dopuszcza wielokąty)
                if face.count >= 3 {
                    for i in 1..<(face.count - 1) {
                        indices.append(face[0]); indices.append(face[i]); indices.append(face[i + 1])
                    }
                }
            }
        }
        guard !positions.isEmpty else { throw MeshError.corrupt("OBJ bez wierzchołków") }
        return TriMesh(positions: positions, indices: indices)
    }

    // MARK: - STL

    public static func readSTL(_ data: Data) throws -> TriMesh {
        // ASCII: zaczyna się od "solid" i zawiera "facet"
        if let text = String(data: data.prefix(2048), encoding: .utf8),
           text.lowercased().contains("facet") {
            return try readSTLAscii(String(decoding: data, as: UTF8.self))
        }
        guard data.count >= 84 else { throw MeshError.corrupt("STL za krótki") }
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) })
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(count * 3)
        indices.reserveCapacity(count * 3)
        var offset = 84
        for _ in 0..<count {
            guard offset + 50 <= data.count else { break }
            let base = offset + 12   // pomijamy normalną
            for v in 0..<3 {
                let p = base + v * 12
                let x = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p, as: Float.self) }
                let y = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p + 4, as: Float.self) }
                let z = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: p + 8, as: Float.self) }
                indices.append(UInt32(positions.count))
                positions.append(SIMD3(x, y, z))
            }
            offset += 50
        }
        guard !positions.isEmpty else { throw MeshError.corrupt("STL bez trójkątów") }
        return TriMesh(positions: positions, indices: indices)
    }

    private static func readSTLAscii(_ text: String) throws -> TriMesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            guard line.hasPrefix("vertex ") else { continue }
            let parts = line.dropFirst(7).split(separator: " ")
            guard parts.count >= 3,
                  let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]) else { continue }
            indices.append(UInt32(positions.count))
            positions.append(SIMD3(x, y, z))
        }
        guard !positions.isEmpty else { throw MeshError.corrupt("STL ASCII bez wierzchołków") }
        return TriMesh(positions: positions, indices: indices)
    }

    // MARK: - wyjście GLB

    /// Zapisuje siatkę jako GLB 2.0 (bez materiałów) — format, który czyta aplikacja.
    public static func writeGLB(_ mesh: TriMesh) throws -> Data {
        guard !mesh.isEmpty else { throw MeshError.corrupt("pusta siatka") }

        var bin = Data()
        for p in mesh.positions {
            var x = p.x, y = p.y, z = p.z
            withUnsafeBytes(of: &x) { bin.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { bin.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { bin.append(contentsOf: $0) }
        }
        let positionsBytes = bin.count
        for i in mesh.indices {
            var value = i
            withUnsafeBytes(of: &value) { bin.append(contentsOf: $0) }
        }
        // dopełnienie do 4 bajtów
        while bin.count % 4 != 0 { bin.append(0) }

        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Karpatia Catalog"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0, "name": "product"]],
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0],
                    "indices": 1,
                    "mode": 4,
                ]]
            ]],
            "accessors": [
                [
                    "bufferView": 0, "componentType": 5126, "count": mesh.positions.count,
                    "type": "VEC3",
                    "min": [mesh.bounds?.min.x ?? 0, mesh.bounds?.min.y ?? 0, mesh.bounds?.min.z ?? 0],
                    "max": [mesh.bounds?.max.x ?? 0, mesh.bounds?.max.y ?? 0, mesh.bounds?.max.z ?? 0],
                ],
                [
                    "bufferView": 1, "componentType": 5125, "count": mesh.indices.count,
                    "type": "SCALAR",
                ],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": positionsBytes, "target": 34962],
                ["buffer": 0, "byteOffset": positionsBytes,
                 "byteLength": mesh.indices.count * 4, "target": 34963],
            ],
            "buffers": [["byteLength": bin.count]],
        ]
        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        var out = Data()
        func appendUInt32(_ value: UInt32) { withUnsafeBytes(of: value) { out.append(contentsOf: $0) } }
        let total = 12 + 8 + jsonData.count + 8 + bin.count
        appendUInt32(0x46546C67)
        appendUInt32(2)
        appendUInt32(UInt32(total))
        appendUInt32(UInt32(jsonData.count))
        appendUInt32(0x4E4F534A)
        out.append(jsonData)
        appendUInt32(UInt32(bin.count))
        appendUInt32(0x004E4942)
        out.append(bin)
        return out
    }
}
