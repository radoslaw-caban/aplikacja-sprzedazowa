import Foundation

/// Co będzie przechowywane w półce/szufladzie. Wysokość zalecana jest
/// produkcyjna (mm) — dobiera się automatycznie po wyborze asortymentu.
public enum StorageKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case plates
    case cups
    case pots
    case cutlery
    case bottles
    case food
    case bread
    case towels
    case cosmetics
    case clothes
    case shoes
    case books
    case electronics
    case cleaning
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .plates: "Talerze"
        case .cups: "Kubki i szklanki"
        case .pots: "Garnki i patelnie"
        case .cutlery: "Sztućce"
        case .bottles: "Butelki"
        case .food: "Produkty spożywcze"
        case .bread: "Pieczywo"
        case .towels: "Ręczniki"
        case .cosmetics: "Kosmetyki"
        case .clothes: "Ubrania"
        case .shoes: "Buty"
        case .books: "Książki"
        case .electronics: "Sprzęt RTV"
        case .cleaning: "Środki czystości"
        case .other: "Inne"
        }
    }

    public var symbol: String {
        switch self {
        case .plates: "circle.grid.3x3"
        case .cups: "cup.and.saucer"
        case .pots: "frying.pan"
        case .cutlery: "fork.knife"
        case .bottles: "waterbottle"
        case .food: "cart"
        case .bread: "bag"
        case .towels: "square.stack.3d.up"
        case .cosmetics: "drop"
        case .clothes: "tshirt"
        case .shoes: "shoe"
        case .books: "books.vertical"
        case .electronics: "tv"
        case .cleaning: "spray.and.wipe"
        case .other: "shippingbox"
        }
    }

    /// Zalecana wysokość wnętrza (światło między półkami).
    public var recommendedHeight: Double {
        switch self {
        case .plates: 300
        case .cups: 200
        case .pots: 350
        case .cutlery: 90
        case .bottles: 350
        case .food: 300
        case .bread: 220
        case .towels: 300
        case .cosmetics: 220
        case .clothes: 1100
        case .shoes: 200
        case .books: 320
        case .electronics: 280
        case .cleaning: 400
        case .other: 280
        }
    }

    /// Szuflady mają mniejszą wysokość niż półki — dobieramy system Blum.
    public var drawerSystem: DrawerSystem {
        switch self {
        case .cutlery: .n
        case .cosmetics: .m
        case .towels: .m
        case .shoes: .k
        default: .k
        }
    }
}

/// Przeznaczenie szafki — wpływa na nazwę i podpowiedzi wyposażenia,
/// nie zmienia wymiarów produkcji.
public enum CabinetPurpose: String, Codable, CaseIterable, Sendable, Identifiable {
    case cooking
    case cleaning
    case tallStorage
    case island
    case wardrobe
    case living
    case bathroom
    case general

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cooking: "Strefa gotowania"
        case .cleaning: "Strefa czystości / zlew"
        case .tallStorage: "Wysoka zabudowa"
        case .island: "Wyspa"
        case .wardrobe: "Garderoba / szafa"
        case .living: "RTV i salon"
        case .bathroom: "Łazienka"
        case .general: "Przechowywanie"
        }
    }

    public var symbol: String {
        switch self {
        case .cooking: "flame"
        case .cleaning: "drop"
        case .tallStorage: "cabinet"
        case .island: "square.split.2x1"
        case .wardrobe: "tshirt"
        case .living: "tv"
        case .bathroom: "shower"
        case .general: "shippingbox"
        }
    }
}
