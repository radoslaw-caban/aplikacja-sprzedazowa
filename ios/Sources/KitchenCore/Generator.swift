import Foundation

/// Generator parametryczny — buduje bryły korpusu, frontów i wyposażenia w mm.
/// Logika jest przeniesiona 1:1 z wersji TypeScript (design/generator.ts).
public enum Generator {

    /// Bryły jednej szafki, w układzie lokalnym: środek w (0,0,0), y od podłogi, front w +Z.
    public static func build(_ c: Cabinet) -> [Box] {
        var out: [Box] = []
        let p = Standards.panel
        let bodyH = c.type == .base ? max(0, c.height - c.plinth) : c.height
        let baseY = c.type == .base ? c.plinth : c.mountHeight

        // ---- cokół (cofnięty o setback, tylko szafki dolne i stojące) ----
        if c.type != .wall, c.plinth > 0 {
            let pd = c.depth - Standards.plinthSetback
            out.append(Box(
                id: "\(c.id):plinth",
                role: .plinth,
                cabinetID: c.id,
                size: SIMD3(c.width, c.plinth, max(0, pd)),
                position: SIMD3(0, c.plinth / 2, Standards.plinthSetback / 2),
                color: "#3a3a37"
            ))
        }

        // ---- boki ----
        for (i, sign) in [(-1.0), (1.0)].enumerated() {
            out.append(Box(
                id: "\(c.id):side:\(i)",
                role: .side,
                cabinetID: c.id,
                size: SIMD3(p, bodyH, c.depth),
                position: SIMD3(sign * (c.width / 2 - p / 2), baseY + bodyH / 2, 0),
                color: c.color
            ))
        }

        // ---- dno i wieniec ----
        let innerW = max(0, c.width - 2 * p)
        out.append(Box(
            id: "\(c.id):bottom",
            role: .bottom,
            cabinetID: c.id,
            size: SIMD3(innerW, p, c.depth),
            position: SIMD3(0, baseY + p / 2, 0),
            color: c.color
        ))
        out.append(Box(
            id: "\(c.id):top",
            role: .top,
            cabinetID: c.id,
            size: SIMD3(innerW, p, c.depth),
            position: SIMD3(0, baseY + bodyH - p / 2, 0),
            color: c.color
        ))

        // ---- plecy ----
        out.append(Box(
            id: "\(c.id):back",
            role: .back,
            cabinetID: c.id,
            size: SIMD3(c.width, bodyH, Standards.back),
            position: SIMD3(0, baseY + bodyH / 2, -c.depth / 2 + Standards.backInset),
            color: "#f2efe9"
        ))

        // ---- wyposażenie ----
        for e in c.elements {
            switch e.kind {
            case .shelf, .divider:
                out.append(Box(
                    id: "\(c.id):\(e.kind):\(e.id)",
                    role: e.kind == .shelf ? .shelf : .divider,
                    cabinetID: c.id,
                    size: SIMD3(innerW - 2, p, c.depth - Standards.backInset - 20),
                    position: SIMD3(0, baseY + e.y + p / 2, 0),
                    color: c.color
                ))
            case .drawer:
                out.append(Box(
                    id: "\(c.id):drawer:\(e.id)",
                    role: .drawerFront,
                    cabinetID: c.id,
                    size: SIMD3(innerW - 2 * Standards.gap, e.height, p),
                    position: SIMD3(0, baseY + e.y + e.height / 2, c.depth / 2 + p / 2),
                    color: c.color
                ))
            case .cutout:
                break
            }
        }

        // ---- front (pełne pokrycie korpusu, szczelina 3 mm) ----
        if c.type != .wall || true {
            let hasDrawers = c.elements.contains { $0.kind == .drawer }
            if !hasDrawers {
                out.append(Box(
                    id: "\(c.id):front",
                    role: .front,
                    cabinetID: c.id,
                    size: SIMD3(
                        max(0, c.width - 2 * Standards.gap),
                        max(0, bodyH - 2 * Standards.gap),
                        p
                    ),
                    position: SIMD3(0, baseY + bodyH / 2, c.depth / 2 + Standards.gap + p / 2),
                    color: c.color
                ))
            }
        }

        return out
    }

    /// Dokłada szafkę w tym samym rzędzie co sąsiad (bez kolizji), zwraca nową pozycję.
    public static func placeNext(to existing: [Cabinet], new: Cabinet, tolerance: Double = 20) -> Cabinet? {
        guard let ref = existing.last else { return new }
        var candidate = new
        candidate.rotation = ref.rotation
        candidate.z = ref.z
        candidate.x = ref.x + (ref.width + new.width) / 2
        let others = existing.filter { $0.id != new.id }
        if others.contains(where: { Collision.overlaps($0, candidate, tolerance: tolerance) }) { return nil }
        return candidate
    }
}
