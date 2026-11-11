import Foundation

/// Ustawienia aplikacji — zapisywane w UserDefaults.
///
/// Ogniskowa kamery jest **stała i równa 47°** (tak widzi oko przy typowym
/// kadrze wnętrza); można ją zmienić wyłącznie w Ustawieniach, nie „przy okazji"
/// gestu, bo rozjeżdżające się FOV przy szczypaniu to najczęstsza skarga.
public struct AppSettings: Codable, Sendable, Equatable {

    /// Pionowe pole widzenia kamery (stopnie). Domyślnie 47.
    public var fieldOfView: Double = 47
    /// Czułość szczypania: 1 = domyślna, mniej = wolniejsze zbliżanie.
    public var zoomSensitivity: Double = 0.7
    /// Czułość przesuwania/obrotu palcem.
    public var panSensitivity: Double = 1.0
    /// Wygładzanie kamery (0,1 = ospałe, 1 = ostre).
    public var smoothing: Double = 0.75
    /// Odległość, od której plan wygląda jak kartka w notesie (metry).
    public var notebookDistance: Double = 3.2
    /// Czy pokazywać ołówek przy oddalonym planie.
    public var showPencil: Bool = true
    /// Domyślna liczba okien/drzwi w zestawieniu.
    public var windowCount: Int = 2
    public var doorCount: Int = 1
    public var paintCoats: Int = 2

    public init() {}

    public static let storageKey = "aplikacja-sprzedazowa:settings:v3"

    public static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// FOV ograniczone do sensownego zakresu — 47° to wartość domyślna.
    public var clampedFieldOfView: Double {
        min(75, max(28, fieldOfView))
    }
}
