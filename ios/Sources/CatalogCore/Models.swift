import Foundation

// MARK: - Producent

/// Producent / hurtownia dodająca produkty do katalogu.
/// Logo jest plikiem obok wpisu — w kafelkach pokazujemy **oficjalne** logo,
/// dlatego jego użycie musi być zatwierdzone prawnie (`trademarkApproved`).
public struct Manufacturer: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    /// nazwa pliku logo w `manufacturers/` (PNG/SVG/PDF)
    public var logoFile: String?
    /// strona producenta — do weryfikacji pochodzenia danych
    public var website: String?
    /// czy zgoda na używanie znaku w katalogu jest potwierdzona (umowa/aneks)
    public var trademarkApproved: Bool
    public var note: String

    public init(id: String, name: String, logoFile: String? = nil,
                website: String? = nil, trademarkApproved: Bool = false, note: String = "") {
        self.id = id
        self.name = name
        self.logoFile = logoFile
        self.website = website
        self.trademarkApproved = trademarkApproved
        self.note = note
    }
}

// MARK: - Produkt

public enum ProductCategory: String, Codable, CaseIterable, Sendable {
    case sink, faucet, hob, oven, microwave, fridge, dishwasher, hood
    case cabinet, worktop, plinth, lighting, accessory, appliance, other

    public var label: String {
        switch self {
        case .sink: "Zlew"
        case .faucet: "Bateria"
        case .hob: "Płyta grzewcza"
        case .oven: "Piekarnik"
        case .microwave: "Mikrofala"
        case .fridge: "Lodówka"
        case .dishwasher: "Zmywarka"
        case .hood: "Okap"
        case .cabinet: "Szafka"
        case .worktop: "Blat"
        case .plinth: "Cokół"
        case .lighting: "Oświetlenie"
        case .accessory: "Akcesorium"
        case .appliance: "Sprzęt"
        case .other: "Inne"
        }
    }
}

/// Podstawa prawna geometrii — decyduje, czy produkt może wejść do biblioteki.
public enum LegalBasis: String, Codable, CaseIterable, Sendable {
    /// geometria wytworzona z wymiarów i dokumentacji technicznej (nasza praca)
    case ownGeometryFromDocs
    /// model dostarczony przez producenta na podstawie umowy
    case manufacturerSupplied
    /// licencja na pliki (np. CC0) — sprawdzić zakres redystrybucji
    case licensedAsset
    /// nieustalone — nie może być zatwierdzone
    case unknown

    public var label: String {
        switch self {
        case .ownGeometryFromDocs: "Geometria własna z dokumentacji"
        case .manufacturerSupplied: "Model od producenta (umowa)"
        case .licensedAsset: "Licencja na pliki (CC0/inna)"
        case .unknown: "Nieustalona"
        }
    }
}

/// Ryzyko naruszenia wzoru przemysłowego.
public enum DesignRisk: String, Codable, CaseIterable, Sendable, Comparable {
    case low, medium, high

    public var label: String {
        switch self {
        case .low: "Niskie (wygląd funkcjonalny)"
        case .medium: "Średnie (produkt markowy, zwykła bryła)"
        case .high: "Wysokie (wzór/ikona designu)"
        }
    }

    private var order: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: DesignRisk, rhs: DesignRisk) -> Bool { lhs.order < rhs.order }
}

/// Dokument potwierdzający pochodzenie danych (karta katalogowa, rysunek, umowa).
public struct Provenance: Codable, Sendable, Equatable {
    /// np. "Karta produktu DEANTE Arnika, wersja 2026-03, PDF"
    public var document: String
    /// gdzie leży oryginał (ścieżka/URL) — dowód przy sporze o wzór
    public var reference: String
    public var retrievedAt: Date

    public init(document: String, reference: String, retrievedAt: Date = Date()) {
        self.document = document
        self.reference = reference
        self.retrievedAt = retrievedAt
    }
}

public struct LegalRecord: Codable, Sendable, Equatable {
    public var basis: LegalBasis
    public var designRisk: DesignRisk
    public var provenance: Provenance?
    /// czy producent zgodził się na użycie nazwy/logo w katalogu
    public var trademarkUseApproved: Bool
    /// notatka prawnika / nasza decyzja przy ryzyku wysokim
    public var note: String

    public init(basis: LegalBasis = .unknown, designRisk: DesignRisk = .medium,
                provenance: Provenance? = nil, trademarkUseApproved: Bool = false, note: String = "") {
        self.basis = basis
        self.designRisk = designRisk
        self.provenance = provenance
        self.trademarkUseApproved = trademarkUseApproved
        self.note = note
    }
}

/// Ceny w groszach — bez błędów zaokrągleń.
public struct Pricing: Codable, Sendable, Equatable {
    public var costGrosze: Int
    public var marginPercent: Double
    /// cena po marży, zaokrąglona do pełnych groszy
    public var retailGrosze: Int {
        Int((Double(costGrosze) * (1 + marginPercent / 100)).rounded())
    }
    public var currency: String

    public init(costGrosze: Int, marginPercent: Double, currency: String = "PLN") {
        self.costGrosze = costGrosze
        self.marginPercent = marginPercent
        self.currency = currency
    }

    public var costText: String { Self.money(costGrosze, currency) }
    public var retailText: String { Self.money(retailGrosze, currency) }

    public static func money(_ grosze: Int, _ currency: String) -> String {
        let sign = grosze < 0 ? "-" : ""
        let abs = Swift.abs(grosze)
        let zł = abs / 100, gr = abs % 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        let whole = formatter.string(from: NSNumber(value: zł)) ?? "\(zł)"
        return "\(sign)\(whole),\(String(format: "%02d", gr)) \(currency)"
    }
}

public enum ProductStatus: String, Codable, CaseIterable, Sendable {
    /// dodany przez producenta, jeszcze nie zgłoszony
    case draft
    /// zgłoszony do nas — czeka na marżę i kontrolę prawną
    case submitted
    /// zatwierdzony — wchodzi do oficjalnej biblioteki
    case approved
    /// odrzucony (z powodem)
    case rejected

    public var label: String {
        switch self {
        case .draft: "Szkic"
        case .submitted: "Do zatwierdzenia"
        case .approved: "W bibliotece"
        case .rejected: "Odrzucony"
        }
    }
}

public struct AssetFile: Codable, Sendable, Equatable, Hashable {
    /// ścieżka względna w katalogu produktu, np. "assets/model.glb"
    public var path: String
    public var kind: Kind
    public var bytes: Int
    public var sha256: String?

    public enum Kind: String, Codable, Sendable {
        case model       // GLB/USDZ/OBJ/STL
        case texture
        case document    // karta PDF, rysunek
        case logo
        case thumbnail
    }

    public init(path: String, kind: Kind, bytes: Int = 0, sha256: String? = nil) {
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// Wpis w katalogu — jeden produkt.
public struct CatalogProduct: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var sku: String
    public var name: String
    public var manufacturerID: String
    public var category: ProductCategory
    /// wymiary gabarytowe w mm (0 = nieznane)
    public var width: Double
    public var depth: Double
    public var height: Double

    public var assets: [AssetFile]
    /// plik miniatury (PNG) — kafelki w bibliotece
    public var thumbnail: String?
    public var legal: LegalRecord
    public var pricing: Pricing
    public var status: ProductStatus
    /// opis zależności: co ten produkt robi z innymi obiektami
    public var dependencies: [DependencyRule]
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    /// kto i kiedy zatwierdził/odrzucił
    public var decision: Decision?

    public struct Decision: Codable, Sendable, Equatable {
        public var by: String
        public var at: Date
        public var reason: String
        public init(by: String, at: Date = Date(), reason: String = "") {
            self.by = by
            self.at = at
            self.reason = reason
        }
    }

    public init(id: String, sku: String, name: String, manufacturerID: String,
                category: ProductCategory, width: Double = 0, depth: Double = 0, height: Double = 0,
                assets: [AssetFile] = [], thumbnail: String? = nil,
                legal: LegalRecord = LegalRecord(),
                pricing: Pricing = Pricing(costGrosze: 0, marginPercent: 0),
                status: ProductStatus = .draft,
                dependencies: [DependencyRule] = [], tags: [String] = [],
                createdAt: Date = Date(), updatedAt: Date = Date(), decision: Decision? = nil) {
        self.id = id
        self.sku = sku
        self.name = name
        self.manufacturerID = manufacturerID
        self.category = category
        self.width = width
        self.depth = depth
        self.height = height
        self.assets = assets
        self.thumbnail = thumbnail
        self.legal = legal
        self.pricing = pricing
        self.status = status
        self.dependencies = dependencies
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.decision = decision
    }

    public var modelAsset: AssetFile? { assets.first { $0.kind == .model } }

    /// Czy produkt jest kompletny wizualnie: model + miniatura + logo producenta.
    public var isPresentable: Bool { modelAsset != nil && thumbnail != nil }
}
