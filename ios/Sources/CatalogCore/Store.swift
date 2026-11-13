import Foundation

/// Katalog na dysku: producenci, produkty, pliki, miniatury, dziennik decyzji.
///
/// Układ katalogu:
/// ```
/// <root>/
///   manufacturers/<id>.json        + logo.png obok
///   products/<id>/product.json     + assets/*.glb, thumb.png
///   audit.log                      (append-only)
///   library.json                   (zatwierdzone — to konsumuje aplikacja)
/// ```
public final class CatalogStore {
    public let root: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(path: String) {
        self.init(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }

    // MARK: - ścieżki

    public var manufacturersDir: URL { root.appendingPathComponent("manufacturers") }
    public var productsDir: URL { root.appendingPathComponent("products") }
    public var auditURL: URL { root.appendingPathComponent("audit.log") }
    public var libraryURL: URL { root.appendingPathComponent("library.json") }

    public func productDir(_ id: String) -> URL { productsDir.appendingPathComponent(id) }
    public func assetsDir(_ id: String) -> URL { productDir(id).appendingPathComponent("assets") }
    public func thumbnailURL(_ id: String) -> URL { productDir(id).appendingPathComponent("thumb.png") }
    public func hasThumbnail(_ id: String) -> Bool { fm.fileExists(atPath: thumbnailURL(id).path) }

    public func ensureLayout() throws {
        for dir in [root, manufacturersDir, productsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - producenci

    public func manufacturers() -> [Manufacturer] {
        contents(of: manufacturersDir, suffix: ".json")
            .compactMap { try? decoder.decode(Manufacturer.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func manufacturer(_ id: String) -> Manufacturer? {
        let url = manufacturersDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Manufacturer.self, from: data)
    }

    public func save(_ manufacturer: Manufacturer) throws {
        try ensureLayout()
        try encoder.encode(manufacturer)
            .write(to: manufacturersDir.appendingPathComponent("\(manufacturer.id).json"), options: .atomic)
    }

    public func logoURL(_ manufacturer: Manufacturer) -> URL? {
        guard let file = manufacturer.logoFile else { return nil }
        let url = manufacturersDir.appendingPathComponent(file)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - produkty

    public func products() -> [CatalogProduct] {
        guard let dirs = try? fm.contentsOfDirectory(at: productsDir, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir -> CatalogProduct? in
            let url = dir.appendingPathComponent("product.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CatalogProduct.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func product(_ id: String) -> CatalogProduct? {
        let url = productDir(id).appendingPathComponent("product.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CatalogProduct.self, from: data)
    }

    public func save(_ product: CatalogProduct) throws {
        try ensureLayout()
        let dir = productDir(product.id)
        try fm.createDirectory(at: assetsDir(product.id), withIntermediateDirectories: true)
        try encoder.encode(product).write(to: dir.appendingPathComponent("product.json"), options: .atomic)
    }

    public func delete(productID: String) throws {
        try fm.removeItem(at: productDir(productID))
        audit("usunięto produkt \(productID)")
    }

    /// Kopiuje plik do katalogu produktu i zwraca wpis zasobu z hashem.
    @discardableResult
    public func importAsset(from source: URL, productID: String,
                            kind: AssetFile.Kind, fileName: String? = nil) throws -> AssetFile {
        try ensureLayout()
        let dir = assetsDir(productID)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = fileName ?? source.lastPathComponent
        let destination = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: source, to: destination)
        let data = try Data(contentsOf: destination)
        return AssetFile(path: "assets/\(name)", kind: kind,
                         bytes: data.count, sha256: SHA256Hex.hash(data))
    }

    public func assetURL(_ product: CatalogProduct, asset: AssetFile) -> URL {
        productDir(product.id).appendingPathComponent(asset.path)
    }

    // MARK: - dziennik

    /// Append-only zapis decyzji: kto, kiedy, co. Nigdy nie nadpisuje historii.
    public func audit(_ message: String, by user: String = "system") {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] [\(user)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: auditURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: auditURL)
        }
    }

    public func auditLines(limit: Int = 50) -> [String] {
        guard let text = try? String(contentsOf: auditURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).suffix(limit).map(String.init)
    }

    // MARK: - biblioteka oficjalna

    /// Pozycja kafelka: miniatura + oficjalne logo producenta + nazwa produktu.
    public struct LibraryEntry: Codable, Sendable, Equatable {
        public var id: String
        public var sku: String
        public var name: String
        public var category: ProductCategory
        public var manufacturerID: String
        public var manufacturerName: String
        public var logoPath: String?
        public var thumbnailPath: String?
        public var costText: String
        public var retailText: String
        public var marginPercent: Double
        public var dependencies: [DependencyRule]
        public var legalBasis: LegalBasis
    }

    public struct LibraryIndex: Codable, Sendable {
        public var generatedAt: Date
        public var entries: [LibraryEntry]
    }

    /// Buduje `library.json` z produktów zatwierdzonych — to jedyny plik,
    /// który w przyszłości czyta aplikacja (moduł nie jest jeszcze podpięty).
    @discardableResult
    public func rebuildLibrary() throws -> LibraryIndex {
        var entries: [LibraryEntry] = []
        for product in products() where product.status == .approved {
            let manufacturer = manufacturer(product.manufacturerID)
            entries.append(LibraryEntry(
                id: product.id,
                sku: product.sku,
                name: product.name,
                category: product.category,
                manufacturerID: product.manufacturerID,
                manufacturerName: manufacturer?.name ?? product.manufacturerID,
                logoPath: manufacturer?.logoFile,
                thumbnailPath: product.thumbnail,
                costText: product.pricing.costText,
                retailText: product.pricing.retailText,
                marginPercent: product.pricing.marginPercent,
                dependencies: product.dependencies,
                legalBasis: product.legal.basis
            ))
        }
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let index = LibraryIndex(generatedAt: Date(), entries: entries)
        try encoder.encode(index).write(to: libraryURL, options: .atomic)
        return index
    }

    // MARK: - pomoc

    private func contents(of dir: URL, suffix: String) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasSuffix(suffix) } ?? []
    }
}

/// SHA-256 bez CryptoKit — działa też w linii komend na starych systemach.
public enum SHA256Hex {
    public static func hash(_ data: Data) -> String {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let base = chunk + i * 4
                w[i] = (UInt32(message[base]) << 24) | (UInt32(message[base + 1]) << 16)
                     | (UInt32(message[base + 2]) << 8) | UInt32(message[base + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
