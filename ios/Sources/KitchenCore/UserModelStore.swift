import Foundation

/// Modele 3D wgrane przez użytkownika (GLB/GLTF). Leżą w Documents/Modele,
/// indeks w `index.json`. Nazwa = nazwa pliku bez rozszerzenia.
public struct UserModel: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var fileName: String
    public var added: Date

    public init(id: UUID = UUID(), name: String, fileName: String, added: Date = Date()) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.added = added
    }
}

public final class UserModelStore: @unchecked Sendable {
    public static let shared = UserModelStore()

    public private(set) var models: [UserModel] = []
    public let folder: URL
    private let indexURL: URL

    public init(folder: URL? = nil) {
        let base = folder ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Modele", isDirectory: true)
        self.folder = base
        self.indexURL = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([UserModel].self, from: data) else { return }
        models = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        try? data.write(to: indexURL)
    }

    @discardableResult
    public func importModel(from url: URL) throws -> UserModel {
        let ext = url.pathExtension.lowercased()
        guard ["glb", "gltf"].contains(ext) else {
            throw NSError(domain: "UserModelStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Obsługiwane są pliki .glb i .gltf"])
        }
        let base = url.deletingPathExtension().lastPathComponent
        var name = base
        var fileName = "\\(base).\\(ext)"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path) {
            name = "\\(base) \\(n)"
            fileName = "\\(base)_\\(n).\\(ext)"
            n += 1
        }
        let dest = folder.appendingPathComponent(fileName)
        if url.path != dest.path {
            try FileManager.default.copyItem(at: url, to: dest)
        }
        let model = UserModel(name: name, fileName: fileName)
        models.append(model)
        save()
        return model
    }

    public func delete(_ id: UUID) {
        guard let i = models.firstIndex(where: { $0.id == id }) else { return }
        let m = models[i]
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(m.fileName))
        models.remove(at: i)
        save()
    }

    public func url(for name: String) -> URL? {
        guard let m = models.first(where: { $0.name == name || $0.fileName == name }) else { return nil }
        let url = folder.appendingPathComponent(m.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
