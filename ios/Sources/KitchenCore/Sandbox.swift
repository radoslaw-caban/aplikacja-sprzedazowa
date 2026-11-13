import Foundation
import SwiftUI
import KitchenCore

/// PIASKOWNICA — obiekty swobodne, niezależne od zabudowy kuchennej.
///
/// Model jest celowo płaski: każdy obiekt ma pozycję, obrót, skalę, kolor
/// i własny dźwięk. Nie ma hierarchii ani rodziców — piaskownica ma być
/// miejscem eksperymentu, a nie drugim systemem szafek.
///
/// Wszystkie wymiary w milimetrach, jak reszta projektu.

/// Co można postawić w piaskownicy.
public enum SandboxKind: String, Codable, Sendable, CaseIterable, Identifiable {
    // ukształtowanie terenu
    case terrainFlat, terrainHill, terrainMound, terrainTrench
    // gleba i skały
    case soil, gravel, boulder, rockSmall, sandPile
    // rośliny
    case tree, bush, grassTuft, flower, hedge
    // zwierzęta i ludzie
    case animalSmall, animalLarge, person
    // ogród
    case pavingTile, fence, gate, planter, bench
    // procesy budowlane
    case foundation, wallSegment, roofPanel, windowFrame, doorFrame, pipeRun
    // wykończenia
    case paintPatch, floorPatch, tilePatch, wallpaperPatch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .terrainFlat: "Teren płaski"
        case .terrainHill: "Wzniesienie"
        case .terrainMound: "Kopiec"
        case .terrainTrench: "Wykop"
        case .soil: "Gleba"
        case .gravel: "Żwir"
        case .boulder: "Głaz"
        case .rockSmall: "Skałka"
        case .sandPile: "Piasek"
        case .tree: "Drzewo"
        case .bush: "Krzew"
        case .grassTuft: "Kępa trawy"
        case .flower: "Kwiaty"
        case .hedge: "Żywopłot"
        case .animalSmall: "Zwierzę małe"
        case .animalLarge: "Zwierzę duże"
        case .person: "Postać"
        case .pavingTile: "Kostka brukowa"
        case .fence: "Ogrodzenie"
        case .gate: "Brama"
        case .planter: "Donica"
        case .bench: "Ławka"
        case .foundation: "Fundament"
        case .wallSegment: "Ściana"
        case .roofPanel: "Połać dachu"
        case .windowFrame: "Okno"
        case .doorFrame: "Drzwi"
        case .pipeRun: "Instalacja"
        case .paintPatch: "Malowanie"
        case .floorPatch: "Podłoga"
        case .tilePatch: "Płytki"
        case .wallpaperPatch: "Tapeta"
        }
    }

    /// Kategoria w bibliotece piaskownicy — kolejność i grupowanie w UI.
    public var category: SandboxCategory {
        switch self {
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench: .terrain
        case .soil, .gravel, .boulder, .rockSmall, .sandPile: .soil
        case .tree, .bush, .grassTuft, .flower, .hedge: .plants
        case .animalSmall, .animalLarge, .person: .creatures
        case .pavingTile, .fence, .gate, .planter, .bench: .garden
        case .foundation, .wallSegment, .roofPanel, .windowFrame, .doorFrame, .pipeRun: .construction
        case .paintPatch, .floorPatch, .tilePatch, .wallpaperPatch: .finishing
        }
    }

    /// Czy obiekt jest „naturalny" — przy takich ręka robi pstryknięcie.
    /// Beton, rury i tapeta nie pstrykają: to robota, nie natura.
    public var isNatural: Bool {
        switch self {
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench,
             .soil, .gravel, .boulder, .rockSmall, .sandPile,
             .tree, .bush, .grassTuft, .flower, .hedge,
             .animalSmall, .animalLarge, .person:
            true
        default:
            false
        }
    }

    /// Domyślne wymiary (mm) — realne, nie „na oko".
    public var defaultSize: SIMD3<Double> {
        switch self {
        case .terrainFlat: SIMD3(4000, 40, 4000)
        case .terrainHill: SIMD3(3000, 900, 3000)
        case .terrainMound: SIMD3(1800, 600, 1800)
        case .terrainTrench: SIMD3(2500, 500, 800)
        case .soil: SIMD3(2000, 200, 2000)
        case .gravel: SIMD3(1500, 80, 1500)
        case .boulder: SIMD3(1200, 900, 1100)
        case .rockSmall: SIMD3(400, 260, 380)
        case .sandPile: SIMD3(1600, 400, 1600)
        case .tree: SIMD3(900, 6000, 900)
        case .bush: SIMD3(800, 700, 800)
        case .grassTuft: SIMD3(400, 250, 400)
        case .flower: SIMD3(300, 350, 300)
        case .hedge: SIMD3(2000, 900, 500)
        case .animalSmall: SIMD3(300, 250, 500)
        case .animalLarge: SIMD3(600, 1500, 1600)
        case .person: SIMD3(500, 1750, 350)
        case .pavingTile: SIMD3(600, 60, 600)
        case .fence: SIMD3(1800, 1100, 80)
        case .gate: SIMD3(1000, 1200, 80)
        case .planter: SIMD3(600, 500, 600)
        case .bench: SIMD3(1500, 450, 500)
        case .foundation: SIMD3(3000, 800, 600)
        case .wallSegment: SIMD3(2400, 2600, 240)
        case .roofPanel: SIMD3(3000, 200, 2400)
        case .windowFrame: SIMD3(1200, 1400, 140)
        case .doorFrame: SIMD3(900, 2100, 140)
        case .pipeRun: SIMD3(2000, 120, 120)
        case .paintPatch: SIMD3(2000, 2400, 20)
        case .floorPatch: SIMD3(2000, 20, 2000)
        case .tilePatch: SIMD3(1200, 20, 1200)
        case .wallpaperPatch: SIMD3(2000, 2400, 10)
        }
    }

    /// Domyślny kolor — ziemia brązowa, beton szary, rośliny zielone.
    public var defaultColor: String {
        switch self {
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench: "#7a6a52"
        case .soil: "#6b5741"
        case .gravel: "#9a958c"
        case .boulder, .rockSmall: "#8a8681"
        case .sandPile: "#d9c8a3"
        case .tree: "#4a6b3f"
        case .bush: "#557a48"
        case .grassTuft: "#6b8f52"
        case .flower: "#b06a8a"
        case .hedge: "#43643a"
        case .animalSmall, .animalLarge: "#8a7358"
        case .person: "#c9b6a0"
        case .pavingTile: "#b0a89c"
        case .fence: "#8b7355"
        case .gate: "#6d6156"
        case .planter: "#a89478"
        case .bench: "#8f7554"
        case .foundation: "#8c8c8c"
        case .wallSegment: "#d8d3c9"
        case .roofPanel: "#6a4a3a"
        case .windowFrame: "#e8e6e0"
        case .doorFrame: "#8a6a4a"
        case .pipeRun: "#b8bcc1"
        case .paintPatch: "#e4ded2"
        case .floorPatch: "#c2a882"
        case .tilePatch: "#cfcac0"
        case .wallpaperPatch: "#ddd2c4"
        }
    }

    /// Fach, który odpowiada za wykonanie tego elementu.
    /// nil = natura, nikt tego nie wykonuje — wtedy ręka jest ręką Boga.
    /// Człowiek robi wszystko pozostałe, a każdy element ma swojego fachowca,
    /// bo to on odpowiada za jakość i on się pod tym podpisuje.
    public var trade: SandboxTrade? {
        switch self {
        // natura — ręka Boga, pstryknięcie
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench,
             .soil, .gravel, .boulder, .rockSmall, .sandPile,
             .tree, .bush, .grassTuft, .flower, .hedge,
             .animalSmall, .animalLarge, .person:
            nil
        // robota ludzka — ręka fachowca z narzędziem
        case .pavingTile: .brukarz
        case .fence, .gate: .monter
        case .planter, .bench: .stolarz
        case .foundation: .betoniarz
        case .wallSegment: .murarz
        case .roofPanel: .dekarz
        case .windowFrame, .doorFrame: .stolarz
        case .pipeRun: .hydraulik
        case .paintPatch: .malarz
        case .floorPatch: .posadzkarz
        case .tilePatch: .glazurnik
        case .wallpaperPatch: .malarz
        }
    }

    /// Dźwięk wstawienia — krótki, rozpoznawalny, bez plików audio.
    /// Generowany proceduralnie, więc apka nie wozi zbędnych zasobów.
    public var defaultSound: SandboxSound {
        switch self {
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench,
             .soil, .sandPile: .thud
        case .gravel: .crunch
        case .boulder, .rockSmall: .stone
        case .tree, .bush, .hedge: .leaves
        case .grassTuft, .flower: .rustle
        case .animalSmall, .animalLarge: .chirp
        case .person: .pop
        case .pavingTile: .tap
        case .fence, .gate: .knock
        case .planter, .bench: .wood
        case .foundation, .wallSegment, .roofPanel: .thud
        case .windowFrame, .doorFrame: .knock
        case .pipeRun: .metal
        case .paintPatch: .swish
        case .floorPatch, .tilePatch, .wallpaperPatch: .swish
        }
    }
}

/// Fach odpowiadający za element — z ikoną narzędzia, które trzyma ręka.
///
/// To nie jest ozdoba: przy każdym elemencie wiadomo, kto go wykonuje,
/// a więc kto odpowiada za poprawkę i kto go policzy w wycenie.
public enum SandboxTrade: String, Codable, Sendable, CaseIterable, Identifiable {
    case brukarz, monter, stolarz, betoniarz, murarz, dekarz
    case hydraulik, elektryk, malarz, posadzkarz, glazurnik

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .brukarz: "Brukarz"
        case .monter: "Monter"
        case .stolarz: "Stolarz"
        case .betoniarz: "Betoniarz"
        case .murarz: "Murarz"
        case .dekarz: "Dekarz"
        case .hydraulik: "Hydraulik"
        case .elektryk: "Elektryk"
        case .malarz: "Malarz"
        case .posadzkarz: "Posadzkarz"
        case .glazurnik: "Glazurnik"
        }
    }

    /// Narzędzie w dłoni — SF Symbol, który rysuje się przy kursorze.
    public var tool: String {
        switch self {
        case .brukarz: "square.grid.3x3.fill"      // kostka / kielnia brukarska
        case .monter: "wrench.and.screwdriver.fill"
        case .stolarz: "ruler.fill"                 // kątownik stolarski
        case .betoniarz: "cylinder.fill"            // mieszadło / wiadro
        case .murarz: "rectangle.stack.fill"        // kielnia i pustaki
        case .dekarz: "triangle.fill"               // połać dachu
        case .hydraulik: "pipe.and.drop.fill"       // rura i kropla
        case .elektryk: "bolt.fill"
        case .malarz: "paintbrush.pointed.fill"
        case .posadzkarz: "square.split.2x2.fill"   // wylewka / deski
        case .glazurnik: "square.grid.2x2.fill"     // płytki
        }
    }

    /// Kolor fachu — stonowany, żeby nie konkurował z kolorem kategorii.
    public var tintHex: String {
        switch self {
        case .brukarz: "#9a8f7a"
        case .monter: "#8a94a0"
        case .stolarz: "#a8855f"
        case .betoniarz: "#9a9a9a"
        case .murarz: "#b08a72"
        case .dekarz: "#8a6a5a"
        case .hydraulik: "#6f8fa8"
        case .elektryk: "#c2a24a"
        case .malarz: "#8fa07a"
        case .posadzkarz: "#a89478"
        case .glazurnik: "#8496a8"
        }
    }
}

public enum SandboxCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case terrain, soil, plants, creatures, garden, construction, finishing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .terrain: "Ukształtowanie terenu"
        case .soil: "Skałki i gleba"
        case .plants: "Rośliny"
        case .creatures: "Zwierzęta, ludzie"
        case .garden: "Ogród"
        case .construction: "Procesy budowlane"
        case .finishing: "Wykończenia"
        }
    }

    public var items: [SandboxKind] {
        SandboxKind.allCases.filter { $0.category == self }
    }
}

/// Dźwięki wstawiania — proceduralne, bez plików.
public enum SandboxSound: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, pop, thud, stone, leaves, rustle, chirp, crunch, tap, knock, wood, metal, swish, snap

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: "Cisza"
        case .pop: "Pstryknięcie"
        case .thud: "Głuchy stuk"
        case .stone: "Kamień"
        case .leaves: "Liście"
        case .rustle: "Szmer"
        case .chirp: "Ćwierk"
        case .crunch: "Chrzęst"
        case .tap: "Stuknięcie"
        case .knock: "Pukanie"
        case .wood: "Drewno"
        case .metal: "Metal"
        case .swish: "Muśnięcie"
        case .snap: "Trzask"
        }
    }
}

/// Obiekt w piaskownicy.
public struct SandboxObject: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: SandboxKind
    public var name: String
    /// pozycja w mm (X, Y, Z) — Y to wysokość nad terenem
    public var position: SIMD3<Double>
    /// obrót wokół osi Y w stopniach
    public var rotationY: Double
    /// skala (1 = wymiary domyślne)
    public var scale: SIMD3<Double>
    /// rozmiar bazowy w mm (przed skalą)
    public var size: SIMD3<Double>
    public var color: String
    public var sound: SandboxSound
    /// głośność dźwięku wstawienia 0…1
    public var soundVolume: Double
    /// czy obiekt jest przywiązany do terenu (nie lata)
    public var grounded: Bool

    public init(
        id: UUID = UUID(),
        kind: SandboxKind,
        name: String? = nil,
        position: SIMD3<Double> = .zero,
        rotationY: Double = 0,
        scale: SIMD3<Double> = SIMD3(1, 1, 1),
        size: SIMD3<Double>? = nil,
        color: String? = nil,
        sound: SandboxSound? = nil,
        soundVolume: Double = 0.7,
        grounded: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.label
        self.position = position
        self.rotationY = rotationY
        self.scale = scale
        self.size = size ?? kind.defaultSize
        self.color = color ?? kind.defaultColor
        self.sound = sound ?? kind.defaultSound
        self.soundVolume = soundVolume
        self.grounded = grounded
    }

    /// Rzeczywisty rozmiar po uwzględnieniu skali (mm).
    public var effectiveSize: SIMD3<Double> {
        SIMD3(size.x * scale.x, size.y * scale.y, size.z * scale.z)
    }
}
