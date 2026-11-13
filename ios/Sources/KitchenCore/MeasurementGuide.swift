import Foundation

/// Katalog metod pomiaru i pracy nad projektem — dane, nie widok.
///
/// PO CO OSOBNY MODEL: ten sam katalog zasila wybór trybu na iPadzie, stronę
/// w internecie i materiał dla handlowca. Trzymanie go w widoku oznaczałoby,
/// że opis dokładności istnieje w trzech miejscach i w każdym inny.
///
/// ZASADA: każda metoda mówi WPROST, jaką ma dokładność i ile wymiarów
/// zwraca oraz zapisuje. Bez tego klient nie wie, czy „szybki skan" nadaje się
/// do zamówienia szafek, czy tylko do wizualizacji — a to najczęstsze
/// nieporozumienie w tej branży.
public enum MeasurementGuide {

    // MARK: - kategorie

    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case automatic
        case consult
        case plan

        public var id: String { rawValue }

        /// Pytanie, od którego zaczyna się kategoria (formuła pytań).
        public var question: String {
            switch self {
            case .automatic: "Zmierzemy to automatycznie?"
            case .consult: "Chcesz o tym pogadać?"
            case .plan: "A może najpierw plan?"
            }
        }

        public var description: String {
            switch self {
            case .automatic:
                "Skaner albo dalmierz zbiera wymiary za Ciebie. Wybierz, jak dokładnie potrzebujesz."
            case .consult:
                "Nie musisz decydować sam. Możesz zapytać kopię neuronową, człowieka albo zaprosić kogoś do projektu."
            case .plan:
                "Rysujemy obrys: liniami po osiach, prostokątami pomieszczeń albo dalmierzem."
            }
        }

        public var pictogram: String {
            switch self {
            case .automatic: "sensor.tag.radiowaves.forward"
            case .consult: "bubble.left.and.bubble.right"
            case .plan: "ruler"
            }
        }
    }

    // MARK: - opcje

    public enum Option: String, CaseIterable, Identifiable, Sendable {
        // pomiary automatyczne
        case quickScan
        case proScan
        // rozmowa
        case neuralChat
        case humanChat
        case inviteFriend
        // plan
        case lockedLines
        case roomRectangles
        case laserMeter
        case importPlan

        public var id: String { rawValue }

        public var category: Category {
            switch self {
            case .quickScan, .proScan: .automatic
            case .neuralChat, .humanChat, .inviteFriend: .consult
            case .lockedLines, .roomRectangles, .laserMeter, .importPlan: .plan
            }
        }

        public var title: String {
            switch self {
            case .quickScan: "Szybki Skaner projektowy"
            case .proScan: "Profesjonalny skaner wykonawczy"
            case .neuralChat: "Pogadaj z Kopią neuronową"
            case .humanChat: "Spróbuj z człowiekiem"
            case .inviteFriend: "Dodaj znajomego do pomocy"
            case .lockedLines: "Linie po osiach"
            case .roomRectangles: "Pomieszczenia prostokątami"
            case .laserMeter: "Dalmierz sterujący"
            case .importPlan: "Import planu z pliku"
            }
        }

        /// Pytanie widoczne nad opcją — użytkownik ma odpowiedzieć, nie zgadywać.
        public var question: String {
            switch self {
            case .quickScan: "Masz iPada z LiDAR-em i chcesz pomiar teraz?"
            case .proScan: "Potrzebujesz wymiarów, na których można oprzeć produkcję?"
            case .neuralChat: "Chcesz, żeby ktoś przeanalizował pomysł za Ciebie?"
            case .humanChat: "Wolisz porozmawiać z człowiekiem z branży?"
            case .inviteFriend: "Ktoś pomaga Ci przy tym projekcie?"
            case .lockedLines: "Wiesz, jak ten budynek wygląda w rzucie?"
            case .roomRectangles: "Chcesz poukładać pomieszczenia z prostokątów?"
            case .laserMeter: "Masz dalmierz i chcesz mierzyć na żywo?"
            case .importPlan: "Masz już plan w pliku?"
            }
        }

        /// Krótki opis: co się właściwie stanie po kliknięciu.
        public var description: String {
            switch self {
            case .quickScan:
                "Wbudowany skaner LiDAR-a w iPadzie obchodzi pomieszczenie i zapisuje chmurę punktów prosto do projektu."
            case .proScan:
                "Skaner stojący (Trimble X9 albo podobny). Plik E57 wczytujemy i budujemy z niego ściany."
            case .neuralChat:
                "Kopia neuronowa zna Twój projekt, bibliotekę i wymiary. Odpowie na pytania i podpowie rozwiązania."
            case .humanChat:
                "Łączymy Cię z doradcą, projektantem albo technikiem. Rozmowa telefoniczna albo wideo."
            case .inviteFriend:
                "Wysyłasz zaproszenie — osoba dostaje dostęp do tego projektu i może doradzać na bieżąco."
            case .lockedLines:
                "Rysujesz układ ścian, a program blokuje linie do poziomu i pionu (albo 15°/45°). Wymiar wpisujesz z klawiatury."
            case .roomRectangles:
                "Przeciągasz prostokąty pomieszczeń — przyciągają się narożnikami. Każde dostaje nazwę i kolor. Gdy kontur się domknie, prostokąt staje się pomieszczeniem."
            case .laserMeter:
                "Stoisz z dalmierzem, a aplikacja rysuje układ linii. Podajesz wymiar bezprzewodowo, program poprawia kolejny odcinek od wybranego początku i kierunku."
            case .importPlan:
                "Wczytujesz zdjęcie albo PDF planu. Aplikacja wykrywa obrys i skaluje go do wpisanej szerokości."
            }
        }

        public var pictogram: String {
            switch self {
            case .quickScan: "ipad.gen2"
            case .proScan: "camera.metering.center.weighted"
            case .neuralChat: "brain.head.profile"
            case .humanChat: "person.wave.2"
            case .inviteFriend: "person.badge.plus"
            case .lockedLines: "line.diagonal"
            case .roomRectangles: "rectangle.3.group"
            case .laserMeter: "dot.radiowaves.left.and.right"
            case .importPlan: "doc.viewfinder"
            }
        }

        /// Parametry — to jest istota wyboru, więc na pierwszym planie.
        public var parameters: Params {
            switch self {
            case .quickScan:
                Params(
                    accuracyMM: 20,
                    accuracyNote: "±1–2 cm na 5 m; fuzja map głębi daje σ 2–4 mm na ścianę, ale błąd systematyczny czujnika zostaje",
                    dimensionsReturned: 4,
                    dimensionsSaved: 200_000,
                    timeOnSite: "15–30 min (przejście całego pomieszczenia)",
                    requiresHardware: "iPad Pro z LiDAR (2020+) albo iPhone Pro 12+",
                    suitableForProduction: false
                )
            case .proScan:
                Params(
                    accuracyMM: 2,
                    accuracyNote: "±1–2 mm na 10 m po kalibracji producenta",
                    dimensionsReturned: 6,
                    dimensionsSaved: 50_000_000,
                    timeOnSite: "40–90 min (z rozstawianiem stanowisk)",
                    requiresHardware: "Trimble X9, FARO, Leica RTC360 (zakup lub wypożyczalnia)",
                    suitableForProduction: true
                )
            case .laserMeter:
                Params(
                    accuracyMM: 3,
                    accuracyNote: "±1,5 mm typowo dla dalmierza klasy Boscha/Leica Disto",
                    dimensionsReturned: 3,
                    dimensionsSaved: 500,
                    timeOnSite: "20–40 min",
                    requiresHardware: "dalmierz laserowy z Bluetooth (Disto, Bosch GLM)",
                    suitableForProduction: true
                )
            case .lockedLines, .roomRectangles, .importPlan:
                Params(
                    accuracyMM: 0,
                    accuracyNote: "dokładność wpisana przez Ciebie — program tylko pilnuje osi i domykania",
                    dimensionsReturned: 2,
                    dimensionsSaved: 100,
                    timeOnSite: "10–30 min",
                    requiresHardware: "brak — wystarczy iPad albo telefon",
                    suitableForProduction: true
                )
            case .neuralChat, .humanChat, .inviteFriend:
                Params(
                    accuracyMM: nil,
                    accuracyNote: "doradztwo nie mierzy — pomaga podjąć decyzję",
                    dimensionsReturned: 0,
                    dimensionsSaved: 0,
                    timeOnSite: "5–30 min",
                    requiresHardware: "brak",
                    suitableForProduction: false
                )
            }
        }
    }

    /// Parametry metody pomiaru.
    public struct Params: Sendable, Equatable {
        /// Dokładność w milimetrach; `nil` = metoda nie mierzy.
        public var accuracyMM: Int?
        /// Zdanie wyjaśniające, skąd ta dokładność.
        public var accuracyNote: String
        /// Ile wymiarów zwraca w jednym pomiarze (np. szerokość × głębokość × wysokość).
        public var dimensionsReturned: Int
        /// Ile wymiarów trafia do zapisanych danych projektu.
        public var dimensionsSaved: Int
        public var timeOnSite: String
        public var requiresHardware: String
        /// Czy nadaje się do wymiarowania pod produkcję (decyzja handlowa).
        public var suitableForProduction: Bool

        public var accuracyText: String {
            guard let mm = accuracyMM else { return "—" }
            if mm == 0 { return "z klawiatury" }
            return "±\(mm) mm"
        }

        public var savedText: String {
            if dimensionsSaved >= 1_000_000 {
                return "\(dimensionsSaved / 1_000_000) mln punktów"
            }
            if dimensionsSaved >= 1000 {
                return "\(dimensionsSaved / 1000) tys. punktów"
            }
            return "\(dimensionsSaved) wymiarów"
        }
    }

    // MARK: - oferta towarzysząca

    /// Co jeszcze można zrobić przy danej metodzie: kupić, wykupić, spotkać.
    ///
    /// To jest jednocześnie treść handlowa i model danych — te same wpisy
    /// zasilają ekran w aplikacji i rozmowę handlowca z klientem.
    public enum Offer: Sendable, CaseIterable, Identifiable {
        case buyHardware
        case subscribeModule
        case meetCudotworcy
        case meetStarszyzna

        public var id: String { self == .buyHardware ? "buy" : self == .subscribeModule ? "sub" : self == .meetCudotworcy ? "cudo" : "starsz" }

        public var title: String {
            switch self {
            case .buyHardware: "Kup urządzenie pomiarowe"
            case .subscribeModule: "Wykup dostęp do modułu"
            case .meetCudotworcy: "Spotkaj się z Cudotwórcą"
            case .meetStarszyzna: "Porozmawiaj ze Starszyzną"
            }
        }

        public var description: String {
            switch self {
            case .buyHardware:
                "Sprzęt dopasowany do tego trybu: skaner, dalmierz albo akcesoria. Doradzimy zakup, dzierżawę albo wypożyczenie na jedną realizację."
            case .subscribeModule:
                "Dostęp do modułu na miesiąc albo na projekt. Bez subskrypcji projekt działa w trybie odczytu."
            case .meetCudotworcy:
                "Zrzeszenie Cudotwórcy: wykonawcy, technicy, pracownicy, klienci, doradcy, projektanci, sklepy i hurtownie. Umów spotkanie z kimś, kto to robi na co dzień."
            case .meetStarszyzna:
                "Starszyzna: elitarna grupa współpracy kluczowych firm w branży. Rozmowa o rozwiązaniach, których nie znajdziesz w katalogu."
            }
        }

        public var pictogram: String {
            switch self {
            case .buyHardware: "shippingbox"
            case .subscribeModule: "key.horizontal"
            case .meetCudotworcy: "person.3.sequence"
            case .meetStarszyzna: "crown"
            }
        }
    }

    /// Które oferty pasują do metody — nie pokazujemy zakupu skanera komuś,
    /// kto wybrał rysowanie palcem (zniechęca i psuje zaufanie).
    public static func offers(for option: Option) -> [Offer] {
        switch option {
        case .quickScan:
            [.subscribeModule, .buyHardware, .meetCudotworcy]
        case .proScan:
            [.buyHardware, .subscribeModule, .meetStarszyzna, .meetCudotworcy]
        case .laserMeter:
            [.buyHardware, .subscribeModule, .meetCudotworcy]
        case .lockedLines, .roomRectangles, .importPlan:
            [.subscribeModule, .meetCudotworcy]
        case .neuralChat:
            [.subscribeModule, .meetCudotworcy]
        case .humanChat, .inviteFriend:
            [.meetCudotworcy, .meetStarszyzna]
        }
    }
}
