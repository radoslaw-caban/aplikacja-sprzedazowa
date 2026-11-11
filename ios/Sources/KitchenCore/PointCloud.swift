import Foundation

/// Chmura punktów: wczytywanie PLY (ASCII i binarne), decymacja i wyznaczanie obrysu.
/// Wszystko w mm — tak jak geometria szafek.
public struct PointCloud: Sendable {
    public var positions: [SIMD3<Float>]
    public var colors: [SIMD3<UInt8>]?
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)

    public var count: Int { positions.count }

    public init(positions: [SIMD3<Float>], colors: [SIMD3<UInt8>]? = nil) {
        self.positions = positions
        self.colors = colors
        if positions.isEmpty {
            bounds = (SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 0))
        } else {
            var lo = positions[0], hi = positions[0]
            for p in positions {
                lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
            bounds = (lo, hi)
        }
    }

    /// Obrys z percentyli 2–98% — odporny na pojedyncze punkty odstające.
    public func robustBounds(lowPercentile: Double = 0.02, highPercentile: Double = 0.98) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard !positions.isEmpty else { return bounds }
        func axisBounds(_ axis: Int) -> (Float, Float) {
            var values = positions.map { axis == 0 ? $0.x : (axis == 1 ? $0.y : $0.z) }
            values.sort()
            let lo = values[Int(Double(values.count - 1) * lowPercentile)]
            let hi = values[Int(Double(values.count - 1) * highPercentile)]
            return (lo, hi)
        }
        let x = axisBounds(0), y = axisBounds(1), z = axisBounds(2)
        return (SIMD3(x.0, y.0, z.0), SIMD3(x.1, y.1, z.1))
    }

    /// Ile metrów ma jedna jednostka pliku: CloudCompare zapisuje metry,
    /// ale bywają pliki w milimetrach — rozstrzyga obrys (pokój to kilka metrów).
    public var unitScaleToMeters: Float {
        let b = bounds
        let e = Swift.max(b.max.x - b.min.x, Swift.max(b.max.y - b.min.y, b.max.z - b.min.z))
        return e > 100 ? 0.001 : 1
    }

    /// Decymacja równomierna — do limitu punktów wyświetlanych w scenie.
    public func decimated(maxPoints: Int) -> PointCloud {
        guard positions.count > maxPoints, maxPoints > 0 else { return self }
        let step = Double(positions.count) / Double(maxPoints)
        var newPositions: [SIMD3<Float>] = []
        newPositions.reserveCapacity(maxPoints)
        var newColors: [SIMD3<UInt8>]? = colors == nil ? nil : []
        var i = 0.0
        while Int(i) < positions.count && newPositions.count < maxPoints {
            let idx = Int(i)
            newPositions.append(positions[idx])
            if let c = colors { newColors?.append(c[idx]) }
            i += step
        }
        return PointCloud(positions: newPositions, colors: newColors)
    }
}

public enum PLYError: Error, CustomStringConvertible {
    case notPLY
    case unsupportedFormat(String)
    case missingXYZ
    case truncated(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .notPLY: "Plik nie jest PLY (brak nagłówka 'ply')"
        case .unsupportedFormat(let f): "Nieobsługiwany format PLY: \(f)"
        case .missingXYZ: "W nagłówku brak współrzędnych x/y/z"
        case .truncated(let e, let g): "Plik ucięty: oczekiwano \(e) punktów, jest \(g)"
        }
    }
}

/// Parser PLY: obsługuje ASCII oraz binary_little_endian (najczęstszy zapis z CloudCompare).
public enum PLYParser {

    public static func parse(data: Data) throws -> PointCloud {
        guard let headerEnd = findHeaderEnd(data) else { throw PLYError.notPLY }
        guard let header = String(data: data[0..<headerEnd], encoding: .utf8) else { throw PLYError.notPLY }
        guard header.hasPrefix("ply") else { throw PLYError.notPLY }

        var format = ""
        var count = 0
        var properties: [(name: String, type: String)] = []
        var inVertex = false
        var vertexIndex = -1

        for line in header.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard let key = parts.first else { continue }
            switch key {
            case "format":
                format = parts.count > 1 ? parts[1] : ""
            case "element":
                inVertex = parts.count > 2 && parts[1] == "vertex"
                if inVertex {
                    vertexIndex = properties.count
                    count = Int(parts[2]) ?? 0
                }
            case "property" where inVertex && vertexIndex >= 0:
                guard parts.count >= 3 else { continue }
                properties.append((name: parts[2], type: parts[1]))
            default:
                continue
            }
        }

        let names = properties.map(\.name)
        guard let ix = names.firstIndex(of: "x"), let iy = names.firstIndex(of: "y"),
              let iz = names.firstIndex(of: "z") else { throw PLYError.missingXYZ }
        let ir = names.firstIndex(of: "red"), ig = names.firstIndex(of: "green"), ib = names.firstIndex(of: "blue")

        let body = data[headerEnd...]

        switch format {
        case "ascii":
            return try parseASCII(body: body, count: count, ix: ix, iy: iy, iz: iz, ir: ir, ig: ig, ib: ib)
        case "binary_little_endian", "binary_big_endian":
            let little = format == "binary_little_endian"
            return try parseBinary(
                body: body, count: count, properties: properties, little: little,
                ix: ix, iy: iy, iz: iz, ir: ir, ig: ig, ib: ib
            )
        default:
            throw PLYError.unsupportedFormat(format)
        }
    }

    public static func parse(contentsOf url: URL) throws -> PointCloud {
        try parse(data: try Data(contentsOf: url))
    }

    // MARK: - szczegóły

    private static func findHeaderEnd(_ data: Data) -> Int? {
        let needle = Data("end_header".utf8)
        guard let range = data.range(of: needle) else { return nil }
        // przesuń za znak nowej linii
        var i = range.upperBound
        while i < data.count, data[i] != 0x0A { i += 1 }
        return min(i + 1, data.count)
    }

    private static func parseASCII(
        body: Data, count: Int, ix: Int, iy: Int, iz: Int, ir: Int?, ig: Int?, ib: Int?
    ) throws -> PointCloud {
        guard let text = String(data: body, encoding: .utf8) else {
            throw PLYError.unsupportedFormat("ascii bez kodowania UTF-8")
        }
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<UInt8>] = []
        positions.reserveCapacity(count)
        for line in text.split(separator: "\n") where !line.isEmpty {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count > max(ix, max(iy, iz)) else { continue }
            guard let x = Float(f[ix]), let y = Float(f[iy]), let z = Float(f[iz]) else { continue }
            positions.append(SIMD3(x, y, z))
            if let ir, let ig, let ib, f.count > max(ir, max(ig, ib)) {
                colors.append(SIMD3(
                    UInt8(truncatingIfNeeded: Int(Float(f[ir]) ?? 0)),
                    UInt8(truncatingIfNeeded: Int(Float(f[ig]) ?? 0)),
                    UInt8(truncatingIfNeeded: Int(Float(f[ib]) ?? 0))
                ))
            }
        }
        guard positions.count >= count - 1 || positions.count == count else {
            throw PLYError.truncated(expected: count, got: positions.count)
        }
        return PointCloud(positions: positions, colors: colors.isEmpty ? nil : colors)
    }

    private static func parseBinary(
        body: Data, count: Int, properties: [(name: String, type: String)], little: Bool,
        ix: Int, iy: Int, iz: Int, ir: Int?, ig: Int?, ib: Int?
    ) throws -> PointCloud {
        // rozmiar rekordu i offsety
        var offsets: [Int] = []
        var recordSize = 0
        for p in properties {
            offsets.append(recordSize)
            recordSize += size(of: p.type)
        }
        guard recordSize > 0 else { throw PLYError.missingXYZ }
        guard body.count >= recordSize * count else {
            throw PLYError.truncated(expected: count, got: body.count / recordSize)
        }

        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<UInt8>] = []
        positions.reserveCapacity(count)
        if ir != nil { colors.reserveCapacity(count) }

        let bytes = [UInt8](body)
        for i in 0..<count {
            let base = i * recordSize
            func readDouble(_ propIndex: Int) -> Float {
                let off = base + offsets[propIndex]
                let type = properties[propIndex].type
                switch type {
                case "float":
                    let raw = readUInt32(bytes, off, little)
                    return Float(bitPattern: raw)
                case "double":
                    let lo = UInt64(readUInt32(bytes, off, little))
                    let hi = UInt64(readUInt32(bytes, off + 4, little))
                    let raw = little ? (hi << 32 | lo) : (lo << 32 | hi)
                    return Float(Double(bitPattern: raw))
                default:
                    return Float(Int(readUInt32(bytes, off, little)))
                }
            }
            positions.append(SIMD3(readDouble(ix), readDouble(iy), readDouble(iz)))
            if let ir, let ig, let ib {
                colors.append(SIMD3(
                    bytes[base + offsets[ir]],
                    bytes[base + offsets[ig]],
                    bytes[base + offsets[ib]]
                ))
            }
        }
        return PointCloud(positions: positions, colors: colors.isEmpty ? nil : colors)
    }

    private static func size(of type: String) -> Int {
        switch type {
        case "char", "uchar", "int8", "uint8": 1
        case "short", "ushort", "int16", "uint16": 2
        case "int", "uint", "int32", "uint32", "float", "float32": 4
        case "double", "float64": 8
        default: 4
        }
    }

    private static func readUInt32(_ bytes: [UInt8], _ off: Int, _ little: Bool) -> UInt32 {
        guard off + 3 < bytes.count else { return 0 }
        let b0 = UInt32(bytes[off]), b1 = UInt32(bytes[off + 1])
        let b2 = UInt32(bytes[off + 2]), b3 = UInt32(bytes[off + 3])
        return little ? (b0 | b1 << 8 | b2 << 16 | b3 << 24) : (b3 | b2 << 8 | b1 << 16 | b0 << 24)
    }
}
