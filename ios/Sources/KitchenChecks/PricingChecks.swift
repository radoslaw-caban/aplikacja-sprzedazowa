// Testy modułu sprzedażowego: cennik, przeliczanie na wymiar, koszyk z projektu.
// Uruchomienie: swift run KitchenChecks  (sekcja „Sprzedaż")
import Foundation
import simd
import KitchenCore

func runPricingChecks(_ r: Reporter) {
    print("\nSprzedaż — cennik, wymiar, koszyk")

    // 1) przeliczanie ceny wg podstawy
    do {
        let perPiece = Pricing.Item(id: "t1", name: "Test sztuka", unitPrice: 100,
                                    basis: .perPiece, group: .hardware,
                                    summary: "", purpose: "")
        r.check("cena za sztukę nie zależy od wymiaru",
                Pricing.price(item: perPiece, dimensionMM: 600, quantity: 1) == 100
                && Pricing.price(item: perPiece, dimensionMM: 1200, quantity: 1) == 100)

        let perMetre = Pricing.Item(id: "t2", name: "Test metr", unitPrice: 200,
                                    basis: .perMetre, group: .worktop,
                                    summary: "", purpose: "")
        r.check("cena za metr: 2,5 m × 200 = 500",
                abs(Pricing.price(item: perMetre, dimensionMM: 2500, quantity: 1) - 500) < 0.01,
                "\(Pricing.price(item: perMetre, dimensionMM: 2500, quantity: 1))")
        r.check("cena za metr: 0,8 m × 200 = 160",
                abs(Pricing.price(item: perMetre, dimensionMM: 800, quantity: 1) - 160) < 0.01)

        let perSqm = Pricing.Item(id: "t3", name: "Test m2", unitPrice: 400,
                                  basis: .perSquareMetre, group: .front,
                                  summary: "", purpose: "")
        // blat 1,2 m → 1,44 m² × 400 = 576
        r.check("cena za m²: 1,2 m → 1,44 m² × 400 = 576",
                abs(Pricing.price(item: perSqm, dimensionMM: 1200, quantity: 1) - 576) < 0.01,
                "\(Pricing.price(item: perSqm, dimensionMM: 1200, quantity: 1))")

        let perPiecePerMetre = Pricing.Item(id: "t4", name: "Test szt+metr", unitPrice: 100,
                                            basis: .perPiecePerMetre, group: .cabinet,
                                            summary: "", purpose: "")
        r.check("za sztukę + metr: 0,6 m = cena bazowa",
                abs(Pricing.price(item: perPiecePerMetre, dimensionMM: 600, quantity: 1) - 100) < 0.01)
        // 1,2 m → 1 metr bazowy + 1 zaczęty kolejny (35% × 100 = 35) = 135
        r.check("za sztukę + metr: 1,2 m = baza + 35%",
                abs(Pricing.price(item: perPiecePerMetre, dimensionMM: 1200, quantity: 1) - 135) < 0.01,
                "\(Pricing.price(item: perPiecePerMetre, dimensionMM: 1200, quantity: 1))")
    }

    // 2) suma koszyka: netto, VAT, brutto
    do {
        var summary = CartSummary()
        summary.lines = [
            Pricing.Line(itemID: "a", name: "Szafka", quantity: 2, unitPrice: 1000, vatPercent: 23),
            Pricing.Line(itemID: "b", name: "Montaż", quantity: 1, unitPrice: 500,
                         vatPercent: 8, isService: true),
        ]
        r.check("koszyk: netto = 2500", abs(summary.netTotal - 2500) < 0.01,
                "\(summary.netTotal)")
        // VAT: 2000×23% = 460, 500×8% = 40 → razem 500
        r.check("koszyk: VAT = 500", abs(summary.vatTotal - 500) < 0.01,
                "\(summary.vatTotal)")
        r.check("koszyk: brutto = 3000", abs(summary.grossTotal - 3000) < 0.01,
                "\(summary.grossTotal)")

        // VAT w podziale na stawki — wymóg faktury
        let rates = summary.vatByRate
        r.check("koszyk: VAT rozdzielony na stawki", rates.count == 2,
                "\(rates.map(\.rate))")
        r.check("koszyk: stawka 23% ma 460 VAT",
                abs((rates.first { $0.rate == 23 }?.vat ?? 0) - 460) < 0.01)
    }

    // 3) „Już to mam" — nie wchodzi do sumy, ale jest w zestawieniu
    do {
        var summary = CartSummary()
        summary.lines = [
            Pricing.Line(itemID: "a", name: "Nowa szafka", quantity: 1, unitPrice: 1000),
            Pricing.Line(itemID: "fridge", name: "Lodówka klienta", quantity: 1,
                         unitPrice: 3290, ownedByClient: true),
        ]
        r.check("„już to mam” — nie wchodzi do netto",
                abs(summary.netTotal - 1000) < 0.01, "\(summary.netTotal)")
        r.check("„już to mam” — widoczne jako własność klienta",
                summary.owned.count == 1 && abs(summary.ownedReferenceValue - 3290) < 0.01,
                "\(summary.ownedReferenceValue)")
        r.check("„już to mam” — osobno od płatnych", summary.billable.count == 1)
    }

    // 4) koszyk z projektu: szafki → pozycje
    do {
        var cabinets: [Cabinet] = []
        cabinets.append(Library.make(Library.base[0]))            // dolna 600 / 1 front
        cabinets.append(Library.make(Library.base[1]))            // dolna 600 / 3 szuflady
        cabinets.append(Library.make(Library.base[2]))            // dolna 800
        cabinets.append(Library.make(Library.wall[0]))            // wisząca 600

        let cart = CartBuilder.build(cabinets: cabinets, worktopMetres: 2.6,
                                     plinthMetres: 2.6, assemblyMetres: 2.6)

        let cabinetLines = cart.lines.filter { $0.source == .fromProject
            && $0.itemID.hasPrefix("base-") || $0.itemID.hasPrefix("wall-") }
        r.check("z projektu: 4 szafki w koszyku", cabinetLines.count == 4,
                "\(cabinetLines.count)")

        // ceny z katalogu: 890 + 1480 + 1040 + 720 = 4130
        let cabinetsNet = cabinetLines.reduce(0) { $0 + $1.netValue }
        r.check("z projektu: szafki netto = 4130",
                abs(cabinetsNet - 4130) < 0.01, "\(cabinetsNet)")

        r.check("z projektu: blat 2,6 m × 285 = 741",
                abs((cart.lines.first { $0.itemID == "worktop-lam" }?.netValue ?? 0) - 741) < 0.01,
                "\(cart.lines.first { $0.itemID == "worktop-lam" }?.netValue ?? 0)")
        r.check("z projektu: montaż 2,6 m × 190 = 494",
                abs((cart.lines.first { $0.itemID == "sv-assembly" }?.netValue ?? 0) - 494) < 0.01)
        r.check("z projektu: montaż ma VAT 8%",
                cart.lines.first { $0.itemID == "sv-assembly" }?.vatPercent == 8)
    }

    // 5) pozycje ręczne przeżywają przeliczanie z projektu
    do {
        let manual = [Pricing.line(from: Pricing.catalogByID["hw-handle"]!, quantity: 12)]
        let cabinets = [Library.make(Library.base[0])]
        let cart = CartBuilder.build(cabinets: cabinets, manualLines: manual)

        r.check("ręczne: uchwyty zostają w koszyku",
                cart.lines.contains { $0.itemID == "hw-handle" && $0.quantity == 12 })
        r.check("ręczne: oznaczone jako ręczne",
                cart.lines.first { $0.itemID == "hw-handle" }?.source == .manual)
        r.check("ręczne: szafka też jest", cart.lines.contains { $0.itemID == "base-600-1f" })
        // uchwyty: 12 × 42 = 504
        r.check("ręczne: 12 uchwytów = 504",
                abs((cart.lines.first { $0.itemID == "hw-handle" }?.netValue ?? 0) - 504) < 0.01)
    }

    // 6) szafka bez ceny → pozycja z zerem i oznaczeniem (luka widoczna)
    do {
        let unknown = Cabinet(name: "Szafka nietypowa 450", type: .base,
                              width: 450, height: 720, depth: 560, plinth: 150)
        let cart = CartBuilder.build(cabinets: [unknown])
        let line = cart.lines.first
        r.check("brak ceny: pozycja ma zero i słowo (brak ceny)",
                line?.unitPrice == 0 && (line?.name.contains("brak ceny") ?? false),
                line?.name ?? "brak pozycji")
    }

    // 7) dopasowanie szablonu ze strefy (po wymiarach, nie po nazwie)
    do {
        // szafka ze strefy: nazwa inna, ale 600 dolna bez szuflad
        let zone = Cabinet(name: "Strefa zlew", type: .base, width: 600,
                           height: 720, depth: 560, plinth: 150)
        r.check("strefa: dopasowanie po wymiarach → base-600-1f",
                CartBuilder.templateID(for: zone) == "base-600-1f",
                CartBuilder.templateID(for: zone) ?? "nil")

        var withDrawer = zone
        withDrawer.elements = [CabinetElement(kind: .drawer, y: 0, height: 128.5)]
        r.check("strefa: z szufladą → base-600-3d",
                CartBuilder.templateID(for: withDrawer) == "base-600-3d",
                CartBuilder.templateID(for: withDrawer) ?? "nil")
    }

    // 8) AGD z projektu liczone raz na sztukę
    do {
        var cab = Library.make(Library.base[0])
        cab.appliances = [.oven, .oven, .hob]
        let cart = CartBuilder.build(cabinets: [cab])
        r.check("AGD: dwa piekarniki = ilość 2",
                cart.lines.first { $0.itemID == "app-oven" }?.quantity == 2,
                "\(cart.lines.first { $0.itemID == "app-oven" }?.quantity ?? 0)")
        r.check("AGD: piekarnik 2 × 2490 = 4980",
                abs((cart.lines.first { $0.itemID == "app-oven" }?.netValue ?? 0) - 4980) < 0.01)
        r.check("AGD: zlew nie ma ceny (nie sprzedajemy)",
                !cart.lines.contains { $0.itemID.contains("sink") && $0.source == .fromProject })
    }

    // 9) katalog: każda pozycja ma opis i przeznaczenie
    do {
        let missing = Pricing.catalog.filter { $0.summary.isEmpty || $0.purpose.isEmpty }
        r.check("katalog: każda pozycja ma opis i przeznaczenie",
                missing.isEmpty, missing.map(\.id).joined(separator: ", "))
        let ids = Pricing.catalog.map(\.id)
        r.check("katalog: brak duplikatów identyfikatorów",
                Set(ids).count == ids.count, "\(ids.count) pozycji")
    }
}
