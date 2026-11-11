import Foundation
import KitchenCore
import KitchenScene

/// Samokontrola bez Xcode: te same warunki co testy jednostkowe.
/// Uruchomienie: `swift run KitchenChecks` — kod wyjścia 1, gdy coś nie przejdzie.

final class Reporter {
    var checks = 0
    var failures = 0

    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks += 1
        if condition {
            print("  ✓ \(name)")
        } else {
            failures += 1
            print("  ✗ \(name) \(detail)")
        }
    }
}

func near(_ a: Double, _ b: Double, _ eps: Double = 0.001) -> Bool { abs(a - b) <= eps }

@MainActor
func runChecks() {
    let r = Reporter()

    print("Standardy produkcyjne")
    r.check("płyta 18 mm", Standards.panel == 18)
    r.check("szafka dolna 720 mm", Standards.baseHeight == 720)
    r.check("głębokość 560 mm", Standards.baseDepth == 560)
    r.check("blat 38 mm", Standards.worktopThickness == 38)
    r.check("LEGRABOX K = 128.5", DrawerSystem.k.frontHeight == 128.5)

    print("\nBlat i cokół")
    let cabinet = Library.make(Library.base[0])
    let runs = Runs.compute([cabinet])
    r.check("jeden bieg", runs.count == 1)
    r.check("górna krawędź korpusu 720", near(runs[0].bodyTop, 720), "= \(runs[0].bodyTop)")

    let worktop = Runs.worktops(runs)
    r.check("jeden blat na bieg", worktop.count == 1)
    r.check("blat leży na korpusie (y = 739)", near(worktop[0].position.y, 739), "= \(worktop[0].position.y)")
    r.check("nawis 20 mm z każdej strony", near(worktop[0].size.x, 640), "= \(worktop[0].size.x)")

    let plinth = Runs.plinths(runs)
    r.check("cokół 150 mm", near(plinth[0].size.y, 150))
    r.check("cokół cofnięty (głębokość 500)", near(plinth[0].size.z, 500), "= \(plinth[0].size.z)")
    r.check("cokół przesunięty do tyłu o 20", near(plinth[0].position.z, 20), "= \(plinth[0].position.z)")

    print("\nKorpus i front")
    let boxes = Generator.build(cabinet)
    r.check("dwa boki", boxes.filter { $0.role == .side }.count == 2)
    r.check("dno", boxes.contains { $0.role == .bottom })
    r.check("wieniec", boxes.contains { $0.role == .top })
    r.check("plecy", boxes.contains { $0.role == .back })
    if let front = boxes.first(where: { $0.role == .front }) {
        r.check("front pokrywa korpus 564 mm", near(front.size.y, 564), "= \(front.size.y)")
        r.check("front wyśrodkowany (y = 435)", near(front.position.y, 435), "= \(front.position.y)")
    } else {
        r.check("front istnieje", false)
    }

    print("\nSzuflady")
    // korpus bez wyposażenia — czysta szufladowa kolumna
    let empty = Cabinet(name: "Test szuflad", type: .base, width: 600, height: 720, depth: 560, plinth: 150)
    var c = empty
    var ys: [Double] = []
    for _ in 0..<4 {
        guard let next = Collision.addDrawer(c, system: .k) else { break }
        c = next
        ys.append(c.elements.last!.y)
    }
    r.check("wysokości 0 / 128.5 / 257 / 385.5", ys == [0, 128.5, 257, 385.5], "= \(ys)")

    var c2 = cabinet
    var count = 0
    while count < 10, let next = Collision.addDrawer(c2, system: .k) {
        c2 = next
        count += 1
    }
    r.check("w korpusie 570 mm mieszczą się 4 szuflady K", count == 4, "= \(count)")

    print("\nKolizje i dokładanie")
    let a = Library.make(Library.base[0], at: 0, z: 0)
    var b = Library.make(Library.base[0], at: 300, z: 0)
    r.check("nakładanie wykryte", Collision.overlaps(a, b))
    b.x = 600
    r.check("styk bez nakładania", !Collision.overlaps(a, b))

    let first = Library.make(Library.base[0], at: -1200, z: -2200)
    if let second = Generator.placeNext(to: [first], new: Library.make(Library.base[0])) {
        r.check("nowa szafka w rzędzie (x = -600)", near(second.x, -600), "= \(second.x)")
        r.check("ten sam wiersz (z = -2200)", near(second.z, -2200), "= \(second.z)")
    } else {
        r.check("dokładanie w rzędzie", false, "zwróciło nil")
    }

    print("\nChmura punktów (PLY)")
    // 1) ASCII
    let asciiPLY = """
    ply
    format ascii 1.0
    element vertex 3
    property float x
    property float y
    property float z
    property uchar red
    property uchar green
    property uchar blue
    end_header
    0 0 0 255 0 0
    100 0 0 0 255 0
    0 50 20 0 0 255
    """
    if let cloud = try? PLYParser.parse(data: Data(asciiPLY.utf8)) {
        r.check("ASCII: 3 punkty", cloud.count == 3, "= \(cloud.count)")
        r.check("ASCII: obrys 100 × 50 × 20", near(Double(cloud.bounds.max.x), 100) && near(Double(cloud.bounds.max.z), 20))
        r.check("ASCII: kolory odczytane", cloud.colors?.count == 3)
    } else {
        r.check("ASCII: parsowanie", false)
    }

    // 2) binary_little_endian (jak CloudCompare)
    var bin = Data("""
    ply
    format binary_little_endian 1.0
    element vertex 2
    property float x
    property float y
    property float z
    property uchar red
    property uchar green
    property uchar blue
    end_header

    """.utf8)
    for (x, y, z) in [(Float(10), Float(20), Float(30)), (Float(-5), Float(0), Float(100))] {
        withUnsafeBytes(of: x.bitPattern.littleEndian) { bin.append(contentsOf: $0) }
        withUnsafeBytes(of: y.bitPattern.littleEndian) { bin.append(contentsOf: $0) }
        withUnsafeBytes(of: z.bitPattern.littleEndian) { bin.append(contentsOf: $0) }
        bin.append(contentsOf: [200, 100, 50])
    }
    if let cloud = try? PLYParser.parse(data: bin) {
        r.check("binarny: 2 punkty", cloud.count == 2, "= \(cloud.count)")
        r.check("binarny: współrzędne poprawne", cloud.positions[0] == SIMD3<Float>(10, 20, 30), "= \(cloud.positions[0])")
        r.check("binarny: kolor 200/100/50", cloud.colors?[0] == SIMD3<UInt8>(200, 100, 50))
    } else {
        r.check("binarny: parsowanie", false)
    }

    // 3) realny plik ze skanu (jeśli jest w repo)
    let realPath = "\(FileManager.default.currentDirectoryPath)/../app/public/dom-chmura.ply"
    let realPLY = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/../app/public/dom-chmura.ply")
    if FileManager.default.fileExists(atPath: realPLY.path) {
        let started = Date()
        if let cloud = try? PLYParser.parse(contentsOf: realPLY) {
            let seconds = Date().timeIntervalSince(started)
            r.check("realny skan: 491 953 punkty", cloud.count == 491_953, "= \(cloud.count)")
            r.check("realny skan: kolory RGB", cloud.colors?.count == cloud.count)
            let b = cloud.robustBounds()
            let w = b.max.x - b.min.x, h = b.max.y - b.min.y, d = b.max.z - b.min.z
            r.check("realny skan: obrys > 0", w > 0 && h > 0 && d > 0,
                    String(format: "%.0f × %.0f × %.0f", w, h, d))
            print(String(format: "    czas parsowania: %.2f s (%.0f tys. pkt/s)", seconds, Double(cloud.count) / seconds / 1000))
            let dec = cloud.decimated(maxPoints: 100_000)
            r.check("decymacja do 100 tys.", dec.count <= 100_000 && dec.count > 90_000, "= \(dec.count)")
        } else {
            r.check("realny skan: parsowanie", false)
        }
    } else {
        print("    (pominięto realny plik — brak dom-chmura.ply)")
    }

    print("\nScena RealityKit (mm → metry)")
    let sceneCabinets = [Library.make(Library.base[0], at: -1200, z: -2200),
                         Library.make(Library.base[0], at: -600, z: -2200)]
    let built = SceneBuilder.build(cabinets: sceneCabinets)
    let expectedBoxes = sceneCabinets.reduce(0) { $0 + Generator.build($1).count }
        + Runs.worktops(Runs.compute(sceneCabinets)).count
        + Runs.plinths(Runs.compute(sceneCabinets)).count
    r.check("dwie szafki w scenie", built.bodyCount == 2, "= \(built.bodyCount)")
    r.check("liczba brył zgodna z domeną", built.totalBoxes == expectedBoxes, "= \(built.totalBoxes) vs \(expectedBoxes)")
    r.check("korpus w metrach (bok 0,56 m)",
            near(Double(SceneBuilder.meters(560)), 0.56),
            "= \(SceneBuilder.meters(560))")

    if let side = sceneCabinets.first.flatMap({ c in
        Generator.build(c).first { $0.role == .side }
    }) {
        r.check("bok korpusu: 18 mm płyty", near(side.size.x, 18), "= \(side.size.x)")
        r.check("bok korpusu: 570 mm wysokości", near(side.size.y, 570), "= \(side.size.y)")
        r.check("bok w metrach: 0,018 × 0,570", near(Double(SceneBuilder.meters(side.size.x)), 0.018)
                && near(Double(SceneBuilder.meters(side.size.y)), 0.57))
    } else {
        r.check("bok korpusu istnieje", false)
    }
    print(String(format: "    kadr: center (%.2f, %.2f, %.2f), extents (%.2f, %.2f, %.2f)",
                 built.center.x, built.center.y, built.center.z, built.extents.x, built.extents.y, built.extents.z))
    r.check("szerokość zabudowy 1,24 m (z nawisem blatu)", near(Double(built.widthMeters), 1.24, 0.02), "= \(built.widthMeters)")

    print("\nWokselizacja skanu (wydajność)")
    if FileManager.default.fileExists(atPath: realPath) {
        if let cloud = try? PLYParser.parse(contentsOf: URL(fileURLWithPath: realPath)) {
            let b = cloud.robustBounds()
            let t = ScanTransform.autoFit(cloudMin: b.min * cloud.unitScaleToMeters,
                                          cloudMax: b.max * cloud.unitScaleToMeters,
                                          room: Room())
            let started = Date()
            let geo = VoxelSurfaceBuilder.geometry(cloud, transform: t)
            let seconds = Date().timeIntervalSince(started)
            print(String(format: "    woksele: %d, siatka: %d, trójkątów: %d, czas: %.2f s",
                         geo.voxelCount, geo.pickCells.count,
                         geo.buckets.reduce(0) { $0 + $1.indices.count / 3 }, seconds))
            #if DEBUG
            print("    (debug — próg czasu wokselizacji pominięty)")
            #else
            r.check("wokselizacja < 3 s", seconds < 3, String(format: "= %.2f s", seconds))
            #endif
        }
    } else {
        print("    (pominięto — brak pliku skanu)")
    }

    print("\nSurface nets na realnym skanie")
    if FileManager.default.fileExists(atPath: realPath) {
        if let cloud = try? PLYParser.parse(contentsOf: URL(fileURLWithPath: realPath)) {
            let k = cloud.unitScaleToMeters
            let dec = cloud.decimated(maxPoints: 200_000)
            let points = dec.positions.map { $0 * k }
            var opts = SurfaceNets.Options()
            opts.cell = 0.032
            opts.isoLevel = 0.45
            let rb = cloud.robustBounds()
            opts.bounds = (rb.min * k, rb.max * k)
            var lo = points[0], hi = points[0]
            for q in points {
                lo = SIMD3(Swift.min(lo.x, q.x), Swift.min(lo.y, q.y), Swift.min(lo.z, q.z))
                hi = SIMD3(Swift.max(hi.x, q.x), Swift.max(hi.y, q.y), Swift.max(hi.z, q.z))
            }
            print(String(format: "    debug: %d pkt, obrys %.1f × %.1f × %.1f, k = %.3f",
                         points.count, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, k))
            let started = Date()
            let mesh = SurfaceNets.build(points: points, colors: dec.colors, options: opts)
            let seconds = Date().timeIntervalSince(started)
            print(String(format: "    wierzchołki: %d, trójkąty: %d, czas: %.2f s",
                         mesh.positions.count, mesh.indices.count / 3, seconds))
            r.check("siatka surface nets powstała", !mesh.isEmpty)
            r.check("kolory wierzchołków policzone", mesh.colors.count == mesh.positions.count)
            #if DEBUG
            print("    (kompilacja debug — próg czasu pominięty; użyj: swift run -c release KitchenChecks)")
            #else
            r.check("surface nets < 4 s", seconds < 4, String(format: "= %.2f s", seconds))
            #endif
        }
    }

    let passed = r.checks - r.failures
    print("\n\(passed)/\(r.checks) warunków spełnionych")
    if r.failures > 0 {
        print("NIEPOWODZENIE: \(r.failures)")
        exit(1)
    }
    print("OK")
}

runChecks()
