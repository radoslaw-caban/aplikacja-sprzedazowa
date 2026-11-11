import Foundation

/// Kartoteki klientów wprowadzone z tabeli zamówień (13 pozycji).
///
/// Po co w kodzie, a nie w pliku JSON: przy pierwszym uruchomieniu nowej
/// wersji każdy iPad dostaje te same kartoteki, bez ręcznego importu.
/// Wgrywamy **tylko brakujące** — istniejące projekty nie są nadpisywane.
public struct SeedClient: Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var deliveryYear: Int
    public var deliveryMonth: Int
    public var deliveryDay: Int
    /// suma całkowita (zł)
    public var total: Double
    /// zaliczka wpłacona (zł)
    public var deposit: Double
    public var status: String
    public var address: String
    public var phone: String
    public var email: String
    public var note: String

    public init(_ firstName: String, _ lastName: String, _ year: Int, _ month: Int, _ day: Int,
                _ total: Double, _ deposit: Double, status: String = "Do dostarczenia",
                address: String = "", phone: String = "", email: String = "", note: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.deliveryYear = year
        self.deliveryMonth = month
        self.deliveryDay = day
        self.total = total
        self.deposit = deposit
        self.status = status
        self.address = address
        self.phone = phone
        self.email = email
        self.note = note
    }

    public var fullName: String { "\(firstName) \(lastName)" }

    public var deliveryDate: Date? {
        var components = DateComponents()
        components.year = deliveryYear
        components.month = deliveryMonth
        components.day = deliveryDay
        components.hour = 8
        return Calendar(identifier: .gregorian).date(from: components)
    }

    public var remaining: Double { max(0, total - deposit) }
}

public enum ClientSeed {

    public static let version = 3
    public static let defaultsKey = "aplikacja-sprzedazowa:seed:clients:v\(version)"

    /// Tabela z załącznika — kolejność jak na liście.
    public static let all: [SeedClient] = [
        SeedClient("Alicja", "Lidwin", 2027, 9, 30, 11_500, 4_000,
                   address: "ul. Królowej Jadwigi 22/4, 34-400 Nowy Targ",
                   phone: "602 118 447", email: "a.lidwin@wp.pl",
                   note: "Kuchnia w bloku, winda do 3. piętra. Fronty białe mat, blat laminat jasny dąb."),
        SeedClient("Paulina", "Bartodziej", 2027, 5, 31, 27_600, 0,
                   address: "ul. Szaflarska 118, 34-400 Nowy Targ",
                   phone: "660 902 331", email: "paulina.bartodziej@gmail.com",
                   note: "Dom jednorodzinny, szafa w przedpokoju + zabudowa pralki. Wejście od tarasu."),
        SeedClient("Sebastian", "Jaźwiecki", 2027, 5, 31, 23_350, 7_000,
                   address: "os. Bór 14/7, 34-400 Nowy Targ",
                   phone: "501 448 902", email: "s.jazwiecki@interia.pl",
                   note: "Salon z RTV, blat kamień. Klient dostarcza własne uchwyty."),
        SeedClient("Paulina", "Bartodziej", 2027, 5, 31, 30_900, 10_000,
                   address: "ul. Szaflarska 118, 34-400 Nowy Targ",
                   phone: "660 902 331", email: "paulina.bartodziej@gmail.com",
                   note: "Drugie zlecenie — garderoba na piętrze. Montaż po ułożeniu podłóg."),
        SeedClient("Kamila", "Kustroń", 2027, 3, 22, 35_500, 0,
                   address: "ul. Waksmundzka 63, 34-400 Nowy Targ",
                   phone: "784 221 610", email: "kamila.kustron@onet.pl",
                   note: "Kuchnia w kształcie L, zmywarka pod blatem. Wymaga pomiaru po tynkach."),
        SeedClient("Małgorzata", "Półchłopek", 2027, 2, 28, 36_813, 0,
                   address: "ul. Ludźmierska 41, 34-400 Nowy Targ",
                   phone: "600 337 118", email: "m.polchlopek@gmail.com",
                   note: "Zabudowa pod schody + szafka RTV. Dąb naturalny, okucia Blum."),
        SeedClient("Grzegorz", "Przepióra", 2027, 2, 28, 26_000, 0,
                   address: "ul. Jana Pawła II 9/12, 34-400 Nowy Targ",
                   phone: "512 660 074", email: "g.przepiora@wp.pl",
                   note: "Szafa wnękowa 2,4 m, drzwi przesuwne. Klient prosi o cichy montaż (małe dziecko)."),
        SeedClient("Emil", "Kędra", 2027, 2, 28, 45_000, 0,
                   address: "ul. Kościuszki 77, 34-400 Nowy Targ",
                   phone: "668 214 500", email: "emil.kedra@gmail.com",
                   note: "Cała kuchnia + wyspa. Blat spiek kwarcowy, fronty lakier mat grafit."),
        SeedClient("Dorota", "Kustroń", 2027, 2, 28, 20_500, 7_700,
                   address: "ul. Wojska Polskiego 3/8, 34-400 Nowy Targ",
                   phone: "502 887 341", email: "dorota.kustron@interia.pl",
                   note: "Łazienka — szafka pod umywalkę i słupek. Płyta wodoodporna."),
        SeedClient("Aneta", "Rachwał", 2027, 2, 28, 7_400, 0,
                   address: "ul. Podtatrzańska 12, 34-400 Nowy Targ",
                   phone: "730 118 226", email: "aneta.rachwal@onet.pl",
                   note: "Mała szafka pod bojler. Montaż szybki, do 2 godzin."),
        SeedClient("Marzena", "Gierlach", 2027, 2, 28, 40_800, 0,
                   address: "ul. Kokoszków 88, 34-400 Nowy Targ",
                   phone: "604 552 913", email: "m.gierlach@gmail.com",
                   note: "Kuchnia z jadalnią, stół na wymiar. Dojazd drogą gruntową — auto dostawcze dojedzie."),
        SeedClient("Renata", "Gazda", 2027, 2, 28, 26_800, 8_000,
                   address: "ul. Szpitalna 5/2, 34-400 Nowy Targ",
                   phone: "691 340 558", email: "renata.gazda@wp.pl",
                   note: "Garderoba i szafa w sypialni. Lustro w drzwiach, oświetlenie LED w listwie."),
        SeedClient("Aleksandra", "Wanca", 2027, 2, 28, 27_300, 0,
                   address: "ul. Grel 21, 34-400 Nowy Targ",
                   phone: "505 771 209", email: "ola.wanca@gmail.com",
                   note: "Kuchnia otwarta na salon. Okap podszafkowy, bez uchwytów (push-to-open)."),

    ]

    /// Projekt-kartoteka z jednej pozycji tabeli.
    public static func project(from client: SeedClient) -> Project {
        let order = ProjectOrder(
            clientLastName: client.lastName,
            clientFirstName: client.firstName,
            address: client.address,
            phone: client.phone,
            email: client.email,
            price: client.total,
            deposit: client.deposit,
            notes: client.note,
            deliveryDate: client.deliveryDate,
            status: client.status
        )
        var project = Project(name: "\(client.firstName) \(client.lastName)")
        project.order = order
        return project
    }
}
