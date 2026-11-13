import XCTest
import simd
@testable import CatalogCore

final class CatalogWorkflowTests: XCTestCase {

    private func makeStore() throws -> CatalogStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-test-\(UUID().uuidString)")
        let store = CatalogStore(root: root)
        try store.ensureLayout()
        return store
    }

    private func makeManufacturer(trademark: Bool = true) -> Manufacturer {
        Manufacturer(id: "deante", name: "DEANTE", logoFile: "deante.png",
                     trademarkApproved: trademark)
    }

    private func makeSink(status: ProductStatus = .draft) -> CatalogProduct {
        var product = CatalogProduct(id: "deante-arnika", sku: "ARNIKA-2", name: "Zlew Arnikа 2",
                                     manufacturerID: "deante", category: .sink,
                                     width: 560, depth: 500, height: 160)
        product.assets = [AssetFile(path: "assets/model.glb", kind: .model, bytes: 1000)]
        product.thumbnail = "thumb.png"
        product.legal = LegalRecord(
            basis: .ownGeometryFromDocs,
            designRisk: .low,
            provenance: Provenance(document: "Karta DEANTE Arnika 2, 2026-03", reference: "file:///karty.pdf"),
            trademarkUseApproved: true
        )
        product.pricing = Pricing(costGrosze: 32_000, marginPercent: 0)
        product.status = status
        return product
    }

    // MARK: - marże

    func testRetailPriceIsCostPlusMargin() {
        let pricing = Pricing(costGrosze: 32_000, marginPercent: 35)
        XCTAssertEqual(pricing.retailGrosze, 43_200)                        // 320,00 → 432,00
        XCTAssertEqual(pricing.retailText, "432,00 PLN")
        XCTAssertEqual(Pricing(costGrosze: 9_999, marginPercent: 12.5).retailGrosze, 11_249)
    }

    // MARK: - legalność

    func testApprovalBlockedWithoutProvenance() {
        var product = makeSink(status: .submitted)
        product.legal.provenance = nil
        let report = CatalogWorkflow.review(product, manufacturer: makeManufacturer(), hasThumbnail: true)
        XCTAssertFalse(report.canApprove)
        XCTAssertTrue(report.blocking.contains { $0.code == "provenance" })
    }

    func testApprovalBlockedWithoutTrademarkPermission() {
        let product = makeSink(status: .submitted)
        let report = CatalogWorkflow.review(product, manufacturer: makeManufacturer(trademark: false),
                                            hasThumbnail: true)
        XCTAssertFalse(report.canApprove)
        XCTAssertTrue(report.blocking.contains { $0.code == "trademark" })
    }

    func testHighDesignRiskNeedsLegalNote() {
        var product = makeSink(status: .submitted)
        product.legal.designRisk = .high
        var report = CatalogWorkflow.review(product, manufacturer: makeManufacturer(), hasThumbnail: true)
        XCTAssertTrue(report.blocking.contains { $0.code == "design-risk" })

        product.legal.note = "Opinia prawna: bryła funkcjonalna, brak naruszenia wzoru (23.10.2026)"
        report = CatalogWorkflow.review(product, manufacturer: makeManufacturer(), hasThumbnail: true)
        XCTAssertFalse(report.blocking.contains { $0.code == "design-risk" })
    }

    func testUnknownLegalBasisBlocks() {
        var product = makeSink(status: .submitted)
        product.legal.basis = .unknown
        let report = CatalogWorkflow.review(product, manufacturer: makeManufacturer(), hasThumbnail: true)
        XCTAssertFalse(report.canApprove)
        XCTAssertTrue(report.blocking.contains { $0.code == "legal-basis" })
    }

    func testApproveRequiresSubscribedStatusAndMargin() throws {
        var draft = makeSink(status: .draft)
        XCTAssertThrowsError(try CatalogWorkflow.approve(&draft, manufacturer: makeManufacturer(),
                                                         hasThumbnail: true, by: "RC", marginPercent: 30))

        var submitted = makeSink(status: .submitted)
        XCTAssertThrowsError(try CatalogWorkflow.approve(&submitted, manufacturer: makeManufacturer(),
                                                         hasThumbnail: true, by: "RC", marginPercent: 120))

        try CatalogWorkflow.approve(&submitted, manufacturer: makeManufacturer(),
                                    hasThumbnail: true, by: "RC", marginPercent: 35)
        XCTAssertEqual(submitted.status, .approved)
        XCTAssertEqual(submitted.pricing.marginPercent, 35, accuracy: 0.001)
        XCTAssertEqual(submitted.pricing.retailGrosze, 43_200)
        XCTAssertEqual(submitted.decision?.by, "RC")
    }

    func testRejectRequiresReason() {
        var product = makeSink(status: .submitted)
        XCTAssertThrowsError(try CatalogWorkflow.reject(&product, by: "RC", reason: "  "))
        XCTAssertNoThrow(try CatalogWorkflow.reject(&product, by: "RC", reason: "Brak zgody na logo"))
        XCTAssertEqual(product.status, .rejected)
    }

    func testSubmitAddsDefaultDependencies() throws {
        var product = makeSink()
        XCTAssertTrue(product.dependencies.isEmpty)
        try CatalogWorkflow.submit(&product)
        XCTAssertEqual(product.status, .submitted)
        XCTAssertFalse(product.dependencies.isEmpty, "zlew musi dostać reguły produkcyjne")
    }

    // MARK: - katalog na dysku

    func testStoreRoundtripAndLibrary() throws {
        let store = try makeStore()
        try store.save(makeManufacturer())
        var product = makeSink(status: .submitted)
        try store.save(product)

        XCTAssertEqual(store.products().count, 1)
        XCTAssertEqual(store.manufacturer("deante")?.name, "DEANTE")

        try CatalogWorkflow.approve(&product, manufacturer: makeManufacturer(),
                                    hasThumbnail: true, by: "RC", marginPercent: 30)
        try store.save(product)
        let index = try store.rebuildLibrary()
        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries.first?.manufacturerName, "DEANTE")
        XCTAssertEqual(index.entries.first?.retailText, "416,00 PLN")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.libraryURL.path))
    }

    func testDraftProductsStayOutOfLibrary() throws {
        let store = try makeStore()
        try store.save(makeSink(status: .draft))
        let index = try store.rebuildLibrary()
        XCTAssertTrue(index.entries.isEmpty)
    }

    func testAuditLogIsAppendOnly() throws {
        let store = try makeStore()
        store.audit("pierwszy wpis", by: "RC")
        store.audit("drugi wpis", by: "RC")
        let lines = store.auditLines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("pierwszy wpis"))
        XCTAssertTrue(lines[1].contains("drugi wpis"))
    }
}

final class CatalogDependencyTests: XCTestCase {

    func testSinkTurnsCabinetIntoSinkCabinet() {
        var sink = CatalogProduct(id: "sink", sku: "S", name: "Zlew", manufacturerID: "m", category: .sink)
        sink.dependencies = DependencyLibrary.defaultRules(for: .sink)

        let cabinets = [
            PlacedItem(id: "cab-600", category: .cabinet, width: 600, level: .base),
            PlacedItem(id: "cab-450", category: .cabinet, width: 450, level: .base),
            PlacedItem(id: "wall-600", category: .cabinet, width: 600, level: .wall),
        ]
        let effects = DependencyEngine.resolve(product: sink, placed: cabinets, trigger: .onWorktop)
        let roles = effects.filter { $0.effect.kind == .setRole }
        XCTAssertEqual(roles.count, 2, "zlew działa na obie szafki dolne, nie na wiszącą")
        XCTAssertTrue(roles.allSatisfy { $0.effect.role == "zlewowa" })
        XCTAssertTrue(effects.contains { $0.effect.kind == .removeTopRail })

        let state = DependencyEngine.apply(products: [sink], to: cabinets)
        XCTAssertEqual(state.first { $0.id == "cab-600" }?.role, "zlewowa")
        XCTAssertEqual(state.first { $0.id == "wall-600" }?.role, "")
    }

    func testHobAddsWorktopCutout() {
        var hob = CatalogProduct(id: "hob", sku: "H", name: "Płyta", manufacturerID: "m", category: .hob)
        hob.dependencies = DependencyLibrary.defaultRules(for: .hob)
        let worktop = [PlacedItem(id: "wt", category: .worktop, width: 2400)]
        let effects = DependencyEngine.resolve(product: hob, placed: worktop)
        let cutout = effects.first { $0.effect.kind == .addWorktopCutout }
        XCTAssertNotNil(cutout)
        XCTAssertEqual(cutout?.effect.width, 560)
        XCTAssertEqual(cutout?.effect.depth, 490)
    }

    func testHoodKeepsDistanceAboveHob() {
        var hood = CatalogProduct(id: "hood", sku: "HD", name: "Okap", manufacturerID: "m", category: .hood)
        hood.dependencies = DependencyLibrary.defaultRules(for: .hood)
        let effects = DependencyEngine.resolve(product: hood,
                                               placed: [PlacedItem(id: "hob", category: .hob, width: 560)],
                                               trigger: .above)
        XCTAssertTrue(effects.contains { $0.effect.kind == .minDistance && $0.effect.distance == 650 })
        XCTAssertTrue(effects.contains { $0.effect.kind == .addVent })
    }

    func testSelectorRespectsWidthRangeAndLevel() {
        var product = CatalogProduct(id: "p", sku: "P", name: "Test", manufacturerID: "m", category: .accessory)
        product.dependencies = [
            DependencyRule(id: "narrow", trigger: .inRun,
                           target: DependencySelector(categories: [.cabinet], minWidth: 500, maxWidth: 700, level: .base),
                           effects: [DependencyEffect(kind: .noteOnly, text: "test")])
        ]
        let placed = [
            PlacedItem(id: "a", category: .cabinet, width: 600, level: .base),
            PlacedItem(id: "b", category: .cabinet, width: 450, level: .base),
            PlacedItem(id: "c", category: .cabinet, width: 600, level: .wall),
        ]
        let effects = DependencyEngine.resolve(product: product, placed: placed)
        XCTAssertEqual(effects.map { $0.targetID }, ["a"])
    }

    func testOvenReservesNicheAndNeedsAdjacentService() {
        var oven = CatalogProduct(id: "oven", sku: "O", name: "Piekarnik", manufacturerID: "m", category: .oven)
        oven.dependencies = DependencyLibrary.defaultRules(for: .oven)
        let effects = DependencyEngine.resolve(product: oven,
                                               placed: [PlacedItem(id: "tall", category: .cabinet, width: 600, level: .tall)],
                                               trigger: .inside)
        XCTAssertTrue(effects.contains { $0.effect.kind == .reserveNiche && $0.effect.width == 560 })
        XCTAssertTrue(effects.contains { $0.effect.kind == .requireServiceAdjacent })
    }
}

final class CatalogMeshTests: XCTestCase {

    /// Prostopadłościan jako siatka — do testów konwersji.
    private func cube(size: Float = 0.6) -> TriMesh {
        let s = size / 2
        let p: [SIMD3<Float>] = [
            [-s, -s, -s], [s, -s, -s], [s, s, -s], [-s, s, -s],
            [-s, -s, s], [s, -s, s], [s, s, s], [-s, s, s],
        ]
        let idx: [UInt32] = [
            0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
            0, 1, 5, 0, 5, 4, 3, 7, 6, 3, 6, 2,
            0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5,
        ]
        return TriMesh(positions: p, indices: idx)
    }

    func testBoundingBoxInMillimetres() {
        let mesh = TriMesh(positions: [SIMD3(0, 0, 0), SIMD3(0.56, 0.16, 0.5)],
                           indices: [0, 1, 1])
        let b = mesh.bounds!
        XCTAssertEqual(b.sizeMM.width, 560, accuracy: 1)
        XCTAssertEqual(b.sizeMM.height, 160, accuracy: 1)
        XCTAssertEqual(b.sizeMM.depth, 500, accuracy: 1)
    }

    func testGLBWritesAndReadsBack() throws {
        let mesh = cube()
        let data = try MeshIO.writeGLB(mesh)
        XCTAssertEqual(data.count % 4, 0, "GLB musi być wyrównane do 4 bajtów")
        let read = try MeshIO.readGLB(data)
        XCTAssertEqual(read.positions.count, mesh.positions.count)
        XCTAssertEqual(read.indices.count, mesh.indices.count)
        let b1 = mesh.bounds!, b2 = read.bounds!
        XCTAssertEqual(b2.size.x, b1.size.x, accuracy: 0.001)
    }

    func testOBJConversion() throws {
        let obj = """
        v 0 0 0
        v 0.6 0 0
        v 0.6 0.7 0
        v 0 0.7 0
        f 1 2 3 4
        """
        let mesh = try MeshIO.readOBJ(obj)
        XCTAssertEqual(mesh.triangleCount, 2, "czworokąt ma być potrojony na 2 trójkąty")
        XCTAssertEqual(mesh.bounds!.sizeMM.width, 600, accuracy: 1)
    }

    func testSTLBinaryConversion() throws {
        var data = Data(count: 80)                       // nagłówek
        var count = UInt32(1)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for _ in 0..<3 { data.append(contentsOf: [0, 0, 0, 0]) }   // normalna
        let vertices: [Float] = [0, 0, 0, 0.5, 0, 0, 0, 0.5, 0]
        for value in vertices {
            var v = value
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [0, 0])
        let mesh = try MeshIO.readSTL(data)
        XCTAssertEqual(mesh.triangleCount, 1)
        XCTAssertEqual(mesh.bounds!.sizeMM.width, 500, accuracy: 1)

        let glb = try MeshIO.writeGLB(mesh)
        XCTAssertEqual(try MeshIO.readGLB(glb).triangleCount, 1)
    }

    func testScalingToRealSize() {
        let mesh = cube(size: 1.0)              // 1 m sześcian
        let scaled = mesh.scaled(toLongestMM: 600)
        XCTAssertEqual(scaled.bounds!.sizeMM.width, 600, accuracy: 1)
    }

    func testSHA256KnownValue() {
        // znana wartość: sha256("abc")
        let digest = SHA256Hex.hash(Data("abc".utf8))
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
