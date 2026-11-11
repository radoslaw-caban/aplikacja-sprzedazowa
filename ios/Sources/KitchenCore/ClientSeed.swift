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

    public init(_ firstName: String, _ lastName: String, _ year: Int, _ month: Int, _ day: Int,
                _ total: Double, _ deposit: Double, status: String = "Do dostarczenia") {
        self.firstName = firstName
        self.lastName = lastName
        self.deliveryYear = year
        self.deliveryMonth = month
        self.deliveryDay = day
        self.total = total
        self.deposit = deposit
        self.status = status
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

    public static let version = 1
    public static let defaultsKey = "aplikacja-sprzedazowa:seed:clients:v\(version)"

    /// Tabela z załącznika — kolejność jak na liście.
    public static let all: [SeedClient] = [
        SeedClient("Alicja", "Lidwin", 2027, 9, 30, 11_500, 4_000),
        SeedClient("Paulina", "Bartodziej", 2027, 5, 31, 27_600, 0),
        SeedClient("Sebastian", "Jaźwiecki", 2027, 5, 31, 23_350, 7_000),
        SeedClient("Paulina", "Bartodziej", 2027, 5, 31, 30_900, 10_000),
        SeedClient("Kamila", "Kustroń", 2027, 3, 22, 35_500, 0),
        SeedClient("Małgorzata", "Półchłopek", 2027, 2, 28, 36_813, 0),
        SeedClient("Grzegorz", "Przepióra", 2027, 2, 28, 26_000, 0),
        SeedClient("Emil", "Kędra", 2027, 2, 28, 45_000, 0),
        SeedClient("Dorota", "Kustroń", 2027, 2, 28, 20_500, 7_700),
        SeedClient("Aneta", "Rachwał", 2027, 2, 28, 7_400, 0),
        SeedClient("Marzena", "Gierlach", 2027, 2, 28, 40_800, 0),
        SeedClient("Renata", "Gazda", 2027, 2, 28, 26_800, 8_000),
        SeedClient("Aleksandra", "Wanca", 2027, 2, 28, 27_300, 0),
    ]

    /// Projekt-kartoteka z jednej pozycji tabeli.
    public static func project(from client: SeedClient) -> Project {
        let order = ProjectOrder(
            clientLastName: client.lastName,
            clientFirstName: client.firstName,
            price: client.total,
            deposit: client.deposit,
            notes: "Kartoteka wprowadzona z tabeli zamówień.",
            deliveryDate: client.deliveryDate,
            status: client.status
        )
        var project = Project(name: "\(client.firstName) \(client.lastName)")
        project.order = order
        return project
    }
}
