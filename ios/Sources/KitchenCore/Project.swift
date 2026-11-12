import Foundation

/// Rodzaj dokumentu klienta — determinuje ikonę i kolejność na liście.
public enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case umowa
    case skan
    case rzut
    case zdjecie
    case pomiar
    case oferta
    case inne

    public var label: String {
        switch self {
        case .umowa: "Umowa"
        case .skan: "Skan pomieszczenia"
        case .rzut: "Rzut"
        case .zdjecie: "Zdjęcie"
        case .pomiar: "Pomiar"
        case .oferta: "Oferta"
        case .inne: "Inne"
        }
    }

    public var icon: String {
        switch self {
        case .umowa: "doc.text"
        case .skan: "cube.transparent"
        case .rzut: "square.grid.3x3"
        case .zdjecie: "photo"
        case .pomiar: "ruler"
        case .oferta: "doc.plaintext"
        case .inne: "paperclip"
        }
    }

    /// Rozpoznanie po rozszerzeniu pliku.
    public static func from(fileName: String) -> DocumentKind {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return .umowa
        case "e57", "ply", "pcd", "xyz": return .skan
        case "dwg", "dxf", "skp": return .rzut
        case "jpg", "jpeg", "png", "heic", "heif": return .zdjecie
        default: return .inne
        }
    }
}

/// Dokument przypisany do projektu (plik leży w katalogu projektu).
public struct ClientDocument: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: DocumentKind
    public var fileName: String
    public var sizeBytes: Int
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, kind: DocumentKind, fileName: String, sizeBytes: Int, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
    }

    public var sizeLabel: String {
        let mb = Double(sizeBytes) / 1_000_000
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f kB", Double(sizeBytes) / 1000)
    }
}

/// Projekt: jedna aranżacja (szafki, pokój, dokumenty klienta).
public struct Project: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var cabinets: [Cabinet]
    public var room: Room
    public var documents: [ClientDocument]
    public var locked: Bool
    public var updatedAt: Date
    /// Plan domu rysowany w widoku mapy. `nil` = plan jeszcze nie narysowany,
    /// wtedy obowiązuje prostokąt z `room`.
    public var plan: FloorPlan?
    /// Szczegóły zamówienia — ekran startowy aplikacji.
    public var order: ProjectOrder?
    /// Strefy zabudowy (auto-projekt) — brak pola = projekt bez stref.
    public var zones: [Zone]?
    /// kolor ścian wybrany magicznym ołówkiem w trybie FPS
    public var wallColor: String?

    public init(
        id: UUID = UUID(),
        name: String,
        cabinets: [Cabinet] = [],
        room: Room = Room(),
        documents: [ClientDocument] = [],
        locked: Bool = false,
        updatedAt: Date = Date(),
        plan: FloorPlan? = nil,
        order: ProjectOrder? = nil,
        zones: [Zone]? = nil,
        wallColor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cabinets = cabinets
        self.room = room
        self.documents = documents
        self.locked = locked
        self.updatedAt = updatedAt
        self.plan = plan
        self.order = order
        self.zones = zones
        self.wallColor = wallColor
    }
}

/// Zapis projektów i plików klienta na dysku (Documents/Projekty).
public struct ProjectStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Domyślna lokalizacja w aplikacji: ~/Documents/Projekty
    public static func standard() -> ProjectStore {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return ProjectStore(root: base.appendingPathComponent("Projekty", isDirectory: true))
    }

    private var indexURL: URL { root.appendingPathComponent("projects.json") }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func load() -> [Project] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Project].self, from: data)) ?? []
    }

    public func save(_ projects: [Project]) throws {
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: indexURL, options: .atomic)
    }

    /// Katalog plików jednego projektu.
    public func directory(for project: Project) -> URL {
        root.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    public func url(for document: ClientDocument, in project: Project) -> URL {
        directory(for: project).appendingPathComponent(document.fileName)
    }

    /// Zapisuje chmurę punktów jako PLY w katalogu projektu i zwraca wpis dokumentu.
    ///
    /// Skan trafia do projektu jako zwykły dokument — dzięki temu jest widoczny
    /// na liście plików klienta, przetrwa restart aplikacji i można go wysłać
    /// mailem tak samo jak umowę czy zdjęcie.
    public func writeScan(_ cloud: PointCloud, into project: Project, at date: Date = Date()) throws -> (ClientDocument, Project) {
        try ensureDirectories()
        let dir = directory(for: project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = ScanPLYWriter.fileName(at: date)
        let target = dir.appendingPathComponent(fileName)
        try ScanPLYWriter.write(cloud, to: target)

        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
        let doc = ClientDocument(
            name: "Skan pomieszczenia",
            kind: .skan,
            fileName: fileName,
            sizeBytes: size,
            addedAt: date
        )
        var updated = project
        updated.documents.append(doc)
        updated.updatedAt = date
        return (doc, updated)
    }

    /// Kopiuje plik do katalogu projektu i zwraca wpis na liście dokumentów.
    public func importDocument(from source: URL, into project: Project) throws -> (ClientDocument, Project) {
        try ensureDirectories()
        let dir = directory(for: project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let name = source.lastPathComponent
        var target = dir.appendingPathComponent(name)
        // kolizja nazw: dopisz numer
        var counter = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: target.path) {
            let candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            target = dir.appendingPathComponent(candidate)
            counter += 1
        }

        try FileManager.default.copyItem(at: source, to: target)
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
        let doc = ClientDocument(
            name: base,
            kind: DocumentKind.from(fileName: name),
            fileName: target.lastPathComponent,
            sizeBytes: size
        )
        var updated = project
        updated.documents.append(doc)
        updated.updatedAt = Date()
        return (doc, updated)
    }

    /// Usuwa dokument z projektu razem z plikiem.
    public func deleteDocument(_ document: ClientDocument, from project: Project) -> Project {
        let file = url(for: document, in: project)
        try? FileManager.default.removeItem(at: file)
        var updated = project
        updated.documents.removeAll { $0.id == document.id }
        updated.updatedAt = Date()
        return updated
    }
}

/// Nawigacja gestami: pion = projekty, poziom = dokumenty.
public enum GestureNav {

    public enum Axis: Sendable { case vertical, horizontal, none }

    /// Który gest dominuje przy danym przesunięciu (progi w punktach).
    public static func axis(dx: Double, dy: Double, threshold: Double = 60) -> Axis {
        let ax = abs(dx), ay = abs(dy)
        guard max(ax, ay) > threshold else { return .none }
        if ax > ay * 1.4 { return .horizontal }
        if ay > ax * 1.4 { return .vertical }
        return .none
    }

    /// Następny indeks z zawijaniem (np. ostatni → pierwszy).
    public static func nextIndex(_ current: Int, count: Int, step: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = current + step
        if raw < 0 { return count - 1 }
        if raw >= count { return 0 }
        return raw
    }

    /// Kierunek gestu na indeks: w górę = następny projekt, w prawo = poprzedni dokument.
    public static func step(for axis: Axis, dx: Double, dy: Double) -> Int {
        switch axis {
        case .vertical: return dy < 0 ? 1 : -1      // palec w górę → następny
        case .horizontal: return dx > 0 ? -1 : 1     // palec w lewo → następny
        case .none: return 0
        }
    }
}
