import SwiftUI
import KitchenCore

/// Przepływ pracy według diagramu: ekrany przewijane poziomo, start na
/// „Szczegółach zamówienia" (zielony na diagramie).
///
/// KOLEJNOŚĆ JEST DECYZJĄ PRODUKTOWĄ, nie estetyką: handlowiec otwiera
/// aplikację na danych klienta, w lewo ma panel akcji i pliki, w prawo —
/// kolejne widoki projektu 3D (główny, kuchnia, następne pomieszczenia).
struct OrderFlowView: View {
    @Bindable var model: AppModel
    /// plan domu ze skanu (chmura X9); nil = willa proceduralna
    var scanPlan: ScanPlan?
    @Binding var interiorView: Bool
    @Binding var locked: Bool
    /// Warstwa skanu włączana niezależnie od bryły budynku.
    var showScan: Bool = true
    /// Warstwa budynku (ściany, podłoga, sufit) niezależnie od skanu.
    var showBuilding: Bool = true
    var openPlan: () -> Void
    var openScan: () -> Void
    var openDocuments: () -> Void
    var openContract: () -> Void = {}
    var openClientProjects: () -> Void = {}

    /// 2 = Szczegóły zamówienia — ekran startowy.
    /// `flowPage` w UserDefaults pozwala zweryfikować dowolny ekran bez dotykania.
    @State private var page: Int = (UserDefaults.standard.object(forKey: "flowPage") as? Int) ?? 2

    private let pageTitles = [
        "Panel akcji",
        "Pliki",
        "Szczegóły zamówienia",
        "Projekt 3D główny",
        "Projekt 3D kuchnia",
        "Projekt 3D kolejne pomieszczenie",
    ]

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            TabView(selection: $page) {
                ActionPanelPage(model: model, openPlan: openPlan, openScan: openScan,
                                openDocuments: openDocuments, interiorView: $interiorView)
                    .tag(0)
                FilesPage(model: model, openDocuments: openDocuments)
                    .tag(1)
                OrderDetailsPage(model: model,
                                 openContract: openContract,
                                 openClientProjects: openClientProjects)
                    .tag(2)
                ProjectScenePage(model: model, interior: false, scanPlan: scanPlan, locked: locked,
                                 note: "Dom w otoczeniu — widok dla klienta",
                                 showScan: showScan, showBuilding: showBuilding)
                    .tag(3)
                ProjectScenePage(model: model, interior: true, scanPlan: scanPlan, locked: locked,
                                 note: "Kuchnia — zabudowa w skali 1:1",
                                 showScan: showScan, showBuilding: showBuilding)
                    .tag(4)
                NextRoomPage(model: model)
                    .tag(5)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
    }

    // MARK: - nagłówek z numeracją ekranów

    private var pageHeader: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageTitles.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { page = index }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(index == page ? accent(for: index) : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                        Text(pageTitles[index])
                            .font(.system(size: 11, weight: index == page ? .semibold : .regular))
                            .foregroundStyle(index == page ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(index == page ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.clear),
                                in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button {
                locked = true
            } label: {
                Label("Zablokuj", systemImage: "lock.open.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Zablokuj projekt: widok wraca do przewijania, UI się chowa")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func accent(for index: Int) -> Color {
        index == 2 ? .green : .accentColor
    }
}

// MARK: - 1. Panel akcji

struct ActionPanelPage: View {
    @Bindable var model: AppModel
    var openPlan: () -> Void
    var openScan: () -> Void
    var openDocuments: () -> Void
    var openContract: () -> Void = {}
    var openClientProjects: () -> Void = {}
    @Binding var interiorView: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Panel akcji").font(.title2.bold())
                Text("Wszystko, co robisz przy kliencie — w jednym miejscu.")
                    .font(.callout).foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    action("Nowy projekt", "plus.rectangle.on.folder", "Dodaje pusty projekt i przełącza na niego") {
                        model.addProject()
                    }
                    action("Skanuj pomieszczenie", "sensor.tag.radiowaves.forward", "LiDAR: chmura punktów prosto do projektu") {
                        openScan()
                    }
                    action("Plan domu", "map", "Rysuj ściany kreskami i zmieniaj ich długości") {
                        openPlan()
                    }
                    action("Dokumenty klienta", "folder", "Umowy, zdjęcia, rzuty — \(model.documents.count) plików") {
                        openDocuments()
                    }
                    action(interiorView ? "Pokaż dom z zewnątrz" : "Pokaż wnętrze",
                           interiorView ? "tree" : "house",
                           "Przełącza kadr 3D: otoczenie ↔ kuchnia") {
                        interiorView.toggle()
                    }
                    action("Wyczyść szafki", "trash", "Usuwa zabudowę z bieżącego projektu") {
                        model.updateCabinets([])
                        model.persist()
                    }
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bieżący projekt").font(.headline)
                    Text(model.current.name).font(.callout)
                    Text("\(model.current.cabinets.count) szafek · \(model.documents.count) dokumentów · \(String(format: "%.1f", model.current.room.area)) m²")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.96, green: 0.95, blue: 0.93))
    }

    private func action(_ title: String, _ icon: String, _ subtitle: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. Pliki związane z zamówieniem

struct FilesPage: View {
    @Bindable var model: AppModel
    var openDocuments: () -> Void
    var openContract: () -> Void = {}
    var openClientProjects: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pliki związane z zamówieniem").font(.title2.bold())
                Spacer()
                Button { openDocuments() } label: {
                    Label("Dodaj", systemImage: "doc.badge.plus")
                }
            }
            if model.documents.isEmpty {
                ContentUnavailableView("Brak plików",
                                       systemImage: "folder",
                                       description: Text("Umowy, rendery i rzuty wysłane przez klienta trafiają tutaj."))
            } else {
                List(model.documents) { doc in
                    HStack(spacing: 10) {
                        Image(systemName: doc.kind.icon).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.name).font(.callout).lineLimit(1)
                            Text("\(doc.kind.label) · \(doc.sizeLabel)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(red: 0.96, green: 0.95, blue: 0.93))
    }
}

// MARK: - 3. Szczegóły zamówienia (START)

struct OrderDetailsPage: View {
    @Bindable var model: AppModel
    @State private var draft = ProjectOrder()
    var openContract: () -> Void = {}
    var openClientProjects: () -> Void = {}

    /// Rodzaj klawiatury bez wciągania UIKit do wspólnego kodu (macOS).
    enum FieldKind { case text, phone, email }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                card("Klient") {
                    field("Nazwisko", text: $draft.clientLastName)
                    field("Imię", text: $draft.clientFirstName)
                    field("Adres", text: $draft.address)
                    field("Telefon", text: $draft.phone, kind: .phone)
                    field("E-mail", text: $draft.email, kind: .email)
                }

                card("Warunki") {
                    HStack(spacing: 14) {
                        numberField("Cena (zł)", value: $draft.price)
                        numberField("Zaliczka (zł)", value: $draft.deposit)
                    }
                    HStack(spacing: 14) {
                        numberField("Rabat (%)", value: Binding(
                            get: { draft.discountPercent ?? 0 },
                            set: { draft.discountPercent = $0 }
                        ))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cena po rabacie").font(.caption).foregroundStyle(.secondary)
                            Text(draft.finalPrice, format: .currency(code: "PLN"))
                                .font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        Spacer()
                    }
                    HStack {
                        Text("Do zapłaty po zaliczce").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(max(0, draft.finalPrice - draft.deposit), format: .currency(code: "PLN"))
                            .font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    ProgressView(value: draft.finalPrice > 0 ? min(1, draft.deposit / draft.finalPrice) : 0)
                        .tint(.green)
                }

                card("Kartoteka klienta") {
                    HStack(spacing: 10) {
                        Button {
                            model.addProjectForCurrentClient()
                        } label: {
                            Label("Dodaj kolejny projekt", systemImage: "plus.rectangle.on.folder")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openClientProjects()
                        } label: {
                            Label("Projekty klienta", systemImage: "square.stack.3d.up")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        openContract()
                    } label: {
                        Label(draft.isContractSigned ? "Umowa podpisana — zobacz" : "Umowa do podpisu",
                              systemImage: draft.isContractSigned ? "checkmark.seal.fill" : "signature")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(draft.isContractSigned ? .green : .accentColor)
                }

                card("Ustalenia") {
                    label("Powód zmiany")
                    TextField("np. klient chce szerszy blat i piekarnik pod blatem",
                              text: $draft.changeReason, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    label("Konwersacja z klientem")
                    TextField("Co ustalono, na kiedy, co obiecano", text: $draft.notes, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.95, blue: 0.93))
        .onAppear { draft = model.currentOrder }
        .onChange(of: model.currentIndex) { _, _ in draft = model.currentOrder }
        .onChange(of: draft) { _, new in
            model.updateOrder(new)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Szczegóły zamówienia").font(.title2.bold())
                Text("\(draft.clientName) · \(model.current.name)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("START").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.green, in: Capsule())
                Text("przesuń w bok → projekt 3D")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1))
        )
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }

    private func field(_ title: String, text: Binding<String>, kind: FieldKind = .text) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            TextField("", text: text, prompt: Text(placeholder(for: title)).foregroundStyle(.tertiary))
                #if os(iOS)
                .keyboardType(keyboardType(kind))
                .textInputAutocapitalization(kind == .text ? .words : .never)
                .autocorrectionDisabled(kind != .text)
                #endif
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    #if os(iOS)
    private func keyboardType(_ kind: FieldKind) -> UIKeyboardType {
        switch kind {
        case .text: .default
        case .phone: .phonePad
        case .email: .emailAddress
        }
    }
    #endif

    /// Podpowiedź w polu — inna niż etykieta, żeby nie było dwóch takich samych napisów.
    private func placeholder(for title: String) -> String {
        switch title {
        case "Nazwisko": "np. Kowalski"
        case "Imię": "np. Jan"
        case "Adres": "ul., nr, kod, miasto"
        case "Telefon": "np. 600 100 200"
        case "E-mail": "np. jan.kowalski@example.com"
        default: title
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            TextField(title, value: value, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.plain)
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 7. Widok zablokowany (pole robocze)

/// Projekt zablokowany: na ekranie zostaje TYLKO pole robocze i kłódka.
///
/// Po co: przy kliencie ekran ma pokazywać kuchnię, a nie formularze. Pasek
/// zakładek, przyciski i menu znikają; wraca je kłódką albo wyciągnięciem
/// menu z lewej krawędzi.
struct LockedWorkspace: View {
    @Bindable var model: AppModel
    var interiorView: Bool
    /// plan domu ze skanu (chmura X9); nil = willa proceduralna
    var scanPlan: ScanPlan?
    /// nałóż chmurę punktów na dom (kontrola dopasowania)
    var showScanCloud: Bool = false
    @Binding var locked: Bool

    /// Pokój z ręcznego planu (jeśli projekt go ma) — ma pierwszeństwo nad skanem.
    private var manualRoom: Room? {
        guard let plan = model.current.plan, plan.points.count >= 3 else { return nil }
        return plan.room(name: model.current.room.name)
    }

    var body: some View {
        ZStack {
            SceneView(
                cabinets: model.current.cabinets,

                // Kolejność ważności: ręcznie wpisany plan → plan ze skanu → pokój projektu.
                // Wcześniej skan nadpisywał wymiary, więc wpisanie „3,0 × 3,6 m" nic nie dawało.
                room: manualRoom
                    ?? scanPlan.map { plan in
                        Room(width: Double(plan.width) * 1000,
                             depth: Double(plan.depth) * 1000,
                             height: Double(plan.height) * 1000)
                    }
                    ?? model.current.room,
                scan: model.scan,
                transform: model.scanTransform,
                interiorView: interiorView,
                scanPlan: scanPlan,
                showScanCloud: showScanCloud,
                locked: true
            )

            VStack {
                HStack {
                    Spacer()
                    Button {
                        locked = false
                    } label: {
                        Label("Odblokuj", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Odblokuj projekt: wraca interfejs i obracanie projektu")
                }
                Spacer()
                Text("Przeciągnij, aby przesuwać  ·  kłódka = obrót projektu")
                    .font(.caption2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 14)
            }
            .padding(14)
        }
    }
}


struct ProjectScenePage: View {
    @Bindable var model: AppModel
    var interior: Bool
    /// plan domu ze skanu (nil = willa proceduralna)
    var scanPlan: ScanPlan?
    /// false = odblokowany: można edytować projekt
    var locked: Bool
    var note: String
    /// rozdzielne przełączniki: skan i bryła budynku niezależnie
    var showScan = true
    var showBuilding = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(
                cabinets: model.current.cabinets,
                room: model.current.room,
                scan: model.scan,
                transform: model.scanTransform,
                interiorView: interior,
                scanPlan: scanPlan,
                locked: locked,
                showScan: showScan,
                showBuilding: showBuilding
            )
            Text(note)
                .font(.caption2)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
    }
}

struct NextRoomPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.split.bottomrightquarter").font(.system(size: 44, weight: .light))
            Text("Projekt 3D kolejne pomieszczenie").font(.headline)
            Text("Kuchnia jest pierwszym pomieszczeniem. Tutaj pojawią się kolejne — sypialnia, łazienka, garderoba — z tą samą zabudową i planem.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).frame(maxWidth: 420)
            if let plan = model.current.plan {
                Text("Plan domu: \(plan.wallCount) ścian · \(String(format: "%.1f", plan.areaM2)) m²")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.95, blue: 0.93))
    }
}
