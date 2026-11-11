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

    /// Zapisuje chmurę jako PLY binary_little_endian z kolorami
    /// (i z niepewnością, gdy jest znana).
    ///
    /// - Parameter cloud: chmura w metrach
    /// - Returns: dane pliku (nagłówek ASCII + rekordy 15 B lub 19 B z `sigma`)
    public static func data(for cloud: PointCloud) -> Data {
        guard !cloud.positions.isEmpty else { return Data() }

        let hasSigma = cloud.uncertainty?.count == cloud.count
        let recordSize = hasSigma ? 19 : 15

        var out = Data()
        // Nagłówek budujemy linia po linii i kończymy DOKŁADNIE jednym "\n"
        // po "end_header". Każdy dodatkowy bajt przesuwa ciało pliku i parser
        // czyta współrzędne z błędnego offsetu (testy złapały to jako 1e35 m).
        var headerLines = [
            "ply",
            "format binary_little_endian 1.0",
            "comment Karpatia — skan LiDAR (fuzja map glebi ARKit), metry",
            "comment sigma = niepewnosc pozycji punktu w metrach (1 sigma)",
            "element vertex \(cloud.count)",
            "property float x",
            "property float y",
            "property float z",
            "property uchar red",
            "property uchar green",
            "property uchar blue",
        ]
        if hasSigma {
            headerLines.append("property float sigma")
        }
        headerLines.append("end_header")
        out.append(Data((headerLines.joined(separator: "\n") + "\n").utf8))

        // rekord: 3 × float32 (12 B) + 3 × uint8 (3 B) [+ 1 × float32 (4 B)]
        var record = [UInt8](repeating: 0, count: recordSize)
        let colors = cloud.colors
        let sigma = cloud.uncertainty

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
            if hasSigma, let s = sigma?[i] {
                record.withUnsafeMutableBytes { raw in
                    raw.storeBytes(of: s.bitPattern.littleEndian, toByteOffset: 15, as: UInt32.self)
                }
            }
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

    /// Raport jakości skanu — do statusu i do pliku obok chmury.
    ///
    /// Mediana jest lepszą miarą niż średnia: pojedyncze punkty z niską
    /// ufnością na krawędziach zawyżają średnią i sugerują, że skan jest
    /// gorszy, niż jest w rzeczywistości.
    public static func qualityReport(_ cloud: PointCloud) -> String? {
        guard let sigma = cloud.uncertainty, sigma.count == cloud.count, !sigma.isEmpty else {
            return nil
        }
        var sorted = sigma
        sorted.sort()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let mm = { (v: Float) in String(format: "%.1f", v * 1000) }

        var text = "punkty: \(cloud.count.formatted())\n"
        text += "σ mediana: \(mm(median)) mm\n"
        text += "σ 95 percentyl: \(mm(p95)) mm\n"
        let b = cloud.bounds
        let s = b.max - b.min
        text += String(format: "wymiary: %.0f × %.0f × %.0f mm\n",
                       s.x * 1000, s.y * 1000, s.z * 1000)
        return text
    }
}
