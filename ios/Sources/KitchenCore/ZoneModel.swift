import Foundation

/// STREFY ZABUDOWY — model danych i typy wspólne.
/// Wszystkie wymiary w milimetrach, tak jak reszta KitchenCore.

public enum ApplianceKind: String, Codable, Sendable, CaseIterable {
    case sink, hob, oven, microwave, fridge, hood, dishwasher, washer, tv, mirror, basin, bin
}

/// Wartość odpowiedzi w kreatorze strefy (JSON: string / liczba / bool).
public enum ZoneValue: Codable, Sendable, Equatable {
    case text(String)
    case number(Double)
    case flag(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .flag(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        self = .text(try c.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .number(let d): try c.encode(d)
        case .flag(let b): try c.encode(b)
        }
    }

    public var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }

    public var stringValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .flag(let b) = self { return b }
        return nil
    }
}

/// Odpowiedzi strefy — słownik z dostępem typowanym (z wartościami domyślnymi).
public struct ZoneAnswers: Sendable, Equatable {
    public var values: [String: ZoneValue]

    public init(_ values: [String: ZoneValue] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> ZoneValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func number(_ key: String, _ fallback: Double) -> Double {
        values[key]?.doubleValue ?? fallback
    }

    public func text(_ key: String, _ fallback: String) -> String {
        values[key]?.stringValue ?? fallback
    }

    public func flag(_ key: String, _ fallback: Bool) -> Bool {
        values[key]?.boolValue ?? fallback
    }
}

public enum ZoneGroup: String, Codable, Sendable, CaseIterable {
    case kitchen, bedroom, living, bathroom

    public var label: String {
        switch self {
        case .kitchen: "Kuchnia"
        case .bedroom: "Sypialnia"
        case .living: "Salon"
        case .bathroom: "Łazienka"
        }
    }
}

public enum ZoneKind: String, Codable, Sendable, CaseIterable {
    case kitchenCook = "kitchen-cook"
    case kitchenClean = "kitchen-clean"
    case kitchenTall = "kitchen-tall"
    case kitchenIsland = "kitchen-island"
    case wardrobeHinged = "wardrobe-hinged"
    case wardrobeSliding = "wardrobe-sliding"
    case livingTV = "living-tv"
    case bathroom
}

/// Strefa zabudowy przypięta do ściany planu.
public struct Zone: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: ZoneKind
    /// indeks ściany w FloorPlan (0…wallCount-1)
    public var wallIndex: Int
    public var answers: [String: ZoneValue]
    public var name: String

    public init(id: UUID = UUID(), kind: ZoneKind, wallIndex: Int, answers: [String: ZoneValue], name: String) {
        self.id = id
        self.kind = kind
        self.wallIndex = wallIndex
        self.answers = answers
        self.name = name
    }

    public var typedAnswers: ZoneAnswers { ZoneAnswers(answers) }
}

public enum ZoneInterior: String, Sendable {
    case none, shelf, pantry, glass, rail
}

/// Część planu strefy — jedna szafka do wygenerowania.
public struct ZonePart: Sendable {
    public var role: String
    public var type: CabinetType
    public var width: Double
    public var height: Double
    public var depth: Double
    public var plinth: Double
    public var mountHeight: Double
    public var worktop: Bool
    public var label: String
    public var at: Double
    public var doors: Int
    public var drawers: [Double]
    public var interior: ZoneInterior
    public var appliances: [ApplianceKind]
    public var feature: String?
    public var worktopDepth: Double?
    public var worktopShift: Double?
    public var slidingPanels: Int?
}

public struct ZoneContext: Sendable {
    public var wallLength: Double
    public var wallHeight: Double
    public var roomWidth: Double
    public var roomDepth: Double

    public init(wallLength: Double, wallHeight: Double, roomWidth: Double, roomDepth: Double) {
        self.wallLength = wallLength
        self.wallHeight = wallHeight
        self.roomWidth = roomWidth
        self.roomDepth = roomDepth
    }
}

public struct ZonePlan: Sendable {
    public var parts: [ZonePart]
    public var start: Double
    public var width: Double
    public var notes: [String]
    public var warnings: [String]

    public init(parts: [ZonePart] = [], start: Double = 0, width: Double = 0,
                notes: [String] = [], warnings: [String] = []) {
        self.parts = parts
        self.start = start
        self.width = width
        self.notes = notes
        self.warnings = warnings
    }
}

// MARK: - pytania

public struct ZoneChoice: Sendable {
    public var value: ZoneValue
    public var label: String
    public var hint: String?

    public init(_ value: ZoneValue, _ label: String, hint: String? = nil) {
        self.value = value
        self.label = label
        self.hint = hint
    }
}

public enum ZoneQuestionType: String, Sendable {
    case choice, position
}

public struct ZoneQuestion: Sendable {
    public var id: String
    public var label: String
    public var help: String?
    public var type: ZoneQuestionType
    public var choices: [ZoneChoice]
    public var min: Double
    public var max: Double
    public var step: Double
    public var unit: String
    public var feature: String?
    public var placement: Bool
    /// pytanie widoczne tylko gdy wszystkie pary zgadzają się z odpowiedziami
    public var showWhen: [String: ZoneValue]?
    public var hideWhen: [String: ZoneValue]?

    public init(
        id: String, label: String, type: ZoneQuestionType = .choice,
        feature: String? = nil, help: String? = nil, choices: [ZoneChoice] = [],
        min: Double = 0, max: Double = 100, step: Double = 5, unit: String = "%",
        placement: Bool = false,
        showWhen: [String: ZoneValue]? = nil, hideWhen: [String: ZoneValue]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.help = help
        self.choices = choices
        self.min = min
        self.max = max
        self.step = step
        self.unit = unit
        self.feature = feature
        self.placement = placement
        self.showWhen = showWhen
        self.hideWhen = hideWhen
    }

    public func isActive(_ a: ZoneAnswers) -> Bool {
        if let showWhen {
            for (k, v) in showWhen where a[k] != v { return false }
        }
        if let hideWhen {
            for (k, v) in hideWhen where a[k] == v { return false }
        }
        return true
    }
}

public struct ZoneSpec: Sendable {
    public var kind: ZoneKind
    public var label: String
    public var short: String
    public var group: ZoneGroup
    public var icon: String
    public var description: String
    public var relations: [String]
    public var defaults: [String: ZoneValue]
    public var questions: [ZoneQuestion]

    public init(kind: ZoneKind, label: String, short: String, group: ZoneGroup, icon: String,
                description: String, relations: [String], defaults: [String: ZoneValue],
                questions: [ZoneQuestion]) {
        self.kind = kind
        self.label = label
        self.short = short
        self.group = group
        self.icon = icon
        self.description = description
        self.relations = relations
        self.defaults = defaults
        self.questions = questions
    }
}

// MARK: - pomocnicze

public enum ZoneMath {
    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

    public static func round50(_ v: Double) -> Double {
        (v / 50).rounded() * 50
    }

    /// Równe moduły ~600–900 mm, suma dokładnie `total`.
    public static func splitModules(_ total: Double, _ n: Int) -> [Double] {
        guard n > 0 else { return [] }
        let base = Swift.max(300, round50(total / Double(n)))
        var out = [Double](repeating: base, count: n)
        var diff = total - base * Double(n)
        var i = 0
        var guardCount = 0
        while abs(diff) >= 50, guardCount < 400 {
            let idx = i % n
            if diff > 0 {
                out[idx] += 50
                diff -= 50
            } else if out[idx] > 300 {
                out[idx] -= 50
                diff += 50
            }
            i += 1
            guardCount += 1
        }
        if diff != 0 { out[n - 1] += diff }
        return out
    }
}
