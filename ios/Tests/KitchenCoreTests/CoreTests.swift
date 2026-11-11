import XCTest
@testable import KitchenCore

final class GeneratorTests: XCTestCase {

    func testWorktopSitsOnCarcass() {
        let cabinet = Library.make(Library.base[0])
        let runs = Runs.compute([cabinet])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].bodyTop, 720)
        let worktop = Runs.worktops(runs)
        XCTAssertEqual(worktop[0].position.y, 739)
    }

    func testPlinthRecessed() {
        let plinth = Runs.plinths(Runs.compute([Library.make(Library.base[0])]))
        XCTAssertEqual(plinth[0].size.y, 150)
        XCTAssertEqual(plinth[0].size.z, 500)
        XCTAssertEqual(plinth[0].position.z, 20)
    }

    func testFrontCoversBody() {
        let boxes = Generator.build(Library.make(Library.base[0]))
        let front = boxes.first { $0.role == .front }
        XCTAssertNotNil(front)
        XCTAssertEqual(front?.size.y, 564)
        XCTAssertEqual(front?.position.y, 435)
    }
}

final class DrawerTests: XCTestCase {

    func testDrawerStack() {
        let empty = Cabinet(name: "Test", type: .base, width: 600, height: 720, depth: 560, plinth: 150)
        var c = empty
        var ys: [Double] = []
        for _ in 0..<4 {
            guard let next = Collision.addDrawer(c, system: .k) else { break }
            c = next
            ys.append(c.elements.last!.y)
        }
        XCTAssertEqual(ys, [0, 128.5, 257, 385.5])
    }

    func testCapacity() {
        var c = Cabinet(name: "Test", type: .base, width: 600, height: 720, depth: 560, plinth: 150)
        var added = 0
        while added < 10, let next = Collision.addDrawer(c, system: .k) { c = next; added += 1 }
        XCTAssertEqual(added, 4)
    }

    func testPlaceNextInRow() {
        let first = Library.make(Library.base[0], at: -1200, z: -2200)
        let second = Generator.placeNext(to: [first], new: Library.make(Library.base[0]))
        XCTAssertEqual(second?.x, -600)
        XCTAssertEqual(second?.z, -2200)
    }
}

final class PointCloudTests: XCTestCase {

    func testAsciiPLY() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        end_header
        0 0 0
        100 0 0
        0 50 20
        """
        let cloud = try PLYParser.parse(data: Data(ply.utf8))
        XCTAssertEqual(cloud.count, 3)
        XCTAssertEqual(cloud.bounds.max.x, 100)
        XCTAssertEqual(cloud.bounds.max.z, 20)
    }

    func testDecimation() {
        var positions: [SIMD3<Float>] = []
        for i in 0..<10_000 { positions.append(SIMD3(Float(i), 0, 0)) }
        let cloud = PointCloud(positions: positions)
        XCTAssertEqual(cloud.decimated(maxPoints: 1_000).count, 1_000)
    }

    func testBinaryPLY() throws {
        var data = Data("""
        ply
        format binary_little_endian 1.0
        element vertex 1
        property float x
        property float y
        property float z
        end_header

        """.utf8)
        for v in [Float(1), Float(2), Float(3)] {
            withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        let cloud = try PLYParser.parse(data: data)
        XCTAssertEqual(cloud.count, 1)
        XCTAssertEqual(cloud.positions[0], SIMD3<Float>(1, 2, 3))
    }
}


final class AlignmentTests: XCTestCase {

    func testAutoFitScalesAndCenters() {
        // chmura 4 × 2,6 × 3 m, przesunięta w przestrzeni
        let min = SIMD3<Float>(10, 5, -20)
        let max = SIMD3<Float>(14, 7.6, -17)
        let room = Room(width: 5000, depth: 5000, height: 2600)
        let t = ScanTransform.autoFit(cloudMin: min, cloudMax: max, room: room)

        // skala: 5 m pokoju / 4 m chmury (z 2% luzem) = 1.225
        XCTAssertEqual(t.scale, 1.225, accuracy: 0.001)

        // po transformacji obrys leży w pokoju, podłoga na 0, środek na 0
        let b = t.transformedBounds(min: min, max: max)
        XCTAssertEqual(b.min.y, 0, accuracy: 0.01)
        XCTAssertEqual((b.min.x + b.max.x) / 2, 0, accuracy: 0.01)
        XCTAssertEqual((b.min.z + b.max.z) / 2, 0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(b.max.x - b.min.x, 5.0)
    }

    func testRotationSwapsFootprint() {
        let min = SIMD3<Float>(0, 0, 0)
        let max = SIMD3<Float>(4, 2.6, 2)
        let room = Room(width: 5000, depth: 5000, height: 2600)
        let t = ScanTransform.autoFit(cloudMin: min, cloudMax: max, room: room, rotationDeg: 90)
        let b = t.transformedBounds(min: min, max: max)
        // po obrocie 90° szerokość w X to pierwotna głębokość (2 m × skala)
        XCTAssertEqual(Double(b.max.x - b.min.x), 2 * t.scale, accuracy: 0.01)
        XCTAssertEqual(Double(b.max.z - b.min.z), 4 * t.scale, accuracy: 0.01)
    }

    func testUnitScaleDetection() {
        let meters = PointCloud(positions: [SIMD3(0, 0, 0), SIMD3(5, 2.6, 4)])
        XCTAssertEqual(meters.unitScaleToMeters, 1)
        let millimetres = PointCloud(positions: [SIMD3(0, 0, 0), SIMD3(5000, 2600, 4000)])
        XCTAssertEqual(millimetres.unitScaleToMeters, 0.001)
    }

    func testRoomArea() {
        XCTAssertEqual(Room(width: 6000, depth: 4500).area, 27, accuracy: 0.001)
    }
}
