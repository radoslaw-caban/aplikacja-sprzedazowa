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
    /// pierwszy krok: pytanie „jak określimy budynek?"
    @State private var showPlanMethod = false
    @State private var planStartMode: PlanEditorView.Mode? = nil
    @State private var planStartPresets = false
    @State private var planStartImport = false
    @State private var showZones = false
    @State private var zoneWall = 0
    @State private var showTextures = false
    @State private var showSettings = false
    @State private var showNewClient = false
    @State private var showContract = false
    @State private var showFPS = false
    @State private var showClientProjects = false
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
        .overlay(alignment: .topLeading) {
            if !locked {
                HStack(alignment: .top, spacing: 8) {
                    ClientSearchBar(
                        projects: model.projects,
                        currentName: ClientDirectory.displayName(model.current),
                        currentAddress: model.current.order?.address ?? "",
                        workingSet: model.workingSet,
                        onOpen: { id in
                            if let index = model.projects.firstIndex(where: { $0.id == id }) {
                                model.selectProject(index)
                            }
                        },
                        onToggleWorking: { model.toggleWorkingSet($0) },
                        onNewClient: { showNewClient = true }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24).onEnded { value in
                            guard model.workingSet.count > 1 else { return }
                            if value.translation.height > 40 { model.switchWorking(step: 1) }
                            if value.translation.height < -40 { model.switchWorking(step: -1) }
                        }
                    )

                    if model.workingSet.count > 1 {
                        VStack(spacing: 4) {
                            Button { model.switchWorking(step: -1) } label: {
                                Image(systemName: "chevron.up").font(.caption.weight(.bold))
                            }
                            Button { model.switchWorking(step: 1) } label: {
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 14)
            }
        }
        .planPresentation(isPresented: $showPlanMethod) {
            PlanMethodChooser(
                onPick: { method in
                    showPlanMethod = false
                    planStartMode = nil
                    planStartPresets = false
                    planStartImport = false
                    switch method {
                    case .presets:
                        planStartPresets = true
                        planStartMode = .dimensions
                    case .dimensions:
                        planStartMode = .dimensions
                    case .rectangle:
                        planStartMode = .rectangle
                    case .lines:
                        planStartMode = .lines
                    case .image:
                        planStartMode = .rectangle
                        planStartImport = true
                    case .scan:
                        showScan = true
                        return
                    }
                    planDraft = model.currentPlan
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPlan = true
                    }
                },
                onCancel: { showPlanMethod = false },
                projectName: ClientDirectory.displayName(model.current)
            )
        }
        .planPresentation(isPresented: $showFPS) {
            FirstPersonView(
                room: model.current.room,
                cabinets: model.current.cabinets,
                wallColor: model.current.wallColor,
                onExit: { showFPS = false },
                onAddElement: { id, element in
                    model.addElement(to: id, element: element)
                },
                onWallColor: { hex in
                    model.updateWallColor(hex)
                },
                onSaveCabinet: { cabinet in
                    model.updateCabinet(cabinet)
                },
                onDeleteCabinet: { id in
                    model.deleteCabinet(id)
                }
            )
        }
        .planPresentation(isPresented: $showNewClient) {
            NewClientFlow(startStep: UserDefaults.standard.integer(forKey: "demoIntroStep")) { firstName, lastName, address, phone, email in
                let project = model.createClient(firstName: firstName, lastName: lastName,
                                                 address: address, phone: phone, email: email)
                model.addToWorkingSet(project.id)
                UserDefaults.standard.set(true, forKey: "introDone")
                // po pytaniach: wybór metody planu, potem edytor i 3D
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 550_000_000)
                    planDraft = model.currentPlan
                    planStartMode = nil
                    planStartPresets = false
                    planStartImport = false
                    showPlanMethod = true
                }
            }
        }
        .sheet(isPresented: $showContract) {
            ContractSheet(project: model.current) { file in
                model.signContract(signatureFile: file)
            }
        }
        .sheet(isPresented: $showClientProjects) {
            ClientProjectsSheet(model: model, onClose: { showClientProjects = false })
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
                startMode: planStartMode,
                startWithPresets: planStartPresets,
                startWithImport: planStartImport,
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
            // hak diagnostyczny: otwórz kartotekę o zadanym indeksie
            if UserDefaults.standard.object(forKey: "demoClient") != nil {
                let index = UserDefaults.standard.integer(forKey: "demoClient")
                if model.projects.indices.contains(index) { model.selectProject(index) }
            }

            // hak diagnostyczny: widok FPS na podjeździe
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demoZoneInsert") {
                // weryfikacja 3D: jedna strefa gotowania, bez otwierania kreatora
                for z in model.currentZones { model.deleteZone(z.id) }
                let z = model.addZone(kind: .kitchenCook, wallIndex: 0)
                if UserDefaults.standard.bool(forKey: "demoZoneFinal") {
                    model.finalizeZone(z.id)
                }
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
            if UserDefaults.standard.bool(forKey: "demoFPS") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                showFPS = true
            }

            // haki diagnostyczne: umowa i kreator klienta
            if UserDefaults.standard.bool(forKey: "demoContract") {
                try? await Task.sleep(nanoseconds: 700_000_000)
                showContract = true
            }
            if UserDefaults.standard.bool(forKey: "demoNewClient") {
                try? await Task.sleep(nanoseconds: 700_000_000)
                showNewClient = true
            }

            // kartoteki klientów z tabeli zamówień (raz, brakujące)
            let added = model.seedClients()
            if added > 0 { NSLog("[dane] dodano %d kartotek klientów", added) }

            if UserDefaults.standard.bool(forKey: "demoTextures") {
                try? await Task.sleep(nanoseconds: 800_000_000)
                showTextures = true
            }
            // hak diagnostyczny: od razu edytor w zadanym trybie (bez pytania)
            if let method = UserDefaults.standard.string(forKey: "demoPlanMethod") {
                switch method {
                case "dimensions": planStartMode = .dimensions
                case "rectangle": planStartMode = .rectangle
                case "lines": planStartMode = .lines
                case "presets": planStartMode = .dimensions; planStartPresets = true
                case "image": planStartMode = .rectangle; planStartImport = true
                default: planStartMode = .dimensions
                }
                planDraft = model.currentPlan
                try? await Task.sleep(nanoseconds: 500_000_000)
                showPlan = true
            }

            // Start aplikacji: najpierw wstęp (chmura punktów, logo) i pytania
            // o dane klienta — dopiero potem pytanie o metodę planu.
            let introDone = UserDefaults.standard.bool(forKey: "introDone")
            if !introDone, !showNewClient {
                try? await Task.sleep(nanoseconds: 500_000_000)
                showNewClient = true
            } else if UserDefaults.standard.object(forKey: "startWithPlan") == nil
                        || UserDefaults.standard.bool(forKey: "startWithPlan") {
                if !showPlan, !showPlanMethod {
                    planDraft = model.currentPlan
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    showPlanMethod = true
                }
            }
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

    /// Podpis wiersza: data dostawy i status, jeśli kartoteka ma zamówienie.
    private func projectSubtitle(_ project: Project) -> String {
        guard let order = project.order, let date = order.deliveryDate else {
            return "\(project.cabinets.count) szafek · \(project.documents.count) dok."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        let status = order.status ?? "Do dostarczenia"
        return "\(status) · \(formatter.string(from: date))"
    }

    /// Kwota w formacie „11 500 zł".
    private func priceLabel(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        let text = formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(text) zł"
    }

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
                                Text(projectSubtitle(project))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let order = project.order, order.price > 0 {
                                Text(priceLabel(order.price))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
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
                    openDocuments: { showDocuments = true },
                    openContract: { showContract = true },
                    openClientProjects: { showClientProjects = true }
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
            Button { showFPS = true } label: {
                Label("Wejdź do domu", systemImage: "figure.walk")
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
