import XCTest
@testable import KitchenCore

/// Kolizje i interakcje obiektów piaskownicy.
///
/// Te testy istnieją, bo kolizja „na oko" zawsze wygląda dobrze do pierwszego
/// obiektu postawionego pod kątem. Sprawdzają rzeczy, które łatwo zepsuć:
/// obrót, skalę, styk krawędziami i symetrię par.
final class SandboxPhysicsTests: XCTestCase {

    private func obj(_ kind: SandboxKind,
                     x: Double = 0, y: Double = 0, z: Double = 0,
                     rot: Double = 0, scale: Double = 1) -> SandboxObject {
        SandboxObject(
            kind: kind,
            position: SIMD3(x, y, z),
            rotationY: rot,
            scale: SIMD3(scale, scale, scale)
        )
    }

    // MARK: - bryły otaczające

    func testBoundsMatchDefaultSize() {
        let b = SandboxPhysics.bounds(of: obj(.boulder))
        // boulder: 1200 × 900 × 1100
        XCTAssertEqual(b.size.x, 1200, accuracy: 0.01)
        XCTAssertEqual(b.size.y, 900, accuracy: 0.01)
        XCTAssertEqual(b.size.z, 1100, accuracy: 0.01)
    }

    func testBoundsFollowPosition() {
        let b = SandboxPhysics.bounds(of: obj(.boulder, x: 5000, z: -3000))
        XCTAssertEqual(b.center.x, 5000, accuracy: 0.01)
        XCTAssertEqual(b.center.z, -3000, accuracy: 0.01)
    }

    func testRotationSwapsFootprint() {
        // Ławka 1500 × 500. Po obrocie o 45° rzut AABB to
        // X = (1500+500)·0,707 = 1414 i Z = 1414 — czyli X maleje,
        // a Z rośnie. Sprawdzamy więc sumę i oś Z, nie samą X.
        let flat = SandboxPhysics.bounds(of: obj(.bench, rot: 0))
        let turned = SandboxPhysics.bounds(of: obj(.bench, rot: 45))
        XCTAssertGreaterThan(turned.size.z, flat.size.z, "Z musi urosnąć przy obrocie")
        XCTAssertEqual(turned.size.x, turned.size.z, accuracy: 0.01,
                       "przy 45° rzut powinien być kwadratowy")
    }

    func testBoundsScaleWithScale() {
        let one = SandboxPhysics.bounds(of: obj(.tree))
        let two = SandboxPhysics.bounds(of: obj(.tree, scale: 2))
        XCTAssertEqual(two.size.x, one.size.x * 2, accuracy: 0.01)
        XCTAssertEqual(two.size.y, one.size.y * 2, accuracy: 0.01)
    }

    // MARK: - kolizja

    func testSamePositionCollides() {
        XCTAssertTrue(SandboxPhysics.collides(obj(.boulder), obj(.boulder)))
    }

    func testFarApartDoesNotCollide() {
        XCTAssertFalse(SandboxPhysics.collides(
            obj(.boulder, x: 0),
            obj(.boulder, x: 10_000)
        ))
    }

    func testSideBySideTouchingDoesNotCollide() {
        // boulder 1200 szeroki; drugi dokładnie przy krawędzi → styk, nie kolizja
        XCTAssertFalse(SandboxPhysics.collides(
            obj(.boulder, x: 0),
            obj(.boulder, x: 1200),
            tolerance: 1
        ))
    }

    func testOverlappingSideBySideCollides() {
        // 100 mm najazdu na siebie → kolizja
        XCTAssertTrue(SandboxPhysics.collides(
            obj(.boulder, x: 0),
            obj(.boulder, x: 1100),
            tolerance: 1
        ))
    }

    func testVerticalSeparationAvoidsCollision() {
        // jeden obiekt nad drugim, bez styku wysokości
        XCTAssertFalse(SandboxPhysics.collides(
            obj(.boulder, y: 0),
            obj(.boulder, y: 2000)
        ))
    }

    func testDifferentSizesRespectTheirOwnBounds() {
        // mała skałka 400×260×380 zmieści się obok dużego głazu
        let small = obj(.rockSmall, x: 1000)
        let big = obj(.boulder, x: 0)
        XCTAssertFalse(SandboxPhysics.collides(small, big, tolerance: 1))
    }

    // MARK: - najbliższe wolne miejsce

    func testFreeSpotReturnsSameWhenPlaceIsFree() {
        let candidate = obj(.bush, x: 0, z: 0)
        let moved = SandboxPhysics.nearestFreeSpot(for: candidate, in: [])
        XCTAssertEqual(moved?.position.x, 0)
        XCTAssertEqual(moved?.position.z, 0)
    }

    func testFreeSpotMovesWhenOccupied() {
        let occupied = [obj(.boulder, x: 0, z: 0)]
        let candidate = obj(.boulder, x: 0, z: 0)
        guard let moved = SandboxPhysics.nearestFreeSpot(for: candidate, in: occupied) else {
            return XCTFail("nie znalazł wolnego miejsca")
        }
        XCTAssertFalse(SandboxPhysics.collides(moved, occupied[0], tolerance: 1))
        // odsunięcie może pójść w X albo w Z — liczy się odległość, nie oś
        let shift = hypot(moved.position.x, moved.position.z)
        XCTAssertGreaterThan(shift, 0, "obiekt nie został odsunięty")
    }

    // MARK: - interakcje

    func testStoneOnStoneKnocks() {
        let r = SandboxPhysics.interaction(obj(.boulder), obj(.rockSmall))
        XCTAssertEqual(r, .knock(.stone))
    }

    func testStoneOnGlassShatters() {
        // okno traktujemy jako szkło — kamień w szybę tłucze
        let r = SandboxPhysics.interaction(obj(.boulder), obj(.windowFrame))
        XCTAssertEqual(r, .shatter(.crunch))
    }

    func testFoliageOnFoliageRustles() {
        let r = SandboxPhysics.interaction(obj(.tree), obj(.bush))
        XCTAssertEqual(r, .sound(.leaves))
    }

    func testInteractionIsSymmetric() {
        // kolejność argumentów nie może zmieniać wyniku
        let pairs: [(SandboxKind, SandboxKind)] = [
            (.boulder, .windowFrame),
            (.tree, .person),
            (.pipeRun, .bench),
            (.gravel, .foundation),
        ]
        for (a, b) in pairs {
            XCTAssertEqual(
                SandboxPhysics.interaction(obj(a), obj(b)),
                SandboxPhysics.interaction(obj(b), obj(a)),
                "para \(a) / \(b) nie jest symetryczna"
            )
        }
    }

    func testEveryPairHasSound() {
        // w kolizji nigdy nie ma ciszy — zawsze jest jakiś dźwięk
        for a in SandboxKind.allCases {
            for b in SandboxKind.allCases {
                let r = SandboxPhysics.interaction(obj(a), obj(b))
                XCTAssertNotNil(r.sound, "brak dźwięku dla \(a) / \(b)")
            }
        }
    }

    // MARK: - dotknięcie

    func testTapSoundFollowsMaterial() {
        XCTAssertEqual(SandboxPhysics.tapSound(.boulder), .stone)
        XCTAssertEqual(SandboxPhysics.tapSound(.tree), .rustle)
        XCTAssertEqual(SandboxPhysics.tapSound(.pipeRun), .metal)
        XCTAssertEqual(SandboxPhysics.tapSound(.gravel), .thud)
    }

    func testMaterialMappingIsSane() {
        XCTAssertEqual(SandboxPhysics.material(.windowFrame), .glass)
        XCTAssertEqual(SandboxPhysics.material(.hedge), .foliage)
        XCTAssertEqual(SandboxPhysics.material(.person), .creature)
        XCTAssertEqual(SandboxPhysics.material(.pavingTile), .stone)
        XCTAssertEqual(SandboxPhysics.material(.bench), .wood)
    }
}
