import Foundation

/// Kontrola przed wejściem produktu do oficjalnej biblioteki.
///
/// Zasada: **producent dodaje, my nadajemy marżę i sprawdzamy legalność**.
/// Moduł nie pozwala zatwierdzić produktu, którego podstawa prawna jest
/// nieustalona, bez udokumentowanego pochodzenia wymiarów albo bez zgody
/// na pokazanie logo producenta (kafelek zawsze pokazuje logo).
public struct ReviewBlocker: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable {
        case blocking
        case warning
    }
    public var id: String { code }
    public var code: String
    public var message: String
    public var severity: Severity

    public init(code: String, message: String, severity: Severity) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct ReviewReport: Sendable, Equatable {
    public var blockers: [ReviewBlocker]
    public var productID: String

    public var canApprove: Bool { !blockers.contains { $0.severity == .blocking } }
    public var blocking: [ReviewBlocker] { blockers.filter { $0.severity == .blocking } }
    public var warnings: [ReviewBlocker] { blockers.filter { $0.severity == .warning } }
    public var summary: String {
        if canApprove && warnings.isEmpty { return "Gotowy do zatwierdzenia" }
        var parts: [String] = []
        if !blocking.isEmpty { parts.append("blokady: \(blocking.count)") }
        if !warnings.isEmpty { parts.append("ostrzeżenia: \(warnings.count)") }
        return parts.joined(separator: ", ")
    }
}

public enum CatalogError: Error, CustomStringConvertible, Equatable {
    case invalidTransition(String)
    case missingModel
    case missingManufacturer(String)
    case approvalBlocked([String])
    case marginOutOfRange(Double)
    case productExists(String)

    public var description: String {
        switch self {
        case .invalidTransition(let text): "Niedozwolone przejście: \(text)"
        case .missingModel: "Produkt nie ma pliku modelu (GLB/USDZ/OBJ/STL)"
        case .missingManufacturer(let id): "Brak producenta „\(id)” w katalogu"
        case .approvalBlocked(let reasons): "Nie można zatwierdzić: " + reasons.joined(separator: "; ")
        case .marginOutOfRange(let value): "Marża \(value)% poza zakresem 0–80%"
        case .productExists(let id): "Produkt „\(id)” już istnieje"
        }
    }
}

public enum CatalogWorkflow {
    public static let marginRange: ClosedRange<Double> = 0...80

    /// Raport kontroli — czysta funkcja, używana i przez CLI, i przez UI.
    public static func review(_ product: CatalogProduct,
                              manufacturer: Manufacturer?,
                              hasThumbnail: Bool) -> ReviewReport {
        var items: [ReviewBlocker] = []

        // 1. prawo do geometrii
        if product.legal.basis == .unknown {
            items.append(.init(code: "legal-basis",
                               message: "Nieustalona podstawa prawna geometrii (własna z dokumentacji / od producenta / licencja)",
                               severity: .blocking))
        }
        if product.legal.provenance?.document.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
            items.append(.init(code: "provenance",
                               message: "Brak dokumentu pochodzenia wymiarów (karta katalogowa, rysunek, umowa)",
                               severity: .blocking))
        }
        if product.legal.designRisk == .high, product.legal.note.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(.init(code: "design-risk",
                               message: "Wysokie ryzyko wzoru przemysłowego — wymagana notatka/decyzja prawna",
                               severity: .blocking))
        }

        // 2. znak towarowy producenta (kafelek pokazuje logo)
        if manufacturer == nil {
            items.append(.init(code: "manufacturer", message: "Brak producenta",
                               severity: .blocking))
        } else if manufacturer?.trademarkApproved != true {
            items.append(.init(code: "trademark",
                               message: "Brak zgody na używanie logo/nazwy producenta w katalogu",
                               severity: .blocking))
        }
        if manufacturer?.logoFile == nil {
            items.append(.init(code: "logo", message: "Producent nie ma pliku logo — kafelek będzie bez znaku",
                               severity: .warning))
        }

        // 3. model i miniatura
        if product.modelAsset == nil {
            items.append(.init(code: "model", message: "Brak pliku modelu 3D", severity: .blocking))
        }
        if !hasThumbnail {
            items.append(.init(code: "thumbnail", message: "Brak miniatury modelu (kafelek bez obrazka)",
                               severity: .blocking))
        }
        if product.width <= 0 || product.depth <= 0 || product.height <= 0 {
            items.append(.init(code: "dimensions", message: "Niepełne wymiary gabarytowe",
                               severity: .warning))
        }

        // 4. handel
        if product.pricing.costGrosze <= 0 {
            items.append(.init(code: "cost", message: "Brak ceny zakupu", severity: .blocking))
        }
        if !marginRange.contains(product.pricing.marginPercent) {
            items.append(.init(code: "margin", message: "Marża poza zakresem 0–80%",
                               severity: .blocking))
        }

        // 5. zależności — dla kategorii, które ich wymagają
        let expected = DependencyLibrary.defaultRules(for: product.category)
        if !expected.isEmpty, product.dependencies.isEmpty {
            items.append(.init(code: "dependencies",
                               message: "Brak opisu zależności — dla „\(product.category.label)” obowiązują reguły produkcyjne",
                               severity: .warning))
        }
        return ReviewReport(blockers: items, productID: product.id)
    }

    // MARK: - przejścia

    public static func submit(_ product: inout CatalogProduct) throws {
        guard product.status == .draft || product.status == .rejected else {
            throw CatalogError.invalidTransition("\(product.status.rawValue) → submitted")
        }
        guard product.modelAsset != nil else { throw CatalogError.missingModel }
        // producent zgłasza produkt: od razu dociągamy domyślne reguły zależności
        if product.dependencies.isEmpty {
            product.dependencies = DependencyLibrary.defaultRules(for: product.category)
        }
        product.status = .submitted
        product.updatedAt = Date()
    }

    public static func approve(_ product: inout CatalogProduct,
                               manufacturer: Manufacturer?,
                               hasThumbnail: Bool,
                               by: String,
                               marginPercent: Double,
                               note: String = "") throws {
        guard product.status == .submitted else {
            throw CatalogError.invalidTransition("\(product.status.rawValue) → approved")
        }
        guard marginRange.contains(marginPercent) else {
            throw CatalogError.marginOutOfRange(marginPercent)
        }
        var candidate = product
        candidate.pricing.marginPercent = marginPercent
        let report = review(candidate, manufacturer: manufacturer, hasThumbnail: hasThumbnail)
        guard report.canApprove else {
            throw CatalogError.approvalBlocked(report.blocking.map { $0.message })
        }
        candidate.status = .approved
        candidate.updatedAt = Date()
        candidate.decision = .init(by: by, reason: note.isEmpty ? "Zatwierdzony, marża \(marginPercent)%" : note)
        product = candidate
    }

    public static func reject(_ product: inout CatalogProduct, by: String, reason: String) throws {
        guard product.status == .submitted || product.status == .draft else {
            throw CatalogError.invalidTransition("\(product.status.rawValue) → rejected")
        }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CatalogError.invalidTransition("odrzucenie wymaga powodu")
        }
        product.status = .rejected
        product.updatedAt = Date()
        product.decision = .init(by: by, reason: reason)
    }
}
