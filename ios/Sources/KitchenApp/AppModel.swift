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

    // MARK: - zapis

    func persist() {
        do {
            try store.save(projects)
        } catch {
            status = "Błąd zapisu: \(error.localizedDescription)"
        }
    }
}
