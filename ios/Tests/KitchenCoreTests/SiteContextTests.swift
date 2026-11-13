import XCTest
import CoreLocation
@testable import KitchenCore

/// Kontekst działki: pozycja słońca, pory dnia, klasyfikacja otoczenia.
///
/// Te testy są istotne, bo słońce liczymy sami (algorytm NOAA) — jeśli wzór
/// się rozjedzie, użytkownik dostanie złe nasłonecznienie i nie zauważy tego
/// na oko. Sprawdzamy znane przypadki: południe słoneczne w Polsce latem
/// i zimą, noc, wschód/zachód oraz symetrię.
final class SiteContextTests: XCTestCase {

    private let warsaw = (lat: 52.2297, lon: 21.0122)
    private let tz = TimeZone(identifier: "Europe/Warsaw")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: c)!
    }

    // MARK: - pozycja słońca

    func testSummerNoonIsHigh() {
        // 21 czerwca, 12:30 czasu lokalnego w Warszawie — słońce wysoko
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 6, 21, 12, 30), timeZone: tz)
        XCTAssertGreaterThan(sun.elevation, 55, "latem w południe słońce powinno być wysoko")
        XCTAssertLessThan(sun.elevation, 65)
        XCTAssertTrue(sun.isUp)
    }

    func testWinterNoonIsLow() {
        // 21 grudnia — słońce nisko, ale nad horyzontem
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 12, 21, 11, 45), timeZone: tz)
        XCTAssertGreaterThan(sun.elevation, 10)
        XCTAssertLessThan(sun.elevation, 20, "zimą słońce jest nisko")
        XCTAssertTrue(sun.isUp)
    }

    func testMidnightSunIsBelowHorizon() {
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 6, 21, 1, 0), timeZone: tz)
        XCTAssertFalse(sun.isUp, "o 1:00 w Polsce słońce jest pod horyzontem")
    }

    func testSunIsHigherAtNoonThanInMorning() {
        let morning = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                            date: date(2026, 5, 15, 8, 0), timeZone: tz)
        let noon = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                         date: date(2026, 5, 15, 12, 30), timeZone: tz)
        XCTAssertGreaterThan(noon.elevation, morning.elevation)
    }

    func testAzimuthIsSouthAtNoon() {
        // w południe słońce jest na południu: azymut ~180°
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 3, 20, 11, 45), timeZone: tz)
        XCTAssertGreaterThan(sun.azimuth, 150)
        XCTAssertLessThan(sun.azimuth, 210)
    }

    func testMorningAzimuthIsEast() {
        // rano słońce wschodzi na wschodzie: azymut 60–120°
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 6, 21, 7, 0), timeZone: tz)
        XCTAssertGreaterThan(sun.azimuth, 50)
        XCTAssertLessThan(sun.azimuth, 130)
    }

    func testEveningAzimuthIsWest() {
        let sun = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 6, 21, 19, 0), timeZone: tz)
        XCTAssertGreaterThan(sun.azimuth, 230)
        XCTAssertLessThan(sun.azimuth, 310)
    }

    func testWarmthIsHigherNearHorizon() {
        let low = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                        date: date(2026, 6, 21, 20, 30), timeZone: tz)
        let high = SolarPosition.compute(latitude: warsaw.lat, longitude: warsaw.lon,
                                         date: date(2026, 6, 21, 12, 30), timeZone: tz)
        XCTAssertGreaterThan(low.warmth, high.warmth, "niskie słońce = cieplejsze światło")
    }

    func testEquatorNoonIsNearZenith() {
        // Równik, długość 0, południe słoneczne → słońce prawie w zenicie.
        // Data MUSI być w tej samej strefie, w której liczymy słońce —
        // inaczej wychodzi przesunięcie o godzinę i elewacja spada o ~15°.
        let utc = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 20; c.hour = 12; c.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let noonUTC = cal.date(from: c)!

        let sun = SolarPosition.compute(latitude: 0, longitude: 0,
                                        date: noonUTC, timeZone: utc)
        XCTAssertGreaterThan(sun.elevation, 85, "na równiku w południe słońce jest w zenicie")
    }

    // MARK: - wschód / zachód

    func testSunriseBeforeSunset() {
        guard let d = SolarPosition.sunriseSunset(latitude: warsaw.lat, longitude: warsaw.lon,
                                                  date: date(2026, 6, 21, 12), timeZone: tz) else {
            return XCTFail("brak wschodu/zachodu dla Warszawy")
        }
        XCTAssertLessThan(d.sunrise, d.sunset)
    }

    func testSummerDayIsLongerThanWinterDay() {
        guard let summer = SolarPosition.sunriseSunset(latitude: warsaw.lat, longitude: warsaw.lon,
                                                       date: date(2026, 6, 21, 12), timeZone: tz),
              let winter = SolarPosition.sunriseSunset(latitude: warsaw.lat, longitude: warsaw.lon,
                                                       date: date(2026, 12, 21, 12), timeZone: tz) else {
            return XCTFail("brak danych")
        }
        let summerLen = summer.sunset - summer.sunrise
        let winterLen = winter.sunset - winter.sunrise
        XCTAssertGreaterThan(summerLen, winterLen + 2, "latem dzień jest znacznie dłuższy")
    }

    func testPolarNightHasNoSunrise() {
        // Svalbard w grudniu — słońce nie wschodzi (dzień polarny odwrotnie)
        let result = SolarPosition.sunriseSunset(latitude: 78.2, longitude: 15.6,
                                                 date: date(2026, 12, 21, 12),
                                                 timeZone: TimeZone(identifier: "Europe/Oslo")!)
        XCTAssertNil(result, "za kołem polarnym zimą nie ma wschodu")
    }

    // MARK: - pory dnia

    func testTimeOfDayFromElevation() {
        XCTAssertEqual(TimeOfDay.from(elevation: -20, isBeforeNoon: true), .night)
        XCTAssertEqual(TimeOfDay.from(elevation: 0, isBeforeNoon: true), .dawn)
        XCTAssertEqual(TimeOfDay.from(elevation: 20, isBeforeNoon: true), .morning)
        XCTAssertEqual(TimeOfDay.from(elevation: 20, isBeforeNoon: false), .afternoon)
        XCTAssertEqual(TimeOfDay.from(elevation: 60, isBeforeNoon: true), .noon)
        XCTAssertEqual(TimeOfDay.from(elevation: 0, isBeforeNoon: false), .evening)
    }

    func testAllTimesOfDayHaveDistinctLight() {
        let kelvins = Set(TimeOfDay.allCases.map(\.kelvin))
        XCTAssertEqual(kelvins.count, TimeOfDay.allCases.count,
                       "każda pora dnia musi mieć inną temperaturę światła")
    }

    func testNightIsDarkest() {
        XCTAssertLessThan(TimeOfDay.night.ambientIntensity, TimeOfDay.dawn.ambientIntensity)
        XCTAssertEqual(TimeOfDay.noon.ambientIntensity, 1.0)
    }

    // MARK: - klasyfikacja otoczenia

    func testWaterWins() {
        let c = EnvironmentClass.classify(locality: "Warszawa", areasOfInterest: [],
                                          inlandWater: true, populationDensity: 3000)
        XCTAssertEqual(c, .water)
    }

    func testForestBeatsVillage() {
        let c = EnvironmentClass.classify(locality: "Białowieża",
                                          areasOfInterest: ["Białowieski Park Narodowy"],
                                          inlandWater: false, populationDensity: 20)
        XCTAssertEqual(c, .forest)
    }

    func testDensePopulationIsCity() {
        let c = EnvironmentClass.classify(locality: "Kraków", areasOfInterest: [],
                                          inlandWater: false, populationDensity: 2000)
        XCTAssertEqual(c, .city)
    }

    func testMediumPopulationIsVillage() {
        let c = EnvironmentClass.classify(locality: "Mogilany", areasOfInterest: [],
                                          inlandWater: false, populationDensity: 300)
        XCTAssertEqual(c, .village)
    }

    func testEveryEnvironmentHasAmbienceAndNoise() {
        for env in EnvironmentClass.allCases {
            XCTAssertGreaterThan(env.noiseLevel, 0, "\(env) bez poziomu hałasu")
            XCTAssertNotEqual(env.ambience, .none, "\(env) bez dźwięku tła")
        }
    }

    func testCityIsNoisiest() {
        let noises = EnvironmentClass.allCases.map(\.noiseLevel)
        XCTAssertEqual(EnvironmentClass.city.noiseLevel, noises.max())
    }

    // MARK: - SiteContext

    func testSiteContextComputesSunAndTime() {
        let site = SiteContext(address: "Warszawa", latitude: warsaw.lat, longitude: warsaw.lon,
                               environment: .city, locality: "Warszawa")
        let noon = date(2026, 6, 21, 12, 30)
        XCTAssertTrue(site.sun(at: noon, timeZone: tz).isUp)
        XCTAssertEqual(site.timeOfDay(at: noon, timeZone: tz), .noon)
    }

    func testSiteContextRoundtripsThroughJSON() throws {
        let site = SiteContext(address: "Kraków, ul. Testowa 1", latitude: 50.06, longitude: 19.94,
                               environment: .village, locality: "Kraków")
        let data = try JSONEncoder().encode(site)
        let back = try JSONDecoder().decode(SiteContext.self, from: data)
        XCTAssertEqual(back.address, site.address)
        XCTAssertEqual(back.environment, .village)
        XCTAssertEqual(back.latitude, 50.06, accuracy: 0.0001)
    }
}
