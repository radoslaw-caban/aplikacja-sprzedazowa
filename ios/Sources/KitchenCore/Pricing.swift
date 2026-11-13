import Foundation

/// Cennik pozycji: jedna cena dla szafki, elementu wyposażenia i usługi.
///
/// DLACZEGO JEDEN TYP, A NIE TRZY: szafka, blat, zawias i montaż są tym samym
/// z punktu widzenia koszyka — pozycja z ilością, ceną i opisem. Trzy osobne
/// typy oznaczałyby trzy koszyki i trzy sposoby liczenia sumy.
///
/// ZASADA CENOWA (z produkcji): cena zależy od WYMIARU, nie tylko od katalogu.
/// Szafka 600 i 800 nie mogą kosztować tyle samo, a blat 4 m nie może być
/// dwa razy droższy od 2 m, bo robocizna nie skaluje się liniowo. Dlatego
/// cena bazowa jest za jednostkę, a `PriceList` przelicza wg podanej reguły.
public enum Pricing {

    /// Jak liczyć cenę pozycji wraz z rozmiarem.
    public enum Basis: String, Codable, Sendable, CaseIterable {
        /// cena za sztukę, bez zależności od wymiaru (zawias, uchwyt)
        case perPiece
        /// cena za metr bieżący (blaty, listwy, cokoły)
        case perMetre
        /// cena za metr kwadratowy (fronty, panele, blaty kamienne)
        case perSquareMetre
        /// cena za sztukę, ale rośnie o każdy zaczęty metr szerokości
        case perPiecePerMetre

        public var label: String {
            switch self {
            case .perPiece: "za sztukę"
            case .perMetre: "za metr bieżący"
            case .perSquareMetre: "za m²"
            case .perPiecePerMetre: "za sztukę + metr"
            }
        }
    }

    /// Pozycja cennika — „coś, co można sprzedać".
    public struct Item: Identifiable, Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        /// Cena netto za jednostkę wskazaną w `basis` (zł).
        public var unitPrice: Double
        public var basis: Basis
        /// Kategoria do grupowania w bibliotece i koszyku.
        public var group: Group
        /// Krótki opis dla klienta — pokazywany w koszyku i ofercie.
        public var summary: String
        /// Zdanie „do czego to jest" — handlowiec czyta to klientowi.
        public var purpose: String
        /// Stawka VAT w procentach (23 dla większości, 8 dla montażu w budynkach mieszkalnych).
        public var vatPercent: Double
        /// Czy pozycja jest usługą (montaż, transport) — inaczej liczy się do materiałów.
        public var isService: Bool
        /// Powiązanie z szablonem biblioteki (`Library.Template.id`), jeśli to szafka.
        public var templateID: String?

        public init(id: String, name: String, unitPrice: Double, basis: Basis,
                    group: Group, summary: String, purpose: String,
                    vatPercent: Double = 23, isService: Bool = false,
                    templateID: String? = nil) {
            self.id = id
            self.name = name
            self.unitPrice = unitPrice
            self.basis = basis
            self.group = group
            self.summary = summary
            self.purpose = purpose
            self.vatPercent = vatPercent
            self.isService = isService
            self.templateID = templateID
        }
    }

    public enum Group: String, Codable, Sendable, CaseIterable, Identifiable {
        case cabinet
        case worktop
        case front
        case appliance
        case hardware
        case light
        case service

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .cabinet: "Szafki"
            case .worktop: "Blaty i cokoły"
            case .front: "Fronty"
            case .appliance: "AGD i urządzenia"
            case .hardware: "Akcesoria"
            case .light: "Oświetlenie"
            case .service: "Usługi"
            }
        }

        public var pictogram: String {
            switch self {
            case .cabinet: "cabinet"
            case .worktop: "rectangle.split.2x1"
            case .front: "square.on.square"
            case .appliance: "refrigerator"
            case .hardware: "wrench.and.screwdriver"
            case .light: "lightbulb"
            case .service: "figure.walk"
            }
        }
    }

    // MARK: - pozycja w koszyku

    /// Jedna pozycja koszyka: co, ile, za ile i czy klient to już ma.
    public struct Line: Identifiable, Codable, Sendable, Equatable {
        public var id: UUID
        public var itemID: String
        public var name: String
        /// Ilość (sztuki; dla metrów i m² podstawiamy wymiar).
        public var quantity: Double
        /// Wymiar użyty do wyliczenia ceny (mm): szerokość, długość albo bok.
        public var dimensionMM: Double?
        /// Cena jednostkowa po przeliczeniu na wymiar.
        public var unitPrice: Double
        public var vatPercent: Double
        public var isService: Bool
        /// „Już to mam" — klient ma rzecz, wstawiamy ją tylko dla wizualizacji.
        ///
        /// Po co osobna flaga, a nie usunięcie z projektu: klient chce widzieć
        /// swoją lodówkę na wizualizacji i w zestawieniu (żeby wiedzieć, co
        /// zostaje), ale nie chce jej płacić drugi raz.
        public var ownedByClient: Bool
        /// Skąd pozycja: ręcznie z biblioteki czy automatycznie z projektu.
        public var source: Source
        /// Powiązanie z szafką w projekcie (do przeliczania ilości).
        public var cabinetID: UUID?

        public enum Source: String, Codable, Sendable {
            /// dodane ręcznie w bibliotece
            case manual
            /// wyliczone automatycznie z tego, co stoi na projekcie
            case fromProject
        }

        public init(id: UUID = UUID(), itemID: String, name: String,
                    quantity: Double = 1, dimensionMM: Double? = nil,
                    unitPrice: Double, vatPercent: Double = 23,
                    isService: Bool = false, ownedByClient: Bool = false,
                    source: Source = .manual, cabinetID: UUID? = nil) {
            self.id = id
            self.itemID = itemID
            self.name = name
            self.quantity = quantity
            self.dimensionMM = dimensionMM
            self.unitPrice = unitPrice
            self.vatPercent = vatPercent
            self.isService = isService
            self.ownedByClient = ownedByClient
            self.source = source
            self.cabinetID = cabinetID
        }

        /// Wartość netto pozycji. Pozycje „już to mam" liczą się do zera —
        /// inaczej klient płaciłby za coś, co stoi u niego w kuchni.
        public var netValue: Double {
            ownedByClient ? 0 : unitPrice * quantity
        }

        /// Wartość brutto pozycji.
        public var grossValue: Double {
            netValue * (1 + vatPercent / 100)
        }

        /// Wartość netto niezależnie od tego, czy klient to ma — do zestawienia
        /// „co zostaje u klienta" (porównanie stare z nowym).
        public var referenceNetValue: Double { unitPrice * quantity }
    }

    // MARK: - liczenie ceny

    /// Przelicza cenę pozycji na konkretny wymiar.
    ///
    /// - Parameters:
    ///   - item: pozycja cennika
    ///   - dimensionMM: wymiar w milimetrach (szerokość, długość albo bok)
    ///   - quantity: liczba sztuk
    public static func price(item: Item, dimensionMM: Double?, quantity: Double) -> Double {
        let d = Swift.max(0, dimensionMM ?? 0) / 1000   // mm → m
        switch item.basis {
        case .perPiece:
            return item.unitPrice
        case .perMetre:
            return item.unitPrice * Swift.max(d, 0.01)
        case .perSquareMetre:
            return item.unitPrice * Swift.max(d * d, 0.0001)
        case .perPiecePerMetre:
            // pierwszy metr w cenie, każdy zaczęty kolejny doliczany w całości
            let extra = Swift.max(0, ceil(d) - 1)
            return item.unitPrice + extra * item.unitPrice * 0.35
        }
    }

    /// Buduje pozycję koszyka z cennika.
    public static func line(from item: Item, dimensionMM: Double? = nil,
                            quantity: Double = 1, owned: Bool = false,
                            source: Line.Source = .manual,
                            cabinetID: UUID? = nil) -> Line {
        Line(itemID: item.id, name: item.name,
             quantity: quantity, dimensionMM: dimensionMM,
             unitPrice: price(item: item, dimensionMM: dimensionMM, quantity: quantity),
             vatPercent: item.vatPercent, isService: item.isService,
             ownedByClient: owned, source: source, cabinetID: cabinetID)
    }
}

/// Podsumowanie koszyka — kwoty, VAT i to, co klient ma własne.
public struct CartSummary: Sendable, Equatable {
    public var lines: [Pricing.Line]

    public init(lines: [Pricing.Line] = []) {
        self.lines = lines
    }

    /// Pozycje, które klient płaci.
    public var billable: [Pricing.Line] { lines.filter { !$0.ownedByClient } }
    /// Pozycje własne klienta (do zestawienia „co zostaje").
    public var owned: [Pricing.Line] { lines.filter { $0.ownedByClient } }
    /// Pozycje wyliczone automatycznie z projektu.
    public var fromProject: [Pricing.Line] { lines.filter { $0.source == .fromProject } }

    /// Suma netto pozycji płatnych.
    public var netTotal: Double { billable.reduce(0) { $0 + $1.netValue } }
    /// Suma VAT.
    public var vatTotal: Double { billable.reduce(0) { $0 + ($1.netValue * $1.vatPercent / 100) } }
    /// Suma brutto — to pokazuje się klientowi.
    public var grossTotal: Double { netTotal + vatTotal }

    /// Wartość rzeczy, które klient ma własne (oszczędność, nie koszt).
    public var ownedReferenceValue: Double {
        owned.reduce(0) { $0 + $1.referenceNetValue }
    }

    /// VAT w podziale na stawki — wymóg faktury (23% i 8% nie mogą być zsumowane).
    public var vatByRate: [(rate: Double, net: Double, vat: Double)] {
        var buckets: [Double: (net: Double, vat: Double)] = [:]
        for line in billable {
            let net = line.netValue
            let vat = net * line.vatPercent / 100
            let current = buckets[line.vatPercent] ?? (0, 0)
            buckets[line.vatPercent] = (current.net + net, current.vat + vat)
        }
        return buckets.map { (rate: $0.key, net: $0.value.net, vat: $0.value.vat) }
            .sorted { $0.rate > $1.rate }
    }

    /// Pozycje zgrupowane do wyświetlenia.
    public func grouped(_ items: [String: Pricing.Item]) -> [(group: Pricing.Group, lines: [Pricing.Line])] {
        var buckets: [Pricing.Group: [Pricing.Line]] = [:]
        for line in lines {
            let group = items[line.itemID]?.group ?? .cabinet
            buckets[group, default: []].append(line)
        }
        return Pricing.Group.allCases.compactMap { group in
            guard let lines = buckets[group], !lines.isEmpty else { return nil }
            return (group, lines)
        }
    }

    public var isEmpty: Bool { lines.isEmpty }
}
