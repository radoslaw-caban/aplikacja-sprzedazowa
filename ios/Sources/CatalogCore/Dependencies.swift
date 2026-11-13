import Foundation

/// **Opis zależności**: zbiór cech produktu w stosunku do innych obiektów biblioteki.
///
/// Reguła mówi: *gdy ten produkt znajdzie się w relacji X do obiektu pasującego
/// do selektora, wywołaj efekt Y na tym obiekcie (lub na całej grupie)*.
/// Przykład: zlew postawiony nad dowolną szafką dolną robi z niej szafkę zlewową
/// (`setRole("zlewowa")`) i każe usunąć wieniec górny (`removeTopRail`).
public enum PlacementTrigger: String, Codable, CaseIterable, Sendable {
    /// produkt leży na blacie (zlew, płyta) — oddziałuje na szafki pod blatem
    case onWorktop
    /// produkt wisi nad obiektem (okap nad płytą)
    case above
    /// produkt jest wstawiony do środka obiektu (piekarnik w niszy)
    case inside
    /// produkt stoi obok obiektu (zmywarka obok szafki ze zlewem)
    case beside
    /// produkt jest w tym samym biegu zabudowy
    case inRun
    /// dowolna relacja — efekt informacyjny
    case anywhere

    public var label: String {
        switch self {
        case .onWorktop: "postawiony na blacie"
        case .above: "zawieszony nad"
        case .inside: "wstawiony do środka"
        case .beside: "ustawiony obok"
        case .inRun: "w tym samym biegu"
        case .anywhere: "w projekcie"
        }
    }
}

public struct DependencySelector: Codable, Sendable, Equatable, Hashable {
    /// puste = dowolna kategoria
    public var categories: [ProductCategory]
    /// fragment roli, np. "zlewowa" (dopasowanie bez wielkości liter i ogonków)
    public var roleContains: String?
    public var minWidth: Double?
    public var maxWidth: Double?
    public var tagsAll: [String]
    /// poziom zabudowy: dolna / wisząca / stojąca
    public var level: Level?

    public enum Level: String, Codable, Sendable, CaseIterable {
        case base, wall, tall
        public var label: String {
            switch self {
            case .base: "dolna"
            case .wall: "wisząca"
            case .tall: "stojąca"
            }
        }
    }

    public init(categories: [ProductCategory] = [], roleContains: String? = nil,
                minWidth: Double? = nil, maxWidth: Double? = nil,
                tagsAll: [String] = [], level: Level? = nil) {
        self.categories = categories
        self.roleContains = roleContains
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.tagsAll = tagsAll
        self.level = level
    }

    /// Czy obiekt pasuje do selektora.
    public func matches(_ item: PlacedItem) -> Bool {
        if !categories.isEmpty, !categories.contains(item.category) { return false }
        if let level, level != item.level { return false }
        if let roleContains, !item.role.folded.contains(roleContains.folded) { return false }
        if let minWidth, item.width < minWidth { return false }
        if let maxWidth, item.width > maxWidth { return false }
        if !tagsAll.isEmpty, !Set(tagsAll).isSubset(of: Set(item.tags.map { $0.folded })) { return false }
        return true
    }
}

/// Co reguła robi z obiektem docelowym.
public enum EffectKind: String, Codable, CaseIterable, Sendable {
    /// nadaje rolę, np. "zlewowa"
    case setRole
    /// usuwa wieniec górny (syfon, przyłącza)
    case removeTopRail
    /// wycięcie w blacie nad szafką
    case addWorktopCutout
    /// rezerwuje niszę o wymiarach (piekarnik, mikrofala)
    case reserveNiche
    /// wymaga przyłącza w szafce sąsiedniej (gniazdo, woda, odpływ)
    case requireServiceAdjacent
    /// zakazuje sąsiedztwa kategorii (np. płyta przy lodówce)
    case forbidNeighbor
    /// minimalny odstęp od innego obiektu (okap nad płytą)
    case minDistance
    /// kanał/wentylacja o średnicy
    case addVent
    /// tylko notatka dla projektanta
    case noteOnly

    public var label: String {
        switch self {
        case .setRole: "zmienia rolę"
        case .removeTopRail: "usuwa wieniec"
        case .addWorktopCutout: "wycięcie w blacie"
        case .reserveNiche: "rezerwuje niszę"
        case .requireServiceAdjacent: "przyłącze obok"
        case .forbidNeighbor: "zakaz sąsiedztwa"
        case .minDistance: "minimalny odstęp"
        case .addVent: "kanał wentylacyjny"
        case .noteOnly: "notatka"
        }
    }
}

public struct DependencyEffect: Codable, Sendable, Equatable, Hashable {
    public var kind: EffectKind
    /// rola nadawana obiektowi (dla `setRole`)
    public var role: String?
    /// wymiary wycięcia / niszy w mm
    public var width: Double?
    public var depth: Double?
    public var height: Double?
    /// odstęp / średnica w mm (dla `minDistance`, `addVent`)
    public var distance: Double?
    /// kategoria objęta zakazem/dystansem
    public var otherCategory: ProductCategory?
    public var text: String?

    public init(kind: EffectKind, role: String? = nil, width: Double? = nil,
                depth: Double? = nil, height: Double? = nil, distance: Double? = nil,
                otherCategory: ProductCategory? = nil, text: String? = nil) {
        self.kind = kind
        self.role = role
        self.width = width
        self.depth = depth
        self.height = height
        self.distance = distance
        self.otherCategory = otherCategory
        self.text = text
    }

    public var shortLabel: String {
        switch kind {
        case .setRole: "rola „\(role ?? "?")”"
        case .removeTopRail: "bez wieńca górnego"
        case .addWorktopCutout:
            "wycięcie \(mm(width))×\(mm(depth)) mm"
        case .reserveNiche:
            "nisza \(mm(width))×\(mm(height))×\(mm(depth)) mm"
        case .requireServiceAdjacent: "przyłącze w szafce obok"
        case .forbidNeighbor: "zakaz sąsiedztwa: \(otherCategory?.label ?? "?")"
        case .minDistance: "odstęp min. \(mm(distance)) mm"
        case .addVent: "kanał Ø\(mm(distance)) mm"
        case .noteOnly: text ?? "notatka"
        }
    }

    private func mm(_ value: Double?) -> String {
        guard let value else { return "?" }
        return String(Int(value.rounded()))
    }
}

public struct DependencyRule: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var trigger: PlacementTrigger
    public var target: DependencySelector
    public var effects: [DependencyEffect]
    /// twarda reguła produkcyjna (nie da się zignorować) vs podpowiedź
    public var hard: Bool
    public var note: String

    public init(id: String = UUID().uuidString, trigger: PlacementTrigger,
                target: DependencySelector, effects: [DependencyEffect],
                hard: Bool = true, note: String = "") {
        self.id = id
        self.trigger = trigger
        self.target = target
        self.effects = effects
        self.hard = hard
        self.note = note
    }

    public var title: String {
        let what = target.categories.isEmpty
            ? "dowolny obiekt"
            : target.categories.map { $0.label }.joined(separator: "/")
        let role = target.roleContains.map { " „\($0)”" } ?? ""
        return "\(trigger.label.capitalized) \(what)\(role): "
            + effects.map { $0.shortLabel }.joined(separator: ", ")
    }
}

/// Obiekt już wstawiony do projektu — do sprawdzania zależności.
public struct PlacedItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var category: ProductCategory
    public var role: String
    public var width: Double
    public var depth: Double
    public var height: Double
    public var level: DependencySelector.Level
    public var tags: [String]
    public var x: Double
    public var z: Double

    public init(id: String = UUID().uuidString, category: ProductCategory, role: String = "",
                width: Double = 0, depth: Double = 0, height: Double = 0,
                level: DependencySelector.Level = .base, tags: [String] = [],
                x: Double = 0, z: Double = 0) {
        self.id = id
        self.category = category
        self.role = role
        self.width = width
        self.depth = depth
        self.height = height
        self.level = level
        self.tags = tags
        self.x = x
        self.z = z
    }

    /// Obiekt po zastosowaniu efektu (rola/wieniec).
    public func applying(_ effect: DependencyEffect) -> PlacedItem {
        var copy = self
        if effect.kind == .setRole, let role = effect.role {
            copy.role = role
        }
        return copy
    }
}

public struct ResolvedEffect: Sendable, Equatable, Identifiable {
    public var id: String { "\(ruleID)-\(targetID)-\(effect.kind.rawValue)" }
    public var ruleID: String
    public var ruleTitle: String
    public var targetID: String
    public var targetName: String
    public var effect: DependencyEffect
    public var hard: Bool
    public var explanation: String
}

/// Silnik zależności — czysta logika, bez UI i bez sceny.
public enum DependencyEngine {
    /// Zastosuj reguły produktu do obiektów w projekcie.
    /// - Returns: efekty do wykonania (każdy wskazuje obiekt docelowy).
    public static func resolve(product: CatalogProduct,
                               placed: [PlacedItem],
                               trigger: PlacementTrigger? = nil) -> [ResolvedEffect] {
        var out: [ResolvedEffect] = []
        for rule in product.dependencies {
            if let trigger, rule.trigger != trigger { continue }
            for item in placed where rule.target.matches(item) {
                // produkt nie oddziałuje sam na siebie
                guard item.id != product.id else { continue }
                for effect in rule.effects {
                    out.append(ResolvedEffect(
                        ruleID: rule.id,
                        ruleTitle: rule.title,
                        targetID: item.id,
                        targetName: "\(item.category.label) \(Int(item.width)) mm" + (item.role.isEmpty ? "" : " (\(item.role))"),
                        effect: effect,
                        hard: rule.hard,
                        explanation: explain(product: product, item: item, rule: rule, effect: effect)
                    ))
                }
            }
        }
        return out
    }

    /// Zastosuj wszystkie reguły (kilku produktów) i zwróć nowy stan projektu.
    public static func apply(products: [CatalogProduct], to placed: [PlacedItem]) -> [PlacedItem] {
        var state = placed
        for product in products {
            let effects = resolve(product: product, placed: state)
            for resolved in effects {
                guard let index = state.firstIndex(where: { $0.id == resolved.targetID }) else { continue }
                state[index] = state[index].applying(resolved.effect)
            }
        }
        return state
    }

    private static func explain(product: CatalogProduct, item: PlacedItem,
                                rule: DependencyRule, effect: DependencyEffect) -> String {
        switch effect.kind {
        case .setRole:
            return "\(product.name) \(rule.trigger.label) — \(item.category.label) dostaje rolę „\(effect.role ?? "")”"
        case .removeTopRail:
            return "\(product.name): potrzebny syfon i przyłącza, więc korpus bez wieńca górnego"
        case .addWorktopCutout:
            return "\(product.name): wycięcie w blacie pod urządzenie"
        case .reserveNiche:
            return "\(product.name): nisza w zabudowie — urządzenie nie może stać na wieńcu"
        case .requireServiceAdjacent:
            return "\(product.name): przyłącze (woda/prąd/odpływ) w szafce sąsiedniej, nie za urządzeniem"
        case .forbidNeighbor:
            return "\(product.name): nie może sąsiadować z \(effect.otherCategory?.label ?? "tym obiektem")"
        case .minDistance:
            return "\(product.name): zachowaj \(Int((effect.distance ?? 0).rounded())) mm odstępu"
        case .addVent:
            return "\(product.name): kanał Ø\(Int((effect.distance ?? 0).rounded())) mm, nie przez wieniec górny"
        case .noteOnly:
            return effect.text ?? "notatka technologiczna"
        }
    }
}

/// Domyślne reguły dla typowych produktów — zgodne z regułami produkcji.
public enum DependencyLibrary {
    public static func defaultRules(for category: ProductCategory) -> [DependencyRule] {
        switch category {
        case .sink:
            return [
                DependencyRule(
                    id: "sink-above-cabinet",
                    trigger: .onWorktop,
                    target: DependencySelector(categories: [.cabinet], level: .base),
                    effects: [
                        DependencyEffect(kind: .setRole, role: "zlewowa"),
                        DependencyEffect(kind: .removeTopRail,
                                         text: "syfon i przyłącza — bez wieńca górnego"),
                        DependencyEffect(kind: .reserveNiche, width: 500, depth: 400, height: 500,
                                         text: "miejsce na syfon"),
                    ],
                    note: "Zlew nad szafką: szafka zlewowa bez wieńca górnego, z pionową łatą."
                )
            ]
        case .hob:
            return [
                DependencyRule(
                    id: "hob-cutout",
                    trigger: .onWorktop,
                    target: DependencySelector(categories: [.worktop]),
                    effects: [
                        DependencyEffect(kind: .addWorktopCutout, width: 560, depth: 490,
                                         text: "wycięcie pod płytę"),
                    ],
                    note: "Płyta grzewcza: wycięcie w blacie, wentylacja, odstęp od okapu."
                ),
                DependencyRule(
                    id: "hob-not-beside-fridge",
                    trigger: .beside,
                    target: DependencySelector(categories: [.fridge]),
                    effects: [
                        DependencyEffect(kind: .minDistance, distance: 150,
                                         otherCategory: .fridge,
                                         text: "płyta grzewcza obok lodówki: odstęp i ekran cieplny"),
                    ],
                    hard: false,
                    note: "Zalecenie: nie stawiać płyty bezpośrednio przy lodówce."
                )
            ]
        case .oven, .microwave:
            return [
                DependencyRule(
                    id: "oven-niche",
                    trigger: .inside,
                    target: DependencySelector(categories: [.cabinet]),
                    effects: [
                        DependencyEffect(kind: .reserveNiche, width: 560, depth: 560, height: 600,
                                         text: "nisza 600 mm pod piekarnik"),
                        DependencyEffect(kind: .requireServiceAdjacent,
                                         text: "gniazdo w szafce sąsiedniej"),
                    ],
                    note: "Piekarnik: nisza 600, zasilanie w sąsiedniej szafce."
                )
            ]
        case .dishwasher:
            return [
                DependencyRule(
                    id: "dishwasher-service",
                    trigger: .beside,
                    target: DependencySelector(categories: [.cabinet], level: .base),
                    effects: [
                        DependencyEffect(kind: .requireServiceAdjacent,
                                         text: "woda i odpływ w szafce sąsiedniej"),
                        DependencyEffect(kind: .noteOnly,
                                         text: "blat nad zmywarką uszczelniony, bez łączenia płyty nad urządzeniem"),
                    ],
                    note: "Zmywarka: przyłącza w sąsiedniej szafce, blat uszczelniony."
                )
            ]
        case .hood:
            return [
                DependencyRule(
                    id: "hood-above-hob",
                    trigger: .above,
                    target: DependencySelector(categories: [.hob]),
                    effects: [
                        DependencyEffect(kind: .minDistance, distance: 650,
                                         text: "min. 650 mm nad płytą gazową"),
                        DependencyEffect(kind: .addVent, distance: 150,
                                         text: "kanał Ø150"),
                    ],
                    note: "Okap: 650 mm nad płytą, kanał Ø150 poza wieńcem."
                )
            ]
        case .fridge:
            return [
                DependencyRule(
                    id: "fridge-vent",
                    trigger: .anywhere,
                    target: DependencySelector(categories: [.cabinet]),
                    effects: [
                        DependencyEffect(kind: .noteOnly,
                                         text: "szczelina wentylacyjna 50 mm i luz na otwieranie drzwi"),
                    ],
                    hard: false
                )
            ]
        default:
            return []
        }
    }

    /// Wszystkie kategorie, dla których mamy gotowe reguły.
    public static var coveredCategories: [ProductCategory] {
        ProductCategory.allCases.filter { !defaultRules(for: $0).isEmpty }
    }
}

extension String {
    /// porównywanie bez wielkości liter i polskich ogonków
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
    }
}
