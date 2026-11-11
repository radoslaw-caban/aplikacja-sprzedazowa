import Foundation

/// Biegi (runs): łączenie szafek w ciągi i generowanie blatu oraz cokołu jako
/// osobnych obiektów, edytowanych niezależnie od szafek.
public enum Runs {

    public struct Run: Sendable {
        public let id: String
        public let cabinetIDs: [UUID]
        public let cx: Double
        public let cz: Double
        public let length: Double
        public let rotation: Double
        public let bodyTop: Double      // górna krawędź korpusu (mm)
        public let hasBase: Bool
        /// blat głębszy niż korpus (wyspa: 860 z nawisem 300)
        public let worktopDepth: Double?
        /// przesunięcie blatu w głąb (lokalne +Z), mm
        public let worktopShift: Double
        /// realna wysokość cokołu w biegu
        public let plinthHeight: Double
        /// bieg w podglądzie strefy (wszystkie szafki to cień)
        public let preview: Bool
    }

    public struct WorktopParams: Sendable {
        public var enabled = true
        public var thickness = Standards.worktopThickness
        public var overhang = Standards.worktopOverhang
        public var color = "#cfccc5"
        public init() {}
    }

    public struct PlinthParams: Sendable {
        public var enabled = true
        public var height = Standards.plinthHeight
        public var setback = Standards.plinthSetback
        public var color = "#3a3a37"
        public init() {}
    }

    /// Grupuje szafki w biegi: ten sam wiersz (z) i ten sam obrót, stykanie w tolerancji.
    public static func compute(_ cabinets: [Cabinet], tolerance: Double = 20) -> [Run] {
        var rows: [String: [Cabinet]] = [:]
        for c in cabinets {
            let alongZ = c.rotation == 90 || c.rotation == 270
            let key = "\(Int((alongZ ? c.x : c.z) / 50).description):\(Int(c.rotation))"
            rows[key, default: []].append(c)
        }

        var runs: [Run] = []
        for group in rows.values {
            let alongZ = group[0].rotation == 90 || group[0].rotation == 270
            let sorted = group.sorted { ($0.rotation, $1.rotation) != (0, 0) && alongZ ? $0.z < $1.z : $0.x < $1.x }

            var current: [Cabinet] = []
            func flush(_ arr: [Cabinet]) {
                guard !arr.isEmpty else { return }
                let mins = arr.map { alongZ ? $0.z - $0.width / 2 : $0.x - $0.width / 2 }
                let maxs = arr.map { alongZ ? $0.z + $0.width / 2 : $0.x + $0.width / 2 }
                let lo = mins.min()!, hi = maxs.max()!
                let first = arr[0]
                runs.append(Run(
                    id: "run-\(first.id)",
                    cabinetIDs: arr.map(\.id),
                    cx: alongZ ? first.x : (lo + hi) / 2,
                    cz: alongZ ? (lo + hi) / 2 : first.z,
                    length: hi - lo,
                    rotation: first.rotation,
                    // blat leży na korpusie: wysokość szafki jest już łączna (z cokołem)
                    bodyTop: arr.map { $0.height + $0.mountHeight }.max() ?? 0,
                    hasBase: arr.contains { $0.type == .base },
                    worktopDepth: arr.compactMap(\.worktopDepth).max(),
                    worktopShift: arr.compactMap(\.worktopShift).first ?? 0,
                    plinthHeight: arr.map { $0.type == .wall ? 0 : $0.plinth }.max() ?? 0,
                    preview: arr.allSatisfy { $0.preview == true }
                ))
            }

            for c in sorted {
                guard let prev = current.last else { current.append(c); continue }
                let axis: (Cabinet) -> Double = { alongZ ? $0.z : $0.x }
                let gap = axis(c) - c.width / 2 - (axis(prev) + prev.width / 2)
                if abs(gap) <= tolerance { current.append(c) } else { flush(current); current = [c] }
            }
            flush(current)
        }
        return runs
    }

    /// Jeden blat na bieg, łączony automatycznie z sąsiednimi.
    public static func worktops(_ runs: [Run], _ p: WorktopParams = WorktopParams()) -> [Box] {
        guard p.enabled else { return [] }
        return runs.filter(\.hasBase).map { r in
            let rad = r.rotation * .pi / 180
            let shift = r.worktopShift
            return Box(
                id: "\(r.id):worktop",
                role: .worktop,
                cabinetID: r.cabinetIDs.first,
                size: SIMD3(r.length + p.overhang * 2, p.thickness, r.worktopDepth ?? 580),
                position: SIMD3(r.cx + shift * sin(rad), r.bodyTop + p.thickness / 2,
                                r.cz + shift * cos(rad)),
                color: p.color,
                rotationY: r.rotation,
                preview: r.preview
            )
        }
    }

    /// Cokół liczony na bieg (cofnięty o `setback`).
    public static func plinths(_ runs: [Run], _ p: PlinthParams = PlinthParams()) -> [Box] {
        guard p.enabled else { return [] }
        return runs.filter { $0.hasBase && $0.plinthHeight > 0 }.map { r in
            let h = r.plinthHeight
            return Box(
                id: "\(r.id):plinth",
                role: .plinth,
                cabinetID: r.cabinetIDs.first,
                size: SIMD3(r.length, h, 540 - p.setback),
                position: SIMD3(r.cx, h / 2, r.cz + p.setback / 2),
                color: p.color,
                rotationY: r.rotation,
                preview: r.preview
            )
        }
    }

    /// Miękki cień kontaktowy pod biegiem (trzy warstwy o malejącym kryciu).
    public static func contactShadows(_ runs: [Run]) -> [Box] {
        var out: [Box] = []
        let layers: [(grow: Double, y: Double)] = [(10, 6), (45, 4), (105, 2)]
        for r in runs {
            for (i, l) in layers.enumerated() {
                out.append(Box(
                    id: "\(r.id):shadow-\(i)",
                    role: .scene,
                    cabinetID: r.cabinetIDs.first,
                    size: SIMD3(r.length + l.grow * 2, 2, 620 + l.grow * 2),
                    position: SIMD3(r.cx, l.y, r.cz),
                    color: "#000000",
                    rotationY: r.rotation
                ))
            }
        }
        return out
    }
}
