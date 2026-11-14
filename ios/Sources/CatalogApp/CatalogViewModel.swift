import Foundation
import SwiftUI
import CatalogCore
import CatalogRender

@MainActor
@Observable
final class CatalogViewModel {
    var store: CatalogStore
    var products: [CatalogProduct] = []
    var manufacturers: [Manufacturer] = []
    var selection: String?
    var filter: StatusFilter = .all
    var search: String = ""
    var statusLine: String = ""
    var marginPercent: Double = 30
    var pendingImport: [URL] = []
    var showImportSheet = false

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "Wszystkie"
        case draft = "Szkice"
        case submitted = "Do zatwierdzenia"
        case approved = "W bibliotece"
        case rejected = "Odrzucone"
        var id: String { rawValue }
        var status: ProductStatus? {
            switch self {
            case .all: nil
            case .draft: .draft
            case .submitted: .submitted
            case .approved: .approved
            case .rejected: .rejected
            }
        }
    }

    init(store: CatalogStore? = nil) {
        let path = UserDefaults.standard.string(forKey: "catalogRoot") ?? "~/KarpatiaCatalog"
        let resolved = store ?? CatalogStore(path: path)
        self.store = resolved
        try? resolved.ensureLayout()
        reload()
    }

    var selected: CatalogProduct? {
        guard let selection else { return nil }
        return products.first { $0.id == selection }
    }

    var filtered: [CatalogProduct] {
        products.filter { product in
            if let status = filter.status, product.status != status { return false }
            guard !search.isEmpty else { return true }
            let needle = search.lowercased()
            return product.name.lowercased().contains(needle)
                || product.sku.lowercased().contains(needle)
                || (store.manufacturer(product.manufacturerID)?.name.lowercased().contains(needle) ?? false)
        }
    }

    func reload() {
        products = store.products()
        manufacturers = store.manufacturers()
        if selection == nil || !products.contains(where: { $0.id == selection }) {
            selection = filtered.first?.id
        }
        try? store.rebuildLibrary()
    }

    func manufacturerName(_ id: String) -> String {
        store.manufacturer(id)?.name ?? id
    }

    func logoURL(_ id: String) -> URL? {
        guard let manufacturer = store.manufacturer(id) else { return nil }
        return store.logoURL(manufacturer)
    }

    func thumbnailURL(_ product: CatalogProduct) -> URL? {
        guard let thumb = product.thumbnail else { return nil }
        let url = store.productDir(product.id).appendingPathComponent(thumb)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func review(_ product: CatalogProduct) -> ReviewReport {
        CatalogWorkflow.review(product,
                               manufacturer: store.manufacturer(product.manufacturerID),
                               hasThumbnail: store.hasThumbnail(product.id))
    }

    // MARK: - import (drag & drop)

    func beginImport(_ urls: [URL]) {
        let models = urls.filter { MeshFormat.detect($0) != nil }
        guard !models.isEmpty else {
            statusLine = "To nie jest model 3D (obsługiwane: GLB, OBJ, STL)"
            return
        }
        pendingImport = models
        showImportSheet = true
    }

    /// Dodaje produkt z pliku: konwersja → wymiary → miniatura → wpis w katalogu.
    func importModel(at url: URL, name: String, sku: String,
                     manufacturerID: String, category: ProductCategory, costGrosze: Int) {
        let id = slug("\(manufacturerID)-\(sku)")
        if store.product(id) != nil {
            statusLine = "Produkt \(id) już istnieje"
            return
        }
        var product = CatalogProduct(id: id, sku: sku, name: name,
                                     manufacturerID: manufacturerID, category: category)
        do {
            let mesh = try MeshIO.load(url: url)
            let dir = store.assetsDir(id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = dir.appendingPathComponent("model.glb")
            if url.pathExtension.lowercased() == "glb" {
                try FileManager.default.copyItem(at: url, to: target)
            } else {
                let glb = try MeshIO.writeGLB(mesh)
                try glb.write(to: target)
            }
            let data = try Data(contentsOf: target)
            product.assets = [AssetFile(path: "assets/model.glb", kind: .model,
                                        bytes: data.count, sha256: SHA256Hex.hash(data))]
            if let bounds = mesh.bounds {
                let mm = bounds.sizeMM
                product.width = (mm.width * 10).rounded() / 10
                product.depth = (mm.depth * 10).rounded() / 10
                product.height = (mm.height * 10).rounded() / 10
            }
            product.pricing = Pricing(costGrosze: costGrosze, marginPercent: 0)
            product.dependencies = DependencyLibrary.defaultRules(for: category)
            try store.save(product)
            try ThumbnailRenderer.renderThumbnail(for: &product, store: store)
            try store.save(product)
            store.audit("dodano produkt \(id) z pliku \(url.lastPathComponent)", by: "katalog-app")
            statusLine = "Dodano \(name) — \(Int(product.width)) × \(Int(product.depth)) × \(Int(product.height)) mm"
            reload()
            selection = id
        } catch {
            statusLine = "Błąd importu: \(error)"
        }
    }

    // MARK: - edycja

    func save(_ product: CatalogProduct) {
        do {
            try store.save(product)
            store.audit("zapisano zmiany \(product.id)", by: "katalog-app")
            reload()
        } catch {
            statusLine = "Nie zapisano: \(error)"
        }
    }

    func submit(_ product: CatalogProduct) {
        var copy = product
        do {
            try CatalogWorkflow.submit(&copy)
            try store.save(copy)
            store.audit("produkt \(product.id) zgłoszony", by: "katalog-app")
            statusLine = "Zgłoszony do zatwierdzenia"
            reload()
        } catch {
            statusLine = "Błąd: \(error)"
        }
    }

    func approve(_ product: CatalogProduct, margin: Double) {
        var copy = product
        do {
            try CatalogWorkflow.approve(&copy,
                                        manufacturer: store.manufacturer(product.manufacturerID),
                                        hasThumbnail: store.hasThumbnail(product.id),
                                        by: NSFullUserName(),
                                        marginPercent: margin)
            try store.save(copy)
            store.audit("zatwierdzono \(product.id) z marżą \(margin)%", by: NSFullUserName())
            try store.rebuildLibrary()
            statusLine = "W bibliotece: \(copy.name) — \(copy.pricing.retailText)"
            reload()
        } catch {
            statusLine = "Nie można zatwierdzić: \(error)"
        }
    }

    func reject(_ product: CatalogProduct, reason: String) {
        var copy = product
        do {
            try CatalogWorkflow.reject(&copy, by: NSFullUserName(), reason: reason)
            try store.save(copy)
            store.audit("odrzucono \(product.id): \(reason)", by: NSFullUserName())
            statusLine = "Odrzucony"
            reload()
        } catch {
            statusLine = "Błąd: \(error)"
        }
    }

    func makeThumbnail(_ product: CatalogProduct) {
        var copy = product
        do {
            try ThumbnailRenderer.renderThumbnail(for: &copy, store: store)
            try store.save(copy)
            statusLine = "Miniatura odświeżona"
            reload()
        } catch {
            statusLine = "Miniatura nie powstała: \(error)"
        }
    }

    // MARK: - producenci

    func addManufacturer(name: String, logo: URL?, trademarkApproved: Bool) {
        let id = slug(name)
        var manufacturer = Manufacturer(id: id, name: name, trademarkApproved: trademarkApproved)
        if let logo {
            let destination = store.manufacturersDir.appendingPathComponent(logo.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try? FileManager.default.copyItem(at: logo, to: destination)
            manufacturer.logoFile = logo.lastPathComponent
        }
        try? store.save(manufacturer)
        store.audit("dodano producenta \(id)", by: NSFullUserName())
        reload()
    }

    // MARK: - pomoc

    func slug(_ text: String) -> String {
        let map = ["ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
                   "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"]
        var out = text
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        let allowed = out.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }

    func statusColor(_ status: ProductStatus) -> Color {
        switch status {
        case .draft: Color(red: 0.55, green: 0.58, blue: 0.64)
        case .submitted: Color(red: 0.85, green: 0.63, blue: 0.23)
        case .approved: Color(red: 0.25, green: 0.70, blue: 0.50)
        case .rejected: Color(red: 0.85, green: 0.33, blue: 0.31)
        }
    }
}
