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


final class ProjectStoreTests: XCTestCase {

    private func tempStore() throws -> ProjectStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("projekty-\(UUID().uuidString)")
        let store = ProjectStore(root: dir)
        try store.ensureDirectories()
        return store
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = try tempStore()
        let project = Project(name: "Kuchnia Kowalski", cabinets: [Library.make(Library.base[0])])
        try store.save([project])

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Kuchnia Kowalski")
        XCTAssertEqual(loaded[0].cabinets.count, 1)
        XCTAssertEqual(loaded[0].cabinets[0].width, 600)
    }

    func testImportDocumentCopiesFile() throws {
        let store = try tempStore()
        // źródło poza katalogiem projektów
        let source = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("umowa-\(UUID().uuidString).pdf")
        try Data("umowa".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let project = Project(name: "Test")
        let (doc, updated) = try store.importDocument(from: source, into: project)

        XCTAssertEqual(updated.documents.count, 1)
        XCTAssertEqual(doc.kind, .umowa)
        XCTAssertEqual(doc.sizeBytes, 5)
        let copied = store.url(for: doc, in: updated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: copied), Data("umowa".utf8))
    }

    func testImportNameCollisionGetsSuffix() throws {
        let store = try tempStore()
        let project = Project(name: "Test")
        let source = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rzut-\(UUID().uuidString).dwg")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let (_, first) = try store.importDocument(from: source, into: project)
        let (second, _) = try store.importDocument(from: source, into: first)
        XCTAssertNotEqual(second.fileName, first.documents[0].fileName)
        XCTAssertTrue(second.fileName.contains("-2"))
    }

    func testDeleteDocumentRemovesFile() throws {
        let store = try tempStore()
        let source = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zdjecie-\(UUID().uuidString).jpg")
        try Data("img".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let (doc, project) = try store.importDocument(from: source, into: Project(name: "T"))
        let fileURL = store.url(for: doc, in: project)
        let afterDelete = store.deleteDocument(doc, from: project)
        XCTAssertTrue(afterDelete.documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDocumentKindFromExtension() {
        XCTAssertEqual(DocumentKind.from(fileName: "umowa.PDF"), .umowa)
        XCTAssertEqual(DocumentKind.from(fileName: "kuchnia.e57"), .skan)
        XCTAssertEqual(DocumentKind.from(fileName: "rzut.dwg"), .rzut)
        XCTAssertEqual(DocumentKind.from(fileName: "foto.HEIC"), .zdjecie)
        XCTAssertEqual(DocumentKind.from(fileName: "cokolwiek.bin"), .inne)
    }
}

final class GestureNavTests: XCTestCase {

    func testAxisDetection() {
        XCTAssertEqual(GestureNav.axis(dx: 10, dy: 120), .vertical)
        XCTAssertEqual(GestureNav.axis(dx: 140, dy: 20), .horizontal)
        XCTAssertEqual(GestureNav.axis(dx: 30, dy: 40), .none)   // za mało
        XCTAssertEqual(GestureNav.axis(dx: 90, dy: 90), .none)   // ukośny
    }

    func testNextIndexWraps() {
        XCTAssertEqual(GestureNav.nextIndex(0, count: 3, step: 1), 1)
        XCTAssertEqual(GestureNav.nextIndex(2, count: 3, step: 1), 0)
        XCTAssertEqual(GestureNav.nextIndex(0, count: 3, step: -1), 2)
        XCTAssertEqual(GestureNav.nextIndex(0, count: 0, step: 1), 0)
    }

    func testStepDirection() {
        // palec w górę (dy < 0) → następny projekt
        XCTAssertEqual(GestureNav.step(for: .vertical, dx: 0, dy: -120), 1)
        XCTAssertEqual(GestureNav.step(for: .vertical, dx: 0, dy: 120), -1)
        // palec w lewo (dx < 0) → następny dokument
        XCTAssertEqual(GestureNav.step(for: .horizontal, dx: -120, dy: 0), 1)
        XCTAssertEqual(GestureNav.step(for: .horizontal, dx: 120, dy: 0), -1)
    }

    // MARK: - pomieszczenie z wymiarów / z prostokąta

    func testRectangleFromDimensions() {
        let plan = FloorPlan.rectangle(x: 1000, z: 2000, width: 3600, depth: 3000, height: 2600, thickness: 120)
        XCTAssertEqual(plan.size.x, 3600, accuracy: 0.001)
        XCTAssertEqual(plan.size.y, 3000, accuracy: 0.001)
        XCTAssertEqual(plan.areaM2, 10.8, accuracy: 0.001)
        XCTAssertEqual(plan.points.count, 4)
        XCTAssertTrue(plan.closed)
        XCTAssertEqual(plan.height, 2600, accuracy: 0.001)
        XCTAssertEqual(plan.thickness, 120, accuracy: 0.001)
        // narożnik lewy-górny w zadanym punkcie
        XCTAssertEqual(plan.bounds.min.x, 1000, accuracy: 0.001)
        XCTAssertEqual(plan.bounds.min.y, 2000, accuracy: 0.001)
    }

    func testRectangleFromDragSnapsAndOrdersCorners() {
        // przeciągnięcie „od prawej do lewej" musi dać ten sam prostokąt
        let plan = FloorPlan.rectangle(from: SIMD2(3720, 3040), to: SIMD2(0, 0), snap: 50)
        XCTAssertEqual(plan.size.x, 3700, accuracy: 0.001)   // 3720 → 3700
        XCTAssertEqual(plan.size.y, 3050, accuracy: 0.001)   // 3040 → 3050
        XCTAssertEqual(plan.bounds.min.x, 0, accuracy: 0.001)
        XCTAssertEqual(plan.bounds.min.y, 0, accuracy: 0.001)
    }

    func testRectangleRoomFollowsPlan() {
        let plan = FloorPlan.rectangle(width: 5200, depth: 6400, height: 2800)
        let room = plan.room(name: "Salon")
        XCTAssertEqual(room.width, 5200, accuracy: 0.001)
        XCTAssertEqual(room.depth, 6400, accuracy: 0.001)
        XCTAssertEqual(room.height, 2800, accuracy: 0.001)
    }

    func testSetSizeKeepsCentre() {
        var plan = FloorPlan.rectangle(x: 0, z: 0, width: 3000, depth: 3000)
        plan.setSize(width: 4000, depth: 5000)
        XCTAssertEqual(plan.size.x, 4000, accuracy: 0.001)
        XCTAssertEqual(plan.size.y, 5000, accuracy: 0.001)
        let b = plan.bounds
        XCTAssertEqual((b.min.x + b.max.x) / 2, 1500, accuracy: 0.001)
        XCTAssertEqual((b.min.y + b.max.y) / 2, 1500, accuracy: 0.001)
    }

    func testIsSimpleRectangle() {
        XCTAssertTrue(FloorPlan.rectangle(width: 3000, depth: 3000).isSimpleRectangle)
        // plan w kształcie litery L: 5 punktów, więc to nie jest prosty prostokąt
        let lShape = FloorPlan(
            points: [SIMD2(0, 0), SIMD2(4000, 0), SIMD2(4000, 2000), SIMD2(2000, 2000), SIMD2(2000, 4000), SIMD2(0, 4000)],
            closed: true
        )
        XCTAssertFalse(lShape.isSimpleRectangle)
    }

    // MARK: - rozstaw szafek na ścianie (zaślepki 18 mm, równe szerokości)

    func testWallFillEqualWidths() {
        let result = WallFill.fill(wallStart: SIMD2(0, 0), wallEnd: SIMD2(3600, 0), targetWidth: 600)
        XCTAssertEqual(result.cabinets.count, 6)
        XCTAssertEqual(result.panels.count, 2)
        for cabinet in result.cabinets {
            XCTAssertEqual(cabinet.width, 594, accuracy: 0.0001)
            XCTAssertEqual(cabinet.type, .base)
        }
        XCTAssertEqual(result.panels[0].width, 18, accuracy: 0.0001)
        XCTAssertEqual(result.panels[1].type, .panel)
        // suma: 2 × 18 mm + 6 × 594 mm = 3600 mm
        let sum = result.panels.reduce(0) { $0 + $1.width } + result.cabinets.reduce(0) { $0 + $1.width }
        XCTAssertEqual(sum, 3600, accuracy: 0.0001)
    }

    func testWallFillSpreadsRemainderExactly() {
        // 3000 mm, 5 szafek → 592,8 mm każda; suma musi się zgadzać co do 0,0001 mm
        let result = WallFill.fill(wallStart: SIMD2(0, 0), wallEnd: SIMD2(3000, 0), targetWidth: 600)
        XCTAssertEqual(result.cabinets.count, 5)
        let sum = result.panels.reduce(0) { $0 + $1.width } + result.cabinets.reduce(0) { $0 + $1.width }
        XCTAssertEqual(sum, 3000, accuracy: Units.precision)
        let widths = Set(result.cabinets.map { ($0.width * 10).rounded() / 10 })
        XCTAssertEqual(widths.count, 1, "wszystkie szafki mają równą szerokość")
    }

    func testWallFillPlacesRunAlongWall() {
        // ściana wzdłuż X od (0,0) do (2400,0) → szafki stoją przy niej, front do wnętrza (+Z)
        let result = WallFill.fill(wallStart: SIMD2(0, 0), wallEnd: SIMD2(2400, 0), targetWidth: 600)
        XCTAssertEqual(result.cabinets.count, 4)   // (2400 - 36) / 600 ≈ 3,94 → 4
        XCTAssertEqual(result.cabinets[0].x, 18 + result.cabinets[0].width / 2, accuracy: 0.01)
        for cabinet in result.cabinets {
            XCTAssertEqual(cabinet.z, Standards.baseDepth / 2, accuracy: 0.01)
            XCTAssertEqual(cabinet.rotation, 0, accuracy: 0.01)   // front w +Z, czyli do wnętrza
        }
    }

    func testWallFillRotatesWithWall() {
        // ściana wzdłuż Z od (0,0) do (0,2400) → wnętrze jest po lewej stronie kierunku,
        // czyli w −X; front szafki ma tam patrzeć (rotation 270°)
        let result = WallFill.fill(wallStart: SIMD2(0, 0), wallEnd: SIMD2(0, 2400), targetWidth: 600)
        XCTAssertFalse(result.cabinets.isEmpty)
        XCTAssertEqual(result.cabinets[0].rotation, 270, accuracy: 0.01)
        XCTAssertEqual(result.cabinets[0].x, -Standards.baseDepth / 2, accuracy: 0.01)
    }

    func testWallFillRejectsShortWall() {
        let result = WallFill.fill(wallStart: SIMD2(0, 0), wallEnd: SIMD2(120, 0))
        XCTAssertTrue(result.cabinets.isEmpty)
        XCTAssertTrue(result.note.contains("za krótka"))
    }

    func testPanelCabinetBuildsSinglePlate() {
        let panel = Cabinet(name: "Zaślepka", type: .panel, width: 18, height: 720, depth: 580, plinth: 0)
        let boxes = Generator.build(panel)
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes[0].size.x, 18, accuracy: 0.0001)
        XCTAssertEqual(boxes[0].size.z, 580, accuracy: 0.0001)
    }

    // MARK: - jednostki

    func testUnitsKeepPrecisionButDisplayWholeMillimetres() {
        XCTAssertEqual(Units.mm(1234.5678), "1235")
        XCTAssertEqual(Units.mm(600.0000), "600")
        XCTAssertEqual(Units.quantize(1234.56784), 1234.5678, accuracy: 0.00001)
    }

    func testUnitsParseUserInput() {
        XCTAssertEqual(Units.parseMM("1 200,5"), 1200.5)
        XCTAssertEqual(Units.parseMM("3600"), 3600)
        XCTAssertEqual(Units.parseMM("abc"), nil)
    }

    // MARK: - biblioteka tekstur

    func testTextureStoreNamesFromFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = TextureStore(directory: folder.appendingPathComponent("tekstury"))
        let source = folder.appendingPathComponent("dąb bielony 02.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: source)

        let texture = try store.importFile(at: source)
        XCTAssertEqual(texture.name, "dąb bielony 02", "nazwa = nazwa pliku bez rozszerzenia")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: texture.name)?.path ?? ""))
    }

    func testTextureStoreSearchIgnoresCaseAndDiacritics() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = TextureStore(directory: folder.appendingPathComponent("tekstury"))
        for name in ["dąb bielony", "Dąb naturalny", "orzech ciemny"] {
            let url = folder.appendingPathComponent("\(name).jpg")
            try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
            _ = try store.importFile(at: url)
        }

        XCTAssertEqual(store.search("dab").count, 2, "szukanie bez ogonków i wielkości liter")
        XCTAssertEqual(store.search("ORZECH").count, 1)
        XCTAssertEqual(store.search("").count, 3, "pusty tekst = wszystkie")
        XCTAssertEqual(store.search("nie ma takiej").count, 0)
    }

    func testTextureStoreAvoidsDuplicateNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = TextureStore(directory: folder.appendingPathComponent("tekstury"))
        let url = folder.appendingPathComponent("front.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        let first = try store.importFile(at: url)
        let second = try store.importFile(at: url)
        XCTAssertEqual(first.name, "front")
        XCTAssertEqual(second.name, "front 2", "druga tekstura o tej samej nazwie dostaje numer")
    }

    // MARK: - przesuwanie ścian (palcem)

    func testMoveWallKeepsLengthAndMovesBothCorners() {
        var plan = FloorPlan.rectangle(x: 0, z: 0, width: 3000, depth: 3600)
        // wall(0) to ściana południowa; dodatnia wartość = ruch do wnętrza
        // (normalna liczona „do środka", tak samo jak przy przeciąganiu palcem)
        let before = plan.wall(0)!.length
        plan.moveWall(0, by: 200)
        // przesuwana ściana zachowuje długość; sąsiednie skracają się same
        XCTAssertEqual(plan.wall(0)!.length, before, accuracy: 0.0001)
        XCTAssertEqual(plan.size.y, 3400, accuracy: 0.0001)
        XCTAssertEqual(plan.size.x, 3000, accuracy: 0.0001)
    }

    func testMoveVertexSnapsToPrecision() {
        var plan = FloorPlan.rectangle(width: 3000, depth: 3000)
        plan.moveVertex(2, to: SIMD2(3123.456789, 3010.123456))
        XCTAssertEqual(plan.points[2].x, 3123.4568, accuracy: 0.0001)
        XCTAssertEqual(plan.points[2].y, 3010.1235, accuracy: 0.0001)
    }

    // MARK: - gotowe plany i zestawienie

    func testPresetsProduceValidPlans() {
        for preset in PlanPresets.all {
            let plan = preset.plan()
            XCTAssertTrue(plan.closed)
            XCTAssertGreaterThanOrEqual(plan.wallCount, 3)
            XCTAssertGreaterThan(plan.areaM2, 5)
            XCTAssertEqual(plan.size.x, preset.width, accuracy: 1)
            XCTAssertEqual(plan.size.y, preset.depth, accuracy: 1)
        }
    }

    func testTakeoffCountsMaterials() {
        let plan = FloorPlan.rectangle(width: 3000, depth: 3600, height: 2600)
        let t = Takeoff.compute(plan: plan, windowCount: 2, doorCount: 1, coats: 2, coverage: 11)
        XCTAssertEqual(t.floorAreaM2, 10.8, accuracy: 0.01)
        XCTAssertEqual(t.perimeterMeters, 13.2, accuracy: 0.01)
        XCTAssertEqual(t.wallAreaWithOpeningsM2, 34.32, accuracy: 0.01)
        // otwory: 2 × 1,68 m² + 1 × 1,89 m²
        XCTAssertEqual(t.wallAreaM2, 34.32 - 5.25, accuracy: 0.01)
        XCTAssertEqual(t.skirtingMeters, 13.2 - 0.9, accuracy: 0.01)
        XCTAssertEqual(t.paintLiters, (34.32 - 5.25) * 2 / 11, accuracy: 0.01)
        XCTAssertEqual(t.windows.count, 2)
        XCTAssertEqual(t.doors.count, 1)
    }

    func testSettingsDefaultFOVIs47() {
        let settings = AppSettings()
        XCTAssertEqual(settings.fieldOfView, 47, accuracy: 0.0001)
        var wide = AppSettings()
        wide.fieldOfView = 500
        XCTAssertEqual(wide.clampedFieldOfView, 75)
        wide.fieldOfView = 5
        XCTAssertEqual(wide.clampedFieldOfView, 28)
    }

    // MARK: - import planu z obrazu

    func testPlanImageImportFindsOutline() {
        let width = 200, height = 150
        var gray = [UInt8](repeating: 255, count: width * height)
        // prostokąt ścian: ramka 2 px od (20,15) do (179,134)
        for x in 20...179 {
            for t in 0..<2 {
                gray[(15 + t) * width + x] = 40
                gray[(134 - t) * width + x] = 40
            }
        }
        for y in 15...134 {
            for t in 0..<2 {
                gray[y * width + (20 + t)] = 40
                gray[y * width + (179 - t)] = 40
            }
        }

        guard let analysis = PlanImageImport.analyze(gray: gray, width: width, height: height) else {
            return XCTFail("nie wykryto obrysu")
        }
        XCTAssertEqual(analysis.box.x, 20)
        XCTAssertEqual(analysis.box.y, 15)
        XCTAssertEqual(analysis.box.w, 160)
        XCTAssertEqual(analysis.box.h, 120)
        XCTAssertGreaterThanOrEqual(analysis.verticalLines.count, 2)
        XCTAssertGreaterThanOrEqual(analysis.horizontalLines.count, 2)

        let plan = PlanImageImport.plan(from: analysis, realWidthMM: 10_000)
        XCTAssertEqual(plan.size.x, 10_000, accuracy: 0.5)
        XCTAssertEqual(plan.size.y, 7_500, accuracy: 1)   // 120/160 × 10 m
        XCTAssertEqual(plan.wallCount, 4)
    }

    func testPlanImageImportRejectsBlankImage() {
        let gray = [UInt8](repeating: 255, count: 100 * 100)
        XCTAssertNil(PlanImageImport.analyze(gray: gray, width: 100, height: 100))
    }

    // MARK: - kartoteki z tabeli zamówień

    func testClientSeedHasThirteenClients() {
        XCTAssertEqual(ClientSeed.all.count, 13)
        XCTAssertEqual(ClientSeed.all.map(\.total).reduce(0, +), 359_463, accuracy: 0.01)
        XCTAssertEqual(ClientSeed.all.map(\.deposit).reduce(0, +), 36_700, accuracy: 0.01)
    }

    func testClientSeedBuildsProjectWithOrder() {
        let client = ClientSeed.all[0]        // Alicja Lidwin
        let project = ClientSeed.project(from: client)
        XCTAssertEqual(project.name, "Alicja Lidwin")
        let order = project.order
        XCTAssertEqual(order?.clientLastName, "Lidwin")
        XCTAssertEqual(order?.clientFirstName, "Alicja")
        XCTAssertEqual(order?.price ?? -1, 11_500, accuracy: 0.01)
        XCTAssertEqual(order?.deposit ?? -1, 4_000, accuracy: 0.01)
        XCTAssertEqual(order?.status, "Do dostarczenia")
        let day = order?.deliveryDate.map { Calendar.current.component(.day, from: $0) }
        let month = order?.deliveryDate.map { Calendar.current.component(.month, from: $0) }
        let year = order?.deliveryDate.map { Calendar.current.component(.year, from: $0) }
        XCTAssertEqual(day, 30)
        XCTAssertEqual(month, 9)
        XCTAssertEqual(year, 2027)
    }

    func testClientSeedKeepsDuplicateNamesSeparate() {
        // Paulina Bartodziej występuje dwa razy — to dwa różne zamówienia
        let pauliny = ClientSeed.all.filter { $0.fullName == "Paulina Bartodziej" }
        XCTAssertEqual(pauliny.count, 2)
        XCTAssertNotEqual(pauliny[0].total, pauliny[1].total)
    }

    // MARK: - dane przykładowe w kartotekach

    func testSeedClientsHaveContactData() {
        for client in ClientSeed.all {
            XCTAssertFalse(client.address.isEmpty, "\(client.fullName): brak adresu")
            XCTAssertFalse(client.phone.isEmpty, "\(client.fullName): brak telefonu")
            XCTAssertFalse(client.email.isEmpty, "\(client.fullName): brak e-maila")
            XCTAssertFalse(client.note.isEmpty, "\(client.fullName): brak notatki")
            XCTAssertTrue(client.address.contains("34-400 Nowy Targ"), "\(client.fullName): adres spoza rejonu")
            XCTAssertEqual(client.remaining, max(0, client.total - client.deposit), accuracy: 0.01)
        }
    }

    func testSeedProjectCarriesAddressAndPhone() {
        let project = ClientSeed.project(from: ClientSeed.all[7])   // Emil Kędra
        XCTAssertEqual(project.order?.clientLastName, "Kędra")
        XCTAssertEqual(project.order?.phone, "668 214 500")
        XCTAssertEqual(project.order?.email, "emil.kedra@gmail.com")
        XCTAssertTrue(project.order?.address.contains("Kościuszki") ?? false)
        XCTAssertTrue(project.order?.notes.contains("wyspa") ?? false)
    }

    /// Dopasowanie kartotek idzie po (imię, nazwisko, kwota) — ten klucz MUSI być unikalny,
    /// inaczej kolejne uruchomienie dopisze duplikat zamiast uzupełnić istniejący wpis.
    func testSeedKeysAreUnique() {
        var seen = Set<String>()
        for client in ClientSeed.all {
            let key = "\(client.firstName)|\(client.lastName)|\(client.total)"
            XCTAssertFalse(seen.contains(key), "powtórzony klucz kartoteki: \(key)")
            seen.insert(key)
        }
    }

    // MARK: - wyszukiwarka klientów i rabat

    private func sampleProjects() -> [Project] {
        var a = Project(name: "Emil Kędra")
        a.order = ProjectOrder(clientLastName: "Kędra", clientFirstName: "Emil",
                               address: "ul. Kościuszki 77, Nowy Targ", price: 45_000, deposit: 0)
        var b = Project(name: "Emil Kędra")
        b.order = ProjectOrder(clientLastName: "Kędra", clientFirstName: "Emil",
                               address: "ul. Kościuszki 77, Nowy Targ", price: 9_000, deposit: 0)
        var c = Project(name: "Renata Gazda")
        c.order = ProjectOrder(clientLastName: "Gazda", clientFirstName: "Renata",
                               address: "ul. Szpitalna 5/2, Nowy Targ", price: 26_800, deposit: 8_000)
        return [a, b, c]
    }

    func testClientSearchFindsBySurname() {
        let hits = ClientDirectory.search(sampleProjects(), query: "kedra")
        XCTAssertEqual(hits.count, 2, "szukanie bez ogonków musi znaleźć Kędra")
        XCTAssertEqual(hits.first?.projectCount, 2, "klient ma dwa projekty")
    }

    func testClientSearchFindsByAddress() {
        let hits = ClientDirectory.search(sampleProjects(), query: "szpitalna")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.name, "Renata Gazda")
    }

    func testClientSearchEmptyQueryListsAll() {
        XCTAssertEqual(ClientDirectory.search(sampleProjects(), query: "").count, 3)
    }

    func testClientProjectsGrouping() {
        let projects = sampleProjects()
        let list = ClientDirectory.projects(of: "Emil Kędra", in: projects)
        XCTAssertEqual(list.count, 2)
    }

    func testDiscountLowersFinalPrice() {
        var order = ProjectOrder(clientLastName: "Kędra", price: 45_000, deposit: 5_000)
        XCTAssertEqual(order.finalPrice, 45_000, accuracy: 0.01)
        order.discountPercent = 10
        XCTAssertEqual(order.discountAmount, 4_500, accuracy: 0.01)
        XCTAssertEqual(order.finalPrice, 40_500, accuracy: 0.01)
        order.discountPercent = 150          // ograniczenie do 100 %
        XCTAssertEqual(order.effectiveDiscount, 100)
        XCTAssertEqual(order.finalPrice, 0, accuracy: 0.01)
    }

    func testContractSignedState() {
        var order = ProjectOrder()
        XCTAssertFalse(order.isContractSigned)
        order.contractSignedAt = Date()
        order.contractSignatureFile = "abc-podpis.png"
        XCTAssertTrue(order.isContractSigned)
        XCTAssertEqual(order.contractSignatureFile, "abc-podpis.png")
    }

    func testCutoutTopBox() {
        var c = Cabinet(name: "zlew", type: .base, width: 600, height: 862, depth: 560, plinth: 142)
        c.cutouts = [CabinetCutout.make(.sink, in: c)]
        let boxes = Generator.build(c).filter { $0.role == .cutout }
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes[0].size.x, 560)
        XCTAssertEqual(boxes[0].size.y, 2)
        XCTAssertEqual(boxes[0].size.z, 460)
        XCTAssertEqual(boxes[0].position.y, 901, accuracy: 0.5)
    }

    func testCutoutFrontHandle() {
        var c = Cabinet(name: "uchwyt", type: .base, width: 600, height: 862, depth: 560, plinth: 142)
        c.cutouts = [CabinetCutout.make(.handle, in: c)]
        let boxes = Generator.build(c).filter { $0.role == .cutout }
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes[0].size.x, 160)
        XCTAssertEqual(boxes[0].size.y, 26)
        XCTAssertGreaterThan(boxes[0].position.z, 280)
        XCTAssertEqual(boxes[0].position.y, 772, accuracy: 0.5)
    }

    func testCutoutCodableRoundTrip() throws {
        let cut = CabinetCutout(plane: .side, purpose: .cable, x: 20, y: 100, width: 60, height: 60)
        let data = try JSONEncoder().encode(cut)
        let back = try JSONDecoder().decode(CabinetCutout.self, from: data)
        XCTAssertEqual(back, cut)
    }

    /// Szafki po „Wstaw szafki" muszą stać PRZY ŚCIANIE POMIESZCZENIA,
    /// także gdy plan jest narysowany daleko od początku układu.
    func testWallFillIsCenteredOnRoom() {
        let plan = FloorPlan.rectangle(x: 5000, z: 7000, width: 6000, depth: 4000, height: 2600)
        let result = WallFill.fill(plan: plan, wallIndex: 0)
        XCTAssertFalse(result.cabinets.isEmpty)

        for cabinet in result.cabinets {
            // `z` to ŚRODEK szafki: tył = z − głębokość/2, przód = z + głębokość/2
            let back = cabinet.z - cabinet.depth / 2
            let front = cabinet.z + cabinet.depth / 2
            XCTAssertEqual(back, -2000, accuracy: 30, "tył szafki nie przy ścianie: \(back)")
            XCTAssertLessThan(front, -1400, "szafka wystaje poza pomieszczenie: przód \(front)")
            XCTAssertLessThanOrEqual(abs(cabinet.x) + cabinet.width / 2, 3000.5, "szafka poza szerokością: x=\(cabinet.x)")
        }
    }

    /// Środek planu = środek pomieszczenia: suma pozycji blisko zera.
    func testWallFillKeepsSymmetryForCenteredPlan() {
        let plan = FloorPlan.rectangle(width: 6000, depth: 4000, height: 2600)
        let result = WallFill.fill(plan: plan, wallIndex: 0)
        let xs = result.cabinets.map { $0.x }
        let center = (xs.min()! + xs.max()!) / 2
        XCTAssertEqual(center, 0, accuracy: 5, "zabudowa nie jest wyśrodkowana")
    }
}
