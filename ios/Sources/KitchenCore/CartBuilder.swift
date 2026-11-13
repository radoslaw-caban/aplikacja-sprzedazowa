import Foundation

/// Zamienia projekt (szafki, blaty, AGD) na koszyk z cenami.
///
/// ZASADA (wymóg sprzedażowy): co wstawione na projekt wchodzi do koszyka
/// automatycznie, na podstawie liczby sztuk. Dzięki temu handlowiec nie
/// przepisuje projektu do oferty ręcznie — a to jest miejsce, gdzie powstają
/// najdroższe pomyłki (zapomniana szafka, policzona dwa razy).
///
/// KLUCZOWE ROZRÓŻNIENIE: pozycja ręczna z biblioteki („dodaję blat") zostaje,
/// a pozycja wyliczona z projektu jest PRZELICZANA od nowa przy każdej zmianie.
/// Bez tego rozdziału albo duplikaty rosłyby w nieskończoność, albo ręcznie
/// dodany blat znikałby przy każdej zmianie szafki.
public enum CartBuilder {

    /// Buduje koszyk z projektu.
    ///
    /// - Parameters:
    ///   - cabinets: szafki stojące na projekcie
    ///   - manualLines: pozycje dodane ręcznie (nie liczone z projektu)
    ///   - ownedSignatures: klucze pozycji oznaczonych „Już to mam"
    ///     (`itemID` albo `UUID` szafki) — zachowywane przy przeliczaniu
    ///   - worktopMetres: długość blatów w metrach (z biegów), 0 = brak
    ///   - plinthMetres: długość cokołów w metrach, 0 = brak
    ///   - assemblyMetres: długość zabudowy do montażu w metrach, 0 = brak
    /// - Returns: podsumowanie koszyka
    public static func build(
        cabinets: [Cabinet],
        manualLines: [Pricing.Line] = [],
        ownedSignatures: Set<String> = [],
        worktopMetres: Double = 0,
        plinthMetres: Double = 0,
        assemblyMetres: Double = 0
    ) -> CartSummary {
        var lines: [Pricing.Line] = []

        // 1) szafki — jedna pozycja na szafkę, żeby dało się ją oznaczyć osobno
        for cabinet in cabinets {
            // Szafka BEZ odpowiednika w cenniku też trafia do koszyka — z zerem
            // i dopiskiem „brak ceny". Inaczej handlowiec nie widzi luki
            // w wycenie: pozycja znika po cichu, a projekt wygląda na policzony.
            if templateID(for: cabinet) == nil {
                lines.append(Pricing.Line(
                    itemID: "unknown",
                    name: cabinet.name + " (brak ceny)",
                    quantity: 1,
                    dimensionMM: cabinet.width,
                    unitPrice: 0,
                    isService: false,
                    ownedByClient: ownedSignatures.contains(cabinet.id.uuidString),
                    source: .fromProject,
                    cabinetID: cabinet.id))
                continue
            }
            let templateID = templateID(for: cabinet)!
            let owned = ownedSignatures.contains(cabinet.id.uuidString)
                || ownedSignatures.contains(templateID)
            guard let item = Pricing.item(forTemplate: templateID) else {
                // brak ceny: wpis z zerem i nazwą, żeby handlowiec zobaczył lukę
                lines.append(Pricing.Line(
                    itemID: templateID,
                    name: cabinet.name + " (brak ceny)",
                    quantity: 1,
                    dimensionMM: cabinet.width,
                    unitPrice: 0,
                    isService: false,
                    ownedByClient: owned,
                    source: .fromProject,
                    cabinetID: cabinet.id))
                continue
            }
            lines.append(Pricing.line(from: item,
                                      dimensionMM: cabinet.width,
                                      quantity: 1,
                                      owned: owned,
                                      source: .fromProject,
                                      cabinetID: cabinet.id))
        }

        // 2) AGD wbudowane w szafki (jedno urządzenie może wystąpić w kilku szafkach)
        var applianceCounts: [String: Int] = [:]
        for cabinet in cabinets {
            for kind in cabinet.appliances ?? [] {
                guard let id = applianceItemID(for: kind) else { continue }
                applianceCounts[id, default: 0] += 1
            }
        }
        for (id, count) in applianceCounts.sorted(by: { $0.key < $1.key }) {
            guard let item = Pricing.catalogByID[id] else { continue }
            let owned = ownedSignatures.contains(id)
            lines.append(Pricing.line(from: item, quantity: Double(count),
                                      owned: owned, source: .fromProject))
        }

        // 3) blaty, cokoły i montaż — liczone z długości biegu
        if worktopMetres > 0, let item = Pricing.catalogByID["worktop-lam"] {
            lines.append(Pricing.line(from: item, dimensionMM: worktopMetres * 1000,
                                      owned: ownedSignatures.contains("worktop-lam"),
                                      source: .fromProject))
        }
        if plinthMetres > 0, let item = Pricing.catalogByID["plinth"] {
            lines.append(Pricing.line(from: item, dimensionMM: plinthMetres * 1000,
                                      source: .fromProject))
        }
        if assemblyMetres > 0, let item = Pricing.catalogByID["sv-assembly"] {
            lines.append(Pricing.line(from: item, dimensionMM: assemblyMetres * 1000,
                                      source: .fromProject))
        }

        // 4) pozycje ręczne — zachowujemy w całości (nie przeliczamy z projektu)
        lines.append(contentsOf: manualLines)

        return CartSummary(lines: lines)
    }

    /// Identyfikator szablonu cennika dla szafki.
    ///
    /// Szafka z projektu może pochodzić z generatora stref i nie mieć szablonu —
    /// wtedy dopasowujemy po wymiarach i typie, bo strefy tworzą szafki
    /// parametrycznie (600, 800, 300…), a te mają odpowiedniki w cenniku.
    public static func templateID(for cabinet: Cabinet) -> String? {
        // 1) dokładne dopasowanie po nazwie szablonu (szafki z biblioteki)
        if let hit = Pricing.catalog.first(where: {
            $0.templateID != nil && $0.name == cabinet.name
        }) {
            return hit.templateID
        }
        // 2) dopasowanie po typie i szerokości (szafki ze stref)
        let width = Int(cabinet.width.rounded())
        switch cabinet.type {
        case .base:
            if width == 600 { return hasDrawers(cabinet) ? "base-600-3d" : "base-600-1f" }
            if width == 800 { return "base-800-1f" }
            if width == 300 { return "base-300" }
        case .wall:
            if width == 600 { return cabinet.height > 800 ? "wall-600-filler" : "wall-600" }
            if width == 400 { return "wall-400" }
        case .tall:
            if width == 600 { return "tall-600" }
        case .panel:
            return nil   // zaślepka wchodzi w cenę szafki obok
        }
        return nil
    }

    private static func hasDrawers(_ cabinet: Cabinet) -> Bool {
        cabinet.elements.contains { $0.kind == .drawer }
    }

    /// Pozycja cennika dla rodzaju AGD.
    ///
    /// Część urządzeń (zlew, umywalka, kosz, lustro) NIE MA ceny w katalogu
    /// i celowo zwraca `nil` — to nie są urządzenia, które sprzedajemy
    /// (klient wybiera je sam), więc nie mogą trafić do koszyka.
    public static func applianceItemID(for kind: ApplianceKind) -> String? {
        switch kind {
        case .oven: "app-oven"
        case .hob: "app-hob"
        case .fridge: "app-fridge"
        case .hood: "app-vent"
        case .dishwasher: "app-dish"
        case .microwave: "app-micro"
        default: nil
        }
    }
}
