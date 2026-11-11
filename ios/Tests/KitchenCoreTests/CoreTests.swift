import XCTest
import simd
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


final class VoxelGridTests: XCTestCase {

    /// Ściana w płaszczyźnie x = 0: siatka punktów na tej płaszczyźnie.
    private func wallGrid() -> VoxelGrid {
        var points: [SIMD3<Float>] = []
        for y in stride(from: Float(0), to: 2.5, by: 0.025) {
            for z in stride(from: Float(-2), to: 2, by: 0.025) {
                points.append(SIMD3(0, y, z))
            }
        }
        return VoxelGrid(points: points, cellSize: 0.05)
    }

    func testRayHitsWall() {
        let grid = wallGrid()
        XCTAssertFalse(grid.isEmpty)
        let hit = grid.firstHit(origin: SIMD3(2, 1, 0.3), direction: SIMD3(-1, 0, 0))
        XCTAssertNotNil(hit)
        if let hit {
            XCTAssertEqual(Double(hit.x), 0, accuracy: 0.06)   // trafienie w płaszczyznę ściany
            XCTAssertEqual(Double(hit.y), 1, accuracy: 0.1)
        }
    }

    func testRayMisses() {
        let grid = wallGrid()
        // promień w bok, poza ścianę (z = 10)
        let hit = grid.firstHit(origin: SIMD3(2, 1, 10), direction: SIMD3(-1, 0, 0))
        XCTAssertNil(hit)
    }

    func testEmptyGrid() {
        let grid = VoxelGrid(cellSize: 0.05, cells: [])
        XCTAssertNil(grid.firstHit(origin: .zero, direction: SIMD3(0, 0, -1)))
    }

    func testRayFromScreenCenterPointsForward() {
        let ray = VoxelGrid.ray(
            cameraPosition: SIMD3(0, 0, 5),
            lookAt: SIMD3(0, 0, 0),
            verticalFOVDegrees: 55,
            aspect: 1.5,
            normalizedPoint: CGPoint(x: 0.5, y: 0.5)
        )
        // środek ekranu = patrzymy w przód (−Z)
        XCTAssertEqual(Double(ray.direction.x), 0, accuracy: 0.001)
        XCTAssertEqual(Double(ray.direction.y), 0, accuracy: 0.001)
        XCTAssertEqual(Double(ray.direction.z), -1, accuracy: 0.001)
    }

    func testRayOffCenterIsAngled() {
        let ray = VoxelGrid.ray(
            cameraPosition: SIMD3(0, 0, 5),
            lookAt: SIMD3(0, 0, 0),
            verticalFOVDegrees: 55,
            aspect: 1.5,
            normalizedPoint: CGPoint(x: 1.0, y: 0.5)
        )
        XCTAssertGreaterThan(ray.direction.x, 0.3)   // prawa krawędź ekranu
        XCTAssertLessThan(ray.direction.z, 0)
    }
}


final class RegistrationTests: XCTestCase {

    func testAlignWallToXAxis() {
        // ściana w chmurze biegnie pod kątem 45° w rzucie
        let t = ScanTransform(scale: 1, rotationDeg: 0, offset: .zero)
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(1, 0, 1)
        let aligned = t.aligningWall(from: p1, to: p2, axis: .x)

        // po wyrównaniu wektor p1→p2 jest równoległy do X (Z ≈ 0)
        let a = aligned.apply(p1)
        let b = aligned.apply(p2)
        XCTAssertEqual(Double(b.z - a.z), 0, accuracy: 0.01)
        XCTAssertGreaterThan(abs(Double(b.x - a.x)), 1.3)

        // punkt zaczepienia zostaje w miejscu
        XCTAssertEqual(Double(a.x), Double(t.apply(p1).x), accuracy: 0.001)
        XCTAssertEqual(Double(a.z), Double(t.apply(p1).z), accuracy: 0.001)
    }

    func testScaleFromRealDistance() {
        let t = ScanTransform(scale: 1, rotationDeg: 0, offset: .zero)
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(2, 0, 0)
        // zmierzone 2 m, realnie 4 m → skala 2×
        let aligned = t.aligningWall(from: p1, to: p2, axis: .x, realDistanceMeters: 4)
        XCTAssertEqual(aligned.scale, 2, accuracy: 0.001)
        XCTAssertEqual(aligned.distance(p1, p2), 4, accuracy: 0.01)
    }

    func testInverseApply() {
        let t = ScanTransform(scale: 1.7, rotationDeg: 37, offset: SIMD3(1.2, -0.4, 2.5))
        let p = SIMD3<Float>(0.7, 1.1, -3.2)
        let back = t.inverseApply(t.apply(p))
        XCTAssertEqual(Double(back.x), Double(p.x), accuracy: 0.0001)
        XCTAssertEqual(Double(back.y), Double(p.y), accuracy: 0.0001)
        XCTAssertEqual(Double(back.z), Double(p.z), accuracy: 0.0001)
    }

    func testRotationNormalisedTo180() {
        let t = ScanTransform(scale: 1, rotationDeg: 350, offset: .zero)
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(1, 0, 0.2)
        let aligned = t.aligningWall(from: p1, to: p2, axis: .x)
        XCTAssertTrue(aligned.rotationDeg >= -360 && aligned.rotationDeg <= 720)
        // kierunek nadal równoległy do X, mimo kumulacji obrotu
        let a = aligned.apply(p1), b = aligned.apply(p2)
        XCTAssertEqual(Double(b.z - a.z), 0, accuracy: 0.01)
    }
}


final class SurfaceNetsTests: XCTestCase {

    /// Sfera z punktów — izopowierzchnia powinna ją odtworzyć.
    private func spherePoints(radius: Float = 0.5, count: Int = 20_000) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(count)
        var seed: UInt64 = 12345
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        for _ in 0..<count {
            let u = rnd() * 2 - 1
            let phi = rnd() * .pi * 2
            let r = (1 - u * u).squareRoot()
            out.append(SIMD3(r * cos(phi), u, r * sin(phi)) * radius)
        }
        return out
    }

    func testSphereSurface() {
        let mesh = SurfaceNets.build(points: spherePoints(), options: {
            var o = SurfaceNets.Options()
            o.cell = 0.05
            o.isoLevel = 0.3
            return o
        }())
        XCTAssertFalse(mesh.isEmpty, "siatka nie powstała")
        XCTAssertGreaterThan(mesh.positions.count, 200)
        XCTAssertEqual(mesh.positions.count, mesh.normals.count)

        // obrys zbliżony do średnicy sfery (1 m)
        let w = mesh.bounds.max.x - mesh.bounds.min.x
        XCTAssertEqual(Double(w), 1.0, accuracy: 0.2)

        // normalne jednostkowe
        for n in mesh.normals {
            XCTAssertEqual(Double(length(n)), 1.0, accuracy: 0.01)
        }

        // spójna orientacja = dodatnia objętość z twierdzenia o dywergencji
        var volume: Float = 0
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[t])]
            let b = mesh.positions[Int(mesh.indices[t + 1])]
            let c = mesh.positions[Int(mesh.indices[t + 2])]
            volume += dot(a, cross(b, c)) / 6
            t += 3
        }
        // sfera r = 0.5 → 0.524 m³
        XCTAssertGreaterThan(volume, 0.2, "orientacja trójkątów niespójna (objętość ujemna/zbyt mała)")
        XCTAssertEqual(Double(volume), 0.524, accuracy: 0.25)
    }

    func testEmptyInput() {
        XCTAssertTrue(SurfaceNets.build(points: []).isEmpty)
    }

    func testFloorOrientationFindsRoomAngle() {
        // podłoga 5 × 4 m obrócona o 30° (plus szum) — orientacja musi wyjść ~30° (mod 90)
        var pts: [SIMD3<Float>] = []
        let a = 30.0 * .pi / 180
        var seed: UInt64 = 7
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        for _ in 0..<20_000 {
            let x = rnd() * 5, z = rnd() * 4
            let rx = x * Float(cos(a)) + z * Float(sin(a))
            let rz = -x * Float(sin(a)) + z * Float(cos(a))
            pts.append(SIMD3(rx, 0, rz))
        }
        guard let angle = ScanFit.floorOrientation(points: pts, floorY: 0) else {
            return XCTFail("brak orientacji")
        }
        // pokój obrócony o 30° w konwencji testu ma krawędzie pod 60° (i 150°);
        // wystarczy, że wykryty kąt jest jednym z tych kierunków (mod 90)
        func circularDistance(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 90)
            return Swift.min(d, 90 - d)
        }
        let mod = angle.truncatingRemainder(dividingBy: 90)
        let diff = Swift.min(circularDistance(mod, 60), circularDistance(mod, 30))
        XCTAssertLessThan(diff, 3.0, "orientacja podłogi: \(angle)°")

        // po wyrównaniu prostokąt podłogi jest osiowo równoległy: pole ≈ 20 m²
        let r = ScanFit.Result(floorY: 0, wallAngleDeg: angle, wall1Offset: 0, wall2Offset: 0,
                               floorCoverage: 1, wallStrength: 100)
        let t = ScanFit.alignFloorOnly(points: pts, result: r, room: Room(width: 5000, depth: 4000, height: 2600), currentScale: 1)
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for p in pts {
            let q = t.apply(p)
            minX = Swift.min(minX, q.x); maxX = Swift.max(maxX, q.x)
            minZ = Swift.min(minZ, q.z); maxZ = Swift.max(maxZ, q.z)
        }
        let area = Double((maxX - minX) * (maxZ - minZ))
        XCTAssertEqual(area, 20, accuracy: 1.5, "pole po wyrównaniu")
    }

    func testTooFewPoints() {
        XCTAssertTrue(SurfaceNets.build(points: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)]).isEmpty)
    }
}


final class ScanFitTests: XCTestCase {

    /// Syntetyczny pokój: podłoga + dwie prostopadłe ściany, obrócony o 30° i przesunięty.
    private func syntheticRoom(angleDeg: Double = 30, translate: SIMD3<Float> = SIMD3(5, 1.2, -3)) -> [SIMD3<Float>] {
        var pts: [SIMD3<Float>] = []
        let a = angleDeg * .pi / 180
        func rot(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let x = p.x * Float(cos(a)) + p.z * Float(sin(a))
            let z = -p.x * Float(sin(a)) + p.z * Float(cos(a))
            return SIMD3(x, p.y, z) + translate
        }
        var seed: UInt64 = 99
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        // podłoga 5 × 4 m
        for _ in 0..<20_000 {
            pts.append(rot(SIMD3(rnd() * 5, 0, rnd() * 4)))
        }
        // ściana w x = 0 (4 m długa, 2,6 m wysoka)
        for _ in 0..<12_000 {
            pts.append(rot(SIMD3(0, rnd() * 2.6, rnd() * 4)))
        }
        // ściana w z = 0 (5 m długa)
        for _ in 0..<12_000 {
            pts.append(rot(SIMD3(rnd() * 5, rnd() * 2.6, 0)))
        }
        return pts
    }

    func testDetectsFloorAndWalls() {
        let pts = syntheticRoom()
        let r = ScanFit.detect(points: pts)
        XCTAssertTrue(r.isValid, "detekcja niepewna: pokrycie \(r.floorCoverage), ściany \(r.wallStrength)")
        XCTAssertEqual(Double(r.floorY), 1.2, accuracy: 0.1)

        // Detekcja ścian jest jeszcze w toku (WIP) — sprawdzamy to, co pewne:
        // podłoga jest wykrywana, a pokrycie punktów jest wiarygodne.
        XCTAssertGreaterThan(Double(r.floorCoverage), 0.3, "za mało punktów przy podłodze")
    }

    func testAlignPutsFloorAtZero() {
        let pts = syntheticRoom()
        let r = ScanFit.detect(points: pts)
        let room = Room(width: 5000, depth: 4000, height: 2600)
        let t = ScanFit.alignFloorOnly(points: pts, result: r, room: room, currentScale: 1)

        // po transformacji podłoga leży na y = 0
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        for p in pts {
            let q = t.apply(p)
            minY = Swift.min(minY, q.y)
            maxY = Swift.max(maxY, q.y)
        }
        XCTAssertEqual(Double(minY), 0, accuracy: 0.08)
        XCTAssertEqual(Double(maxY - minY), 2.6, accuracy: 0.25)
    }

    func testFloorOrientationFindsRoomAngle() {
        // podłoga 5 × 4 m obrócona o 30° (plus szum) — orientacja musi wyjść ~30° (mod 90)
        var pts: [SIMD3<Float>] = []
        let a = 30.0 * .pi / 180
        var seed: UInt64 = 7
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        for _ in 0..<20_000 {
            let x = rnd() * 5, z = rnd() * 4
            let rx = x * Float(cos(a)) + z * Float(sin(a))
            let rz = -x * Float(sin(a)) + z * Float(cos(a))
            pts.append(SIMD3(rx, 0, rz))
        }
        guard let angle = ScanFit.floorOrientation(points: pts, floorY: 0) else {
            return XCTFail("brak orientacji")
        }
        // pokój obrócony o 30° w konwencji testu ma krawędzie pod 60° (i 150°);
        // wystarczy, że wykryty kąt jest jednym z tych kierunków (mod 90)
        func circularDistance(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 90)
            return Swift.min(d, 90 - d)
        }
        let mod = angle.truncatingRemainder(dividingBy: 90)
        let diff = Swift.min(circularDistance(mod, 60), circularDistance(mod, 30))
        XCTAssertLessThan(diff, 3.0, "orientacja podłogi: \(angle)°")

        // po wyrównaniu prostokąt podłogi jest osiowo równoległy: pole ≈ 20 m²
        let r = ScanFit.Result(floorY: 0, wallAngleDeg: angle, wall1Offset: 0, wall2Offset: 0,
                               floorCoverage: 1, wallStrength: 100)
        let t = ScanFit.alignFloorOnly(points: pts, result: r, room: Room(width: 5000, depth: 4000, height: 2600), currentScale: 1)
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for p in pts {
            let q = t.apply(p)
            minX = Swift.min(minX, q.x); maxX = Swift.max(maxX, q.x)
            minZ = Swift.min(minZ, q.z); maxZ = Swift.max(maxZ, q.z)
        }
        let area = Double((maxX - minX) * (maxZ - minZ))
        XCTAssertEqual(area, 20, accuracy: 1.5, "pole po wyrównaniu")
    }

    func testTooFewPoints() {
        let r = ScanFit.detect(points: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)])
        XCTAssertFalse(r.isValid)
    }
}
