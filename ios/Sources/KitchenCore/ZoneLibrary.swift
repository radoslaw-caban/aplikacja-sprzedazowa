import Foundation

/// Biblioteka stref: opisy zależności, odpowiedzi domyślne i pytania kreatora.
public enum ZoneLibrary {

    public static func spec(_ kind: ZoneKind) -> ZoneSpec {
        specs.first { $0.kind == kind } ?? specs[0]
    }

    public static func defaults(_ kind: ZoneKind) -> [String: ZoneValue] {
        spec(kind).defaults
    }

    public static func activeQuestions(_ kind: ZoneKind, answers: ZoneAnswers) -> [ZoneQuestion] {
        spec(kind).questions.filter { $0.isActive(answers) }
    }

    public static let specs: [ZoneSpec] = [

        // MARK: - kuchnia: gotowanie
        ZoneSpec(
            kind: .kitchenCook,
            label: "Kuchnia — strefa gotowania",
            short: "Gotowanie",
            group: .kitchen,
            icon: "flame.fill",
            description: "Ciąg z płytą grzewczą, strefami pracy po bokach, słupkiem piekarnika i zabudową lodówki. Witryny zamykają meble na obu końcach, okap prowadzi komin do sufitu.",
            relations: [
                "Płyta min. 600 mm, indukcja 800 na życzenie; strefy pracy min. 400 mm z każdej strony.",
                "Pod płytą szuflady (nie skrzydła) — dostęp bez schylania.",
                "Okap 650 mm nad płytą; bez okapu wymagana wentylacja mechaniczna.",
                "Piekarnik w słupku 600 na wysokości 900–1500; mikrofala nad piekarnikiem.",
                "Lodówka na końcu ciągu (600/700/900), witryny 400 na skrajach.",
                "Szafki górne 600 mm nad blatem, pomijane nad oknem.",
                "Wysokość blatu 860–910 → cokół liczony automatycznie.",
            ],
            defaults: [
                "width": .number(2400), "align": .text("center"),
                "worktopHeight": .number(900), "fronts": .text("handle"),
                "hob": .text("induction-600"), "hobPos": .number(50),
                "hood": .text("chimney"), "oven": .text("column"),
                "microwave": .text("above-oven"), "fridge": .text("built-in"),
                "vitrines": .flag(true), "dishwasher": .flag(true),
                "wallCabinets": .flag(true),
            ],
            questions: [
                widthQ("Długość ciągu dolnego", 1200, 3600),
                alignQuestion,
                ZoneQuestion(id: "hob", label: "Rodzaj płyty grzewczej", feature: "hob",
                             choices: [
                                c("induction-600", "Indukcja 600", "Standard, 4 pola"),
                                c("induction-800", "Indukcja 800", "5 pól, szeroki front"),
                                c("gas-600", "Gaz 600", "Palniki + ruszt"),
                                c("none", "Bez płyty", "Tylko blat roboczy"),
                             ]),
                ZoneQuestion(id: "hobPos", label: "Gdzie płyta na blacie", type: .position,
                             feature: "hob", help: "Przeciągnij po blacie albo ustaw suwakiem.",
                             placement: true, hideWhen: ["hob": .text("none")]),
                ZoneQuestion(id: "hood", label: "Okap nad płytą", feature: "hob",
                             choices: [c("chimney", "Kominowy"), c("flat", "Płaski"), c("none", "Brak")],
                             hideWhen: ["hob": .text("none")]),
                ZoneQuestion(id: "oven", label: "Piekarnik", feature: "oven",
                             choices: [
                                c("column", "Słupek 600", "Piekarnik + mikrofala na wysokości"),
                                c("under", "Pod blatem", "Nisza 595×595"),
                                c("none", "Brak"),
                             ]),
                ZoneQuestion(id: "microwave", label: "Mikrofala", feature: "oven",
                             choices: [c("above-oven", "Nad piekarnikiem"), c("none", "Brak")],
                             showWhen: ["oven": .text("column")]),
                ZoneQuestion(id: "fridge", label: "Rodzaj lodówki", feature: "fridge",
                             choices: [
                                c("built-in", "Do zabudowy 600"),
                                c("freestanding", "Wolnostojąca 700"),
                                c("side-by-side", "Side-by-side 900"),
                                c("none", "Bez lodówki"),
                             ]),
                ZoneQuestion(id: "vitrines", label: "Witryny na końcu mebli", feature: "vitrine",
                             choices: [c(true, "Tak — 2 × 400 szklane"), c(false, "Nie")]),
                ZoneQuestion(id: "dishwasher", label: "Zmywarka w ciągu", feature: "dishwasher",
                             choices: [c(true, "Tak 600"), c(false, "Nie")]),
                ZoneQuestion(id: "wallCabinets", label: "Szafki górne",
                             choices: [c(true, "Tak, 600 nad blatem"), c(false, "Tylko blat")]),
                worktopQuestion,
                frontsQuestion,
            ]
        ),

        // MARK: - kuchnia: czystość
        ZoneSpec(
            kind: .kitchenClean,
            label: "Kuchnia — strefa czystości",
            short: "Czystość",
            group: .kitchen,
            icon: "drop.fill",
            description: "Zlew, zmywarka i segregacja odpadów w jednym ciągu, z szafkami górnymi pomijającymi okno. Pozycję zlewu przesuwa się po blacie.",
            relations: [
                "Zlew 600/800/900; szafka bez półki (syfon, kosz), dojście serwisowe 600 mm.",
                "Zmywarka 600 w promieniu 1200 mm od zlewu.",
                "Kosz na odpady w szufladzie pod zlewem, segregacja 2–3 frakcje.",
                "Szafki górne 600 mm nad blatem; nad oknem pomijane.",
                "Min. 400 mm strefy odkładczej przy zlewie.",
                "Blat 860–910 mm, cokół liczony automatycznie.",
            ],
            defaults: [
                "width": .number(1800), "align": .text("center"),
                "worktopHeight": .number(900), "fronts": .text("handle"),
                "sink": .text("one-half"), "sinkPos": .number(40),
                "dishwasher": .flag(true), "bin": .flag(true),
                "wallCabinets": .flag(true), "tallStorage": .flag(false),
            ],
            questions: [
                widthQ("Długość ciągu", 1200, 4200),
                alignQuestion,
                ZoneQuestion(id: "sink", label: "Rodzaj zlewu", feature: "sink",
                             choices: [
                                c("single", "1-komorowy 600"),
                                c("one-half", "1,5-komorowy 800"),
                                c("double", "2-komorowy 900"),
                                c("none", "Brak zlewu"),
                             ]),
                ZoneQuestion(id: "sinkPos", label: "Gdzie zlew na blacie", type: .position,
                             feature: "sink", help: "Przeciągnij zlew po blacie albo ustaw suwakiem.",
                             placement: true, hideWhen: ["sink": .text("none")]),
                ZoneQuestion(id: "dishwasher", label: "Zmywarka", feature: "dishwasher",
                             choices: [c(true, "Tak 600, obok zlewu"), c(false, "Nie")]),
                ZoneQuestion(id: "bin", label: "Segregacja odpadów pod zlewem", feature: "sink",
                             choices: [c(true, "Tak, 2–3 frakcje"), c(false, "Nie")]),
                ZoneQuestion(id: "tallStorage", label: "Słupek/spiżarnia na końcu",
                             choices: [c(true, "Tak 600"), c(false, "Nie")]),
                ZoneQuestion(id: "wallCabinets", label: "Szafki górne",
                             choices: [c(true, "Tak"), c(false, "Nie")]),
                worktopQuestion,
                frontsQuestion,
            ]
        ),

        // MARK: - kuchnia: wysoka zabudowa
        ZoneSpec(
            kind: .kitchenTall,
            label: "Kuchnia — wysoka zabudowa",
            short: "Wysoka",
            group: .kitchen,
            icon: "cabinet.fill",
            description: "Słupki od lodówki przez piekarnik z mikrofalą do spiżarni. Wysokość 2216 lub do sufitu, cokół zlicowany z ciągiem dolnym.",
            relations: [
                "Lodówka 600/700/900, piekarnik 600, spiżarnia 450/600/900.",
                "Wysokość 2216 mm lub do sufitu (zaślepka 40 mm).",
                "Cokół 150 mm — zlicowany z kuchnią dolną.",
                "Piekarnik 900–1500 mm nad podłogą, mikrofala bezpośrednio nad nim.",
                "Spiżarnia: półki 350 mm, cargo 450/600.",
            ],
            defaults: [
                "align": .text("left"), "fridge": .text("built-in"),
                "oven": .flag(true), "microwave": .flag(true),
                "pantryWidth": .number(600), "toCeiling": .flag(true),
            ],
            questions: [
                alignQuestion,
                ZoneQuestion(id: "fridge", label: "Rodzaj lodówki", feature: "fridge",
                             choices: [
                                c("built-in", "Do zabudowy 600"),
                                c("freestanding", "Wolnostojąca 700"),
                                c("side-by-side", "Side-by-side 900"),
                                c("none", "Bez lodówki"),
                             ]),
                ZoneQuestion(id: "oven", label: "Piekarnik w słupku", feature: "oven",
                             choices: [c(true, "Tak 600"), c(false, "Nie")]),
                ZoneQuestion(id: "microwave", label: "Mikrofala nad piekarnikiem", feature: "oven",
                             choices: [c(true, "Tak"), c(false, "Nie")],
                             showWhen: ["oven": .flag(true)]),
                ZoneQuestion(id: "pantryWidth", label: "Spiżarnia", feature: "pantry",
                             choices: [c(450, "450 mm"), c(600, "600 mm"), c(900, "900 mm"), c(0, "Brak")]),
                ZoneQuestion(id: "toCeiling", label: "Wysokość zabudowy",
                             choices: [c(true, "Do sufitu"), c(false, "Korpus 2216")]),
            ]
        ),

        // MARK: - kuchnia: wyspa
        ZoneSpec(
            kind: .kitchenIsland,
            label: "Kuchnia — wyspa",
            short: "Wyspa",
            group: .kitchen,
            icon: "square.split.2x1",
            description: "Wyspa 1800–3600 z płytą lub zlewem, blatem 860 i nawisem 300 na siedzenie. Stoi w świetle pomieszczenia — bez szafek górnych, z okapem sufitowym.",
            relations: [
                "Długość 1800–3600, korpus 560, blat 860 (nawis 300 na krzesła).",
                "Płyta lub zlew na środku, szuflady pod urządzeniem.",
                "Przejścia min. 900 mm z każdej strony (rekomendowane 1000–1200).",
                "Okap sufitowy nad płytą, kanał w suficie.",
                "Blat 38 mm, cokół 80–220 mm.",
            ],
            defaults: [
                "width": .number(2400), "align": .text("center"),
                "worktopHeight": .number(900), "fronts": .text("handle"),
                "islandFeature": .text("hob"), "seating": .flag(true),
            ],
            questions: [
                widthQ("Długość wyspy", 1800, 3600),
                ZoneQuestion(id: "islandFeature", label: "Co na wyspie", feature: "zone",
                             choices: [c("hob", "Płyta grzewcza"), c("sink", "Zlew"), c("none", "Tylko blat roboczy")]),
                ZoneQuestion(id: "seating", label: "Nawis na siedzenie", feature: "zone",
                             choices: [c(true, "Tak, 300 mm"), c(false, "Nie")]),
                worktopQuestion,
                frontsQuestion,
            ]
        ),

        // MARK: - szafa otwierana
        ZoneSpec(
            kind: .wardrobeHinged,
            label: "Sypialnia — szafa otwierana",
            short: "Szafa otwierana",
            group: .bedroom,
            icon: "door.left.hand.open",
            description: "Szafa 600 mm głębokości, skrzydła 400–600, wymagane 600 mm wolnej przestrzeni przed frontem. Drążek i półki, wysokość 2216 lub do sufitu.",
            relations: [
                "Głębokość 600 mm — ubrania na drążku bez gniecenia.",
                "Skrzydła 400–600 mm; przy 2 skrzydłach sekcja do 1200 mm.",
                "Wymagane 600 mm przed frontem na otwarcie skrzydła.",
                "Wysokość 2216 lub do sufitu (zaślepka 40 mm).",
                "Drążek 1800 mm, półki 350 mm, cokół 100 mm.",
            ],
            defaults: [
                "width": .number(1800), "align": .text("center"),
                "doors": .number(2), "toCeiling": .flag(true), "interior": .text("rail"),
            ],
            questions: [
                widthQ("Szerokość szafy", 900, 4200, feature: "wardrobe"),
                alignQuestion,
                ZoneQuestion(id: "doors", label: "Skrzydła w sekcji", feature: "wardrobe",
                             choices: [c(1, "1 skrzydło"), c(2, "2 skrzydła")]),
                ZoneQuestion(id: "interior", label: "Wnętrze", feature: "wardrobe",
                             choices: [c("rail", "Drążek + półki"), c("shelf", "Same półki")]),
                ZoneQuestion(id: "toCeiling", label: "Wysokość",
                             choices: [c(true, "Do sufitu"), c(false, "Korpus 2216")]),
            ]
        ),

        // MARK: - szafa przesuwna
        ZoneSpec(
            kind: .wardrobeSliding,
            label: "Sypialnia — szafa przesuwna",
            short: "Szafa przesuwna",
            group: .bedroom,
            icon: "arrow.left.and.right.square",
            description: "Szafa 650 mm głębokości z 2–3 panelami przesuwnymi. Nie potrzebuje miejsca na otwieranie, wymaga prowadnic góra/dół i równej podłogi.",
            relations: [
                "Głębokość 650 mm — miejsce na prowadnice i ubrania.",
                "Panele 2 lub 3, szerokość panelu ~900–1200 mm.",
                "Bez strefy otwierania — może stać przy łóżku.",
                "Prowadnica górna w suficie, dolna w podłodze, poziom 1 mm/m.",
                "Opcja panelu lustrzanego.",
            ],
            defaults: [
                "width": .number(1800), "align": .text("center"),
                "panels": .number(2), "mirror": .flag(false),
                "toCeiling": .flag(true), "interior": .text("rail"),
            ],
            questions: [
                widthQ("Szerokość szafy", 900, 4200, feature: "wardrobe"),
                alignQuestion,
                ZoneQuestion(id: "panels", label: "Liczba paneli", feature: "wardrobe",
                             choices: [c(2, "2 panele"), c(3, "3 panele")]),
                ZoneQuestion(id: "mirror", label: "Panel lustrzany", feature: "wardrobe",
                             choices: [c(false, "Nie"), c(true, "Tak")]),
                ZoneQuestion(id: "interior", label: "Wnętrze", feature: "wardrobe",
                             choices: [c("rail", "Drążek + półki"), c("shelf", "Same półki")]),
                ZoneQuestion(id: "toCeiling", label: "Wysokość",
                             choices: [c(true, "Do sufitu"), c(false, "Korpus 2216")]),
            ]
        ),

        // MARK: - salon RTV
        ZoneSpec(
            kind: .livingTV,
            label: "Salon — strefa RTV",
            short: "RTV / salon",
            group: .living,
            icon: "tv.fill",
            description: "Niska szafka RTV z opcją podwieszenia, TV 55–75 cali i nadbudowa na ścianie. Przepusty na kable i listwa maskująca.",
            relations: [
                "Wysokość szafki 400–450 mm, głębokość 400 mm (sprzęt, kable).",
                "TV 55/65/75 cali, środek ekranu 1100–1300 mm nad podłogą.",
                "Podwieszenie 250 mm nad podłogą albo cokół 100 mm.",
                "Nadbudowa 400 mm głębokości 350, nad telewizorem.",
                "Przepusty kablowe w środkowym module.",
            ],
            defaults: [
                "width": .number(1800), "align": .text("center"),
                "height": .number(450), "floating": .flag(true),
                "tvSize": .number(65), "wallUnit": .flag(true),
            ],
            questions: [
                widthQ("Szerokość szafki RTV", 1200, 3600, feature: "tv"),
                alignQuestion,
                ZoneQuestion(id: "tvSize", label: "Wielkość telewizora", feature: "tv",
                             choices: [c(55, "55\""), c(65, "65\""), c(75, "75\""), c(83, "83\"")]),
                ZoneQuestion(id: "height", label: "Wysokość szafki", feature: "tv",
                             choices: [c(400, "400 mm"), c(450, "450 mm"), c(500, "500 mm")]),
                ZoneQuestion(id: "floating", label: "Montaż",
                             choices: [c(true, "Wisząca 250 mm"), c(false, "Na cokole 100 mm")]),
                ZoneQuestion(id: "wallUnit", label: "Nadbudowa na ścianie",
                             choices: [c(true, "Tak"), c(false, "Nie")]),
            ]
        ),

        // MARK: - łazienka
        ZoneSpec(
            kind: .bathroom,
            label: "Łazienka",
            short: "Łazienka",
            group: .bathroom,
            icon: "bathtub.fill",
            description: "Szafka pod umywalkę z blatem ceramicznym, lustro z podświetleniem i słupek 400. Wersja wisząca lub na cokole, płyta wodoodporna.",
            relations: [
                "Szafka 800/1000/1200, głębokość 500, blat 850 mm.",
                "Wisząca 300 mm nad podłogą albo cokół 60–200 mm.",
                "Lustro 700 mm wysokości, 250 mm nad blatem, podświetlenie LED.",
                "Słupek 400 × 350 × 2000 na kosmetyki i ręczniki.",
                "Płyta wodoodporna, krawędzie klejone, cokół PVC.",
            ],
            defaults: [
                "vanity": .number(800), "align": .text("center"),
                "hanging": .flag(true), "mirror": .flag(true),
                "tall": .flag(true), "worktopHeight": .number(850),
            ],
            questions: [
                widthQ("Szerokość szafki", 600, 1600, feature: "sink", id: "vanity"),
                alignQuestion,
                ZoneQuestion(id: "hanging", label: "Montaż szafki",
                             choices: [c(true, "Wisząca"), c(false, "Na cokole")]),
                ZoneQuestion(id: "mirror", label: "Lustro z podświetleniem", feature: "sink",
                             choices: [c(true, "Tak"), c(false, "Nie")]),
                ZoneQuestion(id: "tall", label: "Słupek łazienkowy 400",
                             choices: [c(true, "Tak"), c(false, "Nie")]),
                ZoneQuestion(id: "worktopHeight", label: "Wysokość blatu", feature: "sink",
                             choices: [c(830, "830 mm"), c(850, "850 mm"), c(880, "880 mm")]),
            ]
        ),
    ]

    // MARK: - wspólne pytania

    private static func c(_ v: Double, _ label: String, _ hint: String? = nil) -> ZoneChoice {
        ZoneChoice(.number(v), label, hint: hint)
    }

    private static func c(_ v: String, _ label: String, _ hint: String? = nil) -> ZoneChoice {
        ZoneChoice(.text(v), label, hint: hint)
    }

    private static func c(_ v: Bool, _ label: String, _ hint: String? = nil) -> ZoneChoice {
        ZoneChoice(.flag(v), label, hint: hint)
    }

    private static func widthQ(_ label: String, _ min: Double, _ max: Double,
                               feature: String = "zone", id: String = "width") -> ZoneQuestion {
        ZoneQuestion(id: id, label: label, type: .position, feature: feature,
                     help: "Skaluj zabudowę wzdłuż ściany — podgląd (cień szafek) zmienia się na żywo.",
                     min: min, max: max, step: 50, unit: " mm")
    }

    private static let alignQuestion = ZoneQuestion(
        id: "align", label: "Ustawienie na ścianie", feature: "zone",
        choices: [c("left", "Od lewej"), c("center", "Na środku"), c("right", "Od prawej")]
    )

    private static let frontsQuestion = ZoneQuestion(
        id: "fronts", label: "Rodzaj frontów",
        choices: [c("handle", "Z uchwytami"), c("handleless", "Bezuchwytowe")]
    )

    private static let worktopQuestion = ZoneQuestion(
        id: "worktopHeight", label: "Wysokość blatu", feature: "zone",
        help: "Cokół liczy się sam: H − 38 mm (blat) − 720 mm (korpus).",
        choices: [c(860, "860 mm — niski"), c(880, "880 mm — kompakt"),
                  c(900, "900 mm — standard"), c(910, "910 mm — wysoki")]
    )
}
