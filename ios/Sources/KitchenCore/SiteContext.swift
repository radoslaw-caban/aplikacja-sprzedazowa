import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

/// ZGODA NA LOKALIZACJĘ — jedno miejsce, bo pyta o nią kilka modułów.
///
/// Bez zgody ARKit nie ustawi północy geograficznej (`.gravityAndHeading`
/// wymaga Location Services), a bez północy nie policzymy nasłonecznienia.
/// Dlatego sprawdzamy stan PRZED konfiguracją sesji, zamiast zakładać zgodę.
public enum LocationAuthorization {

    public static var status: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    public static var isGranted: Bool {
        #if os(iOS)
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        return true
        #endif
    }

    /// Prosi o zgodę „przy użyciu". Wywoływać przy pierwszym skanie,
    /// nie na starcie aplikacji — zgoda bez kontekstu jest częściej odrzucana.
    @discardableResult
    public static func request() -> Bool {
        #if os(iOS)
        let mgr = CLLocationManager()
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        }
        return isGranted
        #else
        return true
        #endif
    }
}

/// POZYCJA SŁOŃCA — bez zewnętrznego API, czysta astronomia.
///
/// Po co własna implementacja: żadnych kluczy, żadnych limitów zapytań,
/// działa offline i jest deterministyczna (ten sam adres + data = ta sama
/// pozycja słońca, zawsze). Dokładność ~0,1° — więcej niż potrzeba do
/// wizualizacji nasłonecznienia wnętrza.
public enum SolarPosition {

    public struct Result: Sendable, Equatable {
        /// wysokość nad horyzontem w stopniach (ujemna = słońce pod horyzontem)
        public var elevation: Double
        /// azymut w stopniach, 0 = północ, 90 = wschód, 180 = południe, 270 = zachód
        public var azimuth: Double
        /// czy słońce jest nad horyzontem
        public var isUp: Bool { elevation > 0 }
        /// kolor światła — ciepły o wschodzie/zachodzie, biały w południe
        public var warmth: Double
    }

    /// Oblicza pozycję słońca (algorytm NOAA, uproszczony).
    /// - Parameters:
    ///   - latitude: szerokość geograficzna w stopniach (N dodatnia)
    ///   - longitude: długość geograficzna w stopniach (E dodatnia)
    ///   - date: moment; strefa czasowa jest brana z kalendarza
    public static func compute(latitude: Double, longitude: Double,
                               date: Date, timeZone: TimeZone = .current) -> Result {
        let cal = Calendar(identifier: .gregorian)
        var local = cal
        local.timeZone = timeZone

        let dayOfYear = Double(local.ordinality(of: .day, in: .year, for: date) ?? 1)

        // deklinacja słońca (stopnie)
        let decl = 23.44 * sin(2 * .pi * (284 + dayOfYear) / 365)

        // równanie czasu (minuty) — poprawka na eliptyczną orbitę
        let b = 2 * .pi * (dayOfYear - 81) / 364
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        // czas słoneczny lokalny (godziny)
        let comps = local.dateComponents([.hour, .minute], from: date)
        let clockHours = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let solarHours = clockHours + (4 * (longitude - 15 * Double(timeZone.secondsFromGMT(for: date) / 3600)) + eot) / 60

        // kąt godzinny (stopnie)
        let hourAngle = 15 * (solarHours - 12)

        let latRad = latitude * .pi / 180
        let declRad = decl * .pi / 180
        let haRad = hourAngle * .pi / 180

        // wysokość
        let sinElev = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(haRad)
        let elevation = asin(max(-1, min(1, sinElev))) * 180 / .pi

        // azymut (0 = N, zgodnie z ruchem wskazówek)
        let cosAz = (sin(declRad) - sin(latRad) * sinElev) / (cos(latRad) * cos(asin(max(-1, min(1, sinElev)))))
        var azimuth = acos(max(-1, min(1, cosAz))) * 180 / .pi
        if hourAngle > 0 { azimuth = 360 - azimuth }

        // ciepło: 1 przy horyzoncie, 0 w zenicie
        let warmth = max(0, min(1, 1 - elevation / 45))

        return Result(elevation: elevation, azimuth: azimuth, warmth: warmth)
    }

    /// Wschód i zachód słońca dla dnia (godziny lokalne, 0–24).
    /// nil gdy słońce nie wschodzi/zachodzi (dzień lub noc polarna).
    public static func sunriseSunset(latitude: Double, longitude: Double,
                                     date: Date, timeZone: TimeZone = .current) -> (sunrise: Double, sunset: Double)? {
        let cal = Calendar(identifier: .gregorian)
        var local = cal
        local.timeZone = timeZone
        let dayOfYear = Double(local.ordinality(of: .day, in: .year, for: date) ?? 1)
        let decl = 23.44 * sin(2 * .pi * (284 + dayOfYear) / 365)
        let latRad = latitude * .pi / 180
        let declRad = decl * .pi / 180

        // kąt godzinny wschodu
        let cosH = -tan(latRad) * tan(declRad)
        guard cosH >= -1, cosH <= 1 else { return nil }
        let h = acos(cosH) * 180 / .pi / 15   // godziny

        let solarNoon = 12 - longitude / 15 + Double(timeZone.secondsFromGMT(for: date) / 3600)
        return (solarNoon - h, solarNoon + h)
    }
}

/// PORY DNIA — sześć stanów, każdy z własnym oświetleniem i dźwiękiem tła.
public enum TimeOfDay: String, Codable, Sendable, CaseIterable, Identifiable {
    case dawn, morning, noon, afternoon, evening, night

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .dawn: "Świt"
        case .morning: "Rano"
        case .noon: "Południe"
        case .afternoon: "Popołudnie"
        case .evening: "Wieczór"
        case .night: "Noc"
        }
    }

    /// Zakres wysokości słońca, który definiuje porę (stopnie).
    public var elevationRange: ClosedRange<Double> {
        switch self {
        case .dawn: -6...6
        case .morning: 6...35
        case .noon: 35...90
        case .afternoon: 15...35
        case .evening: -6...15
        case .night: -90...(-6)
        }
    }

    /// Intensywność światła otoczenia 0…1.
    public var ambientIntensity: Double {
        switch self {
        case .dawn: 0.25
        case .morning: 0.75
        case .noon: 1.0
        case .afternoon: 0.85
        case .evening: 0.45
        case .night: 0.08
        }
    }

    /// Temperatura barwowa światła (K) — do doboru HDRI i lamp.
    public var kelvin: Int {
        switch self {
        case .dawn: 2600
        case .morning: 4200
        case .noon: 5600
        case .afternoon: 4800
        case .evening: 2900
        case .night: 2100
        }
    }

    /// Pora z pozycji słońca. Rozróżnienie rano/popołudnie wymaga czasu,
    /// bo ta sama wysokość występuje dwa razy dziennie.
    public static func from(elevation: Double, isBeforeNoon: Bool) -> TimeOfDay {
        if elevation < -6 { return .night }
        if elevation < 6 { return isBeforeNoon ? .dawn : .evening }
        if elevation < 35 { return isBeforeNoon ? .morning : .afternoon }
        return .noon
    }
}

/// KLASA OTOCZENIA — rozpoznawana z adresu, decyduje o scenografii i dźwięku.
///
/// Nie zgadujemy z nazwy ulicy: bierzemy to, co zwraca reverse geocoding
/// (typ drogi, zabudowa, tereny zielone) i mapujemy na cztery klasy.
/// Każda klasa ma własne modele, tekstury i dźwięk tła.
public enum EnvironmentClass: String, Codable, Sendable, CaseIterable, Identifiable {
    case city, village, forest, water

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .city: "Miasto"
        case .village: "Wieś"
        case .forest: "Las"
        case .water: "Nad wodą"
        }
    }

    /// Gęstość zabudowy w otoczeniu (0 = brak, 1 = zwarta).
    public var buildingDensity: Double {
        switch self {
        case .city: 0.9
        case .village: 0.35
        case .forest: 0.02
        case .water: 0.15
        }
    }

    /// Gęstość zieleni (drzewa, krzewy).
    public var greeneryDensity: Double {
        switch self {
        case .city: 0.15
        case .village: 0.55
        case .forest: 0.95
        case .water: 0.5
        }
    }

    /// Dźwięk tła — warstwa otoczenia.
    public var ambience: SandboxSound {
        switch self {
        case .city: .swish       // szum komunikacyjny
        case .village: .rustle   // wiatr w zbożu, ptaki
        case .forest: .leaves    // szum liści, dzięcioł
        case .water: .swish      // szum wody
        }
    }

    /// Przybliżony poziom hałasu tła (0…1) — miasto jest głośniejsze.
    public var noiseLevel: Double {
        switch self {
        case .city: 0.8
        case .village: 0.35
        case .forest: 0.3
        case .water: 0.45
        }
    }

    /// Klasa z danych reverse geocodingu.
    ///
    /// Reguły są proste i przewidywalne — wolimy policzalną heurystykę
    /// od „AI, które zgadnie". Kolejność ma znaczenie: las wygrywa z wsią,
    /// woda z miastem (nabrzeże to jednak miasto).
    public static func classify(
        locality: String?,
        areasOfInterest: [String],
        inlandWater: Bool,
        populationDensity: Double?
    ) -> EnvironmentClass {
        let aoi = areasOfInterest.map { $0.lowercased() }.joined(separator: " ")

        if inlandWater { return .water }
        if aoi.contains("forest") || aoi.contains("park narodowy")
            || aoi.contains("las") || aoi.contains("wood") {
            return .forest
        }
        if let density = populationDensity {
            if density > 1000 { return .city }      // os./km²
            if density > 100 { return .village }
            return .forest
        }
        // brak danych: po nazwie miejscowości
        let name = (locality ?? "").lowercased()
        if name.isEmpty { return .village }
        if name.hasSuffix("ice") || name.hasSuffix("owo") || name.hasSuffix("ów") {
            return .village
        }
        return .city
    }
}

/// KONTEKST DZIAŁKI — wszystko, co wiemy o miejscu, zapisane przy projekcie.
///
/// Trzymamy to razem, bo te dane zawsze idą w parze: adres bez współrzędnych
/// nie da słońca, współrzędne bez klasy otoczenia nie dadzą scenografii.
/// Zapis w projekcie = brak ponownego geokodowania przy każdym otwarciu.
public struct SiteContext: Codable, Sendable, Equatable {
    /// adres w formie wpisanej przez użytkownika
    public var address: String
    public var latitude: Double
    public var longitude: Double
    /// rozpoznana klasa otoczenia (miasto / wieś / las / woda)
    public var environment: EnvironmentClass
    /// nazwa miejscowości z reverse geocodingu (do wyświetlenia)
    public var locality: String
    /// kiedy rozwiązano — żeby wiedzieć, czy dane nie są przestarzałe
    public var resolvedAt: Date

    public init(address: String, latitude: Double, longitude: Double,
                environment: EnvironmentClass, locality: String = "",
                resolvedAt: Date = Date()) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.environment = environment
        self.locality = locality
        self.resolvedAt = resolvedAt
    }

    /// Pozycja słońca dla tego miejsca i podanego momentu.
    public func sun(at date: Date, timeZone: TimeZone = .current) -> SolarPosition.Result {
        SolarPosition.compute(latitude: latitude, longitude: longitude,
                              date: date, timeZone: timeZone)
    }

    /// Pora dnia wynikająca z pozycji słońca.
    public func timeOfDay(at date: Date, timeZone: TimeZone = .current) -> TimeOfDay {
        let sun = sun(at: date, timeZone: timeZone)
        let cal = Calendar(identifier: .gregorian)
        var local = cal
        local.timeZone = timeZone
        let hour = local.component(.hour, from: date)
        return TimeOfDay.from(elevation: sun.elevation, isBeforeNoon: hour < 12)
    }

    /// Wschód i zachód słońca tego dnia (godziny lokalne).
    public func daylight(on date: Date, timeZone: TimeZone = .current) -> (sunrise: Double, sunset: Double)? {
        SolarPosition.sunriseSunset(latitude: latitude, longitude: longitude,
                                    date: date, timeZone: timeZone)
    }
}
