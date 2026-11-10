import SwiftUI
import KitchenCore
import KitchenScene

@main
struct KitchenApp: App {
    @State private var cabinets: [Cabinet] = [
        Library.make(Library.base[0], at: -1200, z: -2200),
        Library.make(Library.base[1], at: -600, z: -2200),
    ]

    var body: some Scene {
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
            }
            .navigationTitle("Biblioteka")
            #if os(macOS)
            .frame(minWidth: 250)
            #endif
        } detail: {
            VStack(spacing: 0) {
                SceneView(cabinets: cabinets, scan: showScan ? scan : nil)

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
        }
        showScan = true
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
