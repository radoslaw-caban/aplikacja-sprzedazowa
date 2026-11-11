import Foundation

/// Tekstura wczytana przez użytkownika.
///
/// ZASADA: **nazwa = nazwa pliku** (bez rozszerzenia). Nikt nie wymyśla nazw
/// przy imporcie — plik `dąb bielony 02.jpg` nazywa się „dąb bielony 02".
public struct StoredTexture: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String       // nazwa = nazwa pliku bez rozszerzenia
    public var fileName: String   // faktyczny plik w bibliotece
    public var added: Date

    public init(id: UUID = UUID(), name: String, fileName: String, added: Date = Date()) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.added = added
    }
}

/// Biblioteka tekstur: kopiuje pliki do katalogu aplikacji, trzyma indeks
/// i pozwala szukać po nazwie.
public final class TextureStore: @unchecked Sendable {

    public static let shared = TextureStore()

    public private(set) var textures: [StoredTexture] = []
    private let directory: URL
    private let indexURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tekstury", isDirectory: true)
        self.directory = base
        self.indexURL = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    public var folder: URL { directory }

    // MARK: - import

    /// Kopiuje plik do biblioteki. Nazwa bierze się z nazwy pliku.
    @discardableResult
    public func importFile(at url: URL) throws -> StoredTexture {
        let original = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension

        // kolizja nazw: dopisujemy numer, żeby nie nadpisać cudzej tekstury
        var name = original
        var counter = 2
        while textures.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(original) \(counter)"
            counter += 1
        }

        let fileName = "\(UUID().uuidString.prefix(8))-\(name).\(ext)"
        let target = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)

        let texture = StoredTexture(name: name, fileName: fileName)
        textures.append(texture)
        save()
        return texture
    }

    public func delete(_ texture: StoredTexture) {
        textures.removeAll { $0.id == texture.id }
        let url = directory.appendingPathComponent(texture.fileName)
        try? FileManager.default.removeItem(at: url)
        save()
    }

    /// Plik tekstury do wczytania w scenie.
    public func url(for name: String) -> URL? {
        guard let texture = textures.first(where: { $0.name == name }) else { return nil }
        let url = directory.appendingPathComponent(texture.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Wyszukiwarka: fragment nazwy, bez wielkości liter i bez ogonków.
    public func search(_ query: String) -> [StoredTexture] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            return textures.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return textures
            .filter {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .contains(needle)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - zapis indeksu

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([StoredTexture].self, from: data) else { return }
        textures = list
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(textures) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
