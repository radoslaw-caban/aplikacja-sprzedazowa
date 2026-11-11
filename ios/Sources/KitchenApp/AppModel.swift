import Foundation
import SwiftUI
import Observation
import KitchenCore

/// Stan aplikacji: projekty, aktywny projekt, dokumenty klienta.
/// Zapis na dysk po każdej zmianie; brak magii — wszystko jawne i testowalne.
@MainActor
@Observable
final class AppModel {
    var projects: [Project]
    var currentIndex: Int = 0
    /// indeks przeglądanego dokumentu (nil = pokazujemy scenę 3D)
    var documentIndex: Int?
    var status: String?
    /// skan pomieszczenia wczytany do sceny (metry) — nil = brak skanu
    var scan: PointCloud?
    /// transformacja skanu do układu projektu
    var scanTransform = ScanTransform()
    /// nazwa pliku skanu wczytanego do sceny
    var scanName: String?

    /// „Pulpit projektowy": klienci, nad którymi pracujemy teraz (przewijanie góra/dół).
    var workingSet: [UUID] = []
    /// klucz zapisu zestawu roboczego
    static let workingSetKey = "aplikacja-sprzedazowa:workingSet"

    let store: ProjectStore

    init(store: ProjectStore = .standard()) {
        self.store = store
        var loaded = store.load()
        if loaded.isEmpty {
            loaded = [Project(name: "Projekt 1", cabinets: [
                Library.make(Library.base[0], at: -1200, z: -2200),
                Library.make(Library.base[1], at: -600, z: -2200),
            ])]
        }
        self.projects = loaded
        if let raw = UserDefaults.standard.array(forKey: Self.workingSetKey) as? [String] {
            self.workingSet = raw.compactMap(UUID.init(uuidString:))
        }
        // zestaw roboczy nie może wskazywać na usunięte projekty
        let ids = Set(loaded.map(\.id))
        workingSet = workingSet.filter { ids.contains($0) }
    }

    /// Wgrywa kartoteki klientów z tabeli zamówień — raz, tylko brakujące.
    /// Klucz w UserDefaults pilnuje, żeby nie wracały po usunięciu.
    @discardableResult
    func seedClients(force: Bool = false, defaults: UserDefaults = .standard) -> Int {
        if !force, defaults.bool(forKey: ClientSeed.defaultsKey) { return 0 }

        var added = 0
        var filled = 0
        let removed = removeDuplicateClients()

        for client in ClientSeed.all {
            if let index = projects.firstIndex(where: { matches($0, client) }) {
                // kartoteka już jest — uzupełniamy tylko PUSTE pola (nie nadpisujemy danych użytkownika)
                var order = projects[index].order ?? ProjectOrder()
                var changed = false
                if order.address.isEmpty, !client.address.isEmpty { order.address = client.address; changed = true }
                if order.phone.isEmpty, !client.phone.isEmpty { order.phone = client.phone; changed = true }
                if order.email.isEmpty, !client.email.isEmpty { order.email = client.email; changed = true }
                if order.notes.isEmpty, !client.note.isEmpty { order.notes = client.note; changed = true }
                if order.deliveryDate == nil { order.deliveryDate = client.deliveryDate; changed = true }
                if order.status == nil { order.status = client.status; changed = true }
                if changed {
                    projects[index].order = order
                    projects[index].updatedAt = Date()
                    filled += 1
                }
                continue
            }

            projects.append(ClientSeed.project(from: client))
            added += 1
        }

        if added > 0 || filled > 0 || removed > 0 {
            persist()
            if added > 0 {
                status = "Dodano \(added) kartotek klientów"
            } else if filled > 0 {
                status = "Uzupełniono \(filled) kartotek"
            }
            if removed > 0 { NSLog("[dane] usunięto %d duplikatów kartotek", removed) }
        }
        defaults.set(true, forKey: ClientSeed.defaultsKey)
        return added + filled
    }

    /// Usuwa zdublowane kartoteki: zostawia tę z największą liczbą wypełnionych pól.
    @discardableResult
    func removeDuplicateClients() -> Int {
        var removed = 0
        for client in ClientSeed.all {
            let indexes = projects.indices.filter { matches(projects[$0], client) }
            guard indexes.count > 1 else { continue }
            let scored = indexes.map { index -> (Int, Int) in
                let order = projects[index].order ?? ProjectOrder()
                var score = 0
                if !order.address.isEmpty { score += 1 }
                if !order.phone.isEmpty { score += 1 }
                if !order.email.isEmpty { score += 1 }
                if !order.notes.isEmpty { score += 1 }
                if order.deliveryDate != nil { score += 1 }
                return (index, score)
            }
            let keep = scored.max { $0.1 < $1.1 }?.0
            for (index, _) in scored.sorted(by: { $0.0 > $1.0 }) where index != keep {
                projects.remove(at: index)
                removed += 1
            }
        }
        if removed > 0 {
            currentIndex = min(currentIndex, max(0, projects.count - 1))
        }
        return removed
    }

    /// Czy projekt odpowiada pozycji z tabeli. Dopasowujemy po imieniu, nazwisku
    /// i kwocie — data dostawy bywa pusta w starszych zapisach, więc nie może
    /// decydować o dopasowaniu (inaczej powstawały duplikaty kartotek).
    private func matches(_ project: Project, _ client: SeedClient) -> Bool {
        guard let order = project.order else { return false }
        return order.clientLastName == client.lastName
            && order.clientFirstName == client.firstName
            && abs(order.price - client.total) < 0.01
    }

    // MARK: - pulpit projektowy

    /// Projekty z pulpitu (w kolejności ustawionej przez użytkownika).
    var workingProjects: [Project] {
        workingSet.compactMap { id in projects.first { $0.id == id } }
    }

    var isCurrentInWorkingSet: Bool { workingSet.contains(current.id) }

    func addToWorkingSet(_ id: UUID) {
        guard !workingSet.contains(id) else { return }
        workingSet.append(id)
        persistWorkingSet()
        status = "Dodano do pulpitu projektowego"
    }

    func removeFromWorkingSet(_ id: UUID) {
        workingSet.removeAll { $0 == id }
        persistWorkingSet()
    }

    func toggleWorkingSet(_ id: UUID) {
        if workingSet.contains(id) { removeFromWorkingSet(id) } else { addToWorkingSet(id) }
    }

    /// Przewijanie po pulpicie: +1 w dół, -1 w górę.
    func switchWorking(step: Int) {
        let list = workingProjects
        guard !list.isEmpty else { return }
        let currentIndex = list.firstIndex { $0.id == current.id } ?? 0
        let next = (currentIndex + step + list.count) % list.count
        if let index = projects.firstIndex(where: { $0.id == list[next].id }) {
            selectProject(index)
        }
    }

    private func persistWorkingSet() {
        UserDefaults.standard.set(workingSet.map(\.uuidString), forKey: Self.workingSetKey)
    }

    // MARK: - kartoteka klienta

    /// Nowy projekt dla tego samego klienta (dane kontaktowe skopiowane, zabudowa pusta).
    @discardableResult
    func addProjectForCurrentClient() -> Project {
        var new = Project(name: current.name)
        new.order = current.order
        new.room = current.room
        new.plan = current.plan
        projects.append(new)
        persist()
        if let index = projects.firstIndex(where: { $0.id == new.id }) {
            currentIndex = index
        }
        status = "Nowy projekt dla \(new.name)"
        return new
    }

    /// Projekty tego samego klienta co bieżący.
    func projectsOfCurrentClient() -> [Project] {
        ClientDirectory.projects(of: ClientDirectory.displayName(current), in: projects)
    }

    /// Rabat klienta (procent) — wpływa na cenę końcową.
    func setDiscount(percent: Double) {
        guard projects.indices.contains(currentIndex) else { return }
        var order = projects[currentIndex].order ?? ProjectOrder()
        order.discountPercent = min(100, max(0, percent))
        projects[currentIndex].order = order
        projects[currentIndex].updatedAt = Date()
        persist()
    }

    /// Zapis podpisu umowy (plik PNG w Documents/umowy).
    func signContract(signatureFile: String) {
        guard projects.indices.contains(currentIndex) else { return }
        var order = projects[currentIndex].order ?? ProjectOrder()
        order.contractSignedAt = Date()
        order.contractSignatureFile = signatureFile
        projects[currentIndex].order = order
        projects[currentIndex].updatedAt = Date()
        persist()
        status = "Umowa podpisana"
    }

    /// Nowy klient z kreatora — zakłada kartotekę.
    @discardableResult
    func createClient(firstName: String, lastName: String, address: String, phone: String, email: String) -> Project {
        var project = Project(name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces))
        project.order = ProjectOrder(
            clientLastName: lastName,
            clientFirstName: firstName,
            address: address,
            phone: phone,
            email: email,
            status: "Nowy klient"
        )
        projects.append(project)
        persist()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            currentIndex = index
        }
        return project
    }

    var current: Project {
        guard projects.indices.contains(currentIndex) else {
            return Project(name: "Projekt 1")
        }
        return projects[currentIndex]
    }

    var documents: [ClientDocument] { current.documents }

    var currentDocument: ClientDocument? {
        guard let i = documentIndex, documents.indices.contains(i) else { return nil }
        return documents[i]
    }

    // MARK: - projekty

    func selectProject(_ index: Int) {
        guard projects.indices.contains(index) else { return }
        currentIndex = index
        documentIndex = nil
        persist()
    }

    /// Gest pionowy: kolejny/poprzedni projekt. Wyjście z podglądu dokumentu.
    func switchProject(step: Int) {
        guard !projects.isEmpty else { return }
        documentIndex = nil
        currentIndex = GestureNav.nextIndex(currentIndex, count: projects.count, step: step)
        status = "Projekt: \(current.name)"
    }

    func addProject(name: String? = nil) {
        let p = Project(name: name ?? "Projekt \(projects.count + 1)")
        projects.append(p)
        currentIndex = projects.count - 1
        documentIndex = nil
        persist()
    }

    func renameCurrent(_ name: String) {
        guard projects.indices.contains(currentIndex) else { return }
        projects[currentIndex].name = name
        persist()
    }

    func deleteCurrentProject() {
        guard projects.count > 1, projects.indices.contains(currentIndex) else { return }
        let dir = store.directory(for: current)
        try? FileManager.default.removeItem(at: dir)
        projects.remove(at: currentIndex)
        currentIndex = min(currentIndex, projects.count - 1)
        documentIndex = nil
        persist()
    }

    // MARK: - szafki i pokój (zapis do aktywnego projektu)

    func updateCabinets(_ cabinets: [Cabinet]) {
        guard projects.indices.contains(currentIndex) else { return }
        projects[currentIndex].cabinets = cabinets
        projects[currentIndex].updatedAt = Date()
    }

    func updateRoom(_ room: Room) {
        guard projects.indices.contains(currentIndex) else { return }
        projects[currentIndex].room = room
        rebuildZones()
    }

    /// Plan bieżącego projektu. Gdy jeszcze nie rysowany — prostokąt z pokoju,
    /// żeby widok mapy nie startował od pustki.
    var currentPlan: FloorPlan {
        current.plan ?? FloorPlan.rectangle(
            width: current.room.width,
            depth: current.room.depth,
            height: current.room.height
        )
    }

    /// Szczegóły zamówienia (ekran startowy). Brak zapisu = pusty formularz.
    var currentOrder: ProjectOrder { current.order ?? ProjectOrder() }

    func updateOrder(_ order: ProjectOrder) {
        guard projects.indices.contains(currentIndex) else { return }
        var updated = order
        updated.updatedAt = Date()
        projects[currentIndex].order = updated
        projects[currentIndex].updatedAt = Date()
        persist()
    }

    /// Zapis planu: plan jest źródłem prawdy dla bryły domu, więc pokój
    /// przelicza się z jego obrysu (szerokość × głębokość × wysokość).
    func updatePlan(_ plan: FloorPlan) {
        guard projects.indices.contains(currentIndex) else { return }
        projects[currentIndex].plan = plan
        projects[currentIndex].room = plan.room(name: projects[currentIndex].room.name)
        projects[currentIndex].updatedAt = Date()
        // strefy są przypięte do ścian planu — po zmianie planu odbudowujemy je
        rebuildZones()
        persist()
    }

    // MARK: - strefy zabudowy

    /// Strefy bieżącego projektu (brak = pusta lista).
    var currentZones: [Zone] { current.zones ?? [] }

    /// Nowa strefa na ścianie planu — od razu z gotową propozycją.
    @discardableResult
    func addZone(kind: ZoneKind, wallIndex: Int) -> Zone {
        var z = Zones.makeZone(kind: kind, wallIndex: wallIndex)
        z.draft = true            // najpierw podgląd: cień szafek + gwiazdki
        guard projects.indices.contains(currentIndex) else { return z }
        var zones = projects[currentIndex].zones ?? []
        zones.append(z)
        projects[currentIndex].zones = zones
        rebuildZones()
        projects[currentIndex].updatedAt = Date()
        persist()
        status = "Strefa: \(z.name) — gotowa propozycja"
        return z
    }

    /// Zatwierdza podgląd strefy — cień staje się realną zabudową.
    func finalizeZone(_ id: UUID) {
        guard projects.indices.contains(currentIndex) else { return }
        var zones = projects[currentIndex].zones ?? []
        guard let i = zones.firstIndex(where: { $0.id == id }) else { return }
        if zones[i].draft != nil {
            zones[i].draft = false
            projects[currentIndex].zones = zones
            rebuildZones()
            projects[currentIndex].updatedAt = Date()
            persist()
        }
    }

    func updateZone(_ zone: Zone, persistNow: Bool = false) {
        guard projects.indices.contains(currentIndex) else { return }
        var zones = projects[currentIndex].zones ?? []
        guard let i = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        zones[i] = zone
        projects[currentIndex].zones = zones
        rebuildZones()
        projects[currentIndex].updatedAt = Date()
        if persistNow { persist() }
    }

    func setZoneValue(_ zoneID: UUID, key: String, value: ZoneValue) {
        guard var zone = currentZones.first(where: { $0.id == zoneID }) else { return }
        zone.answers[key] = value
        updateZone(zone)
    }

    func deleteZone(_ id: UUID) {
        guard projects.indices.contains(currentIndex) else { return }
        var zones = projects[currentIndex].zones ?? []
        zones.removeAll { $0.id == id }
        projects[currentIndex].zones = zones
        rebuildZones()
        persist()
        status = "Strefa usunięta"
    }

    /// Odtwarza szafki stref (szafki ręczne zostają). Strefa jest właścicielem
    /// swoich szafek — zmiana odpowiedzi przebudowuje tylko jej zabudowę.
    func rebuildZones() {
        guard projects.indices.contains(currentIndex) else { return }
        let zones = projects[currentIndex].zones ?? []
        projects[currentIndex].cabinets = Zones.rebuilt(
            projects[currentIndex].cabinets,
            zones: zones,
            plan: currentPlan
        )
    }

    // MARK: - dokumenty

    /// Gest poziomy: kolejny/poprzedni dokument; wchodzi w podgląd, jeśli jest co pokazać.
    func switchDocument(step: Int) {
        guard !documents.isEmpty else {
            status = "Ten projekt nie ma dokumentów"
            return
        }
        let base = documentIndex ?? (step > 0 ? -1 : 0)
        documentIndex = GestureNav.nextIndex(base, count: documents.count, step: step)
        status = currentDocument.map { "\($0.name) · \($0.kind.label)" }
    }

    func openDocument(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        documentIndex = index
    }

    func closeDocument() { documentIndex = nil }

    @discardableResult
    func importDocuments(from urls: [URL]) -> Int {
        guard projects.indices.contains(currentIndex) else { return 0 }
        var added = 0
        for url in urls {
            do {
                let (_, updated) = try store.importDocument(from: url, into: projects[currentIndex])
                projects[currentIndex] = updated
                added += 1
            } catch {
                status = "Nie udało się dodać \(url.lastPathComponent)"
            }
        }
        if added > 0 {
            status = added == 1 ? "Dodano dokument" : "Dodano \(added) dokumentów"
            documentIndex = projects[currentIndex].documents.count - added
            persist()
        }
        return added
    }

    func deleteDocument(at index: Int) {
        guard projects.indices.contains(currentIndex), documents.indices.contains(index) else { return }
        let doc = documents[index]
        projects[currentIndex] = store.deleteDocument(doc, from: projects[currentIndex])
        if let di = documentIndex {
            if documents.isEmpty { documentIndex = nil }
            else if di >= documents.count { documentIndex = documents.count - 1 }
        }
        persist()
    }

    func fileURL(for document: ClientDocument) -> URL {
        store.url(for: document, in: current)
    }

    // MARK: - skan pomieszczenia

    /// Dodaje skan z LiDAR-u: zapisuje PLY w projekcie i wczytuje do sceny.
    ///
    /// Chmura z ARKit jest w metrach, a `PointCloud` oczekuje współrzędnych
    /// w metrach (parser PLY skaluje mm→m przez `unitScaleToMeters`).
    /// Wczytujemy więc bez konwersji i oznaczamy transformacją domyślną.
    @discardableResult
    func addScan(_ cloud: PointCloud) -> Bool {
        guard projects.indices.contains(currentIndex) else { return false }
        do {
            let (doc, updated) = try store.writeScan(cloud, into: projects[currentIndex])
            projects[currentIndex] = updated
            scan = cloud
            scanName = doc.fileName
            scanTransform = ScanTransform()
            documentIndex = nil
            // pokaz realną dokładność, nie tylko liczbę punktów
            if let report = ScanPLYWriter.qualityReport(cloud) {
                let sigmaLine = report
                    .split(separator: "\n")
                    .first { $0.hasPrefix("σ mediana") }
                    .map(String.init) ?? ""
                status = "Skan dodany · \(ScanOutcome.summary(cloud)) · \(sigmaLine)"
            } else {
                status = "Skan dodany · \(ScanOutcome.summary(cloud))"
            }
            persist()
            return true
        } catch {
            status = "Nie udało się zapisać skanu: \(error.localizedDescription)"
            return false
        }
    }

    /// Wczytuje skan z dokumentu projektu (PLY) do sceny.
    func loadScan(from document: ClientDocument) {
        let url = store.url(for: document, in: current)
        do {
            let cloud = try PLYParser.parse(contentsOf: url)
            scan = cloud
            scanName = document.fileName
            scanTransform = ScanTransform()
            status = "Skan wczytany · \(ScanOutcome.summary(cloud))"
        } catch {
            status = "Nie udało się wczytać skanu: \(error.localizedDescription)"
        }
    }

    /// Usuwa skan ze sceny (plik zostaje w projekcie).
    func clearScan() {
        scan = nil
        scanName = nil
        scanTransform = ScanTransform()
    }

    /// Skan przypisany do bieżącego projektu (pierwszy dokument typu .skan).
    var scanDocument: ClientDocument? {
        documents.first { $0.kind == .skan }
    }

    // MARK: - zapis

    func persist() {
        do {
            try store.save(projects)
        } catch {
            status = "Błąd zapisu: \(error.localizedDescription)"
        }
    }
}
