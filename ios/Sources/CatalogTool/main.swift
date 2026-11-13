import Foundation
import CatalogCore
import SceneKit
import AppKit

// MARK: - pomocnicze

let arguments = Array(CommandLine.arguments.dropFirst())

func value(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.count > index + 1 else { return nil }
    return arguments[index + 1]
}

func flag(_ name: String) -> Bool { arguments.contains(name) }

/// Pierwszy argument pozycyjny (identyfikator produktu) — pomija flagi i ich wartości.
func positionalID() -> String? {
    var index = 1                                   // arguments[0] to komenda
    let flagsWithValue: Set<String> = ["--root", "--margin", "--by", "--note", "--reason",
                                       "--status", "--out", "--id", "--name", "--file", "--sku",
                                       "--mfr", "--category", "--cost", "--basis", "--risk",
                                       "--provenance", "--ref", "--tags", "--logo", "--site"]
    while index < arguments.count {
        let arg = arguments[index]
        if arg.hasPrefix("--") {
            if flagsWithValue.contains(arg), index + 1 < arguments.count { index += 2 } else { index += 1 }
            continue
        }
        return arg
    }
    return nil
}

func requireRoot() -> CatalogStore {
    guard let root = value("--root") else {
        print("Błąd: podaj --root <katalog katalogu>")
        exit(2)
    }
    let store = CatalogStore(path: root)
    try? store.ensureLayout()
    return store
}

func sizeText(_ bytes: Int) -> String {
    bytes >= 1024 ? "\(bytes / 1024) kB" : "\(bytes) B"
}

func money(_ produkt: CatalogProduct) -> String {
    "zakup \(produkt.pricing.costText) → detal \(produkt.pricing.retailText) (marża \(String(format: "%.1f", produkt.pricing.marginPercent))%)"
}

func slug(_ text: String) -> String {
    let map = ["ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
               "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"]
    var out = text
    for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
    let allowed = out.lowercased().map { ch -> Character in
        ch.isLetter || ch.isNumber ? ch : "-"
    }
    return String(allowed).split(separator: "-").joined(separator: "-")
}

// MARK: - miniatura (SceneKit, offscreen)

func renderThumbnail(mesh: TriMesh, to url: URL, size: CGFloat = 512, background: NSColor = .clear) throws {
    let scene = SCNScene()
    scene.background.contents = background

    var vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
    let indices = mesh.indices.map { Int32($0) }
    let geometry = SCNGeometry(
        sources: [SCNGeometrySource(vertices: vertices)],
        elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
    )

    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = NSColor(calibratedWhite: 0.82, alpha: 1)
    material.metalness.contents = 0.15
    material.roughness.contents = 0.55
    material.isDoubleSided = true
    geometry.materials = [material]

    let node = SCNNode(geometry: geometry)
    scene.rootNode.addChildNode(node)

    // obrys → kadr kamery
    let b = mesh.bounds!
    let center = SCNVector3(b.center.x, b.center.y, b.center.z)
    let maxDim = max(b.size.x, max(b.size.y, b.size.z))
    node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)

    let camera = SCNCamera()
    camera.fieldOfView = 40
    camera.zNear = 0.01
    camera.zFar = 100
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    let distance = maxDim * 2.1
    cameraNode.position = SCNVector3(distance * 0.72, distance * 0.55, distance * 0.9)
    cameraNode.look(at: SCNVector3Zero, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    scene.rootNode.addChildNode(cameraNode)

    // światła: główne + wypełniające
    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.intensity = 900
    key.eulerAngles = SCNVector3(-0.9, 0.7, 0)
    scene.rootNode.addChildNode(key)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light?.type = .directional
    fill.light?.intensity = 380
    fill.eulerAngles = SCNVector3(-0.4, -1.9, 0)
    scene.rootNode.addChildNode(fill)

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 260
    scene.rootNode.addChildNode(ambient)

    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size),
                                  antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw MeshError.corrupt("nie udało się wyrenderować miniatury")
    }
    try png.write(to: url)
}

// MARK: - komendy

func printProduct(_ product: CatalogProduct, store: CatalogStore) {
    let manufacturer = store.manufacturer(product.manufacturerID)
    print("""
    \(product.name)  [\(product.status.label)]
      id:        \(product.id)
      SKU:       \(product.sku)
      producent: \(manufacturer?.name ?? product.manufacturerID)  (logo: \(manufacturer?.logoFile ?? "brak"))
      kategoria: \(product.category.label)
      wymiary:   \(Int(product.width)) × \(Int(product.depth)) × \(Int(product.height)) mm
      ceny:      \(money(product))
      prawo:     \(product.legal.basis.label), ryzyko wzoru: \(product.legal.designRisk.label)
      pochodzenie: \(product.legal.provenance?.document ?? "BRAK")
      miniaturka: \(product.thumbnail ?? "brak")
      zasoby:    \(product.assets.map { "\($0.path) (\(sizeText($0.bytes)))" }.joined(separator: ", "))
      zależności: \(product.dependencies.count)
    """)
    for rule in product.dependencies {
        print("      · \(rule.title)\(rule.hard ? "  [twarda]" : "  [miękka]")")
    }
    if let decision = product.decision {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print("      decyzja: \(decision.by), \(formatter.string(from: decision.at)) — \(decision.reason)")
    }
}

func createThumbnailIfPossible(store: CatalogStore, product: inout CatalogProduct) {
    guard let asset = product.modelAsset else {
        print("Brak modelu — nie ma z czego zrobić miniatury")
        return
    }
    let url = store.assetURL(product, asset: asset)
    do {
        let mesh = try MeshIO.load(url: url)
        let saved = url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("thumb.png")
        try renderThumbnail(mesh: mesh, to: saved)
        product.thumbnail = "thumb.png"
        try store.save(product)
        print("Miniatura: \(saved.path)")
    } catch {
        print("Miniatura nie powstała: \(error)")
    }
}

// MARK: - dyspozycja

guard let command = arguments.first else {
    print("""
    Karpatia Catalog — moduł katalogu produktów (samodzielny)

    Użycie:
      CatalogTool init        --root <dir>
      CatalogTool mfr add     --root <dir> --id <id> --name "Nazwa" [--logo plik.png] [--trademark]
      CatalogTool mfr list    --root <dir>

      CatalogTool add         --root <dir> --sku SKU --name "Nazwa" --mfr <id> --category sink
                              --file model.glb [--cost 24000] [--margin 30]
                              [--basis ownGeometryFromDocs|manufacturerSupplied|licensedAsset]
                              [--risk low|medium|high] [--provenance "karta PDF"] [--ref "URL"]
                              [--tags "zlew,stal"] [--thumb]
      CatalogTool thumb       --root <dir> <id>
      CatalogTool review      --root <dir> <id>
      CatalogTool submit      --root <dir> <id>
      CatalogTool approve     --root <dir> <id> --margin 35 [--by "RC"] [--note "..."]
      CatalogTool reject      --root <dir> <id> --reason "..." [--by "RC"]
      CatalogTool list        --root <dir> [--status approved]
      CatalogTool show        --root <dir> <id>
      CatalogTool explain     --root <dir> <id>
      CatalogTool library     --root <dir>
      CatalogTool tiles       --root <dir> --out katalog.html
      CatalogTool audit       --root <dir>
    """)
    exit(0)
}

switch command {
case "init":
    let store = requireRoot()
    try store.ensureLayout()
    store.audit("utworzono katalog w \(store.root.path)")
    print("Katalog utworzony: \(store.root.path)")

case "mfr":
    let sub = arguments.count > 1 ? arguments[1] : ""
    let store = requireRoot()
    switch sub {
    case "add":
        guard let id = value("--id"), let name = value("--name") else {
            print("Błąd: --id i --name są wymagane"); exit(2)
        }
        var manufacturer = Manufacturer(id: id, name: name,
                                        website: value("--site"),
                                        trademarkApproved: flag("--trademark"))
        if let logoPath = value("--logo") {
            let source = URL(fileURLWithPath: (logoPath as NSString).expandingTildeInPath)
            let destination = store.manufacturersDir.appendingPathComponent(source.lastPathComponent)
            try? FileManager.default.copyItem(at: source, to: destination)
            manufacturer.logoFile = source.lastPathComponent
        }
        try store.save(manufacturer)
        store.audit("dodano producenta \(id) (znak: \(manufacturer.trademarkApproved ? "zgoda" : "brak zgody"))")
        print("Producent: \(name) [\(id)]")
    case "list":
        for manufacturer in store.manufacturers() {
            print("\(manufacturer.id)\t\(manufacturer.name)\tlogo: \(manufacturer.logoFile ?? "brak")\tznak: \(manufacturer.trademarkApproved ? "zgoda" : "BRAK")")
        }
    default:
        print("Nieznana podkomenda mfr: \(sub)")
    }

case "add":
    let store = requireRoot()
    guard let sku = value("--sku"), let name = value("--name"),
          let mfrID = value("--mfr"), let categoryRaw = value("--category"),
          let category = ProductCategory(rawValue: categoryRaw),
          let filePath = value("--file") else {
        print("Błąd: --sku --name --mfr --category --file są wymagane"); exit(2)
    }
    guard store.manufacturer(mfrID) != nil else {
        print(CatalogError.missingManufacturer(mfrID).description); exit(1)
    }
    let id = slug("\(mfrID)-\(sku)")
    if store.product(id) != nil {
        print(CatalogError.productExists(id).description); exit(1)
    }
    let source = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
    var product = CatalogProduct(id: id, sku: sku, name: name, manufacturerID: mfrID, category: category)

    // konwersja: OBJ/STL → GLB, GLB kopiujemy bez zmian
    do {
        let mesh = try MeshIO.load(url: source)
        let targetName = "model.glb"
        if source.pathExtension.lowercased() == "glb" {
            product.assets.append(try store.importAsset(from: source, productID: id, kind: .model, fileName: targetName))
        } else {
            let glb = try MeshIO.writeGLB(mesh)
            let dir = store.assetsDir(id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent(targetName)
            try glb.write(to: destination)
            product.assets.append(AssetFile(path: "assets/\(targetName)", kind: .model,
                                            bytes: glb.count, sha256: SHA256Hex.hash(glb)))
            print("Skonwertowano \(source.pathExtension.uppercased()) → GLB (\(mesh.triangleCount) trójkątów)")
        }
        if let bounds = mesh.bounds {
            let mm = bounds.sizeMM
            product.width = (mm.width * 10).rounded() / 10
            product.depth = (mm.depth * 10).rounded() / 10
            product.height = (mm.height * 10).rounded() / 10
            print(String(format: "Wymiary z modelu: %.0f × %.0f × %.0f mm", product.width, product.depth, product.height))
        }
    } catch {
        print("Błąd modelu: \(error)"); exit(1)
    }

    if let cost = value("--cost"), let grosze = Int(cost) {
        product.pricing.costGrosze = grosze
    }
    if let margin = value("--margin"), let m = Double(margin) {
        product.pricing.marginPercent = m
    }
    if let basisRaw = value("--basis"), let basis = LegalBasis(rawValue: basisRaw) {
        product.legal.basis = basis
    }
    if let riskRaw = value("--risk"), let risk = DesignRisk(rawValue: riskRaw) {
        product.legal.designRisk = risk
    }
    if let provenance = value("--provenance") {
        product.legal.provenance = Provenance(document: provenance, reference: value("--ref") ?? "")
    }
    if let tags = value("--tags") {
        product.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    product.dependencies = DependencyLibrary.defaultRules(for: category)

    try store.save(product)
    store.audit("dodano produkt \(id) (\(name))")
    if flag("--thumb") { createThumbnailIfPossible(store: store, product: &product) }
    printProduct(product, store: store)

case "thumb":
    let store = requireRoot()
    guard let id = positionalID(), var product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    createThumbnailIfPossible(store: store, product: &product)

case "submit":
    let store = requireRoot()
    guard let id = positionalID(), var product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    do {
        try CatalogWorkflow.submit(&product)
        try store.save(product)
        store.audit("produkt \(id) zgłoszony do zatwierdzenia", by: value("--by") ?? "producent")
        print("Zgłoszony: \(product.name) — czeka na marżę i kontrolę prawną")
    } catch {
        print("Błąd: \(error)"); exit(1)
    }

case "review":
    let store = requireRoot()
    guard let id = positionalID(), let product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    let report = CatalogWorkflow.review(product,
                                        manufacturer: store.manufacturer(product.manufacturerID),
                                        hasThumbnail: store.hasThumbnail(id))
    print("Kontrola \(product.name): \(report.summary)")
    for blocker in report.blockers {
        print("  \(blocker.severity == .blocking ? "✗" : "!") [\(blocker.code)] \(blocker.message)")
    }

case "approve":
    let store = requireRoot()
    guard let id = positionalID(), var product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    guard let marginText = value("--margin"), let margin = Double(marginText) else {
        print("Błąd: --margin jest wymagane (np. --margin 35)"); exit(2)
    }
    do {
        try CatalogWorkflow.approve(&product,
                                    manufacturer: store.manufacturer(product.manufacturerID),
                                    hasThumbnail: store.hasThumbnail(id),
                                    by: value("--by") ?? "katalog",
                                    marginPercent: margin,
                                    note: value("--note") ?? "")
        try store.save(product)
        store.audit("zatwierdzono \(id) z marżą \(margin)%", by: value("--by") ?? "katalog")
        try store.rebuildLibrary()
        print("Zatwierdzony i w bibliotece: \(product.name) — \(money(product))")
    } catch {
        print("Błąd: \(error)"); exit(1)
    }

case "reject":
    let store = requireRoot()
    guard let id = positionalID(), var product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    guard let reason = value("--reason") else {
        print("Błąd: --reason jest wymagane"); exit(2)
    }
    do {
        try CatalogWorkflow.reject(&product, by: value("--by") ?? "katalog", reason: reason)
        try store.save(product)
        store.audit("odrzucono \(id): \(reason)", by: value("--by") ?? "katalog")
        print("Odrzucony: \(product.name) — \(reason)")
    } catch {
        print("Błąd: \(error)"); exit(1)
    }

case "list":
    let store = requireRoot()
    let filter = value("--status").flatMap(ProductStatus.init(rawValue:))
    let items = store.products().filter { filter == nil || $0.status == filter }
    if items.isEmpty { print("Brak produktów") }
    for product in items {
        let manufacturer = store.manufacturer(product.manufacturerID)
        print("\(product.status.label.padding(toLength: 16, withPad: " ", startingAt: 0)) \(product.name)  ·  \(manufacturer?.name ?? "?")  ·  \(money(product))")
    }

case "show":
    let store = requireRoot()
    guard let id = positionalID(), let product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    printProduct(product, store: store)

case "explain":
    let store = requireRoot()
    guard let id = positionalID(), let product = store.product(id) else {
        print("Brak produktu"); exit(1)
    }
    // pokazujemy efekt na typowej zabudowie: szafki 600/450 dolne, blat, płyta
    let placed: [PlacedItem] = [
        PlacedItem(id: "cab-600", category: .cabinet, width: 600, level: .base),
        PlacedItem(id: "cab-450", category: .cabinet, width: 450, level: .base),
        PlacedItem(id: "worktop", category: .worktop, width: 2400),
        PlacedItem(id: "hob", category: .hob, width: 560),
        PlacedItem(id: "hood", category: .hood, width: 600),
    ]
    let effects = DependencyEngine.resolve(product: product, placed: placed)
    print("Opis zależności: \(product.name)")
    for resolved in effects {
        print("  → \(resolved.targetName): \(resolved.effect.shortLabel)")
        print("      \(resolved.explanation)\(resolved.hard ? "" : "  (miękka)")")
    }
    if effects.isEmpty { print("  (brak efektów na tej zabudowie)") }

case "library":
    let store = requireRoot()
    let index = try store.rebuildLibrary()
    print("Biblioteka oficjalna: \(index.entries.count) produktów → \(store.libraryURL.path)")
    for entry in index.entries {
        print("  \(entry.name) · \(entry.manufacturerName) · logo: \(entry.logoPath ?? "brak") · \(entry.retailText)")
    }

case "audit":
    let store = requireRoot()
    for line in store.auditLines(limit: 40) { print(line) }

case "tiles":
    let store = requireRoot()
    guard let out = value("--out") else { print("Błąd: --out plik.html"); exit(2) }
    let index = try store.rebuildLibrary()
    var html = """
    <!doctype html><html lang="pl"><head><meta charset="utf-8">
    <title>Biblioteka Karpatia</title>
    <style>
    body{background:#0e141f;color:#e7ebf2;font-family:-apple-system,Inter,sans-serif;margin:0;padding:28px}
    h1{font-size:22px;font-weight:600;margin:0 0 4px}
    .sub{color:#8d99ad;font-size:13px;margin-bottom:22px}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:18px}
    .tile{background:#161f2e;border:1px solid #243146;border-radius:16px;overflow:hidden}
    .thumb{height:190px;display:flex;align-items:center;justify-content:center;
           background:radial-gradient(circle at 50% 35%,#233047,#121a26)}
    .thumb img{max-width:86%;max-height:86%}
    .body{padding:12px 14px 14px}
    .mfr{display:flex;align-items:center;gap:8px;margin-bottom:8px;min-height:22px}
    .mfr img{height:18px;max-width:92px;object-fit:contain;opacity:.9}
    .mfr span{font-size:10.5px;letter-spacing:.04em;text-transform:uppercase;color:#8d99ad}
    .name{font-size:14px;font-weight:600;line-height:1.28;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
    .price{display:flex;justify-content:space-between;gap:10px;margin-top:10px;font-size:11px;color:#8d99ad;white-space:nowrap}
    .price b{color:#e7ebf2;font-weight:600}
    .deps{margin-top:8px;font-size:10.5px;color:#5b8def;line-height:1.35}
    </style></head><body>
    <h1>Biblioteka oficjalna</h1>
    <div class="sub">\(index.entries.count) produktów · miniaturka modelu, logo producenta, nazwa — zatwierdzone prawnie</div>
    <div class="grid">
    """
    let base = store.root
    for entry in index.entries {
        let thumb: String
        if let path = entry.thumbnailPath, let product = store.product(entry.id) {
            thumb = "file://" + store.productDir(product.id).appendingPathComponent(path).path
        } else { thumb = "" }
        let logo: String
        if let logoFile = entry.logoPath {
            logo = "file://" + store.manufacturersDir.appendingPathComponent(logoFile).path
        } else { logo = "" }
        let deps = entry.dependencies.map { $0.effects.map { $0.shortLabel }.joined(separator: " · ") }.joined(separator: " / ")
        html += """
        <div class="tile">
          <div class="thumb">\(thumb.isEmpty ? "" : "<img src=\"\(thumb)\" alt=\"\">")</div>
          <div class="body">
            <div class="mfr">\(logo.isEmpty ? "" : "<img src=\"\(logo)\" alt=\"\">")<span>\(entry.manufacturerName)</span></div>
            <div class="name">\(entry.name)</div>
            <div class="price"><span>zakup <b>\(entry.costText)</b></span><span>detal <b>\(entry.retailText)</b></span></div>
            \(deps.isEmpty ? "" : "<div class=\"deps\">\(deps)</div>")
          </div>
        </div>
        """
    }
    html += "</div></body></html>"
    try html.write(toFile: out, atomically: true, encoding: .utf8)
    _ = base
    print("Kafelki: \(out)")

default:
    print("Nieznana komenda: \(command)")
    exit(2)
}
