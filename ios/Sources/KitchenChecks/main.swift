import Foundation
import simd

// bez buforowania: przy crashu widzimy, gdzie stanęło
setvbuf(stdout, nil, _IONBF, 0)
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

func runZoneChecks(_ r: Reporter) {
    print("\nStrefy zabudowy (auto-projekt)")

    let ctx = ZoneContext(wallLength: 5000, wallHeight: 2600, roomWidth: 5000, roomDepth: 4000)

    // każda strefa ma sensowny plan
    for spec in ZoneLibrary.specs {
        let plan = ZonePlanner.plan(spec.kind, ZoneAnswers(spec.defaults), ctx)
        r.check("\(spec.short): plan niepusty", !plan.parts.isEmpty, "\(plan.parts.count) części")
        r.check("\(spec.short): dodatnie wymiary",
                plan.parts.allSatisfy { $0.width > 100 && $0.height > 100 && $0.depth > 100 })
        let base = plan.parts.filter { $0.type == .base }.sorted { $0.at < $1.at }
        var contiguous = true
        for i in 1..<max(1, base.count) where base.count > 1 {
            if abs(base[i].at - (base[i - 1].at + base[i - 1].width)) > 0.6 { contiguous = false }
        }
        r.check("\(spec.short): ciąg dolny bez dziur", contiguous || base.count < 2)
    }

    // gotowanie
    let cook = ZoneAnswers(ZoneLibrary.defaults(.kitchenCook))
    let cookPlan = ZonePlanner.plan(.kitchenCook, cook, ctx)
    let hob = cookPlan.parts.first { $0.role == "hob" }
    r.check("gotowanie: szafka pod płytą 600", hob?.width == 600)
    r.check("gotowanie: cokół 900 − 38 − 720 = 142", hob?.plinth == 142, "\(hob?.plinth ?? -1)")
    r.check("gotowanie: słupek piekarnika 600",
            cookPlan.parts.first { $0.role == "oven" }?.width == 600)
    r.check("gotowanie: piekarnik + mikrofala",
            cookPlan.parts.first { $0.role == "oven" }?.appliances.contains(.microwave) == true)
    r.check("gotowanie: lodówka 600", cookPlan.parts.first { $0.role == "fridge" }?.width == 600)
    r.check("gotowanie: witryny na obu końcach",
            cookPlan.parts.filter { $0.role.hasPrefix("witryna") }.count == 2)
    let wallCab = cookPlan.parts.first { $0.type == .wall }
    r.check("gotowanie: szafki górne 600 nad blatem", wallCab?.mountHeight == 1500)
    r.check("gotowanie: okap na szafce płyty", hob?.appliances.contains(.hood) == true)
    r.check("gotowanie: zmywarka 600", cookPlan.parts.contains { $0.role == "dishwasher" && $0.width == 600 })

    // czystość
    let clean = ZoneAnswers(ZoneLibrary.defaults(.kitchenClean))
    let cleanPlan = ZonePlanner.plan(.kitchenClean, clean, ctx)
    let sink = cleanPlan.parts.first { $0.role == "sink" }
    r.check("czystość: zlew 1,5-komorowy 800", sink?.width == 800)
    r.check("czystość: kosz pod zlewem", sink?.appliances.contains(.bin) == true)
    let dw = cleanPlan.parts.first { $0.role == "dishwasher" }
    r.check("czystość: zmywarka obok zlewu",
            dw != nil && sink != nil && abs(dw!.at - (sink!.at + sink!.width)) < 1)
    var moved = clean
    moved["sinkPos"] = .number(90)
    let movedPlan = ZonePlanner.plan(.kitchenClean, moved, ctx)
    r.check("czystość: przesuwanie zlewu po blacie",
            (movedPlan.parts.first { $0.role == "sink" }?.at ?? 0) > (sink?.at ?? 0))

    // wysoka, wyspa, szafy, RTV, łazienka
    let tallPlan = ZonePlanner.plan(.kitchenTall, ZoneAnswers(ZoneLibrary.defaults(.kitchenTall)), ctx)
    r.check("wysoka: do sufitu 2560", tallPlan.parts.allSatisfy { $0.height == 2560 })

    let island = ZonePlanner.plan(.kitchenIsland, ZoneAnswers(ZoneLibrary.defaults(.kitchenIsland)), ctx)
    r.check("wyspa: blat 860 z nawisem", island.parts.allSatisfy { $0.worktopDepth == 860 })
    r.check("wyspa: okap sufitowy", island.parts.contains { $0.appliances.contains(.hood) })

    let hinged = ZonePlanner.plan(.wardrobeHinged, ZoneAnswers(ZoneLibrary.defaults(.wardrobeHinged)), ctx)
    r.check("szafa otwierana: głębokość 600", hinged.parts.allSatisfy { $0.depth == 600 })
    let sliding = ZonePlanner.plan(.wardrobeSliding, ZoneAnswers(ZoneLibrary.defaults(.wardrobeSliding)), ctx)
    r.check("szafa przesuwna: głębokość 650", sliding.parts.allSatisfy { $0.depth == 650 })
    r.check("szafa przesuwna: 2 panele", sliding.parts.first?.slidingPanels == 2)

    let tv = ZonePlanner.plan(.livingTV, ZoneAnswers(ZoneLibrary.defaults(.livingTV)), ctx)
    r.check("RTV: nadbudowa nad telewizorem", (tv.parts.first { $0.type == .wall }?.mountHeight ?? 0) >= 1600)
    let bath = ZonePlanner.plan(.bathroom, ZoneAnswers(ZoneLibrary.defaults(.bathroom)), ctx)
    r.check("łazienka: umywalka + lustro + słupek",
            bath.parts.contains { $0.appliances.contains(.basin) }
            && bath.parts.contains { $0.appliances.contains(.mirror) }
            && bath.parts.contains { $0.width == 400 && $0.type == .tall })

    // materiał: szafki na ścianie planu
    let plan = FloorPlan.rectangle(width: 5000, depth: 4000, height: 2600)
    let zone = Zones.makeZone(kind: .kitchenCook, wallIndex: 0)
    let cabinets = Zones.cabinets(for: zone, plan: plan)
    r.check("plan: tyle szafek co części", cabinets.count == cookPlan.parts.count,
            "\(cabinets.count) / \(cookPlan.parts.count)")
    r.check("plan: wszystkie mają zoneID", cabinets.allSatisfy { $0.zoneID == zone.id })
    r.check("plan: szafki w granicach pomieszczenia",
            cabinets.allSatisfy { abs($0.x) < 2600 && abs($0.z) < 2100 })
    r.check("plan: front do wnętrza (obrót 0 na ścianie północnej)",
            abs((cabinets.first?.rotation ?? -1)) < 0.01)
    r.check("plan: blat i cokół na biegu",
            !Runs.worktops(Runs.compute(cabinets)).isEmpty && !Runs.plinths(Runs.compute(cabinets)).isEmpty)

    // przebudowa nie rusza szafek ręcznych
    let manual = Library.make(Library.base[0], at: 0, z: 1000)
    let merged = Zones.rebuilt([manual] + cabinets, zones: [zone], plan: plan)
    r.check("przebudowa: szafka ręczna zostaje",
            merged.contains { $0.id == manual.id })
    r.check("przebudowa: szafki strefy odtworzone",
            merged.filter { $0.zoneID == zone.id }.count == cabinets.count)
    let cleared = Zones.rebuilt(merged, zones: [], plan: plan)
    r.check("usunięcie strefy: zostaje tylko ręczna",
            cleared.count == 1 && cleared.first?.id == manual.id)

    // zapis/odczyt strefy (Codable — projekt na dysku)
    if let data = try? JSONEncoder().encode(zone),
       let back = try? JSONDecoder().decode(Zone.self, from: data) {
        r.check("Codable: strefa przechodzi przez JSON",
                back.kind == zone.kind && back.wallIndex == zone.wallIndex && back.answers == zone.answers)
    } else {
        r.check("Codable: strefa przechodzi przez JSON", false)
    }

    // pytania zależne
    var noHob = cook
    noHob["hob"] = .text("none")
    r.check("pytania: okap znika bez płyty",
            !ZoneLibrary.activeQuestions(.kitchenCook, answers: ZoneAnswers(noHob.values)).contains { $0.id == "hood" })
}

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

    print("\nModele GLB (biblioteka)")
    for model in ModelLibrary.catalog {
        guard let dir = ModelLibrary.modelsDirectory() else {
            r.check("katalog modeli", false, "brak Resources/Models")
            break
        }
        let url = dir.appendingPathComponent("\(model.name).glb")
        guard FileManager.default.fileExists(atPath: url.path) else {
            r.check("\(model.name): plik jest", false)
            continue
        }
        let started = Date()
        print("    [glb] wczytuję \(model.name)…")
        do {
            let loaded = try GLBLoader.load(url: url)
            print("    [glb] wczytane: \(loaded.meshCount) siatek")
            print("    [glb] liczę obrys…")
            let bounds = loaded.entity.visualBounds(relativeTo: nil)
            let seconds = Date().timeIntervalSince(started)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let kb = Double(bytes) / 1000.0
            let ex = bounds.extents.x, ey = bounds.extents.y, ez = bounds.extents.z
            print(String(format: "    %@: %d siatek, obrys %.2f × %.2f × %.2f m, %.0f kB, %.2f s",
                         model.name, loaded.meshCount, ex, ey, ez, kb, seconds))
            r.check("\(model.name): siatki wczytane", loaded.meshCount > 0)
            r.check("\(model.name): obrys > 0", bounds.extents.y > 0.001)
        } catch {
            r.check("\(model.name): parsowanie", false, "\(error)")
        }
    }

    // ---- Skan LiDAR: próbkowanie siatki, klasyfikacja, zapis PLY ----
    // Cała ta logika jest bez ARKit, więc sprawdzamy ją bez iPada.
    print("\nSkan LiDAR — próbkowanie siatki")

    func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
              _ color: SIMD3<UInt8>) -> [ScanTriangle] {
        [ScanTriangle(a: a, b: b, c: c, color: color),
         ScanTriangle(a: a, b: c, c: d, color: color)]
    }

    // jeden trójkąt 1×1 m (0.5 m²) przy kroku 2 cm → ~1250 komórek
    do {
        let tri = [ScanTriangle(a: SIMD3(0, 0, 0), b: SIMD3(1, 0, 0), c: SIMD3(0, 1, 0),
                                color: SIMD3(10, 20, 30))]
        let cloud = MeshSampler.sample(triangles: tri, step: 0.02)
        r.check("trójkąt 0.5 m²: 1250–1450 pkt", cloud.count >= 1250 && cloud.count <= 1450, "= \(cloud.count)")
        r.check("trójkąt: kolor zachowany",
                cloud.colors?.allSatisfy { $0 == SIMD3(10, 20, 30) } == true)
        r.check("trójkąt: punkty w płaszczyźnie z=0",
                cloud.positions.allSatisfy { abs($0.z) < 1e-6 })
    }

    // pomieszczenie 4 × 2.6 × 3 m, pełne 6 ścian
    do {
        var tris: [ScanTriangle] = []
        let floor = SurfaceClassifier.floorColor
        let wall = SurfaceClassifier.wallColor
        let ceil = SurfaceClassifier.ceilingColor
        tris += quad(SIMD3(-2, 0, -1.5), SIMD3(2, 0, -1.5), SIMD3(2, 0, 1.5), SIMD3(-2, 0, 1.5), floor)
        tris += quad(SIMD3(-2, 2.6, -1.5), SIMD3(-2, 2.6, 1.5), SIMD3(2, 2.6, 1.5), SIMD3(2, 2.6, -1.5), ceil)
        tris += quad(SIMD3(-2, 0, -1.5), SIMD3(2, 0, -1.5), SIMD3(2, 2.6, -1.5), SIMD3(-2, 2.6, -1.5), wall)
        tris += quad(SIMD3(-2, 0, 1.5), SIMD3(-2, 2.6, 1.5), SIMD3(2, 2.6, 1.5), SIMD3(2, 0, 1.5), wall)
        tris += quad(SIMD3(-2, 0, -1.5), SIMD3(-2, 0, 1.5), SIMD3(-2, 2.6, 1.5), SIMD3(-2, 2.6, -1.5), wall)
        tris += quad(SIMD3(2, 0, -1.5), SIMD3(2, 2.6, -1.5), SIMD3(2, 2.6, 1.5), SIMD3(2, 0, 1.5), wall)

        let floorArea: Float = 4 * 3
        let wallN: Float = 4 * 2.6
        let wallW: Float = 3 * 2.6
        let area: Float = 2 * floorArea + 2 * wallN + 2 * wallW   // 60.4 m²
        let expected = Int(area / 0.0004)                        // krok 2 cm
        let t0 = Date()
        let cloud = MeshSampler.sample(triangles: tris, step: 0.02)
        let dt = Date().timeIntervalSince(t0)
        r.check("pokój: ~\(expected) pkt (±15%)",
                abs(cloud.count - expected) < expected / 7, "= \(cloud.count)")
        r.check("pokój: próbkowanie < 3 s", dt < 3, String(format: "%.2f s", dt))
        let s = cloud.bounds.max - cloud.bounds.min
        r.check("pokój: obrys 4×2.6×3 m",
                abs(s.x - 4) < 0.06 && abs(s.y - 2.6) < 0.06 && abs(s.z - 3) < 0.06,
                String(format: "%.2f×%.2f×%.2f", s.x, s.y, s.z))
        // w metrach CloudCompare rozpozna jednostkę jako metry
        r.check("pokój: jednostka rozpoznana jako metry", cloud.unitScaleToMeters == 1)
    }

    // determinizm i deduplikacja
    do {
        let tris = quad(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0), SIMD3(1, 2, 3))
        let a = MeshSampler.sample(triangles: tris, step: 0.05)
        let b = MeshSampler.sample(triangles: tris, step: 0.05)
        r.check("determinizm: powtórzenie daje tę samą chmurę",
                a.count == b.count && a.positions == b.positions, "\(a.count) vs \(b.count)")
        let single = MeshSampler.sample(triangles: tris, step: 0.05)
        let doubled = MeshSampler.sample(triangles: tris + tris, step: 0.05)
        r.check("dedup: nachodzące trójkąty nie dublują", doubled.count == single.count,
                "\(single.count) → \(doubled.count)")
    }

    // odporność na artefakty ARKit (zerwany tracking generuje gigantyczne trójkąty)
    do {
        let bad = [
            ScanTriangle(a: SIMD3(0, 0, 0), b: SIMD3(0, 0, 0), c: SIMD3(0, 0, 0), color: SIMD3(1, 1, 1)),
            ScanTriangle(a: SIMD3(.nan, 0, 0), b: SIMD3(1, 0, 0), c: SIMD3(0, 1, 0), color: SIMD3(1, 1, 1)),
            ScanTriangle(a: SIMD3(0, 0, 0), b: SIMD3(1e9, 0, 0), c: SIMD3(0, 1e9, 0), color: SIMD3(1, 1, 1)),
        ]
        let cloud = MeshSampler.sample(triangles: bad, step: 0.02)
        r.check("artefakty: brak NaN w wyniku",
                cloud.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        r.check("artefakty: gigantyczny trójkąt nie wywala eksportu", cloud.count < 1_000_000, "= \(cloud.count)")
    }

    // limit punktów
    do {
        var tris: [ScanTriangle] = []
        for i in 0..<200 {
            let o = Float(i)
            tris += quad(SIMD3(o, 0, 0), SIMD3(o + 1, 0, 0), SIMD3(o + 1, 1, 0), SIMD3(o, 1, 0), SIMD3(1, 1, 1))
        }
        let cloud = MeshSampler.sample(triangles: tris, step: 0.01, maxPoints: 5000)
        r.check("limit: maxPoints respektowany", cloud.count <= 5000, "= \(cloud.count)")
    }

    // klasyfikacja powierzchni
    print("\nSkan LiDAR — klasyfikacja powierzchni")
    do {
        let up = SIMD3<Float>(0, 1, 0), down = SIMD3<Float>(0, -1, 0), side = SIMD3<Float>(1, 0, 0)
        r.check("nisko = podłoga",
                SurfaceClassifier.color(normal: up, centroidY: 0.2, ceilingY: 2.6) == SurfaceClassifier.floorColor)
        r.check("wysoko = sufit (znak normalnej nieistotny)",
                SurfaceClassifier.color(normal: down, centroidY: 2.5, ceilingY: 2.6) == SurfaceClassifier.ceilingColor
                && SurfaceClassifier.color(normal: up, centroidY: 2.5, ceilingY: 2.6) == SurfaceClassifier.ceilingColor)
        r.check("pionowa = ściana",
                SurfaceClassifier.color(normal: side, centroidY: 1.2, ceilingY: 2.6) == SurfaceClassifier.wallColor)
        r.check("blat 0.9 m ≠ sufit",
                SurfaceClassifier.color(normal: up, centroidY: 0.9, ceilingY: 2.6) == SurfaceClassifier.floorColor)
        r.check("normalna zdegenerowanego = nil",
                MeshSampler.normal(SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 0, 0)) == nil)
    }

    // zapis PLY i odczyt tym samym parserem (pełny obieg)
    print("\nSkan LiDAR — zapis i odczyt PLY")
    do {
        var tris: [ScanTriangle] = []
        tris += quad(SIMD3(-2, 0, -1.5), SIMD3(2, 0, -1.5), SIMD3(2, 0, 1.5), SIMD3(-2, 0, 1.5), SIMD3(150, 115, 85))
        let cloud = MeshSampler.sample(triangles: tris, step: 0.05)
        let data = ScanPLYWriter.data(for: cloud)
        r.check("PLY: niepusty", data.count > 0)

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("check-skan.ply")
        r.check("podsumowanie skanu ma sens",
                ScanOutcome.summary(cloud).contains("pkt") && ScanOutcome.summary(cloud).contains("mm"),
                ScanOutcome.summary(cloud))
        do {
            try data.write(to: url)
            let back = try PLYParser.parse(contentsOf: url)
            r.check("PLY: obieg zamknięty — tyle samo punktów",
                    back.count == cloud.count, "\(cloud.count) → \(back.count)")
            r.check("PLY: kolory zachowane", back.colors?.first == SIMD3(150, 115, 85))
            let s = back.bounds.max - back.bounds.min
            r.check("PLY: obrys zachowany (4×3 m)",
                    abs(s.x - 4) < 0.06 && abs(s.z - 3) < 0.06,
                    String(format: "%.2f×%.2f", s.x, s.z))
            r.check("PLY: jednostka nadal metry", back.unitScaleToMeters == 1)
            try? FileManager.default.removeItem(at: url)
        } catch {
            r.check("PLY: obieg zamknięty", false, "\(error)")
        }
    }

    // ---- Dokładność: fuzja map głębi ----
    // To jest sedno „skanuj dokładniej": N niezależnych pomiarów tego samego
    // fragmentu uśredniamy z wagami 1/σ², więc błąd spada jak σ/√N.
    // Poniżej sprawdzamy to liczbowo, na syntetycznej ścianie z szumem.
    print("\nDokładność — fuzja głębi LiDAR")

    /// Syntetyczna klatka: płaska ściana w z=2.0 m, z szumem Gaussa.
    func wallFrame(
        noise: Float, seed: UInt64, width: Int = 64, height: Int = 48,
        confidence: UInt8 = 2, wallZ: Float = -2.0
    ) -> DepthFrame {
        var state = seed
        func rand() -> Float {
            // xorshift + Box–Muller: powtarzalny szum o rozkładzie normalnym
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let u1 = Float(state & 0xFFFFFF) / Float(0x1000000) + 1e-7
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let u2 = Float(state & 0xFFFFFF) / Float(0x1000000)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        var depths = [Float](repeating: 0, count: width * height)
        var conf = [UInt8](repeating: confidence, count: width * height)
        let fx: Float = 200, fy: Float = 200
        let cx = Float(width) / 2, cy = Float(height) / 2
        // ARKit: „distance from the plane of the camera" = odległość wzdłuż Z,
        // więc płaska ściana prostopadła do osi ma wszędzie tę samą głębokość.
        for y in 0..<height {
            for x in 0..<width {
                depths[y * width + x] = (-wallZ) + rand() * noise
            }
        }
        // kamera w początku układu, patrzy w -Z
        return DepthFrame(
            depths: depths, confidence: conf, width: width, height: height,
            cameraTransform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1)),
            fx: fx, fy: fy, cx: cx, cy: cy, colors: nil
        )
    }

    // 1) pojedyncza klatka: błąd ≈ założone σ
    do {
        var st = DepthFusionState()
        let f = wallFrame(noise: 0.010, seed: 12345)
        let n = DepthFusion.add(frame: f, into: &st, minConfidence: 1)
        r.check("fuzja: jedna klatka przyjmuje punkty", n > 1000, "= \(n)")
        let fused = DepthFusion.fused(from: st, minSamples: 1)
        r.check("fuzja: jest wynik", fused != nil, "")
        if let fused {
            r.check("fuzja: σ pojedynczej klatki > 3 mm", fused.medianSigma * 1000 > 3,
                    String(format: "%.2f mm", fused.medianSigma * 1000))
        }
    }

    // 2) KLUCZOWY TEST: 40 klatek → błąd spada wyraźnie (jak 1/√N)
    do {
        var st = DepthFusionState()
        for i in 0..<40 {
            let f = wallFrame(noise: 0.010, seed: UInt64(1000 + i * 7919))
            DepthFusion.add(frame: f, into: &st, minConfidence: 1)
        }
        let fused = DepthFusion.fused(from: st, minSamples: 2)
        r.check("fuzja 40 klatek: jest wynik", fused != nil, "")
        if let fused {
            let mm = fused.medianSigma * 1000
            // zmierzone: 3,4 mm po 40 klatkach (woksel 12 mm, szum 10 mm)
            r.check("fuzja 40 klatek: σ < 4 mm (błąd spada z liczbą klatek)", mm < 4.0,
                    String(format: "%.2f mm", mm))
            r.check("fuzja: uśrednianie faktycznie zachodzi (σ < szum pojedynczej klatki)",
                    mm < 10.0, String(format: "%.2f mm vs szum 10 mm", mm))
            r.check("fuzja: próbki > 40 tys.", fused.samples > 40_000, "= \(fused.samples)")
            r.check("fuzja: jakość opisana w mm", fused.qualityText.contains("mm"), fused.qualityText)
            // sanity: chmura w metrach wokół z = -2
            let zs = fused.positions.map { $0.z }
            let meanZ = zs.reduce(0, +) / Float(zs.count)
            r.check("fuzja: ściana tam, gdzie była (z ≈ -2 m)", abs(meanZ + 2.0) < 0.05,
                    String(format: "%.3f m", meanZ))
        }
    }

    // 2b) REGRESJA: więcej klatek MUSI dawać mniejsze σ.
    // Ten test złapał realny błąd: przy wokslu mniejszym od rozstawu pikseli
    // każdy piksel trafiał do własnego woksela (1,00 pkt/woksel) i σ nie malało.
    do {
        func sigmaAfter(_ frames: Int) -> Float? {
            var st = DepthFusionState()
            for i in 0..<frames {
                DepthFusion.add(frame: wallFrame(noise: 0.010, seed: UInt64(300 + i * 4099)),
                                into: &st, minConfidence: 1)
            }
            return DepthFusion.fused(from: st, minSamples: 2)?.medianSigma
        }
        let s10 = sigmaAfter(10)
        let s100 = sigmaAfter(100)
        r.check("regresja: σ po 100 klatkach < σ po 10 klatkach",
                (s10 != nil && s100 != nil) ? s100! < s10! : false,
                String(format: "%.2f → %.2f mm",
                       (s10 ?? 0) * 1000, (s100 ?? 0) * 1000))
        r.check("regresja: σ po 100 klatkach < 3 mm",
                (s100 ?? 99) < 0.003, String(format: "%.2f mm", (s100 ?? 0) * 1000))
    }

    // 3) odsiew: niska ufność i dystans poza zakresem nie wchodzą do fuzji
    do {
        var st = DepthFusionState()
        let lowConf = wallFrame(noise: 0.010, seed: 777, confidence: 0)
        let n = DepthFusion.add(frame: lowConf, into: &st, minConfidence: 1)
        r.check("odsiew: niska ufność odrzucona", n == 0, "= \(n)")
        r.check("odsiew: licznik odrzuceń rośnie", st.rejected > 0, "= \(st.rejected)")

        var st2 = DepthFusionState()
        let farWall = wallFrame(noise: 0.001, seed: 99, wallZ: -9.0)  // 9 m > maxDepth
        let n2 = DepthFusion.add(frame: farWall, into: &st2, minConfidence: 1)
        r.check("odsiew: dystans > 5 m odrzucony", n2 == 0, "= \(n2)")
    }

    // 4) determinizm fuzji
    do {
        var a = DepthFusionState()
        var b = DepthFusionState()
        for i in 0..<10 {
            let f = wallFrame(noise: 0.008, seed: UInt64(500 + i * 131))
            DepthFusion.add(frame: f, into: &a, minConfidence: 1)
            DepthFusion.add(frame: f, into: &b, minConfidence: 1)
        }
        let fa = DepthFusion.fused(from: a, minSamples: 1)
        let fb = DepthFusion.fused(from: b, minSamples: 1)
        r.check("fuzja: deterministyczna",
                fa?.count == fb?.count && fa?.medianSigma == fb?.medianSigma,
                "\(fa?.count ?? -1) vs \(fb?.count ?? -1)")
    }

    // 5) geometria rzutowania: oś optyczna trafia dokładnie w -Z
    do {
        let p = DepthFusion.worldPoint(
            x: 32, y: 24, depth: 2.0, fx: 200, fy: 200, cx: 32, cy: 24,
            transform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        )
        r.check("rzutowanie: środek obrazu → (0, 0, -2)",
                abs(p.x) < 1e-4 && abs(p.y) < 1e-4 && abs(p.z + 2.0) < 1e-4,
                String(format: "%.3f, %.3f, %.3f", p.x, p.y, p.z))

        let right = DepthFusion.worldPoint(
            x: 232, y: 24, depth: 2.0, fx: 200, fy: 200, cx: 32, cy: 24,
            transform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        )
        r.check("rzutowanie: piksel w prawo → +X", right.x > 1.9, String(format: "%.2f", right.x))

        // wiersz 0 to GÓRA obrazu → w świecie +Y (kamera patrzy w -Z, +Y w górę)
        let up = DepthFusion.worldPoint(
            x: 32, y: 0, depth: 2.0, fx: 200, fy: 200, cx: 32, cy: 24,
            transform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        )
        r.check("rzutowanie: góra obrazu → +Y świata", up.y > 0,
                String(format: "%.2f", up.y))

        // dolny wiersz → -Y
        let down = DepthFusion.worldPoint(
            x: 32, y: 47, depth: 2.0, fx: 200, fy: 200, cx: 32, cy: 24,
            transform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        )
        r.check("rzutowanie: dół obrazu → -Y świata", down.y < 0,
                String(format: "%.2f", down.y))
    }

    // 6) skalowanie intrinsics obraz → mapa głębi
    do {
        let s = DepthFusion.scaledIntrinsics(
            1500, 1500, 960, 720, from: 1920, to: 256, imageHeight: 1440, depthHeight: 192
        )
        r.check("intrinsics: fx skaluje się proporcjonalnie", abs(s.fx - 200) < 0.01,
                String(format: "%.1f", s.fx))
        r.check("intrinsics: punkt główny w środku mapy głębi", abs(s.cx - 128) < 0.01,
                String(format: "%.1f", s.cx))
    }

    // 7) niepewność rośnie z odległością (fizyka, nie zgadywanie)
    do {
        let near = DepthFusion.pointSigma(confidence: 2, depth: 1.0, fx: 200)
        let far = DepthFusion.pointSigma(confidence: 2, depth: 4.0, fx: 200)
        r.check("niepewność rośnie z odległością", far > near,
                String(format: "%.1f vs %.1f mm", near * 1000, far * 1000))
        let high = DepthFusion.pointSigma(confidence: 2, depth: 2.0, fx: 200)
        let medium = DepthFusion.pointSigma(confidence: 1, depth: 2.0, fx: 200)
        r.check("wysoka ufność dokładniejsza niż średnia", high < medium,
                String(format: "%.1f vs %.1f mm", high * 1000, medium * 1000))
    }

    print("\nLOD (poziom szczegółów)")
    do {
        let near = DetailLOD.level(distance: 10)
        let mid = DetailLOD.level(distance: 100)
        let far = DetailLOD.level(distance: 900)
        print("    10 m → \(near), 100 m → \(mid), 900 m → \(far)  (progi \(DetailLOD.fullDetailDistance)/\(DetailLOD.hideDistance) m)")
        r.check("LOD: z bliska pełny model", near == .full)
        r.check("LOD: w średniej odległości proxy", mid == .proxy)
        r.check("LOD: daleko ukryte", far == .hidden)
        r.check("LOD: próg pełnego detalu > 30 m", DetailLOD.fullDetailDistance > 30)
        r.check("LOD: proxy tańsze niż pełny model", DetailLOD.fullDetailDistance < DetailLOD.hideDistance)
    }

    // 8) niepewność trafia do pliku — bez tego σ ginęło przy eksporcie
    print("\nDokładność — niepewność w pliku PLY")
    do {
        var st = DepthFusionState()
        for i in 0..<30 {
            DepthFusion.add(frame: wallFrame(noise: 0.010, seed: UInt64(900 + i * 6151)),
                            into: &st, minConfidence: 1)
        }
        guard let fused = DepthFusion.fused(from: st, minSamples: 2) else {
            r.check("niepewność: fuzja dała wynik", false, "")
            return
        }
        let cloud = fused.cloud
        r.check("niepewność: chmura ją niesie",
                cloud.uncertainty?.count == cloud.count,
                "\(cloud.uncertainty?.count ?? -1)/\(cloud.count)")

        let data = ScanPLYWriter.data(for: cloud)
        let header = String(decoding: data.prefix(400), as: UTF8.self)
        r.check("PLY: nagłówek deklaruje sigma", header.contains("property float sigma"))
        // rekord 19 B = 3 float + 3 uchar + 1 float
        if let range = data.range(of: Data("end_header\n\n".utf8)) {
            let body = data.count - range.upperBound
            r.check("PLY: rekord 19 B z sigma", body == 19 * cloud.count,
                    "\(body) / \(19 * cloud.count)")
        }

        // odczyt tym samym parserem: dodatkowa właściwość nie może psuć współrzędnych
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("check-sigma.ply")
        do {
            try data.write(to: url)
            let back = try PLYParser.parse(contentsOf: url)
            r.check("PLY z sigma: parser czyta poprawnie", back.count == cloud.count,
                    "\(cloud.count) → \(back.count)")
            let s = back.bounds.max - back.bounds.min
            // syntetyczna ściana 64×48 px przy fx=200 i d=2 m ma ~0,64 × 0,48 m,
            // więc sprawdzamy tylko, że obrys jest sensowny i niezerowy
            r.check("PLY z sigma: obrys nienaruszony (0,4–0,8 m)",
                    s.x > 0.4 && s.x < 0.8, String(format: "%.2f m", s.x))
            try? FileManager.default.removeItem(at: url)
        } catch {
            r.check("PLY z sigma: obieg zamknięty", false, "\(error)")
        }

        let report = ScanPLYWriter.qualityReport(cloud)
        r.check("raport jakości: zawiera σ i wymiary",
                report?.contains("σ mediana") == true && report?.contains("mm") == true,
                report?.replacingOccurrences(of: "\n", with: " | ") ?? "nil")
    }

    runZoneChecks(r)
    runRoomModelChecks(r)
    runRoomMeshChecks(r)

    let passed = r.checks - r.failures
    print("\n\(passed)/\(r.checks) warunków spełnionych")
    if r.failures > 0 {
        print("NIEPOWODZENIE: \(r.failures)")
        exit(1)
    }
    print("OK")
}

if CommandLine.arguments.contains("--sweep") {
    runSweep()
} else {
    runChecks()
}
