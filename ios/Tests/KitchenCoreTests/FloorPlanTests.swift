import XCTest
import simd
@testable import KitchenCore

final class FloorPlanTests: XCTestCase {

    func testRectangleHasFourWallsWithRightLengths() {
        let plan = FloorPlan.rectangle(width: 12800, depth: 9600)
        XCTAssertEqual(plan.wallCount, 4)
        XCTAssertEqual(plan.wall(0)!.length, 12800, accuracy: 1e-6)
        XCTAssertEqual(plan.wall(1)!.length, 9600, accuracy: 1e-6)
        XCTAssertEqual(plan.wall(2)!.length, 12800, accuracy: 1e-6)
        XCTAssertEqual(plan.wall(3)!.length, 9600, accuracy: 1e-6)
        XCTAssertEqual(plan.perimeter, 44800, accuracy: 1e-6)
    }

    func testAreaFromShoelace() {
        let plan = FloorPlan.rectangle(width: 12800, depth: 9600)
        XCTAssertEqual(plan.area, 12800 * 9600, accuracy: 1)
        XCTAssertEqual(plan.areaM2, 122.88, accuracy: 0.01)
    }

    func testChangingWallLengthMovesOnlyItsEnd() {
        var plan = FloorPlan.rectangle(width: 12800, depth: 9600)
        let startBefore = plan.points[0]
        let neighbourStartBefore = plan.points[2]

        // ściana 0: od (-6400,-4800) do (6400,-4800) → skracamy do 9 m
        XCTAssertTrue(plan.setWallLength(0, to: 9000))

        XCTAssertEqual(plan.wall(0)!.length, 9000, accuracy: 1e-6)
        XCTAssertEqual(plan.points[0].x, startBefore.x, accuracy: 1e-9)
        XCTAssertEqual(plan.points[0].y, startBefore.y, accuracy: 1e-9)
        // koniec ściany 0 to początek ściany 1 — przesunięty razem z nim
        XCTAssertEqual(plan.points[1].x, startBefore.x + 9000, accuracy: 1e-6)
        // ściana 2 (przeciwległa) nie ruszyła się
        XCTAssertEqual(plan.points[2], neighbourStartBefore)
        XCTAssertEqual(plan.wall(2)!.length, 12800, accuracy: 1e-6)
    }

    func testChangingTwoAdjacentWallsKeepsChainConnected() {
        var plan = FloorPlan.rectangle()
        XCTAssertTrue(plan.setWallLength(0, to: 10000))
        XCTAssertTrue(plan.setWallLength(1, to: 7000))
        // szew: koniec ściany 1 = początek ściany 2
        XCTAssertEqual(plan.points[2], plan.wall(1)!.b)
        XCTAssertEqual(plan.wall(1)!.length, 7000, accuracy: 1e-6)
    }

    func testMinimumLengthIsEnforced() {
        var plan = FloorPlan.rectangle()
        XCTAssertTrue(plan.setWallLength(0, to: 10))
        XCTAssertEqual(plan.wall(0)!.length, 100, accuracy: 1e-6)
    }

    func testDrawingWithClicksClosesOnFirstPoint() {
        var plan = FloorPlan(points: [], closed: false)
        plan.append(SIMD2(0, 0))
        plan.append(SIMD2(4000, 0))
        plan.append(SIMD2(4000, 3000))
        XCTAssertEqual(plan.wallCount, 2)
        XCTAssertFalse(plan.closed)

        // klik w pobliżu pierwszego punktu zamyka plan
        plan.append(SIMD2(120, 80), snapRadius: 250)
        XCTAssertTrue(plan.closed)
        XCTAssertEqual(plan.points.count, 3)
        XCTAssertEqual(plan.wallCount, 3)
        // trójkąt 4 × 3 m → 6 m²
        XCTAssertEqual(plan.areaM2, 6.0, accuracy: 0.01)
    }

    func testAppendIgnoredWhenClosed() {
        var plan = FloorPlan.rectangle()
        plan.append(SIMD2(0, 0))
        XCTAssertEqual(plan.points.count, 4)
    }

    func testRemoveLastPointKeepsClosedWhilePolygonValid() {
        // zamknięty czworokąt → po usunięciu punktu zostaje zamknięty trójkąt
        var plan = FloorPlan.rectangle()
        plan.removeLastPoint()
        XCTAssertEqual(plan.points.count, 3)
        XCTAssertTrue(plan.closed)
        XCTAssertEqual(plan.wallCount, 3)

        // dopiero zejście do dwóch punktów otwiera plan (nie ma powierzchni)
        plan.removeLastPoint()
        XCTAssertEqual(plan.points.count, 2)
        XCTAssertFalse(plan.closed)
        XCTAssertEqual(plan.area, 0)
    }

    func testNearestWallFindsClosestSegment() {
        let plan = FloorPlan.rectangle(width: 10000, depth: 6000)
        // punkt przy dolnej ścianie (y = -3000) → ściana 0
        let hit = plan.nearestWall(to: SIMD2(1000, -2800))
        XCTAssertEqual(hit?.index, 0)
        XCTAssertEqual(hit!.distance, 200, accuracy: 1)

        // punkt przy prawej ścianie (x = 5000) → ściana 1
        let right = plan.nearestWall(to: SIMD2(4800, 1000))
        XCTAssertEqual(right?.index, 1)
    }

    func testPlanDrivesRoomDimensions() {
        var plan = FloorPlan.rectangle(width: 12800, depth: 9600, height: 2900)
        plan.setWallLength(0, to: 15000)
        let room = plan.room()
        XCTAssertEqual(room.height, 2900, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(room.width, 15000)
    }

    func testCodableRoundTrip() throws {
        var plan = FloorPlan.rectangle()
        plan.setWallLength(0, to: 11111)
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
    }
}
