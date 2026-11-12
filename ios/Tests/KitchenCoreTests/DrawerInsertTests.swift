import XCTest
@testable import KitchenCore

final class DrawerInsertTests: XCTestCase {

    func testInnerDimensionsFollowLegrabox() {
        XCTAssertEqual(DrawerInsertCatalog.innerWidth(cabinetWidth: 600), 558, accuracy: 0.5)
        XCTAssertEqual(DrawerInsertCatalog.innerDepth(cabinetDepth: 560), 500, accuracy: 0.5)
        XCTAssertEqual(DrawerInsertCatalog.innerHeight(drawerFrontHeight: 128.5), 116.5, accuracy: 0.5)
        XCTAssertEqual(DrawerInsertCatalog.innerHeight(drawerFrontHeight: 66.5), 54.5, accuracy: 0.5)
    }

    func testCatalogHasUniqueIDsAndRealisticSizes() {
        let ids = DrawerInsertCatalog.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "identyfikatory wkładów muszą być unikalne")
        for insert in DrawerInsertCatalog.all {
            XCTAssertGreaterThanOrEqual(insert.height, 0)
            if insert.width > 0 { XCTAssertLessThanOrEqual(insert.width, 558, "\(insert.id) szerszy niż szafka 600") }
        }
    }

    /// Wszystkie rodzaje z zadania są w katalogu.
    func testCatalogCoversRequestedKinds() {
        let kinds = Set(DrawerInsertCatalog.all.map { $0.kind })
        for required: DrawerInsertKind in [.mat, .plateRack, .cupOrganizer, .glassOrganizer,
                                           .bakingTrayHolder, .jarHolder, .cutleryTray] {
            XCTAssertTrue(kinds.contains(required), "brak wkładu typu \(required.rawValue)")
        }
    }

    func testAvailabilityDependsOnDrawerHeight() {
        let shallow = DrawerInsertCatalog.available(cabinetWidth: 600, cabinetDepth: 560, drawerFrontHeight: 66.5)
        XCTAssertTrue(shallow.allSatisfy { $0.height <= 54.5 }, "w szufladzie N nie może być wysokiego wkładu")
        XCTAssertFalse(shallow.contains { $0.kind == .plateRack })

        let deep = DrawerInsertCatalog.available(cabinetWidth: 600, cabinetDepth: 560, drawerFrontHeight: 128.5)
        XCTAssertTrue(deep.contains { $0.kind == .plateRack }, "w szufladzie K stojak na talerze ma się mieścić")
        XCTAssertTrue(deep.contains { $0.kind == .cupOrganizer })
    }

    func testMatIsCutToSize() {
        let mat = DrawerInsertCatalog.insert(id: "mat-450")
        XCTAssertNotNil(mat)
        XCTAssertEqual(mat!.fittedWidth(innerWidth: 558), 558, accuracy: 0.5)
        XCTAssertEqual(mat!.fittedDepth(innerDepth: 500), 500, accuracy: 0.5)
        XCTAssertTrue(mat!.fits(innerWidth: 180, innerDepth: 200, innerHeight: 10))
    }

    func testTooWideInsertDoesNotFitNarrowCabinet() {
        let cutlery = DrawerInsertCatalog.insert(id: "cutlery-400")!
        XCTAssertTrue(cutlery.fits(innerWidth: 558, innerDepth: 500, innerHeight: 78))
        XCTAssertFalse(cutlery.fits(innerWidth: 358, innerDepth: 500, innerHeight: 78), "400 mm nie wejdzie w szafkę 400")
    }

    func testSuggestionFollowsStorage() {
        let plates = DrawerInsertCatalog.suggested(for: .plates, cabinetWidth: 600,
                                                   cabinetDepth: 560, drawerFrontHeight: 128.5)
        XCTAssertEqual(plates?.kind, .plateRack)

        let cutlery = DrawerInsertCatalog.suggested(for: .cutlery, cabinetWidth: 600,
                                                    cabinetDepth: 560, drawerFrontHeight: 90.5)
        XCTAssertEqual(cutlery?.kind, .cutleryTray)

        XCTAssertNil(DrawerInsertCatalog.suggested(for: nil, cabinetWidth: 600,
                                                   cabinetDepth: 560, drawerFrontHeight: 90.5))
    }
}
