import Foundation

/// Detekcja kolizji i dociąganie do punktów charakterystycznych.
public enum Collision {

    /// Prostokąt zajmowany przez szafkę w rzucie (mm), z uwzględnieniem obrotu.
    public static func rect(_ c: Cabinet) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double) {
        let alongZ = c.rotation == 90 || c.rotation == 270
        let w = alongZ ? c.depth : c.width
        let d = alongZ ? c.width : c.depth
        return (c.x - w / 2, c.x + w / 2, c.z - d / 2, c.z + d / 2)
    }

    /// Czy dwie szafki nachodzą na siebie (tolerance = margines styku).
    public static func overlaps(_ a: Cabinet, _ b: Cabinet, tolerance: Double = 0) -> Bool {
        let ra = rect(a), rb = rect(b)
        let eps = tolerance
        return ra.minX < rb.maxX - eps && rb.minX < ra.maxX - eps
            && ra.minZ < rb.maxZ - eps && rb.minZ < ra.maxZ - eps
    }

    /// Najniższa wolna pozycja Y dla elementu o wysokości `height` w korpusie.
    public static func findFreeY(_ elements: [CabinetElement], height: Double, bodyHeight: Double) -> Double? {
        let occupied = elements
            .filter { $0.kind == .drawer || $0.kind == .shelf }
            .map { ($0.y, $0.y + $0.height) }
            .sorted { $0.0 < $1.0 }
        var y: Double = 0
        for (lo, hi) in occupied {
            if y + height <= lo + 0.001 { return y }
            y = max(y, hi)
        }
        return (y + height <= bodyHeight + 0.001) ? y : nil
    }

    /// Dokłada szufladę w pierwsze wolne miejsce; zwraca zaktualizowaną szafkę.
    public static func addDrawer(_ c: Cabinet, system: DrawerSystem) -> Cabinet? {
        let bodyH = c.type == .base ? c.height - c.plinth : c.height
        guard let y = findFreeY(c.elements, height: system.frontHeight, bodyHeight: bodyH) else { return nil }
        var updated = c
        updated.elements.append(
            CabinetElement(kind: .drawer, y: y, height: system.frontHeight, drawer: system)
        )
        return updated
    }
}

/// Punkty chwytu: narożniki, środki krawędzi, przecięcia linii.
public enum Snap {

    public struct Point: Sendable {
        public let position: SIMD3<Double>
        public let kind: Kind
        public enum Kind: String, Sendable { case corner, mid, intersection }
    }

    public static func points(for cabinets: [Cabinet]) -> [Point] {
        var out: [Point] = []
        for c in cabinets {
            let r = Collision.rect(c)
            let cx = (r.minX + r.maxX) / 2
            let cz = (r.minZ + r.maxZ) / 2
            for (x, z) in [(r.minX, r.minZ), (r.maxX, r.minZ), (r.minX, r.maxZ), (r.maxX, r.maxZ)] {
                out.append(Point(position: SIMD3(x, 0, z), kind: .corner))
            }
            out.append(Point(position: SIMD3(cx, 0, r.minZ), kind: .mid))
            out.append(Point(position: SIMD3(cx, 0, r.maxZ), kind: .mid))
            out.append(Point(position: SIMD3(r.minX, 0, cz), kind: .mid))
            out.append(Point(position: SIMD3(r.maxX, 0, cz), kind: .mid))
        }
        return out
    }
}
