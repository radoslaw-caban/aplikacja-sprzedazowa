import Foundation

/// Katalog cen — pozycje, które można wstawić do koszyka.
///
/// SKĄD TE CENY: to ceny katalogowe netto przyjęte dla wyceny wstępnej
/// (2026, meble na wymiar, segment średni). Służą do rozmowy z klientem
/// na miejscu — nie są ofertą wiążącą. Handlowiec może je zmienić
/// w Ustawieniach, a ostateczna oferta przechodzi przez rabat zamówienia.
///
/// ZASADA: każda pozycja z biblioteki szafek MA swoją cenę tutaj — inaczej
/// automatyczne przeliczanie z projektu nie miałoby czego użyć i koszyk
/// byłby pusty mimo zabudowy na ekranie.
public extension Pricing {

    /// Cennik domyślny. Klucze `templateID` odpowiadają `Library.Template.id`.
    static let catalog: [Item] = [
        // MARK: szafki dolne
        Item(id: "base-600-1f", name: "Szafka dolna 600 / 1 front",
             unitPrice: 890, basis: .perPiece, group: .cabinet,
             summary: "600 × 720 × 560 mm, korpus 18 mm, 1 półka",
             purpose: "Standard pod blat. Najczęstszy moduł w kuchni.",
             templateID: "base-600-1f"),
        Item(id: "base-600-3d", name: "Szafka dolna 600 / 3 szuflady",
             unitPrice: 1480, basis: .perPiece, group: .cabinet,
             summary: "600 × 720 × 560 mm, szuflady LEGRABOX M",
             purpose: "Pod garnki i sztućce — trzy pełne wysuwy.",
             templateID: "base-600-3d"),
        Item(id: "base-800-1f", name: "Szafka dolna 800 / 1 front",
             unitPrice: 1040, basis: .perPiece, group: .cabinet,
             summary: "800 × 720 × 560 mm",
             purpose: "Szerszy moduł pod zlew albo płytę.",
             templateID: "base-800-1f"),
        Item(id: "base-sink-600", name: "Szafka pod zlew 600",
             unitPrice: 950, basis: .perPiece, group: .cabinet,
             summary: "600 × 720 × 500 mm, bez półki",
             purpose: "Płytka, żeby zmieścić syfon i kosz na odpady.",
             templateID: "base-sink-600"),
        Item(id: "base-300", name: "Szafka dolna 300 (wąska)",
             unitPrice: 690, basis: .perPiece, group: .cabinet,
             summary: "300 × 720 × 560 mm, 2 półki",
             purpose: "Wypełnia koniec biegu i wąskie wnęki.",
             templateID: "base-300"),

        // MARK: szafki wiszące
        Item(id: "wall-600", name: "Szafka wisząca 600",
             unitPrice: 720, basis: .perPiece, group: .cabinet,
             summary: "600 × 720 × 350 mm",
             purpose: "Nad blatem, przy okapie i zlewie.",
             templateID: "wall-600"),
        Item(id: "wall-600-filler", name: "Szafka wisząca 600 + zaślepka",
             unitPrice: 880, basis: .perPiece, group: .cabinet,
             summary: "600 × 960 × 350 mm",
             purpose: "Wyższa — zasłania komin albo przechodzi pod sufit.",
             templateID: "wall-600-filler"),
        Item(id: "wall-400", name: "Szafka wisząca 400",
             unitPrice: 590, basis: .perPiece, group: .cabinet,
             summary: "400 × 720 × 350 mm",
             purpose: "Wypełnia miejsce, gdzie 600 się nie mieści.",
             templateID: "wall-400"),

        // MARK: szafki stojące
        Item(id: "tall-600", name: "Szafa stojąca 600",
             unitPrice: 2180, basis: .perPiece, group: .cabinet,
             summary: "600 × 2016 × 560 mm, 4 półki",
             purpose: "Spiżarnia albo słupek z piekarnikiem.",
             templateID: "tall-600"),

        // MARK: blaty
        Item(id: "worktop-lam", name: "Blat laminowany",
             unitPrice: 285, basis: .perMetre, group: .worktop,
             summary: "38 mm, głębokość 635 mm",
             purpose: "Podstawowy blat. Odporny na wilgoć, łatwy w utrzymaniu."),
        Item(id: "worktop-compact", name: "Blat kompaktowy",
             unitPrice: 690, basis: .perMetre, group: .worktop,
             summary: "12–20 mm, spiek kwarcowy",
             purpose: "Odporny na gorąco i zarysowania — bez podparcia, cieńszy."),
        Item(id: "worktop-stone", name: "Blat kamienny",
             unitPrice: 1450, basis: .perMetre, group: .worktop,
             summary: "20 mm, marmur lub granit",
             purpose: "Najtrwalszy. Wymaga szablonu i montażu kamieniarza."),
        Item(id: "plinth", name: "Cokół",
             unitPrice: 95, basis: .perMetre, group: .worktop,
             summary: "150 mm, PCV lub aluminium",
             purpose: "Zamyka przestrzeń pod szafkami."),

        // MARK: fronty
        Item(id: "front-lam", name: "Front laminowany",
             unitPrice: 380, basis: .perSquareMetre, group: .front,
             summary: "18 mm, okleina ABS",
             purpose: "Standard. Duży wybór dekorów."),
        Item(id: "front-lacquer", name: "Front lakierowany",
             unitPrice: 620, basis: .perSquareMetre, group: .front,
             summary: "18 mm MDF, lakier mat",
             purpose: "Równy kolor bez łączeń, do bezuchwytowych."),
        Item(id: "front-glass", name: "Front szklany",
             unitPrice: 890, basis: .perSquareMetre, group: .front,
             summary: "szkło hartowane 4 mm",
             purpose: "Do witryn i szafek ekspozycyjnych."),

        // MARK: AGD
        Item(id: "app-oven", name: "Piekarnik do zabudowy",
             unitPrice: 2490, basis: .perPiece, group: .appliance,
             summary: "60 × 60 cm, klasa A+",
             purpose: "W słupku albo pod blatem."),
        Item(id: "app-hob", name: "Płyta indukcyjna",
             unitPrice: 1890, basis: .perPiece, group: .appliance,
             summary: "60 cm, 4 pola, dotykowa",
             purpose: "Wymaga blatu o podwyższonej odporności na gorąco."),
        Item(id: "app-fridge", name: "Lodówka do zabudowy",
             unitPrice: 3290, basis: .perPiece, group: .appliance,
             summary: "178 cm, 260 l, klasa E",
             purpose: "Front z tej samej serii co szafki."),
        Item(id: "app-vent", name: "Okap podszafkowy",
             unitPrice: 990, basis: .perPiece, group: .appliance,
             summary: "60 cm, 600 m³/h",
             purpose: "Chowany pod szafką wiszącą."),
        Item(id: "app-dish", name: "Zmywarka do zabudowy",
             unitPrice: 2790, basis: .perPiece, group: .appliance,
             summary: "60 cm, 14 zestawów, klasa C",
             purpose: "Pełne zabudowanie frontem."),
        Item(id: "app-micro", name: "Mikrofala do zabudowy",
             unitPrice: 1690, basis: .perPiece, group: .appliance,
             summary: "38 cm wysokości",
             purpose: "Nad albo obok piekarnika.")

        // MARK: sprzęt
        ,
        Item(id: "hw-drawer-m", name: "Szuflada LEGRABOX M",
             unitPrice: 420, basis: .perPiece, group: .hardware,
             summary: "wysokość 90,5 mm, NL 270–650",
             purpose: "Cicha, samodomykająca. Standard w tym segmencie."),
        Item(id: "hw-drawer-k", name: "Szuflada LEGRABOX K",
             unitPrice: 610, basis: .perPiece, group: .hardware,
             summary: "wysokość 128,5 mm",
             purpose: "Wyższy front — więcej miejsca na wysokie rzeczy."),
        Item(id: "hw-hinge", name: "Zawias Blum CLIP top",
             unitPrice: 38, basis: .perPiece, group: .hardware,
             summary: "110°, z cichym domykaniem",
             purpose: "Standard produkcyjny."),
        Item(id: "hw-handle", name: "Uchwyt",
             unitPrice: 42, basis: .perPiece, group: .hardware,
             summary: "128 mm, stal szczotkowana",
             purpose: "Do wyboru: 6 wzorów, 4 wykończenia."),
        Item(id: "hw-lift", name: "Podnośnik Aventos",
             unitPrice: 690, basis: .perPiece, group: .hardware,
             summary: "HF, do frontów 600–1200 mm",
             purpose: "Do szafek nad blatem — front unosi się do góry."),

        // MARK: oświetlenie
        Item(id: "lt-strip", name: "Taśma LED podszafkowa",
             unitPrice: 165, basis: .perMetre, group: .light,
             summary: "12 V, 4000 K, IP20",
             purpose: "Światło robocze na blacie — bez cieni pod rękami."),
        Item(id: "lt-profile", name: "Profil aluminiowy LED",
             unitPrice: 88, basis: .perMetre, group: .light,
             summary: "wnękowy 12 × 8 mm",
             purpose: "Chowa taśmę i równo rozprasza światło."),

        // MARK: usługi
        Item(id: "sv-design", name: "Projekt i wizualizacja",
             unitPrice: 900, basis: .perPiece, group: .service,
             summary: "rzut, wizualizacja 3D, zestawienie",
             purpose: "Płatne przy zamówieniu, wliczane w realizację.",
             vatPercent: 8, isService: true),
        Item(id: "sv-delivery", name: "Transport",
             unitPrice: 320, basis: .perPiece, group: .service,
             summary: "do 50 km, wniesienie",
             purpose: "Poza strefą dojazdu doliczamy 4 zł/km.",
             vatPercent: 8, isService: true),
        Item(id: "sv-assembly", name: "Montaż",
             unitPrice: 190, basis: .perMetre, group: .service,
             summary: "montaż szafek, blatów i frontów",
             purpose: "Stawka za metr bieżący zabudowy, 8% VAT w budynkach mieszkalnych.",
             vatPercent: 8, isService: true),
        Item(id: "sv-template", name: "Szablon pod blat kamienny",
             unitPrice: 450, basis: .perPiece, group: .service,
             summary: "pomiar i szablon z płyty",
             purpose: "Konieczny przed zamówieniem kamienia.",
             vatPercent: 8, isService: true)
    ]

    /// Szybki dostęp po identyfikatorze.
    static let catalogByID: [String: Item] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.id, $0) }
    )

    /// Pozycja cennika dla szablonu biblioteki — albo `nil`, gdy brak ceny.
    ///
    /// Brak ceny to nie błąd: część szablonów może nie być w ofercie.
    /// Zwracamy `nil`, żeby koszyk pokazał „brak ceny" zamiast zera —
    /// zero wygląda jak „gratis" i handlowiec mógłby tego nie zauważyć.
    static func item(forTemplate templateID: String) -> Item? {
        catalogByID[templateID]
    }
}
