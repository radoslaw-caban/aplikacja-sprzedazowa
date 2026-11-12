import Foundation

/// Płaszczyzna, w której wykonane jest wycięcie.
public enum CutoutPlane: String, Codable, Sendable, CaseIterable, Identifiable {
    case top
    case front
    case side

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .top: "Blat / góra"
        case .front: "Front"
        case .side: "Bok"
        }
    }

    public var symbol: String {
        switch self {
        case .top: "rectangle.topthird.inset.filled"
        case .front: "rectangle.portrait"
        case .side: "rectangle.portrait.rotate"
        }
    }
}

/// Przeznaczenie wycięcia — dobiera typowe wymiary i podpowiada opis.
public enum CutoutPurpose: String, Codable, Sendable, CaseIterable, Identifiable {
    case sink
    case hob
    case handle
    case cable
    case vent
    case niche
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sink: "Zlew"
        case .hob: "Płyta grzewcza"
        case .handle: "Uchwyt"
        case .cable: "Przepust kablowy"
        case .vent: "Wentylacja"
        case .niche: "Wnęka / nisza"
        case .other: "Inne"
        }
    }

    public var symbol: String {
        switch self {
        case .sink: "drop.fill"
        case .hob: "flame.fill"
        case .handle: "hand.raised.fill"
        case .cable: "cable.connector"
        case .vent: "wind"
        case .niche: "rectangle.split.3x1"
        case .other: "scissors"
        }
    }

    public var defaultPlane: CutoutPlane {
        switch self {
        case .sink, .hob: .top
        case .handle, .vent, .niche: .front
        case .cable: .side
        case .other: .front
        }
    }

    /// Wymiary nominalne (mm): szerokość × wysokość.
    public var defaultSize: (width: Double, height: Double) {
        switch self {
        case .sink: (780, 460)
        case .hob: (560, 490)
        case .handle: (160, 26)
        case .cable: (60, 60)
        case .vent: (300, 80)
        case .niche: (500, 300)
        case .other: (200, 100)
        }
    }
}

/// Prostokątne wycięcie w szafce: blat, front albo bok.
/// `x` i `y` to środek w układzie płaszczyzny (mm, względem środka szerokości
/// i odpowiednio: głębokości dla blatu / wysokości dla frontu i boku).
public struct CabinetCutout: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var plane: CutoutPlane
    public var purpose: CutoutPurpose
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var cornerRadius: Double

    public init(id: UUID = UUID(), plane: CutoutPlane, purpose: CutoutPurpose,
                x: Double = 0, y: Double = 0, width: Double, height: Double,
                cornerRadius: Double = 0) {
        self.id = id
        self.plane = plane
        self.purpose = purpose
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    /// Wycięcie z typowymi wymiarami dla przeznaczenia, dopasowane do szafki.
    public static func make(_ purpose: CutoutPurpose, in cabinet: Cabinet) -> CabinetCutout {
        let size = purpose.defaultSize
        let plane = purpose.defaultPlane
        let bodyHeight = max(200, cabinet.height - (cabinet.type == .base ? cabinet.plinth : 0))
        var y: Double = 0
        switch purpose {
        case .handle:
            y = bodyHeight - 90
        case .vent:
            y = bodyHeight - 160
        case .niche:
            y = bodyHeight / 2
        case .cable:
            y = 100
        default:
            y = 0
        }
        return CabinetCutout(plane: plane, purpose: purpose, x: 0, y: y,
                             width: min(size.width, cabinet.width - 40),
                             height: min(size.height, max(30, bodyHeight - 40)),
                             cornerRadius: purpose == .sink ? 15 : (purpose == .hob ? 10 : 0))
    }
}
