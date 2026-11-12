import Foundation

/// Rodzaj zawiasu — wpływa na model i informację w wycenie.
public enum HingeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case softClose
    case pushOpen
    case none

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: "Standardowy (clip)"
        case .softClose: "Soft-close (Blumotion)"
        case .pushOpen: "Push-to-open (Tip-On)"
        case .none: "Bez zawiasów"
        }
    }

    public var symbol: String {
        switch self {
        case .standard: "door.left.hand.closed"
        case .softClose: "door.left.hand.open"
        case .pushOpen: "hand.tap"
        case .none: "nosign"
        }
    }
}

/// Akcesorium wnętrza szafki.
public enum CabinetAccessoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case basket
    case rail
    case cutleryTray
    case wasteBin
    case organizer
    case glassShelf
    case led

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .basket: "Kosz wyciągany"
        case .rail: "Drążek na ubrania"
        case .cutleryTray: "Organizer sztućców"
        case .wasteBin: "Kosz na odpady"
        case .organizer: "Przegrody / organizer"
        case .glassShelf: "Półka szklana"
        case .led: "Oświetlenie LED"
        }
    }

    public var symbol: String {
        switch self {
        case .basket: "basket"
        case .rail: "hanger"
        case .cutleryTray: "fork.knife"
        case .wasteBin: "trash"
        case .organizer: "square.grid.3x3"
        case .glassShelf: "rectangle.split.3x1"
        case .led: "lightbulb.led"
        }
    }

    /// Domyślna wysokość od dna korpusu (mm).
    public var defaultY: Double {
        switch self {
        case .basket: 300
        case .rail: 1700
        case .cutleryTray: 500
        case .wasteBin: 150
        case .organizer: 700
        case .glassShelf: 900
        case .led: 2100
        }
    }
}

public struct CabinetAccessory: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: CabinetAccessoryKind
    /// wysokość od dna korpusu (mm)
    public var y: Double

    public init(id: UUID = UUID(), kind: CabinetAccessoryKind, y: Double? = nil) {
        self.id = id
        self.kind = kind
        self.y = y ?? kind.defaultY
    }
}

public extension Cabinet {
    var bodyHeight: Double {
        type == .base ? max(0, height - plinth) : height
    }

    /// Ustawia liczbę półek. Szuflady zostają na dole; półki rozkładają się
    /// równo nad nimi albo według zadanego rozstawu.
    mutating func setShelfCount(_ count: Int, spacing: Double? = nil) {
        let n = max(0, min(12, count))
        let drawers = elements.filter { $0.kind == .drawer }
        let oldShelves = elements.filter { $0.kind == .shelf }.sorted { $0.y < $1.y }
        let others = elements.filter { $0.kind != .shelf && $0.kind != .drawer }

        let start = drawers.map { $0.y + $0.height }.max() ?? 0
        let available = max(120, bodyHeight - start)
        let panel = Standards.panel
        var shelves: [CabinetElement] = []

        if n > 0 {
            let gap = spacing ?? max(120, (available - panel * Double(n + 1)) / Double(n + 1))
            for i in 0..<n {
                let y = min(max(start + gap * Double(i + 1) - panel, 0), max(0, bodyHeight - panel))
                var e = CabinetElement(kind: .shelf, y: y, height: panel)
                if i < oldShelves.count {
                    e.storage = oldShelves[i].storage
                }
                shelves.append(e)
            }
        }
        elements = drawers + others + shelves
        elements.sort { $0.y < $1.y }
    }

    /// Zmienia rozstaw istniejących półek (bez zmiany ich liczby).
    mutating func setShelfSpacing(_ spacing: Double) {
        let n = elements.filter { $0.kind == .shelf }.count
        setShelfCount(n, spacing: max(120, spacing))
    }

    /// Najczęstszy rozstaw półek w szafce (mm) — do wyświetlenia w edytorze.
    var shelfSpacing: Double {
        let ys = elements.filter { $0.kind == .shelf }.map(\.y).sorted()
        guard ys.count > 1 else { return 280 }
        let diffs = zip(ys.dropFirst(), ys).map { $0 - $1 }
        return diffs.reduce(0, +) / Double(diffs.count)
    }
}
