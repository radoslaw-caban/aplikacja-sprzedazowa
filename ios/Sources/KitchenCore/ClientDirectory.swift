import Foundation

/// Wyszukiwanie klientów po kartotekach i grupowanie projektów jednego klienta.
///
/// ZASADA: klient to **nazwisko + imię**, a nie identyfikator projektu — jeden
/// klient może mieć kilka zamówień (kuchnia, potem garderoba). Dlatego szukamy
/// po kartotekach, a nie po nazwach projektów.
public struct ClientHit: Identifiable, Sendable, Equatable {
    public var id: UUID { projectID }
    public var projectID: UUID
    public var name: String
    public var address: String
    public var status: String
    public var total: Double
    /// ile projektów ma ten klient (do plakietki „3 projekty")
    public var projectCount: Int

    public init(projectID: UUID, name: String, address: String, status: String, total: Double, projectCount: Int) {
        self.projectID = projectID
        self.name = name
        self.address = address
        self.status = status
        self.total = total
        self.projectCount = projectCount
    }
}

public enum ClientDirectory {

    /// Nazwa do interfejsu: **imię i nazwisko** (na umowie zostaje „nazwisko imię").
    public static func displayName(_ project: Project) -> String {
        if let order = project.order {
            let name = [order.clientFirstName, order.clientLastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return project.name
    }

    public static func address(_ project: Project) -> String {
        project.order?.address ?? ""
    }

    /// Szukanie po imieniu, nazwisku i adresie — bez wielkości liter i ogonków
    /// („kędra" znajduje „Emil Kędra", „kedra" też).
    public static func search(_ projects: [Project], query: String, limit: Int = 12) -> [ClientHit] {
        let needle = normalize(query)
        let counts = projectCounts(projects)

        let hits = projects.compactMap { project -> ClientHit? in
            guard project.order != nil else { return nil }
            let name = displayName(project)
            let address = address(project)
            guard !needle.isEmpty
                    || !name.isEmpty else { return nil }
            if !needle.isEmpty {
                let haystack = normalize("\(name) \(address)")
                guard haystack.contains(needle) else { return nil }
            }
            return ClientHit(
                projectID: project.id,
                name: name,
                address: address,
                status: project.order?.status ?? "—",
                total: project.order?.finalPrice ?? 0,
                projectCount: counts[normalize(name)] ?? 1
            )
        }

        // najpierw ci, których nazwisko zaczyna się od wpisanego tekstu
        return hits.sorted { a, b in
            let aStarts = normalize(a.name).hasPrefix(needle)
            let bStarts = normalize(b.name).hasPrefix(needle)
            if aStarts != bStarts { return aStarts }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Wszystkie projekty jednego klienta (po nazwie kartoteki).
    public static func projects(of clientName: String, in projects: [Project]) -> [Project] {
        let key = normalize(clientName)
        return projects.filter { normalize(displayName($0)) == key }
    }

    public static func projectCounts(_ projects: [Project]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for project in projects where project.order != nil {
            counts[normalize(displayName(project)), default: 0] += 1
        }
        return counts
    }

    /// Bez ogonków i wielkości liter — wspólne dla szukania i porównywania.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
