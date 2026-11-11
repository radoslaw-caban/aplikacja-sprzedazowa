import Foundation
import CoreGraphics
import simd

/// Import planu z obrazu (zdjęcie, skan, PDF wyrenderowany do PNG).
///
/// Co robi: znajduje ciemne kreski (ściany), wyznacza obrys i przelicza piksele
/// na milimetry po podanej szerokości rzeczywistej. Nie udaje wektoryzacji
/// każdej kreski — daje **obrys pomieszczenia do korekty**, a użytkownik
/// dociąga ściany palcem. To świadoma decyzja: pełna wektoryzacja planu
/// ze zdjęcia myli się częściej niż człowiek poprawiający prostokąt.
public enum PlanImageImport {

    public struct Analysis: Sendable {
        public var widthPx: Int
        public var heightPx: Int
        /// obrys ciemnych pikseli w pikselach (x, y, szerokość, wysokość)
        public var box: (x: Int, y: Int, w: Int, h: Int)
        /// udział ciemnych pikseli (0…1) — do oceny, czy obraz ma w ogóle kreski
        public var inkRatio: Double
        /// wykryte pionowe linie (kolumny) i poziome (wiersze) — kandydaci na ściany
        public var verticalLines: [Int]
        public var horizontalLines: [Int]
    }

    /// Analiza mapy jasności (8 bit, wiersz po wierszu).
    public static func analyze(gray: [UInt8], width: Int, height: Int, threshold: UInt8 = 110) -> Analysis? {
        guard width > 8, height > 8, gray.count >= width * height else { return nil }

        var minX = width, maxX = -1, minY = height, maxY = -1
        var darkCount = 0
        var colSums = [Int](repeating: 0, count: width)
        var rowSums = [Int](repeating: 0, count: height)

        for y in 0..<height {
            let rowBase = y * width
            for x in 0..<width {
                if gray[rowBase + x] < threshold {
                    darkCount += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    colSums[x] += 1
                    rowSums[y] += 1
                }
            }
        }
        guard darkCount > 50, maxX > minX, maxY > minY else { return nil }

        let box = (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
        let ink = Double(darkCount) / Double(width * height)

        // linie: kolumny/wiersze, w których ciemnych pikseli jest istotnie więcej
        // niż w sąsiedztwie (ściana to ciągła kreska przez większość obrysu)
        let colPeak = Swift.max(1, box.h / 3)
        let rowPeak = Swift.max(1, box.w / 3)
        let vertical = (0..<width).filter { colSums[$0] >= colPeak }
        let horizontal = (0..<height).filter { rowSums[$0] >= rowPeak }

        return Analysis(
            widthPx: width,
            heightPx: height,
            box: box,
            inkRatio: ink,
            verticalLines: merge(vertical),
            horizontalLines: merge(horizontal)
        )
    }

    /// Skleja sąsiednie kolumny/wiersze (gruba kreska = jedna ściana).
    private static func merge(_ values: [Int], gap: Int = 3) -> [Int] {
        guard !values.isEmpty else { return [] }
        var out: [Int] = []
        var group: [Int] = [values[0]]
        for value in values.dropFirst() {
            if value - (group.last ?? value) <= gap {
                group.append(value)
            } else {
                out.append(group[group.count / 2])
                group = [value]
            }
        }
        out.append(group[group.count / 2])
        return out
    }

    /// Plan prostokątny z obrysu — szerokość rzeczywista nadaje skalę.
    public static func plan(
        from analysis: Analysis,
        realWidthMM: Double,
        height: Double = 2600,
        thickness: Double = 120
    ) -> FloorPlan {
        let boxWidth = Double(analysis.box.w)
        let boxHeight = Double(analysis.box.h)
        let scale = boxWidth > 0 ? realWidthMM / boxWidth : 1
        let depth = boxHeight * scale
        return FloorPlan.rectangle(x: 0, z: 0, width: realWidthMM, depth: depth, height: height, thickness: thickness)
    }

    /// Mapa jasności z CGImage (bez zależności od UIKit/AppKit).
    public static func grayscale(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) else { return nil }
        let created = pixels.withUnsafeMutableBytes { buffer -> CGContext? in
            CGContext(data: buffer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        guard let context = created else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }
}
