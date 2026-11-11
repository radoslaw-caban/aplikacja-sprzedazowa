import Foundation
import simd

/// Krótki opis wyniku skanu dla UI i statusu — wspólny dla obu platform.
public enum ScanOutcome {

    /// np. „151 002 pkt · 4000×2600×3000 mm"
    public static func summary(_ cloud: PointCloud) -> String {
        let b = cloud.bounds
        let s = b.max - b.min
        let mm = { (v: Float) in Int((v * 1000).rounded()) }
        return "\(cloud.count.formatted()) pkt · \(mm(s.x))×\(mm(s.y))×\(mm(s.z)) mm"
    }
}

/// Zapis chmury punktów do PLY (binary_little_endian) — format, który czyta
/// parser PLY tej aplikacji i wszystkie programy pomiarowe.
///
/// Jednostka: chmura z ARKit jest w METRACH i taka trafia do pliku — tak samo
/// jak eksporty CloudCompare, więc `PointCloud.unitScaleToMeters` rozpozna ją
/// poprawnie bez żadnej konwersji.
public enum ScanPLYWriter {

    /// Zapisuje chmurę jako PLY binary_little_endian z kolorami.
    ///
    /// - Parameter cloud: chmura w metrach
    /// - Returns: dane pliku (nagłówek ASCII + rekordy 15 B: 3×float32 + 3×uint8)
    public static func data(for cloud: PointCloud) -> Data {
        guard !cloud.positions.isEmpty else { return Data() }

        var out = Data()
        let header = """
        ply
        format binary_little_endian 1.0
        comment Karpatia — skan LiDAR (ARKit scene reconstruction), metry
        element vertex \(cloud.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        out.append(Data(header.utf8))

        // rekord: 3 × float32 (12 B) + 3 × uint8 (3 B) = 15 B
        var record = [UInt8](repeating: 0, count: 15)
        let colors = cloud.colors
        for i in 0..<cloud.count {
            let p = cloud.positions[i]
            record.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: p.x.bitPattern.littleEndian, toByteOffset: 0, as: UInt32.self)
                raw.storeBytes(of: p.y.bitPattern.littleEndian, toByteOffset: 4, as: UInt32.self)
                raw.storeBytes(of: p.z.bitPattern.littleEndian, toByteOffset: 8, as: UInt32.self)
            }
            let c = colors?[i] ?? SIMD3<UInt8>(200, 200, 200)
            record[12] = c.x
            record[13] = c.y
            record[14] = c.z
            out.append(contentsOf: record)
        }
        return out
    }

    /// Zapisuje chmurę do pliku.
    public static func write(_ cloud: PointCloud, to url: URL) throws {
        try data(for: cloud).write(to: url, options: .atomic)
    }

    /// Nazwa pliku skanu — z datą, żeby kolejne skany się nie nadpisywały.
    public static func fileName(at date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "skan-\(f.string(from: date)).ply"
    }
}
