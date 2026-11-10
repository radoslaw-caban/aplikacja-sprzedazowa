import Foundation

/// Biblioteka szablonów — realne wymiary produkcyjne, nie wymyślone.
public enum Library {

    public struct Template: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let type: CabinetType
        public let width: Double
        public let height: Double
        public let depth: Double
        public let drawers: [DrawerSystem]
        public let shelves: Int

        public var summary: String {
            "\(Int(width)) × \(Int(height)) × \(Int(depth)) mm"
        }
    }

    public static let base: [Template] = [
        Template(id: "base-600-1f", name: "Dolna 600 / 1 front", type: .base, width: 600, height: 720, depth: 560, drawers: [], shelves: 1),
        Template(id: "base-600-3d", name: "Dolna 600 / 3 szuflady", type: .base, width: 600, height: 720, depth: 560, drawers: [.m, .m, .m], shelves: 0),
        Template(id: "base-800-1f", name: "Dolna 800 / 1 front", type: .base, width: 800, height: 720, depth: 560, drawers: [], shelves: 1),
        Template(id: "base-sink-600", name: "Pod umywalkę 600", type: .base, width: 600, height: 720, depth: 500, drawers: [], shelves: 0),
        Template(id: "base-300", name: "Dolna 300 (wąska)", type: .base, width: 300, height: 720, depth: 560, drawers: [], shelves: 2),
    ]

    public static let wall: [Template] = [
        Template(id: "wall-600", name: "Wisząca 600", type: .wall, width: 600, height: 720, depth: 350, drawers: [], shelves: 1),
        Template(id: "wall-600-filler", name: "Wisząca 600 + zaślepka", type: .wall, width: 600, height: 960, depth: 350, drawers: [], shelves: 1),
        Template(id: "wall-400", name: "Wisząca 400", type: .wall, width: 400, height: 720, depth: 350, drawers: [], shelves: 1),
    ]

    public static let tall: [Template] = [
        Template(id: "tall-600", name: "Stojąca 600", type: .tall, width: 600, height: 2016, depth: 560, drawers: [], shelves: 4),
        Template(id: "tall-450", name: "Stojąca 450", type: .tall, width: 450, height: 2016, depth: 560, drawers: [], shelves: 4),
    ]

    public static var all: [Template] { base + wall + tall }

    /// Tworzy szafkę z szablonu, z wyposażeniem rozłożonym wg systemu szuflad.
    public static func make(_ t: Template, at x: Double = 0, z: Double = 0) -> Cabinet {
        var elements: [CabinetElement] = []
        var y: Double = 0
        for d in t.drawers {
            elements.append(CabinetElement(kind: .drawer, y: y, height: d.frontHeight, drawer: d))
            y += d.frontHeight
        }
        if t.shelves > 0 {
            let bodyH = t.type == .base ? t.height - Standards.plinthHeight : t.height
            let step = (bodyH - y) / Double(t.shelves + 1)
            for i in 1...t.shelves {
                elements.append(CabinetElement(kind: .shelf, y: y + step * Double(i), height: Standards.panel))
            }
        }
        return Cabinet(
            name: t.name,
            type: t.type,
            width: t.width,
            height: t.height,
            depth: t.depth,
            plinth: t.type == .wall ? 0 : Standards.plinthHeight,
            x: x,
            z: z,
            mountHeight: t.type == .wall ? 1500 : 0,
            elements: elements
        )
    }
}
