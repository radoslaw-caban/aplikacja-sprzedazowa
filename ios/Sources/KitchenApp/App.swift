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
    @State private var interiorView = true
    @State private var showScan = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showDocuments) {
            DocumentsSheet(model: model)
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
                ZStack(alignment: .topLeading) {
                    SceneView(
                        cabinets: model.current.cabinets,
                        room: model.current.room,
                        scan: model.scan,
                        transform: model.scanTransform,
                        interiorView: interiorView
                    )
                    swipeHint
                }
                .contentShape(Rectangle())
                .gesture(swipe)
            }
            bottomBar
        }
    }

    /// Gesty: pion = projekt, poziom = dokument (logika w GestureNav + testy).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let axis = GestureNav.axis(dx: value.translation.width, dy: value.translation.height)
                let step = GestureNav.step(for: axis, dx: value.translation.width, dy: value.translation.height)
                guard step != 0 else { return }
                switch axis {
                case .vertical: model.switchProject(step: step)
                case .horizontal: model.switchDocument(step: step)
                case .none: break
                }
            }
    }

    private var swipeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
            Text("projekty")
            Text("·")
            Image(systemName: "arrow.left.arrow.right")
            Text("dokumenty")
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
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
                interiorView.toggle()
            } label: {
                Label(interiorView ? "Wnętrze" : "Otoczenie",
                      systemImage: interiorView ? "house" : "tree")
            }
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
