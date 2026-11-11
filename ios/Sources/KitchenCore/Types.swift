import Foundation

/// Wszystkie wymiary w milimetrach — tak jak w projekcie produkcyjnym.
/// Renderer przelicza mm → metry (0.001). Nigdy odwrotnie.
public enum Unit {
    public static let mmPerMeter: Double = 1000
}

/// Standardy konstrukcji bezramowej (EN / produkcja mebli).
public enum Standards {
    public static let panel: Double = 18        // płyta korpusu
    public static let back: Double = 4          // plecy HDF
    public static let backInset: Double = 3     // wcięcie pleców
    public static let gap: Double = 3           // szczelina frontu
    public static let baseHeight: Double = 720  // wysokość całkowita szafki dolnej (z cokołem)
    public static let baseDepth: Double = 560
    public static let plinthHeight: Double = 150
    public static let plinthSetback: Double = 40
    public static let worktopThickness: Double = 38
    public static let worktopOverhang: Double = 20
    public static let wallDepth: Double = 350
}

public enum CabinetType: String, Codable, Sendable {
    case base       // podblatowa
    case wall       // wisząca
    case tall       // stojąca
    case panel      // zaślepka 18 mm — płyta widoczna obrzeżem, nie korpus
}

public enum ElementKind: String, Codable, Sendable {
    case shelf
    case drawer
    case divider
    case cutout
}

/// System szuflad — nominalna wysokość frontu (Blum LEGRABOX).
public enum DrawerSystem: String, Codable, Sendable {
    case n = "N"   // 66.5
    case m = "M"   // 90.5
    case k = "K"   // 128.5

    public var frontHeight: Double {
        switch self {
        case .n: 66.5
        case .m: 90.5
        case .k: 128.5
        }
    }
}

public struct CabinetElement: Identifiable, Codable, Sendable {
    public var id: UUID
    public var kind: ElementKind
    /// pozycja dolnej krawędzi elementu od dna korpusu (mm)
    public var y: Double
    /// wysokość elementu (mm)
    public var height: Double
    public var drawer: DrawerSystem?

    public init(id: UUID = UUID(), kind: ElementKind, y: Double, height: Double, drawer: DrawerSystem? = nil) {
        self.id = id
        self.kind = kind
        self.y = y
        self.height = height
        self.drawer = drawer
    }
}

public struct Cabinet: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var type: CabinetType
    public var width: Double        // mm
    public var height: Double       // mm, całkowita (dla base zawiera cokół)
    public var depth: Double        // mm
    public var plinth: Double       // mm, wysokość cokołu
    public var x: Double            // pozycja środka w pokoju
    public var z: Double
    public var rotation: Double     // 0/90/180/270
    public var mountHeight: Double  // dla szafek wiszących
    public var elements: [CabinetElement]
    public var color: String
    /// Nazwa pliku tekstury frontu (biblioteka tekstur). `nil` = kolor jednolity.
    public var texture: String?
    // MARK: - strefy zabudowy (auto-projekt)
    /// Strefa, która wygenerowała szafkę. `nil` = szafka wstawiona ręcznie.
    public var zoneID: UUID?
    /// rola w strefie: sink / hob / oven / fridge / tv / wardrobe…
    public var zoneRole: String?
    /// AGD i urządzenia rysowane razem z szafką
    public var appliances: [ApplianceKind]?
    /// szafa przesuwna: liczba paneli (front rysowany bez zawiasów)
    public var slidingPanels: Int?
    /// blat głębszy niż korpus (wyspa, nawis) — mm
    public var worktopDepth: Double?
    /// przesunięcie blatu w głąb, lokalne +Z — mm
    public var worktopShift: Double?
    /// podgląd strefy: cień szafki (półprzezroczysty) zamiast materiału
    public var preview: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        type: CabinetType = .base,
        width: Double = 600,
        height: Double = Standards.baseHeight,
        depth: Double = Standards.baseDepth,
        plinth: Double = Standards.plinthHeight,
        x: Double = 0,
        z: Double = 0,
        rotation: Double = 0,
        mountHeight: Double = 0,
        elements: [CabinetElement] = [],
        color: String = "#c8bca9",
        texture: String? = nil,
        zoneID: UUID? = nil,
        zoneRole: String? = nil,
        appliances: [ApplianceKind]? = nil,
        slidingPanels: Int? = nil,
        worktopDepth: Double? = nil,
        worktopShift: Double? = nil,
        preview: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.width = width
        self.height = height
        self.depth = depth
        self.plinth = plinth
        self.x = x
        self.z = z
        self.rotation = rotation
        self.mountHeight = mountHeight
        self.elements = elements
        self.color = color
        self.texture = texture
        self.zoneID = zoneID
        self.zoneRole = zoneRole
        self.appliances = appliances
        self.slidingPanels = slidingPanels
        self.worktopDepth = worktopDepth
        self.worktopShift = worktopShift
        self.preview = preview
    }
}

/// Bryła do wygenerowania w scenie (mm, względem środka szafki).
public struct Box: Identifiable, Sendable {
    public enum Role: String, Sendable {
        case side, bottom, top, back, shelf, divider, front, drawerFront, plinth, worktop, scene, appliance
    }

    public let id: String
    public let role: Role
    public let cabinetID: UUID?
    public let size: SIMD3<Double>
    public let position: SIMD3<Double>
    public let color: String
    /// Nazwa pliku tekstury (opcjonalnie) — materiały z biblioteki.
    public var texture: String? = nil
    public var rotationY: Double = 0
    /// podgląd strefy — bryła rysowana jako cień (przezroczysty błękit)
    public var preview: Bool = false

    public init(
        id: String,
        role: Role,
        cabinetID: UUID?,
        size: SIMD3<Double>,
        position: SIMD3<Double>,
        color: String,
        texture: String? = nil,
        rotationY: Double = 0,
        preview: Bool = false
    ) {
        self.id = id
        self.role = role
        self.cabinetID = cabinetID
        self.size = size
        self.position = position
        self.color = color
        self.texture = texture
        self.rotationY = rotationY
        self.preview = preview
    }
}
