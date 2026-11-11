import SwiftUI
import KitchenCore
import KitchenScene

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct KitchenApp: App {
    @State private var model = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView(model: model)
                #if os(macOS)
                .frame(minWidth: 980, minHeight: 640)
                #endif
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    @State private var showDocuments = false
    @State private var interiorView = false   // start: willa w otoczeniu (klient najpierw widzi dom)
    /// bryła domu z chmury punktów (skan X9) zamiast willi proceduralnej
    @State private var useScanHouse = true
    /// nakładka: chmura punktów na zbudowanym domu
    /// (domyślnie wyłączona; `defaults write ... showScanCloud -bool YES`
    /// pozwala zweryfikować dopasowanie bez dotykania ekranu)
    @State private var showScanCloud = UserDefaults.standard.bool(forKey: "showScanCloud")
    @State private var showScan = false
    @State private var showPlan = false
    @State private var showZones = false
    @State private var zoneWall = 0
    @State private var showTextures = false
    @State private var showSettings = false
    @State private var planDraft = FloorPlan.rectangle()
    /// Projekt zablokowany: na ekranie tylko 3D i kłódka (przeciąganie przesuwa).
    @State private var locked = true
    /// Menu wysunięte z lewej krawędzi.
    @State private var drawerOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Pole robocze: zablokowany = tylko 3D + kłódka,
            // odblokowany = pełny interfejs (zakładki, formularze, paski).
            if locked {
                LockedWorkspace(model: model, interiorView: interiorView,
                                scanPlan: useScanHouse ? ScanPlan.bundled() : nil,
                                showScanCloud: showScanCloud,
                                locked: $locked)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                detail
            }

            // Menu wyciągane z lewej krawędzi — zamiast stałego panelu.
            if drawerOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { drawerOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
                drawerPanel
                    .transition(.move(edge: .leading))
                    .zIndex(3)
            }
            edgeHandle
                .zIndex(4)
        }
        .animation(.easeInOut(duration: 0.22), value: drawerOpen)
        .animation(.easeInOut(duration: 0.2), value: locked)
        .sheet(isPresented: $showDocuments) {
            DocumentsSheet(model: model)
        }
        .planPresentation(isPresented: $showPlan) {
            PlanEditorView(
                plan: $planDraft,
                onChange: { newPlan in
                    model.updatePlan(newPlan)
                },
                onFillWall: { wallIndex in
                    fillWall(wallIndex)
                },
                onZoneWall: { wallIndex in
                    zoneWall = wallIndex
                    showPlan = false
                    // najpierw zamknij plan, potem otwórz kreator stref
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        showZones = true
                    }
                },
                onOpen3D: {
                    showPlan = false
                }
            )
            #if os(iOS)
            .presentationSizing(.page)
            #endif
        }
        .sheet(isPresented: $showZones) {
            ZoneDesignerView(model: model, initialWall: zoneWall)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTextures) {
            TextureLibraryView { texture in
                applyTexture(named: texture.name)
            }
        }
        .sheet(isPresented: $showScan) {
            #if os(iOS)
            RoomScanSheet(projectName: model.current.name) { cloud in
                showScan = false
                if let cloud { model.addScan(cloud) }
            }
            #else
            Text("Skanowanie LiDAR jest dostępne tylko na iPadzie.")
                .padding(40)
            #endif
        }
        .task {
            if UserDefaults.standard.bool(forKey: "showDocuments") { showDocuments = true }
            if UserDefaults.standard.bool(forKey: "extView") { interiorView = false }
            #if os(iOS)
            if UserDefaults.standard.bool(forKey: "demoDocuments") {
                // tworzy prawdziwy PDF i przeprowadza go przez import dokumentów
                let pdfURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Umowa Kowalski.pdf")
                try? UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).writePDF(to: pdfURL) { ctx in
                    ctx.beginPage()
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28)]
                    "Umowa 2026/11".draw(at: CGPoint(x: 60, y: 80), withAttributes: attrs)
                    "Kuchnia Kowalski — wartość 24 800 zł".draw(at: CGPoint(x: 60, y: 140), withAttributes: attrs)
                }
                let added = model.importDocuments(from: [pdfURL])
                print("[ui] dokumenty dodane: \(added), razem \(model.documents.count)")
            }
            #endif
            if UserDefaults.standard.bool(forKey: "demoUnlocked") {
                // weryfikacja trybu odblokowanego (obrót projektu + pełny interfejs)
                locked = false
            }
            if UserDefaults.standard.bool(forKey: "demoDrawer") {
                // weryfikacja menu wysuwanego z krawędzi
                drawerOpen = true
            }
            if UserDefaults.standard.bool(forKey: "demoTextures") {
                try? await Task.sleep(nanoseconds: 800_000_000)
                showTextures = true
            }
            // Start aplikacji = edycja planu, nie oglądanie bryły domu.
            if UserDefaults.standard.object(forKey: "startWithPlan") == nil || UserDefaults.standard.bool(forKey: "startWithPlan") {
                if !showPlan {
                    planDraft = model.currentPlan
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    showPlan = true
                }
            }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demoZoneInsert") {
                // weryfikacja 3D: jedna strefa gotowania, bez otwierania kreatora
                for z in model.currentZones { model.deleteZone(z.id) }
                _ = model.addZone(kind: .kitchenCook, wallIndex: 3)
                print("[ui] strefa wstawiona: \(model.current.cabinets.count) szafek, stref \(model.currentZones.count)")
            }
            if UserDefaults.standard.bool(forKey: "demoZones") {
                locked = false
                zoneWall = 0
                try? await Task.sleep(nanoseconds: 900_000_000)
                showZones = true
                print("[ui] strefy otwarte: ściana 1, stref \(model.currentZones.count)")
            }
            #endif
            if UserDefaults.standard.bool(forKey: "demoPlan") {
                // weryfikacja widoku mapy bez dotykania ekranu
                planDraft = model.currentPlan
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showPlan = true
                print("[ui] plan otwarty: \(planDraft.wallCount) ścian, \(planDraft.areaM2) m²")
            }
            if UserDefaults.standard.bool(forKey: "demoSwipe") {
                // weryfikacja gestów bez dotykania ekranu
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                model.addProject(name: "Projekt 2")
                model.switchProject(step: -1)
                print("[ui] projekt: \(model.current.name)")
                model.switchDocument(step: 1)
                print("[ui] dokument: \(model.status ?? "-")")
            }
        }
    }

    // MARK: - panel boczny

    private var sidebar: some View {
        List {
            Section("Projekty") {
                ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        model.selectProject(index)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name).font(.callout)
                                Text("\(project.cabinets.count) szafek · \(project.documents.count) dok.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == model.currentIndex {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
                Button { model.addProject() } label: {
                    Label("Nowy projekt", systemImage: "plus")
                }
            }

            Section("Projekt") {
                Button {
                    zoneWall = 0
                    showZones = true
                    drawerOpen = false
                } label: {
                    Label("Strefy zabudowy (auto-projekt)", systemImage: "sparkles")
                }
            }

            Section("Biblioteka · podblatowe") {
                ForEach(Library.base) { t in Button { add(t) } label: { templateRow(t) } }
            }
            Section("Biblioteka · wiszące") {
                ForEach(Library.wall) { t in Button { add(t) } label: { templateRow(t) } }
            }
            Section("Biblioteka · stojące") {
                ForEach(Library.tall) { t in Button { add(t) } label: { templateRow(t) } }
            }
            Section("Skan pomieszczenia") {
                Button { showScan = true } label: {
                    Label("Skanuj LiDAR-em", systemImage: "sensor.tag.radiowaves.forward")
                }
                .disabled(!RoomScanSession.isSupported)
                if let doc = model.scanDocument {
                    Button { model.loadScan(from: doc) } label: {
                        Label("Wczytaj: \(doc.name)", systemImage: "cube.transparent")
                            .lineLimit(1)
                    }
                }
            }

            Section("Dokumenty klienta") {
                ForEach(Array(model.documents.enumerated()), id: \.element.id) { index, doc in
                    Button { model.openDocument(index) } label: {
                        Label(doc.name, systemImage: doc.kind.icon)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }
                Button { showDocuments = true } label: {
                    Label("Dodaj dokument…", systemImage: "doc.badge.plus")
                }
            }
        }
        .navigationTitle("Konfigurator")
        #if os(macOS)
        .frame(minWidth: 260)
        #endif
    }

    private func templateRow(_ t: Library.Template) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.name).font(.callout)
            Text(t.summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Nakłada teksturę (nazwa pliku) na fronty wszystkich szafek projektu.
    private func applyTexture(named name: String) {
        var cabinets = model.current.cabinets
        guard !cabinets.isEmpty else {
            model.status = "Brak szafek — najpierw wstaw zabudowę"
            return
        }
        for index in cabinets.indices {
            cabinets[index].texture = name
        }
        model.updateCabinets(cabinets)
        model.persist()
        model.status = "Tekstura frontów: \(name)"
    }

    /// Klik na ścianę → program sam rozstawia szafki o równych szerokościach,
    /// z zaślepkami 18 mm przy narożnikach, i wstawia je do projektu.
    private func fillWall(_ index: Int) {
        let result = WallFill.fill(plan: planDraft, wallIndex: index)
        guard !result.cabinets.isEmpty || !result.panels.isEmpty else {
            model.status = result.note
            return
        }

        // podmieniamy poprzednią automatyczną zabudowę tej ściany, jeśli była
        var cabinets = model.current.cabinets.filter { cabinet in
            !(cabinet.name.hasPrefix("Szafka ") || cabinet.name.hasPrefix("Zaślepka "))
        }
        cabinets.append(contentsOf: result.cabinets)
        cabinets.append(contentsOf: result.panels)
        model.updateCabinets(cabinets)
        model.persist()
        model.status = "Ściana \(index + 1): " + result.note
    }

    private func add(_ t: Library.Template) {
        var cabinets = model.current.cabinets
        let new = Library.make(t)
        if let placed = Generator.placeNext(to: cabinets, new: new) {
            cabinets.append(placed)
        } else {
            cabinets.append(new)
        }
        model.updateCabinets(cabinets)
        model.persist()
    }

    // MARK: - pole robocze

    private var detail: some View {
        VStack(spacing: 0) {
            if let doc = model.currentDocument {
                documentViewer(doc)
            } else {
                // Przepływ według diagramu: ekrany przewijane poziomo,
                // start na „Szczegółach zamówienia".
                OrderFlowView(
                    model: model,
                    scanPlan: useScanHouse ? ScanPlan.bundled() : nil,
                    interiorView: $interiorView,
                    locked: $locked,
                    openPlan: {
                        planDraft = model.currentPlan
                        showPlan = true
                    },
                    openScan: { showScan = true },
                    openDocuments: { showDocuments = true }
                )
            }
            bottomBar
        }
    }

    // MARK: - menu z krawędzi

    /// Panel projektów i biblioteki wysuwany z lewej krawędzi.
    /// Stały pasek boczny zjadał miejsce na pole robocze — teraz jest schowany.
    private var drawerPanel: some View {
        NavigationStack { sidebar }
            .frame(width: 340)
            .background(.regularMaterial)
            .ignoresSafeArea(edges: .vertical)
    }

    /// Uchwyt przy lewej krawędzi: przeciągnięcie w prawo otwiera menu.
    private var edgeHandle: some View {
        HStack {
            ZStack(alignment: .center) {
                Rectangle().fill(.clear)
                Capsule()
                    .fill(.secondary.opacity(0.30))
                    .frame(width: 4, height: 84)
            }
            .frame(width: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.width > 36 { drawerOpen = true }
                    }
            )
            .help("Przeciągnij w prawo, aby wysunąć menu")
            Spacer()
        }
    }

    private func documentViewer(_ doc: ClientDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: doc.kind.icon).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.name).font(.callout).lineLimit(1)
                    Text("\(doc.kind.label) · \(doc.sizeLabel)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let i = model.documentIndex {
                    Text("\(i + 1)/\(model.documents.count)").font(.caption).foregroundStyle(.secondary)
                }
                Button { model.switchDocument(step: -1) } label: { Image(systemName: "chevron.left") }
                Button { model.switchDocument(step: 1) } label: { Image(systemName: "chevron.right") }
                Button { model.closeDocument() } label: { Image(systemName: "xmark") }
            }
            .padding(12)

            #if os(iOS)
            QuickLookView(url: model.fileURL(for: doc)) { model.closeDocument() }
            #else
            VStack(spacing: 12) {
                Image(systemName: doc.kind.icon).font(.system(size: 48)).foregroundStyle(.secondary)
                Text(doc.name).font(.title3)
                Text(model.fileURL(for: doc).path).font(.caption).foregroundStyle(.secondary)
                Button("Otwórz w systemie") {
                    NSWorkspace.shared.open(model.fileURL(for: doc))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(model.current.name).font(.callout)
            Text("\(model.current.cabinets.count) szafek").font(.callout).foregroundStyle(.secondary)
            if let status = model.status {
                Text("· \(status)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                planDraft = model.currentPlan
                showPlan = true
            } label: {
                Label("Plan", systemImage: "map")
            }
            .help("Plan domu: rysuj kreskami i zmieniaj długości ścian")
            Button {
                interiorView.toggle()
            } label: {
                Label(interiorView ? "Wnętrze" : "Otoczenie",
                      systemImage: interiorView ? "house" : "tree")
            }
            Button {
                useScanHouse.toggle()
            } label: {
                Label(useScanHouse ? "Dom ze skanu" : "Willa",
                      systemImage: useScanHouse ? "cube.transparent" : "building.2")
            }
            .help("Bryła domu z chmury punktów X9 (ScanPlan) albo willa proceduralna")
            Button {
                showScanCloud.toggle()
            } label: {
                Label(showScanCloud ? "Chmura ON" : "Chmura",
                      systemImage: "circle.grid.3x3")
            }
            .disabled(ScanPlan.bundled() == nil)
            .help("Nałóż chmurę punktów 1:1 na dom — widać, czy ściany pokrywają się ze skanem")
            Button { showScan = true } label: {
                Label("Skanuj", systemImage: "sensor.tag.radiowaves.forward")
            }
            .disabled(!RoomScanSession.isSupported)
            .help(RoomScanSession.isSupported ? "Skan pomieszczenia LiDAR-em" : "Brak LiDAR-u na tym urządzeniu")
            if model.scan != nil {
                Button { model.clearScan() } label: {
                    Label("Usuń skan", systemImage: "xmark.circle")
                }
            }
            Button { showTextures = true } label: {
                Label("Tekstury", systemImage: "photo.on.rectangle.angled")
            }
            Button { showSettings = true } label: {
                Label("Ustawienia", systemImage: "gear")
            }
            Button { showDocuments = true } label: {
                Label("Dokumenty", systemImage: "folder")
            }
            Button { model.addProject() } label: {
                Label("Nowy projekt", systemImage: "plus.rectangle.on.folder")
            }
            Button("Wyczyść szafki") {
                model.updateCabinets([])
                model.persist()
            }
        }
        .padding(12)
        .background(.bar)
    }
}

private extension View {
    /// Plan to główny widok pracy — na iPadzie pełny ekran, na Macu arkusz
    /// (macOS nie ma `fullScreenCover`).
    @ViewBuilder
    func planPresentation<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}
