import Foundation

/// Reguły auto-projektowania zabudowy — czysta logika, bez UI i bez sceny.
/// Port reguł z wersji web (`design/zonePlan.ts`) 1:1, z tymi samymi wymiarami.
public enum ZonePlanner {

    public static let baseH: Double = 720
    public static let baseD: Double = 560
    public static let wallD: Double = 350
    public static let tallD: Double = 561
    public static let worktopT: Double = 38
    public static let sinkGap: Double = 600

    // MARK: - punkt wejścia

    public static func plan(_ kind: ZoneKind, _ answers: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        switch kind {
        case .kitchenCook: planCook(answers, ctx)
        case .kitchenClean: planClean(answers, ctx)
        case .kitchenTall: planTall(answers, ctx)
        case .kitchenIsland: planIsland(answers, ctx)
        case .wardrobeHinged: wardrobe(answers, ctx, sliding: false)
        case .wardrobeSliding: wardrobe(answers, ctx, sliding: true)
        case .livingTV: planTV(answers, ctx)
        case .bathroom: planBathroom(answers, ctx)
        }
    }

    // MARK: - elementy planu

    private static func part(
        _ role: String,
        _ type: CabinetType,
        _ width: Double,
        _ height: Double,
        _ depth: Double,
        plinth: Double = 0,
        mount: Double = 0,
        worktop: Bool = false,
        label: String,
        doors: Int = 0,
        drawers: [Double] = [],
        interior: ZoneInterior = .none,
        appliances: [ApplianceKind] = [],
        feature: String? = nil,
        worktopDepth: Double? = nil,
        worktopShift: Double? = nil,
        slidingPanels: Int? = nil
    ) -> ZonePart {
        ZonePart(
            role: role, type: type, width: width, height: height, depth: depth,
            plinth: plinth, mountHeight: mount, worktop: worktop, label: label,
            at: 0, doors: doors, drawers: drawers, interior: interior,
            appliances: appliances, feature: feature,
            worktopDepth: worktopDepth, worktopShift: worktopShift,
            slidingPanels: slidingPanels
        )
    }

    private static func base(_ role: String, _ width: Double, plinth: Double,
                             drawers: [Double] = [], doors: Int = 0,
                             interior: ZoneInterior = .none,
                             appliances: [ApplianceKind] = [], feature: String? = nil,
                             label: String = "Szafka dolna",
                             worktopDepth: Double? = nil, worktopShift: Double? = nil,
                             height: Double = baseH, depth: Double = baseD) -> ZonePart {
        part(role, .base, width, height, depth, plinth: plinth, worktop: true,
             label: label, doors: doors, drawers: drawers, interior: interior,
             appliances: appliances, feature: feature,
             worktopDepth: worktopDepth, worktopShift: worktopShift)
    }

    private static func wallUnit(_ role: String, _ width: Double, height: Double,
                                 mount: Double, label: String = "Szafka górna",
                                 interior: ZoneInterior = .shelf) -> ZonePart {
        part(role, .wall, width, height, wallD, mount: mount, label: label,
             doors: 1, interior: interior)
    }

    private static func tallUnit(_ role: String, _ width: Double, height: Double,
                                 plinth: Double = 150, depth: Double = tallD,
                                 doors: Int = 1, interior: ZoneInterior = .shelf,
                                 appliances: [ApplianceKind] = [], feature: String? = nil,
                                 label: String, slidingPanels: Int? = nil) -> ZonePart {
        part(role, .tall, width, height, depth, plinth: plinth,
             label: label, doors: doors, interior: interior,
             appliances: appliances, feature: feature, slidingPanels: slidingPanels)
    }

    private static func start(_ a: ZoneAnswers, _ ctx: ZoneContext, _ width: Double,
                              _ warnings: inout [String]) -> Double {
        let align = a.text("align", "center")
        let margin = 50.0
        let free = max(0, ctx.wallLength - margin * 2 - width)
        var s = align == "left" ? margin : align == "right" ? margin + free : margin + free / 2
        s = ZoneMath.clamp(s, 0, max(0, ctx.wallLength - width))
        if width > ctx.wallLength + 1 {
            warnings.append("Zabudowa \(Int(width)) mm nie mieści się na ścianie \(Int(ctx.wallLength)) mm — zmniejsz szerokość.")
        }
        return s
    }

    // MARK: - kuchnia: gotowanie

    private static func planCook(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let worktopH = a.number("worktopHeight", 900)
        let plinth = ZoneMath.clamp(worktopH - worktopT - baseH, 80, 220)
        if worktopH - worktopT - baseH < 80 {
            warnings.append("Cokół poniżej 80 mm — sprawdź poziom podłogi.")
        }
        let handleless = a.text("fronts", "handle") == "handleless"
        let hob = a.text("hob", "induction-600")
        let hobW: Double = hob == "none" ? 0 : hob == "induction-800" ? 800 : 600
        let oven = a.text("oven", "column")
        let micro = a.text("microwave", "above-oven")
        let fridge = a.text("fridge", "built-in")
        let fridgeW: Double = fridge == "side-by-side" ? 900 : fridge == "freestanding" ? 700 : fridge == "built-in" ? 600 : 0
        var vitrines = a.flag("vitrines", true)
        let dw = a.flag("dishwasher", true)
        let wallCabs = a.flag("wallCabinets", true)
        let hood = hob != "none" && a.text("hood", "chimney") != "none"
        let hobPos = ZoneMath.clamp(a.number("hobPos", 50), 0, 100)
        let avail = ctx.wallLength
        var baseTarget = ZoneMath.clamp(ZoneMath.round50(a.number("width", 2400)), 1200, 3600)
        let tallH = min(2216, ctx.wallHeight - 40)

        // wysoka zabudowa na końcach
        var tallL: [ZonePart] = []
        var tallR: [ZonePart] = []
        let tallRough = fridgeW + (oven == "column" ? 600 : 0) + (vitrines ? 800 : 0)
        if avail < tallRough + baseTarget + 100 {
            if vitrines {
                vitrines = false
                warnings.append("Witryny pominięte — ściana za krótka na pełny układ.")
            }
        }
        let tallBase = fridgeW + (oven == "column" ? 600 : 0)
        if avail < tallBase + baseTarget + 100 {
            baseTarget = max(1200, ZoneMath.round50(avail - tallBase - 100))
            warnings.append("Ciąg dolny dopasowany do wolnego odcinka ściany (drzwi / narożnik).")
        }

        if vitrines {
            tallL.append(tallUnit("witryna-l", 400, height: tallH, doors: 1, interior: .glass,
                                  feature: "vitrine", label: "Witryna szklana 400"))
        }
        if fridgeW > 0 {
            tallL.append(tallUnit("fridge", fridgeW, height: tallH,
                                  doors: fridge == "side-by-side" ? 2 : 1, interior: .none,
                                  appliances: [.fridge], feature: "fridge",
                                  label: "Zabudowa lodówki (\(fridge))"))
        }
        if oven == "column" {
            tallR.append(tallUnit("oven", 600, height: tallH,
                                  doors: micro == "above-oven" ? 2 : 1, interior: .shelf,
                                  appliances: micro == "above-oven" ? [.oven, .microwave] : [.oven],
                                  feature: "oven", label: "Słupek piekarnik + mikrofala"))
        }
        if vitrines {
            tallR.append(tallUnit("witryna-p", 400, height: tallH, doors: 1, interior: .glass,
                                  feature: "vitrine", label: "Witryna szklana 400"))
        }

        let tallLw = tallL.reduce(0) { $0 + $1.width }
        // ciąg dolny
        let dwW: Double = dw && baseTarget - hobW - 600 >= 850 ? 600 : 0
        if dw && dwW == 0 { warnings.append("Zmywarka pominięta — za mało miejsca w ciągu dolnym.") }
        let landTotal = baseTarget - hobW - dwW
        var wl = max(400, ZoneMath.round50(landTotal * hobPos / 100))
        var wr = landTotal - wl
        if wr < 400 {
            wr = max(150, min(400, landTotal - 150))
            wl = landTotal - wr
        }
        if hobW > 0 && (wl < 400 || wr < 400) {
            warnings.append("Strefa pracy przy płycie < 400 mm — zwiększ długość ciągu.")
        }

        var parts: [ZonePart] = tallL
        var at = tallLw
        var baseParts: [ZonePart] = []
        if wl > 0 {
            baseParts.append(base("landing-l", wl, plinth: plinth, drawers: [128, 128, 128],
                                  feature: "landing", label: "Szafka z szufladami (strefa pracy)"))
        }
        if hobW > 0 {
            baseParts.append(base("hob", hobW, plinth: plinth, drawers: [90, 240, 240],
                                  appliances: [.hob] + (hood ? [.hood] : []),
                                  feature: "hob",
                                  label: "Szafka pod płytą \(Int(hobW))"))
        }
        if wr > 0 {
            baseParts.append(base("landing-r", wr, plinth: plinth, drawers: [128, 128, 128],
                                  feature: "landing", label: "Szafka z szufladami (strefa pracy)"))
        }
        if dwW > 0 {
            baseParts.append(base("dishwasher", dwW, plinth: plinth,
                                  appliances: [.dishwasher], feature: "dishwasher",
                                  label: "Zmywarka 600"))
        }
        for var p in baseParts {
            p.at = at
            at += p.width
            parts.append(p)
        }
        for var p in tallR {
            p.at = at
            at += p.width
            parts.append(p)
        }
        let runWidth = at

        // szafki górne + okap
        let mount = worktopH + sinkGap
        let wallH = min(720, max(0, ctx.wallHeight - mount - 40))
        if wallCabs && wallH >= 400 {
            for p in baseParts where p.role == "landing-l" || p.role == "landing-r" {
                let w = min(600, p.width)
                parts.append(wallUnit("wall-\(p.role)", w, height: wallH, mount: mount,
                                      label: "Szafka górna 600",
                                      interior: .shelf))
                parts[parts.count - 1].at = p.at + (p.width - w) / 2
            }
            if hobW > 0 && !hood {
                parts.append(wallUnit("wall-hob", min(600, hobW), height: wallH, mount: mount,
                                      label: "Szafka górna nad płytą"))
                parts[parts.count - 1].at = tallLw + wl
            }
        } else if wallCabs {
            warnings.append("Szafki górne pominięte — za niski sufit.")
        }

        notes.append("Blat \(Int(worktopH)) mm = cokół \(Int(plinth)) + korpus 720 + blat 38.")
        notes.append("Strefy pracy: lewa \(Int(wl)) / prawa \(Int(wr)) mm (min. 400).")
        if hood { notes.append("Okap 650 mm nad płytą, komin do sufitu.") }
        if handleless { notes.append("Fronty bezuchwytowe — frez 45°.") }
        if oven == "column" { notes.append("Piekarnik w słupku 600 na wysokości 900–1500.") }

        let s = start(a, ctx, runWidth, &warnings)
        return ZonePlan(parts: parts, start: s, width: runWidth, notes: notes, warnings: warnings)
    }

    // MARK: - kuchnia: czystość

    private static func planClean(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let worktopH = a.number("worktopHeight", 900)
        let plinth = ZoneMath.clamp(worktopH - worktopT - baseH, 80, 220)
        let sink = a.text("sink", "one-half")
        let sinkW: Double = sink == "double" ? 900 : sink == "one-half" ? 800 : sink == "single" ? 600 : 0
        let dw = a.flag("dishwasher", true)
        let bin = a.flag("bin", true)
        let wallCabs = a.flag("wallCabinets", true)
        let tallStorage = a.flag("tallStorage", false)
        let sinkPos = ZoneMath.clamp(a.number("sinkPos", 40), 0, 100)
        let avail = ctx.wallLength
        var total = ZoneMath.clamp(ZoneMath.round50(a.number("width", 1800)), 1200, 4200)
        let tallW: Double = tallStorage ? 600 : 0
        if avail < total + tallW + 100 {
            total = max(1200, ZoneMath.round50(avail - tallW - 100))
            warnings.append("Ciąg skrócony do wolnego odcinka ściany.")
        }
        if sinkW == 0 { warnings.append("Brak zlewu — to nie jest już strefa czystości.") }

        let dwW: Double = dw && sinkW > 0 && total - sinkW - 600 >= 300 ? 600 : 0
        if dw && dwW == 0 { warnings.append("Zmywarka pominięta — za mało miejsca obok zlewu.") }
        let rest = total - sinkW - dwW
        let nRest = max(1, Int((rest / 700).rounded()))
        let restW = rest > 0 ? ZoneMath.splitModules(rest, nRest) : []
        let insertIdx = min(restW.count, max(0, Int((sinkPos / 100 * Double(restW.count)).rounded())))

        var parts: [ZonePart] = []
        var at: Double = 0
        func addSink() {
            guard sinkW > 0 else { return }
            var p = base("sink", sinkW, plinth: plinth, doors: 2,
                         appliances: [.sink] + (bin ? [.bin] : []), feature: "sink",
                         label: "Szafka ze zlewem \(Int(sinkW))")
            p.at = at; at += p.width; parts.append(p)
        }
        func addDW() {
            guard dwW > 0 else { return }
            var p = base("dishwasher", dwW, plinth: plinth, appliances: [.dishwasher],
                         feature: "dishwasher", label: "Zmywarka 600")
            p.at = at; at += p.width; parts.append(p)
        }
        for i in restW.indices {
            if i == insertIdx { addSink(); addDW() }
            var p = base("base-\(i)", restW[i], plinth: plinth, drawers: [128, 128, 128],
                         label: "Szafka z szufladami")
            p.at = at; at += p.width; parts.append(p)
        }
        if insertIdx >= restW.count { addSink(); addDW() }

        if tallW > 0 {
            var p = tallUnit("pantry", tallW, height: min(2216, ctx.wallHeight - 40),
                             doors: 2, interior: .pantry, feature: "pantry",
                             label: "Słupek/spiżarnia 600")
            p.at = at; at += p.width; parts.append(p)
        }

        let mount = worktopH + sinkGap
        let wallH = min(720, max(0, ctx.wallHeight - mount - 40))
        if wallCabs && wallH >= 400 {
            for p in parts where p.type == .base && p.role != "sink" {
                let w = min(600, p.width)
                var wc = wallUnit("wall-\(p.role)", w, height: wallH, mount: mount)
                wc.at = p.at + (p.width - w) / 2
                parts.append(wc)
            }
            if let sinkPart = parts.first(where: { $0.role == "sink" }) {
                let w = min(600, sinkPart.width)
                var wc = wallUnit("wall-sink", w, height: wallH, mount: mount, label: "Szafka górna nad zlewem")
                wc.at = sinkPart.at + (sinkPart.width - w) / 2
                parts.append(wc)
            }
        }

        notes.append("Kosz i syfon pod zlewem, dojście serwisowe 600 mm.")
        notes.append("Zmywarka w promieniu 1200 mm od zlewu (woda i kanalizacja).")
        if bin { notes.append("Segregacja odpadów w szufladzie pod zlewem.") }

        let s = start(a, ctx, at, &warnings)
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }

    // MARK: - kuchnia: wysoka zabudowa

    private static func planTall(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let fridge = a.text("fridge", "built-in")
        let fridgeW: Double = fridge == "none" ? 0 : fridge == "side-by-side" ? 900 : fridge == "freestanding" ? 700 : 600
        let oven = a.flag("oven", true)
        let micro = a.flag("microwave", true)
        let pantry = a.number("pantryWidth", 600)
        let toCeiling = a.flag("toCeiling", true)
        let height = toCeiling ? max(2000, ctx.wallHeight - 40) : 2216
        var parts: [ZonePart] = []
        var at: Double = 0
        if fridgeW > 0 {
            var p = tallUnit("fridge", fridgeW, height: height,
                             doors: fridge == "side-by-side" ? 2 : 1, interior: .none,
                             appliances: [.fridge], feature: "fridge", label: "Zabudowa lodówki")
            p.at = at; at += p.width; parts.append(p)
        }
        if oven {
            var p = tallUnit("oven", 600, height: height, doors: micro ? 2 : 1,
                             appliances: micro ? [.oven, .microwave] : [.oven],
                             feature: "oven", label: "Słupek piekarnik + mikrofala")
            p.at = at; at += p.width; parts.append(p)
        }
        if pantry > 0 {
            var p = tallUnit("pantry", pantry, height: height,
                             doors: pantry >= 900 ? 2 : 1, interior: .pantry,
                             feature: "pantry", label: "Spiżarnia \(Int(pantry))")
            p.at = at; at += p.width; parts.append(p)
        }
        if at == 0 { warnings.append("Pusta strefa — wybierz lodówkę, piekarnik lub spiżarnię.") }
        notes.append("Wysokość \(Int(height)) mm \(toCeiling ? "(do sufitu, zaślepka 40 mm)" : "(korpus 2216)").")
        notes.append("Cokół 150 mm, zlicowany z ciągiem dolnym.")
        let s = start(a, ctx, at, &warnings)
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }

    // MARK: - kuchnia: wyspa

    private static func planIsland(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let worktopH = a.number("worktopHeight", 900)
        let plinth = ZoneMath.clamp(worktopH - worktopT - baseH, 80, 220)
        let feature = a.text("islandFeature", "hob")
        let seating = a.flag("seating", true)
        let len = ZoneMath.clamp(ZoneMath.round50(a.number("width", 2400)), 1800, 3600)
        let depth: Double = 560
        let worktopDepth = seating ? 860.0 : 680.0
        let overhang = worktopDepth - depth
        let n = max(2, Int((len / 800).rounded()))
        let widths = ZoneMath.splitModules(len, n)
        let featureIdx = n / 2
        var parts: [ZonePart] = []
        var at: Double = 0
        for (i, w) in widths.enumerated() {
            let isFeature = i == featureIdx && feature != "none"
            var p = base(isFeature ? feature : "island-\(i)", w, plinth: plinth,
                         drawers: isFeature ? [90, 240, 240] : [128, 128, 128],
                         appliances: isFeature ? ([feature == "hob" ? .hob : .sink] + (feature == "hob" ? [.hood] : [])) : [],
                         feature: isFeature ? feature : nil,
                         label: isFeature ? "Wyspa — \(feature == "sink" ? "zlew" : "płyta")" : "Wyspa — szuflady",
                         worktopDepth: worktopDepth,
                         worktopShift: seating ? overhang / 2 : 0,
                         depth: depth)
            p.at = at; at += w; parts.append(p)
        }
        notes.append("Blat \(Int(worktopH)) mm, nawis \(seating ? 300 : 0) mm na siedzenie.")
        notes.append("Wyspa bez szafek górnych — okap sufitowy.")
        let need = 900.0 + depth + 100
        if ctx.roomDepth < need * 2 {
            warnings.append("Wyspa: przejścia < 900 mm — sprawdź odległość od ścian.")
        }
        let s = ZoneMath.clamp((ctx.wallLength - len) / 2, 50, max(0, ctx.wallLength - len - 50))
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }

    // MARK: - szafy

    private static func wardrobe(_ a: ZoneAnswers, _ ctx: ZoneContext, sliding: Bool) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let width = ZoneMath.clamp(ZoneMath.round50(a.number("width", 1800)), 900, 4200)
        let toCeiling = a.flag("toCeiling", true)
        let height = toCeiling ? max(2000, ctx.wallHeight - 40) : 2216
        let depth: Double = sliding ? 650 : 600
        let plinth: Double = 100
        let interior = a.text("interior", "rail")
        let panels = min(3, max(2, Int(a.number("panels", 2))))
        let mirror = a.flag("mirror", false)
        var parts: [ZonePart] = []
        var at: Double = 0

        if sliding {
            var p = tallUnit("wardrobe", width, height: height, plinth: plinth, depth: depth,
                             doors: 0, interior: interior == "shelf" ? .pantry : .rail,
                             feature: "wardrobe", label: "Szafa przesuwna \(Int(width))",
                             slidingPanels: panels)
            p.at = 0
            parts.append(p)
            at = width
        } else {
            let sections = max(2, Int((width / 550).rounded()))
            let widths = ZoneMath.splitModules(width, sections)
            for (i, w) in widths.enumerated() {
                var p = tallUnit("wardrobe-\(i)", w, height: height, plinth: plinth, depth: depth,
                                 doors: 1, interior: interior == "shelf" ? .pantry : .rail,
                                 feature: "wardrobe", label: "Szafa otwierana \(Int(w))")
                p.at = at; at += w; parts.append(p)
            }
        }
        if sliding {
            notes.append("Panele przesuwne \(panels) × ~\(Int(width / Double(panels))) mm, prowadnice góra/dół.")
            notes.append("Głębokość 650 mm — fronty nie wymagają miejsca na otwieranie.")
            if mirror { notes.append("Jeden panel lustrzany.") }
        } else {
            notes.append("Wymagane 600 mm wolnej przestrzeni przed frontami.")
        }
        notes.append("Wysokość \(Int(height)) mm, cokół 100 mm.")
        let s = start(a, ctx, at, &warnings)
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }

    // MARK: - salon RTV

    private static func planTV(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let width = ZoneMath.clamp(ZoneMath.round50(a.number("width", 1800)), 1200, 3600)
        let lowH = a.number("height", 450)
        let floating = a.flag("floating", true)
        let tvSize = a.number("tvSize", 65)
        let withWallUnit = a.flag("wallUnit", true)
        var parts: [ZonePart] = []
        var at: Double = 0
        let n = max(2, Int((width / 900).rounded()))
        let widths = ZoneMath.splitModules(width, n)
        for (i, w) in widths.enumerated() {
            var p = base("tv-\(i)", w, plinth: floating ? 0 : 100, doors: 2, interior: .shelf,
                         feature: i == n / 2 ? "tv" : nil, label: "Niska szafka RTV",
                         height: lowH, depth: 400)
            p.mountHeight = floating ? 250 : 0
            p.at = at; at += w; parts.append(p)
        }
        if let idx = parts.firstIndex(where: { $0.feature == "tv" }) {
            parts[idx].appliances = [.tv]
        }
        if withWallUnit {
            let mount = lowH + (floating ? 250 : 0) + 1100
            let wh = min(400, ctx.wallHeight - mount - 60)
            if wh >= 300 {
                var wc = wallUnit("tv-wall", min(1800, width), height: wh, mount: mount,
                                  label: "Nadbudowa RTV")
                wc.at = (at - min(1800, width)) / 2
                parts.append(wc)
            } else {
                warnings.append("Nadbudowa RTV pominięta — za nisko sufit.")
            }
        }
        notes.append("TV \(Int(tvSize))\" (\(Int(tvSize * 22.1)) mm szer.), montaż 1100–1300 mm.")
        notes.append(floating ? "Szafka wisząca 250 mm nad podłogą." : "Szafka na cokole 100 mm.")
        notes.append("Przepusty na kable i listwa maskująca w środkowym module.")
        let s = start(a, ctx, at, &warnings)
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }

    // MARK: - łazienka

    private static func planBathroom(_ a: ZoneAnswers, _ ctx: ZoneContext) -> ZonePlan {
        var notes: [String] = []
        var warnings: [String] = []
        let vanity = ZoneMath.clamp(ZoneMath.round50(a.number("vanity", 800)), 600, 1600)
        let hanging = a.flag("hanging", true)
        let mirror = a.flag("mirror", true)
        let tall = a.flag("tall", true)
        let worktopH = a.number("worktopHeight", 850)
        let plinth: Double = hanging ? 0 : ZoneMath.clamp(worktopH - worktopT - baseH, 60, 200)
        var parts: [ZonePart] = []
        var at: Double = 0
        let n = max(1, Int((vanity / 800).rounded()))
        let widths = ZoneMath.splitModules(vanity, n)
        for (i, w) in widths.enumerated() {
            var p = base("vanity-\(i)", w, plinth: plinth, doors: 2,
                         appliances: i == 0 ? [.basin] : [], feature: i == 0 ? "sink" : nil,
                         label: "Szafka pod umywalkę", height: baseH, depth: 500)
            p.mountHeight = hanging ? 300 : 0
            p.at = at; at += w; parts.append(p)
        }
        if mirror {
            let mount = worktopH + 250
            let h = min(700, ctx.wallHeight - mount - 100)
            if h >= 400 {
                var wc = wallUnit("mirror", min(vanity, 1000), height: h, mount: mount,
                                  label: "Lustro z podświetleniem", interior: .none)
                wc.depth = 160
                wc.appliances = [.mirror]
                wc.at = 0
                parts.append(wc)
            } else {
                warnings.append("Lustro pominięte — za nisko sufit.")
            }
        }
        if tall {
            var p = tallUnit("bath-tall", 400, height: min(2000, ctx.wallHeight - 60),
                             depth: 350, doors: 1, interior: .shelf,
                             feature: "pantry", label: "Słupek łazienkowy 400")
            p.at = at; at += p.width; parts.append(p)
        }
        notes.append("Strefa mokra: płyta wodoodporna, krawędzie klejone, cokół PVC.")
        notes.append("Umywalka \(Int(worktopH)) mm nad podłogą, gniazda poza strefą 1.")
        if hanging { notes.append("Szafka wisząca 300 mm nad podłogą — dobra wentylacja.") }
        let s = start(a, ctx, at, &warnings)
        return ZonePlan(parts: parts, start: s, width: at, notes: notes, warnings: warnings)
    }
}
