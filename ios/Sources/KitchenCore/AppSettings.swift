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
    /// Efekty magiczne: świecąca ramka i brokat przy ważnych akcjach.
    public var magicEffects: Bool = true
    /// Odległość orbity od osi obrotu (mnożnik).
    ///
    /// 1,0 = kamera w odległości wyliczonej automatycznie z kadru. Mniejsza
    /// wartość zbliża orbitę do osi obrotu (obrót „ciaśniejszy", mniej wrażenia
    /// krążenia wokół dalekiego punktu), większa — oddala.
    ///
    /// Po co parametr: przy automatycznym kadrze promień potrafi wypaść tak
    /// duży, że obrót wygląda jak lot wokół odległego celu zamiast obracania
    /// projektem w ręku. To jest subiektywne, więc musi być do dostrojenia.
    public var orbitRadiusScale: Double = 0.75

    // MARK: - opcje widoku (przeniesione z dolnego paska do kafelków)

    /// Widok wewnątrz pomieszczenia (true) albo domu w otoczeniu (false).
    public var interiorView: Bool = false
    /// Bryła domu z chmury punktów X9 (true) albo willa proceduralna (false).
    public var useScanHouse: Bool = true
    /// Nakładka: chmura punktów 1:1 na zbudowanym domu.
    public var showScanCloud: Bool = false
    /// Warstwa skanu (chmura z X9 / z iPada) — niezależnie od bryły budynku.
    public var showScanLayer: Bool = true
    /// Warstwa budynku (ściany, podłoga, sufit) — niezależnie od skanu.
    public var showBuildingLayer: Bool = true
    /// Moduł pierwszoosobowy („wejdź do domu"). Domyślnie UKRYTY —
    /// to moduł demonstracyjny, nie część przepływu sprzedażowego.
    public var showFirstPersonModule: Bool = false

    // MARK: - dźwięk

    /// Głośność główna — mnożnik dla wszystkich dźwięków w aplikacji.
    /// 0 = cisza całkowicie (równoważne `soundEnabled = false`).
    public var masterVolume: Double = 0.8
    /// Głośność interfejsu: kliknięcia, stuknięcia kategorii, pstryknięcia.
    /// Osobno od obiektów, bo UI ma być dyskretne, a obiekty mają być słyszalne.
    public var uiVolume: Double = 0.6
    /// Głośność dźwięków obiektów (wstawianie, interakcje, otoczenie).
    public var objectVolume: Double = 0.8
    /// Głośność otoczenia (szum miasta, las, ptaki) — zwykle tło, więc niżej.
    public var ambienceVolume: Double = 0.45
    /// Czy dźwięki w ogóle grają. Wyłączenie nie zeruje suwaków —
    /// po włączeniu wracają poprzednie wartości.
    public var soundEnabled: Bool = true
    /// Cisza nocna: wycisza wszystko w podanych godzinach.
    public var quietHoursEnabled: Bool = false
    public var quietHoursFrom: Int = 22
    public var quietHoursTo: Int = 7
    /// Haptyka: stuknięcia przy akcjach (osobno od dźwięku — ktoś może
    /// chcieć wibrację bez dźwięku, np. w słuchawkach).
    public var hapticsEnabled: Bool = true

    /// Domyślna liczba okien/drzwi w zestawieniu.
    public var windowCount: Int = 2
    public var doorCount: Int = 1
    public var paintCoats: Int = 2

    public init() {}

    /// v4: dodano parametry dźwięku i haptyki. Bump, bo stary zapis v3
    /// nie ma tych pól — dekodowanie uzupełniłoby je zerami i dźwięk
    /// byłby domyślnie wyłączony u każdego, kto już używał aplikacji.
    public static let storageKey = "aplikacja-sprzedazowa:settings:v4"

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

    /// Skala promienia orbity ograniczona do sensownego zakresu.
    public var clampedOrbitRadiusScale: Double {
        min(1.6, max(0.25, orbitRadiusScale))
    }

    /// FOV ograniczone do sensownego zakresu — 47° to wartość domyślna.
    public var clampedFieldOfView: Double {
        min(75, max(28, fieldOfView))
    }

    // MARK: - dźwięk: wartości efektywne

    /// Czy teraz wolno grać (uwzględnia wyłączenie i ciszę nocną).
    public func soundAllowed(at date: Date = Date(),
                             calendar: Calendar = .current) -> Bool {
        guard soundEnabled, masterVolume > 0.01 else { return false }
        guard quietHoursEnabled else { return true }
        let hour = calendar.component(.hour, from: date)
        // zakres może przechodzić przez północ (22 → 7)
        if quietHoursFrom <= quietHoursTo {
            return !(hour >= quietHoursFrom && hour < quietHoursTo)
        }
        return !(hour >= quietHoursFrom || hour < quietHoursTo)
    }

    /// Końcowa głośność UI = główna × UI, przycięta do 0…1.
    public var effectiveUIVolume: Double {
        min(1, max(0, masterVolume * uiVolume))
    }

    /// Końcowa głośność obiektów = główna × obiekty.
    public var effectiveObjectVolume: Double {
        min(1, max(0, masterVolume * objectVolume))
    }

    /// Końcowa głośność otoczenia = główna × otoczenie.
    public var effectiveAmbienceVolume: Double {
        min(1, max(0, masterVolume * ambienceVolume))
    }
}
