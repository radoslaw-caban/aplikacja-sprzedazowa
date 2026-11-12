import Foundation

/// Wkłady do szuflad: maty, stojaki na talerze, segregatory sztućców, organizery
/// kubków/szkłanek, blach, słoików i butelek.
///
/// Wszystkie wymiary w **milimetrach**, zgodne z realnymi szufladami Blum
/// LEGRABOX (światło wewnętrzne = szerokość szafki − 42 mm, głębokość − 60 mm).
/// Katalog jest danymi, nie kodem UI: te same wpisy rysuje 3D i pokazuje panel.
public enum DrawerInsertKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case mat
    case plateRack
    case cutleryTray
    case cupOrganizer
    case glassOrganizer
    case bakingTrayHolder
    case jarHolder
    case bottleRack
    case lidRack

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mat: "Mata antypoślizgowa"
        case .plateRack: "Stojak na talerze"
        case .cutleryTray: "Segregator sztućców"
        case .cupOrganizer: "Organizer kubków"
        case .glassOrganizer: "Organizer szklanek"
        case .bakingTrayHolder: "Stojak na blachy"
        case .jarHolder: "Organizer słoików"
        case .bottleRack: "Stojak na butelki"
        case .lidRack: "Wkład na pokrywki"
        }
    }

    public var symbol: String {
        switch self {
        case .mat: "rectangle.inset.filled"
        case .plateRack: "circle.grid.2x2"
        case .cutleryTray: "fork.knife"
        case .cupOrganizer: "cup.and.saucer"
        case .glassOrganizer: "wineglass"
        case .bakingTrayHolder: "square.stack.3d.up"
        case .jarHolder: "cylinder.split.1x2"
        case .bottleRack: "waterbottle"
        case .lidRack: "circle.dashed"
        }
    }
}

/// Jeden wkład: albo na wymiar (`width == 0` = mata cięta), albo stały moduł.
public struct DrawerInsert: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var kind: DrawerInsertKind
    /// szerokość wkładu (mm); 0 = cięty na wymiar szuflady
    public var width: Double
    /// głębokość wkładu (mm); 0 = cięty na wymiar
    public var depth: Double
    /// wysokość nad dnem szuflady (mm)
    public var height: Double
    /// siatka przegród: kolumny × rzędy (0 = brak przegród)
    public var columns: Int
    public var rows: Int
    /// kolor w hex — tworzywo / drewno / filc
    public var colorHex: String
    public var note: String

    public init(id: String, kind: DrawerInsertKind, width: Double, depth: Double, height: Double,
                columns: Int = 0, rows: Int = 0, colorHex: String, note: String = "") {
        self.id = id
        self.kind = kind
        self.width = width
        self.depth = depth
        self.height = height
        self.columns = columns
        self.rows = rows
        self.colorHex = colorHex
        self.note = note
    }

    /// Czy wkład mieści się w świetle szuflady (szerokość/głębokość/wysokość).
    public func fits(innerWidth: Double, innerDepth: Double, innerHeight: Double) -> Bool {
        guard height <= innerHeight + 1 else { return false }
        if width == 0 || depth == 0 { return true }        // cięty na wymiar
        return width <= innerWidth + 1 && depth <= innerDepth + 1
    }

    /// Rzeczywista szerokość po dopasowaniu (mata rozciąga się na całe światło).
    public func fittedWidth(innerWidth: Double) -> Double { width == 0 ? innerWidth : min(width, innerWidth) }
    public func fittedDepth(innerDepth: Double) -> Double { depth == 0 ? innerDepth : min(depth, innerDepth) }
}

public enum DrawerInsertCatalog {
    /// Światło wewnętrzne szuflady LEGRABOX dla szafki `width`.
    public static func innerWidth(cabinetWidth: Double) -> Double { max(180, cabinetWidth - 42) }
    public static func innerDepth(cabinetDepth: Double) -> Double { max(200, cabinetDepth - 60) }
    /// Wysokość użytkowa nad dnem: front minus dno puszki i luz prowadnicy.
    /// LEGRABOX: N (66,5) → ~54 mm, M (90,5) → ~78 mm, K (128,5) → ~116 mm.
    public static func innerHeight(drawerFrontHeight: Double) -> Double { max(40, drawerFrontHeight - 12) }

    /// Katalog: moduły 300/400/500 mm, głębokość 422 mm (standard 450/500),
    /// wysokości dopasowane do systemów N/M/K (66,5 / 90,5 / 128,5 mm).
    public static let all: [DrawerInsert] = [
        DrawerInsert(id: "mat-450", kind: .mat, width: 0, depth: 0, height: 2,
                     colorHex: "#4a4f57",
                     note: "Filc 2 mm, cięty na światło szuflady — wygłusza i chroni naczynia"),

        DrawerInsert(id: "plates-300", kind: .plateRack, width: 300, depth: 422, height: 110,
                     columns: 8, rows: 1, colorHex: "#c9c3b4",
                     note: "8 slotów, talerze stoją pionowo — do szuflady K"),
        DrawerInsert(id: "plates-400", kind: .plateRack, width: 400, depth: 422, height: 110,
                     columns: 10, rows: 1, colorHex: "#c9c3b4",
                     note: "10 slotów"),

        DrawerInsert(id: "cutlery-300", kind: .cutleryTray, width: 300, depth: 422, height: 45,
                     columns: 5, rows: 1, colorHex: "#b9a88c",
                     note: "5 przegród: noże, widelce, łyżki, łyżeczki, drobne — do N/M"),
        DrawerInsert(id: "cutlery-400", kind: .cutleryTray, width: 400, depth: 422, height: 45,
                     columns: 6, rows: 2, colorHex: "#b9a88c",
                     note: "6 × 2 przegrody z miejscem na sztućce drewniane"),

        DrawerInsert(id: "cups-400", kind: .cupOrganizer, width: 400, depth: 422, height: 90,
                     columns: 3, rows: 2, colorHex: "#d9d2c4",
                     note: "6 kieszeni 130 × 200 mm — kubki i małe miseczki"),
        DrawerInsert(id: "glasses-400", kind: .glassOrganizer, width: 400, depth: 422, height: 110,
                     columns: 3, rows: 2, colorHex: "#d9d2c4",
                     note: "6 kieszeni z przekładkami — szklanki do 100 mm"),

        DrawerInsert(id: "baking-300", kind: .bakingTrayHolder, width: 300, depth: 422, height: 180,
                     columns: 6, rows: 1, colorHex: "#8f8a80",
                     note: "6 pionowych slotów na blachy i formy — do słupka 300"),
        DrawerInsert(id: "jars-400", kind: .jarHolder, width: 400, depth: 422, height: 120,
                     columns: 3, rows: 2, colorHex: "#cfc7b6",
                     note: "6 gniazd na słoiki 90 mm"),
        DrawerInsert(id: "bottles-300", kind: .bottleRack, width: 300, depth: 422, height: 100,
                     columns: 4, rows: 1, colorHex: "#8a7f6d",
                     note: "4 gniazda na butelki 85 mm, leżące"),
        DrawerInsert(id: "lids-300", kind: .lidRack, width: 300, depth: 422, height: 90,
                     columns: 5, rows: 1, colorHex: "#b0b4bb",
                     note: "5 slotów na pokrywki i deski"),
    ]

    public static func insert(id: String?) -> DrawerInsert? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Wszystkie wkłady, które wejdą w daną szufladę.
    public static func available(cabinetWidth: Double, cabinetDepth: Double, drawerFrontHeight: Double) -> [DrawerInsert] {
        let w = innerWidth(cabinetWidth: cabinetWidth)
        let d = innerDepth(cabinetDepth: cabinetDepth)
        let h = innerHeight(drawerFrontHeight: drawerFrontHeight)
        return all.filter { $0.fits(innerWidth: w, innerDepth: d, innerHeight: h) }
    }

    /// Najlepszy domyślny wkład dla asortymentu (np. talerze → stojak na talerze).
    public static func suggested(for storage: StorageKind?,
                                 cabinetWidth: Double, cabinetDepth: Double,
                                 drawerFrontHeight: Double) -> DrawerInsert? {
        guard let storage else { return nil }
        let kind: DrawerInsertKind
        switch storage {
        case .plates: kind = .plateRack
        case .cups: kind = .cupOrganizer
        case .cutlery: kind = .cutleryTray
        case .bottles: kind = .bottleRack
        case .food: kind = .jarHolder
        default: kind = .mat
        }
        let candidates = available(cabinetWidth: cabinetWidth, cabinetDepth: cabinetDepth,
                                   drawerFrontHeight: drawerFrontHeight)
        // najszerszy, który się mieści — lepiej wykorzystuje szufladę
        return candidates.filter { $0.kind == kind }.max { $0.width < $1.width }
            ?? candidates.first { $0.kind == .mat }
    }
}
