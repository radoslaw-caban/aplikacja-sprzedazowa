import Foundation
import AppKit
import CatalogCore

/// Test dymny aplikacji: te same ścieżki, które uruchamia GUI
/// (import modelu → zgłoszenie → zatwierdzenie z marżą → biblioteka).
/// Uruchamiane jako `CatalogApp --selftest`.
@MainActor
enum SelfTest {
    static func run() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-selftest-\(UUID().uuidString)")
        let store = CatalogStore(root: root)
        try? store.ensureLayout()
        let model = CatalogViewModel(store: store)

        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            print(condition ? "  ✓ \(name)" : "  ✗ \(name) \(detail)")
            if !condition { failures += 1 }
        }

        print("Katalog: \(root.path)")
        model.addManufacturer(name: "DEANTE", logo: nil, trademarkApproved: true)
        check("producent dodany", model.manufacturers.count == 1)

        let sample = URL(fileURLWithPath: "/tmp/catdemo/sink.obj")
        guard FileManager.default.fileExists(atPath: sample.path) else {
            print("  ! brak pliku demo /tmp/catdemo/sink.obj — pomijam import")
            print(failures == 0 ? "OK" : "NIEPOWODZENIE: \(failures)")
            exit(failures == 0 ? 0 : 1)
        }

        model.importModel(at: sample, name: "Zlew testowy", sku: "TEST1",
                          manufacturerID: "deante", category: .sink, costGrosze: 32_000)
        check("produkt zaimportowany", model.products.count == 1, model.statusLine)
        guard let created = model.products.first else {
            print("NIEPOWODZENIE: brak produktu")
            exit(1)
        }
        check("wymiary z geometrii", abs(created.width - 560) < 2 && abs(created.depth - 500) < 2,
              "\(created.width)×\(created.depth)×\(created.height)")
        check("miniatura powstała", model.thumbnailURL(created) != nil)
        check("zależności domyślne", !created.dependencies.isEmpty)

        // zatwierdzenie bez dokumentu pochodzenia musi się nie udać
        model.submit(created)
        guard let submitted = model.products.first else { exit(1) }
        check("zgłoszony", submitted.status == .submitted)
        model.approve(submitted, margin: 35)
        let afterBad = model.products.first
        check("bez pochodzenia nie zatwierdzono", afterBad?.status != .approved, model.statusLine)

        // uzupełniamy legalność i zatwierdzamy
        var legal = afterBad ?? submitted
        legal.legal.basis = .ownGeometryFromDocs
        legal.legal.provenance = Provenance(document: "Karta testowa", reference: "file:///test.pdf")
        model.save(legal)
        guard let ready = model.products.first else { exit(1) }
        model.approve(ready, margin: 35)
        let approved = model.products.first
        check("zatwierdzony z marżą", approved?.status == .approved, model.statusLine)
        check("detal policzony", approved?.pricing.retailGrosze == 43_200,
              approved.map { "\($0.pricing.retailGrosze) gr" } ?? "brak")

        let index = (try? store.rebuildLibrary())
        check("w bibliotece oficjalnej", index?.entries.count == 1)

        print(failures == 0 ? "\nOK — aplikacja przechodzi ścieżkę produktu" : "\nNIEPOWODZENIE: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
