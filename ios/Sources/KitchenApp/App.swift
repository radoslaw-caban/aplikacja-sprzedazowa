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
                SceneView(cabinets: cabinets, room: room, scan: showScan ? scan : nil, transform: transform, surfaceEntity: surfaceEntity, showPoints: showPoints)

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
            autoAlign()
            return
        }
        showScan = true
    }

    /// Auto-dopasowanie: skala z obrytu, środek na środku pokoju, podłoga na 0.
    private func autoAlign() {
        guard let scan else { return }
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
        Task { await rebuildSurface() }
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

    /// Wokselizacja w tle (czysta funkcja), encja budowana raz na wątku głównym.
    private func rebuildSurface() async {
        guard let scan else { surfaceEntity = nil; return }
        let t = transform
        let geo = await Task.detached(priority: .userInitiated) {
            VoxelSurfaceBuilder.geometry(scan, transform: t)
        }.value
        surfaceEntity = VoxelSurfaceBuilder.makeEntity(geo)
        status = "powierzchnia: \(geo.voxelCount) wokseli"
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
