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
    /// Warstwa skanu (chmura X9 / z iPada) — włączana NIEZALEŻNIE od budynku.
    @State private var showScanLayer = true
    /// Warstwa budynku (ściany, podłoga, sufit) — niezależnie od skanu.
    @State private var showBuildingLayer = true
    @State private var showScan = false
    @State private var showPlan = false
    /// pierwszy krok: pytanie „jak określimy budynek?"
    @State private var showPlanMethod = false
    @State private var planStartMode: PlanEditorView.Mode? = nil
    @State private var planStartPresets = false
    @State private var planStartImport = false
    @State private var showZones = false
    @State private var showCutouts = false
    @State private var showCabinets = false
    @State private var zoneWall = 0
    @State private var showTextures = false
    @State private var showSettings = false
    @State private var showNewClient = false
    @State private var showContract = false
    @State private var showFPS = false
    @State private var showViewOptions = false
    @State private var showClientProjects = false
    @State private var planDraft = FloorPlan.rectangle()
    /// Projekt zablokowany: na ekranie tylko 3D i kłódka (przeciąganie przesuwa).
    @State private var locked = true
    /// Menu wysunięte z lewej krawędzi.
    @State private var drawerOpen = false
    /// Pasek nawigacji wysunięty z DOLNEJ krawędzi.
    ///
    /// POPRAWKA (zgłoszony błąd): górny pasek zajmował miejsce i kolidował
    /// z gestami sceny 3D — próba obrócenia projektu w górnej części ekranu
    /// przełączała klientów. Teraz jest schowany w dolnej krawędzi i wysuwa
    /// się tylko wtedy, gdy użytkownik go wyciągnie.
    @State private var navOpen = false

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
        // Pasek nawigacji na DOLNEJ krawędzi (wysuwany), zamiast overlay u góry.
        .overlay(alignment: .bottom) {
            if !locked {
                bottomNavigation
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
            ClientProjectsSheet(
                model: model,
                onClose: { showClientProjects = false },
                onUnlock: { locked = false }
            )
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
        .modifier(CutoutPresenter(isPresented: $showCutouts, model: model))
        .modifier(CabinetManagerPresenter(isPresented: $showCabinets, model: model))
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
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                interiorView: $interiorView,
                useScanHouse: $useScanHouse,
                showScanCloud: $showScanCloud,
                showScan: $showScanLayer,
                showBuilding: $showBuildingLayer,
                hasScan: model.scan != nil,
                canScan: RoomScanSession.isSupported,
                onScan: { showScan = true },
                onClearScan: { model.clearScan() },
                onPlan: {
                    planDraft = model.currentPlan
                    showPlan = true
                },
                onTextures: { showTextures = true },
                onFirstPerson: AppSettings.load().showFirstPersonModule ? { showFPS = true } : nil,
                onPersist: {
                    var s = AppSettings.load()
                    s.interiorView = interiorView
                    s.useScanHouse = useScanHouse
                    s.showScanCloud = showScanCloud
                    s.showScanLayer = showScanLayer
                    s.showBuildingLayer = showBuildingLayer
                    s.save()
                }
            )
            .presentationDetents([.medium, .large])
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
            if UserDefaults.standard.bool(forKey: "demoCutouts") {
                var cabinets = model.current.cabinets
                if let index = cabinets.firstIndex(where: { $0.type == .base }) {
                    let cut = CabinetCutout.make(.sink, in: cabinets[index])
                    cabinets[index].cutouts = [cut]
                    model.updateCabinets(cabinets)
                    print("[ui] wycięcie zlewu dodane do: \(cabinets[index].name)")
                }
                if !UserDefaults.standard.bool(forKey: "demoCutout3D") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    showCutouts = true
                }
            }
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
            // Moduł pierwszoosobowy jest ukryty; hak diagnostyczny działa tylko
            // po włączeniu go w Ustawieniach.
            if UserDefaults.standard.bool(forKey: "demoFPS"),
               (AppSettings.load().showFirstPersonModule
                || UserDefaults.standard.bool(forKey: "demoForceFPS")) {
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
            if UserDefaults.standard.bool(forKey: "demoInterior") {
                interiorView = true
            }

            // hak: wypełnij ścianę szafkami i pokaż 3D (weryfikacja położenia)
            if UserDefaults.standard.object(forKey: "demoFillWall") != nil {
                let wall = UserDefaults.standard.integer(forKey: "demoFillWall")
                planDraft = model.currentPlan
                try? await Task.sleep(nanoseconds: 600_000_000)
                fillWall(wall)
                showPlan = false
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
                Button {
                    showCutouts = true
                    drawerOpen = false
                } label: {
                    Label("Wycięcia w szafkach (zlew, płyta, uchwyty)", systemImage: "scissors")
                }
                Button {
                    showCabinets = true
                    drawerOpen = false
                } label: {
                    Label("Szafki — edytor (wymiary, front, wnętrze)", systemImage: "cabinet.fill")
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

    /// Dodaje szafkę z biblioteki — TYŁEM DO ŚCIANY, frontem do pomieszczenia.
    ///
    /// Pierwsza szafka idzie na ścianę północną, kolejne dostawiają się do niej
    /// w tym samym rzędzie (jeśli jest miejsce). Gdy rząd jest pełny, szafka
    /// przeskakuje na następną ścianę — nigdy nie ląduje „w powietrzu"
    /// ani przodem w ścianę.
    private func add(_ t: Library.Template) {
        var cabinets = model.current.cabinets
        let new = Library.make(t)

        if let placed = Generator.placeNext(to: cabinets, new: new) {
            cabinets.append(placed)
        } else if cabinets.isEmpty {
            cabinets.append(Generator.placedAgainstWall(new, wall: 0, room: model.current.room))
        } else {
            // następna ściana z wolnym miejscem
            let walls = [0, 1, 2, 3]
            var done = false
            for wall in walls {
                let candidate = Generator.placedAgainstWall(new, wall: wall, room: model.current.room)
                if !cabinets.contains(where: { Collision.overlaps($0, candidate) }) {
                    cabinets.append(candidate)
                    done = true
                    break
                }
            }
            if !done { cabinets.append(Generator.placedAgainstWall(new, wall: 0, room: model.current.room)) }
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
                    showScan: showScanLayer,
                    showBuilding: showBuildingLayer,
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

    // MARK: - pasek nawigacji z dolnej krawędzi

    /// Pasek nawigacji wysuwany z dolnej krawędzi.
    ///
    /// Ukryty domyślnie — nad sceną 3D został tylko cienki „język" do
    /// pociągnięcia. Wysunięty pokazuje wyszukiwarkę klientów, przełączanie
    /// klientów (przyciskami, bez gestów) i wejścia do pozostałych ekranów.
    /// Nie zajmuje górnej krawędzi, więc nie koliduje z obrotem projektu.
    @ViewBuilder
    private var bottomNavigation: some View {
        VStack(spacing: 0) {
            if navOpen {
                VStack(spacing: 10) {
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
                    statusStrip
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // język do pociągnięcia + przyciski szybkie
            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        navOpen.toggle()
                    }
                } label: {
                    Image(systemName: navOpen ? "chevron.down" : "chevron.up")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(navOpen ? "Ukryj nawigację" : "Pokaż nawigację")

                Button { showViewOptions = true } label: {
                    Label("Opcje", systemImage: "square.grid.2x2")
                        .font(.footnote)
                }
                .buttonStyle(.plain)

                Button {
                    planDraft = model.currentPlan
                    showPlan = true
                } label: {
                    Label("Plan", systemImage: "map").font(.footnote)
                }
                .buttonStyle(.plain)

                Button { showClientProjects = true } label: {
                    Label("Kartoteka", systemImage: "person.2").font(.footnote)
                }
                .buttonStyle(.plain)

                Button { showSettings = true } label: {
                    Label("Ustawienia", systemImage: "gear").font(.footnote)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button { showScan = true } label: {
                    Label("Skanuj", systemImage: "sensor.tag.radiowaves.forward")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .disabled(!RoomScanSession.isSupported)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if value.translation.height < -24 { navOpen = true }
                        if value.translation.height > 24 { navOpen = false }
                    }
                }
        )
    }

    /// Pasek statusu: nazwa klienta, liczba szafek, komunikat. Bez przycisków —
    /// te są w „Opcjach widoku" (kafelki w arkuszu).
    private var statusStrip: some View {
        HStack(spacing: 12) {
            Text(model.current.name).font(.callout.weight(.medium))
            Text("\(model.current.cabinets.count) szafek")
                .font(.callout).foregroundStyle(.secondary)
            if let status = model.status {
                Text("· \(status)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
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
