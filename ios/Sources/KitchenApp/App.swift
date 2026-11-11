import SwiftUI
import KitchenCore
import KitchenScene

@main
struct KitchenApp: App {
    @State private var cabinets: [Cabinet] = [
        Library.make(Library.base[0], at: -1200, z: -2200),
        Library.make(Library.base[1], at: -600, z: -2200),
    ]

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView(cabinets: $cabinets)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
    }
}

struct ContentView: View {
    @Binding var cabinets: [Cabinet]

    @State private var scan: PointCloud?
    @State private var showScan = false
    @State private var loadingScan = false
    @State private var status: String?
    @State private var room = Room(width: 5000, depth: 5000, height: 2600)
    @State private var transform = ScanTransform()
    @State private var rotationDeg: Double = 0
    @State private var scale: Double = 1
    @State private var surfaceEntity: ScanSurface?
    @State private var showPoints = false
    @State private var grid: VoxelGrid?
    @State private var pickedPoints: [SIMD3<Float>] = []
    @State private var picking = false
    @State private var realDistanceMM: String = ""

    var body: some View {
        NavigationSplitView {
            List {
                Section("Szafki podblatowe") {
                    ForEach(Library.base) { t in
                        Button { add(t) } label: { row(t) }
                    }
                }
                Section("Wiszące") {
                    ForEach(Library.wall) { t in
                        Button { add(t) } label: { row(t) }
                    }
                }
                Section("Stojące") {
                    ForEach(Library.tall) { t in
                        Button { add(t) } label: { row(t) }
                    }
                }

                Section("Skan i pomieszczenie") {
                    Button {
                        Task { await toggleScan() }
                    } label: {
                        Label(showScan ? "Skan: włączony" : "Skan: wyłączony", systemImage: "cube.transparent")
                    }
                    if showScan {
                        Button {
                            autoAlign()
                        } label: {
                            Label("Auto-dopasuj do pokoju", systemImage: "square.dashed")
                        }
                        Toggle("Pokaż chmurę punktów", isOn: $showPoints)
                        Button {
                            picking.toggle()
                            status = picking ? "dotknij 3 narożników w skanie" : nil
                        } label: {
                            Label(picking ? "Wskazywanie: WŁ" : "Wskaż punkty skanu",
                                  systemImage: "hand.tap")
                        }
                        if !pickedPoints.isEmpty {
                            ForEach(Array(pickedPoints.enumerated()), id: \.offset) { i, p in
                                Text(String(format: "P%d: %.0f, %.0f, %.0f mm", i + 1, p.x * 1000, p.y * 1000, p.z * 1000))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if pickedPoints.count >= 2 {
                                HStack {
                                    Button("Ściana → X") { alignWall(axis: .x) }
                                    Button("Ściana → Z") { alignWall(axis: .z) }
                                }
                                TextField("realna długość ściany [mm]", text: $realDistanceMM)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button("Wyczyść punkty") { pickedPoints.removeAll() }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Obrót: \(Int(rotationDeg))°").font(.caption)
                            Slider(value: $rotationDeg, in: 0...360, step: 1) { _ in
                                applyTransform()
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "Skala: %.2f", scale)).font(.caption)
                            Slider(value: $scale, in: 0.3...2.0, step: 0.01) { _ in
                                applyTransform()
                            }
                        }
                        Stepper("Odsunięcie X: \(Int(transform.offset.x * 1000)) mm") {
                            transform.offset.x += 0.1
                        } onDecrement: {
                            transform.offset.x -= 0.1
                        }
                        Stepper("Odsunięcie Z: \(Int(transform.offset.z * 1000)) mm") {
                            transform.offset.z += 0.1
                        } onDecrement: {
                            transform.offset.z -= 0.1
                        }
                    }
                    Text("\(room.name): \(Int(room.width)) × \(Int(room.depth)) × \(Int(room.height)) mm · \(String(format: "%.1f", room.area)) m²")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Biblioteka")
            #if os(macOS)
            .frame(minWidth: 250)
            #endif
        } detail: {
            VStack(spacing: 0) {
                SceneView(cabinets: cabinets, room: room, scan: showScan ? scan : nil, transform: transform, surfaceEntity: surfaceEntity, showPoints: showPoints, picking: picking,
                           onPick: { point, size in handlePick(point, size) })

                HStack(spacing: 12) {
                    Text("\(cabinets.count) szafek").font(.callout)
                    if let status {
                        Text("· \(status)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await toggleScan() }
                    } label: {
                        Label(showScan ? "Skan WŁ" : "Skan WYŁ", systemImage: "cube.transparent")
                    }
                    .disabled(loadingScan)
                    Button("Wyczyść") { cabinets.removeAll() }
                }
                .padding(12)
            }
        }
        .task {
            // do automatycznych zrzutów: -showScan 1
            if UserDefaults.standard.bool(forKey: "showScan") {
                await toggleScan()
            }
            // test zaczepiony o kamerę: 3 syntetyczne dotknięcia (środek, lewo, prawo)
            if UserDefaults.standard.bool(forKey: "pickTest") {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                let size = CGSize(width: 1000, height: 700)
                for p in [CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.3, y: 0.55), CGPoint(x: 0.7, y: 0.55)] {
                    handlePick(p, size)
                    print("[pick] \(status ?? "-")")
                }
                if UserDefaults.standard.bool(forKey: "alignTest") {
                    alignWall(axis: .x)
                    print("[pick] po wyrównaniu: \(status ?? "-")")
                    let a = transform.apply(transform.inverseApply(pickedPoints[0]))
                    print(String(format: "[pick] kontrola punktu 1: %.3f %.3f %.3f", a.x, a.y, a.z))
                }
            }
        }
    }

    private func row(_ t: Library.Template) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.name).font(.callout)
            Text(t.summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add(_ t: Library.Template) {
        let new = Library.make(t)
        if let placed = Generator.placeNext(to: cabinets, new: new) {
            cabinets.append(placed)
        } else {
            cabinets.append(new)
        }
    }

    /// Skan (PLY) wczytujemy raz, w tle; potem tylko przełączamy widoczność.
    private func toggleScan() async {
        if showScan { showScan = false; return }
        if scan == nil {
            loadingScan = true
            status = "wczytuję skan…"
            let loaded = await Task.detached(priority: .userInitiated) { () -> (PointCloud, String)? in
                guard let url = Self.scanURL() else { return nil }
                let started = Date()
                guard let cloud = try? PLYParser.parse(contentsOf: url) else { return nil }
                let seconds = Date().timeIntervalSince(started)
                return (cloud, String(format: "%.2f mln pkt w %.1f s", Double(cloud.count) / 1e6, seconds))
            }.value
            loadingScan = false
            guard let loaded else {
                status = "brak pliku skanu"
                return
            }
            scan = loaded.0
            status = loaded.1
            showScan = true
            autoAlign(cloud: loaded.0)
            return
        }
        showScan = true
    }

    /// Auto-dopasowanie: skala z obrytu, środek na środku pokoju, podłoga na 0.
    private func autoAlign(cloud: PointCloud? = nil) {
        guard let scan = cloud ?? self.scan else { return }
        let b = scan.robustBounds()
        let k = scan.unitScaleToMeters
        let fitted = ScanTransform.autoFit(
            cloudMin: b.min * k,
            cloudMax: b.max * k,
            room: room,
            rotationDeg: rotationDeg
        )
        transform = fitted
        scale = fitted.scale
        status = String(format: "skan dopasowany (skala %.2f)", fitted.scale)
        Task { await rebuildSurface(cloud: scan) }
    }

    /// Suwaki obrotu i skali przeliczają transformację od nowa (z zachowaniem auto-dopasowania).
    private func applyTransform() {
        guard let scan else { return }
        let b = scan.robustBounds()
        let k = scan.unitScaleToMeters
        var fitted = ScanTransform.autoFit(
            cloudMin: b.min * k,
            cloudMax: b.max * k,
            room: room,
            rotationDeg: rotationDeg
        )
        fitted.scale *= scale
        fitted.offset.y *= scale
        transform = fitted
        Task { await rebuildSurface() }
    }

    /// Powierzchnia w tle (surface nets), encja budowana raz na wątku głównym.
    private func rebuildSurface(cloud: PointCloud? = nil) async {
        guard let scan = cloud ?? self.scan else { surfaceEntity = nil; return }
        let t = transform
        let t0 = Date()
        status = "liczę powierzchnię skanu…"
        let built = await Task.detached(priority: .userInitiated) { () -> (VoxelSurfaceBuilder.Geometry, VoxelGrid) in
            var opts = VoxelSurfaceBuilder.Options()
            opts.maxPoints = 150_000
            opts.cell = 0.03
            let geo = VoxelSurfaceBuilder.geometry(scan, transform: t, options: opts)
            let k = scan.unitScaleToMeters
            let dec = scan.decimated(maxPoints: 150_000)
            let pts = dec.positions.map { t.apply($0 * k) }
            return (geo, VoxelGrid(points: pts, cellSize: 0.05))
        }.value
        let geo = built.0
        grid = built.1
        surfaceEntity = VoxelSurfaceBuilder.makeEntity(geo)
        status = String(format: "powierzchnia: %d wokseli, %d trójkątów (%.1f s)",
                        geo.voxelCount, geo.buckets.reduce(0) { $0 + $1.indices.count / 3 },
                        Date().timeIntervalSince(t0))
    }

    /// Dotknięcie w scenie → promień z kamery → pierwszy woksel skanu.
    private func handlePick(_ point: CGPoint, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard let grid else {
            status = "siatka skanu jeszcze się liczy…"
            return
        }
        let aspect = Float(size.width / size.height)
        let bounds = surfaceBounds
        let cam = PreviewCamera.make(room: room, scanBounds: bounds)
        let ray = cam.ray(normalizedPoint: point, aspect: aspect)
        guard let hit = grid.firstHit(origin: ray.origin, direction: ray.direction) else {
            status = "nie trafiłem w skan — dotknij ściany"
            return
        }
        if pickedPoints.count >= 3 { pickedPoints.removeAll() }
        pickedPoints.append(hit)
        status = String(format: "punkt %d: %.0f, %.0f, %.0f mm", pickedPoints.count, hit.x * 1000, hit.y * 1000, hit.z * 1000)
    }

    /// Wyrównanie ściany: dwa wskazane punkty + opcjonalna realna długość.
    private func alignWall(axis: ScanTransform.Axis) {
        guard pickedPoints.count >= 2 else { return }
        // punkty są we współrzędnych sceny — wracamy do układu chmury
        let p1 = transform.inverseApply(pickedPoints[0])
        let p2 = transform.inverseApply(pickedPoints[1])
        let real = Double(realDistanceMM).map { $0 / 1000 }
        transform = transform.aligningWall(from: p1, to: p2, axis: axis, realDistanceMeters: real)
        rotationDeg = transform.rotationDeg.truncatingRemainder(dividingBy: 360)
        scale = 1
        status = String(format: "ściana wyrównana (obrót %.0f°, skala %.2f)", transform.rotationDeg, transform.scale)
        Task { await rebuildSurface() }
    }

    /// Obrys skanu po transformacji — musi być ten sam, co w scenie.
    private var surfaceBounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let scan else { return nil }
        let k = scan.unitScaleToMeters
        let b = scan.robustBounds()
        return transform.transformedBounds(min: b.min * k, max: b.max * k)
    }

    /// W aplikacji: z bundle. W `swift run` na Macu: z repo.
    nonisolated static func scanURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "dom-chmura", withExtension: "ply") {
            return bundled
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in ["../app/public/dom-chmura.ply", "app/public/dom-chmura.ply"] {
            let url = cwd.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
