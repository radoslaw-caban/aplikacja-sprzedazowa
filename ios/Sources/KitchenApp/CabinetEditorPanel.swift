import SwiftUI
import KitchenCore

enum CabinetEditorMode: String, CaseIterable {
    case body = "Bryła"
    case interior = "Wnętrze"
}

/// Panel edycji szafki w trybie FPS.
/// Jedno dotknięcie = bryła (wymiary, położenie, rodzaj, przeznaczenie).
/// Dwa dotknięcia = wnętrze (półki, szuflady, co będzie przechowywane).
struct CabinetEditorPanel: View {
    private let cabinet: Cabinet
    let room: Room
    let mode: CabinetEditorMode
    let isOpen: Bool
    let canDrag: Bool
    let dragArmed: Bool
    var onArmDrag: (Bool) -> Void
    var onLiveChange: (Cabinet) -> Void
    var onSave: (Cabinet) -> Void
    var onClose: () -> Void
    var onDelete: (() -> Void)?
    var onDetach: (() -> Void)?
    var onOpenFront: (Bool) -> Void
    var onModeChange: (CabinetEditorMode) -> Void

    @State private var draft: Cabinet
    @State private var showDelete = false

    init(cabinet: Cabinet,
         room: Room,
         mode: CabinetEditorMode,
         isOpen: Bool,
         canDrag: Bool = true,
         dragArmed: Bool,
         onArmDrag: @escaping (Bool) -> Void,
         onLiveChange: @escaping (Cabinet) -> Void,
         onSave: @escaping (Cabinet) -> Void,
         onClose: @escaping () -> Void,
         onDelete: (() -> Void)? = nil,
         onDetach: (() -> Void)? = nil,
         onOpenFront: @escaping (Bool) -> Void,
         onModeChange: @escaping (CabinetEditorMode) -> Void) {
        self.cabinet = cabinet
        self.room = room
        self.mode = mode
        self.isOpen = isOpen
        self.canDrag = canDrag
        self.dragArmed = dragArmed
        self.onArmDrag = onArmDrag
        self.onLiveChange = onLiveChange
        self.onSave = onSave
        self.onClose = onClose
        self.onDelete = onDelete
        self.onDetach = onDetach
        self.onOpenFront = onOpenFront
        self.onModeChange = onModeChange
        _draft = State(initialValue: cabinet)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Tryb", selection: Binding(get: { mode }, set: { onModeChange($0) })) {
                ForEach(CabinetEditorMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if mode == .body {
                        bodyEditor
                    } else {
                        interiorEditor
                    }
                }
                .padding(14)
            }

            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .padding(.trailing, 18)
        .onAppear { applyDemoStorage() }
        .onChange(of: cabinet) { _, new in
            if new != draft { draft = new }
        }
        .alert("Usunąć szafkę?", isPresented: $showDelete) {
            Button("Usuń", role: .destructive) { onDelete?() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Tej operacji nie można cofnąć.")
        }
    }

    private func applyDemoStorage() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "demoStorageKind"),
              let kind = StorageKind(rawValue: raw),
              let first = draft.elements.sorted(by: { $0.y < $1.y }).first else { return }
        setStorage(kind, for: first.id)
        onSave(draft)
        #endif
    }

    // MARK: - nagłówek

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: draft.type))
                .font(.title3)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(draft.purpose?.label ?? "bez przeznaczenia")
                    Text("·")
                    Text("\(Int(draft.width))×\(Int(draft.height))×\(Int(draft.depth))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onSave(draft)
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: - bryła

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            if draft.zoneID != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Szafka ze strefy — zmiana odpowiedzi w strefie może nadpisać ręczną edycję.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    if onDetach != nil {
                        Button {
                            draft.zoneID = nil
                            draft.zoneRole = nil
                            onDetach?()
                            commit()
                        } label: {
                            Label("Odłącz od strefy i edytuj ręcznie", systemImage: "link.badge.plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }

            section("Wymiary") {
                stepperRow("Szerokość", value: value(\.width), range: 150...2400, step: 50)
                stepperRow("Wysokość", value: value(\.height), range: 300...2400, step: 18)
                stepperRow("Głębokość", value: value(\.depth), range: 300...650, step: 10)
                if draft.type == .base {
                    stepperRow("Cokół", value: value(\.plinth), range: 0...220, step: 5)
                }
                if draft.type == .wall {
                    stepperRow("Montaż od podłogi", value: value(\.mountHeight), range: 900...2000, step: 10)
                }
            }

            section("Położenie w budynku") {
                stepperRow("X", value: value(\.x), range: -room.width / 2...room.width / 2, step: 10)
                stepperRow("Z", value: value(\.z), range: -room.depth / 2...room.depth / 2, step: 10)

                HStack {
                    Text("Obrót").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Obrót", selection: Binding(get: { draft.rotation },
                                                      set: { draft.rotation = $0; commit() })) {
                        ForEach([0.0, 90.0, 180.0, 270.0], id: \.self) { r in
                            Text("\(Int(r))°").tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }

                Button {
                    snapToWall()
                } label: {
                    Label("Przyciągnij plecami do najbliższej ściany", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                if canDrag {
                Button {
                    onArmDrag(!dragArmed)
                } label: {
                    Label(dragArmed ? "Przeciąganie włączone — przeciągnij scenę"
                                    : "Przeciągnij szafkę palcem w 3D",
                          systemImage: "hand.draw.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(dragArmed ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                }
            }

            section("Wygląd frontu") {
                HStack(spacing: 8) {
                    ForEach(["#c8bca9", "#f2efe9", "#8fa6b8", "#6b7280", "#2f3437", "#c9a227"], id: \.self) { hex in
                        Button {
                            draft.color = hex
                            draft.texture = nil
                            commit()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.white.opacity(draft.color == hex ? 0.9 : 0.2),
                                                          lineWidth: draft.color == hex ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Menu {
                    Button("Bez tekstury") {
                        draft.texture = nil
                        commit()
                    }
                    Divider()
                    ForEach(TextureStore.shared.textures) { texture in
                        Button(texture.name) {
                            draft.texture = texture.name
                            commit()
                        }
                    }
                } label: {
                    HStack {
                        Label(draft.texture == nil ? "Tekstura z biblioteki" : "Tekstura: \(draft.texture!)",
                              systemImage: "square.grid.3x3")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
            }

            section("Rodzaj i przeznaczenie") {
                Picker("Liczba drzwi", selection: Binding(get: { draft.doorCount ?? 1 },
                                                         set: { draft.doorCount = $0; commit() })) {
                    Text("1 skrzydło").tag(1)
                    Text("2 skrzydła").tag(2)
                }
                .pickerStyle(.segmented)

                Picker("Typ", selection: Binding(get: { draft.type }, set: { setType($0) })) {
                    Text("Dolna").tag(CabinetType.base)
                    Text("Wisząca").tag(CabinetType.wall)
                    Text("Stojąca").tag(CabinetType.tall)
                    Text("Zaślepka").tag(CabinetType.panel)
                }
                .pickerStyle(.segmented)

                Menu {
                    ForEach(Library.all) { t in
                        Button {
                            apply(template: t)
                        } label: {
                            Text("\(t.name) · \(t.summary)")
                        }
                    }
                } label: {
                    HStack {
                        Label("Szablon z biblioteki", systemImage: "square.grid.2x2")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }

                HStack {
                    Label("Przeznaczenie", systemImage: "tag")
                        .font(.caption)
                    Spacer()
                    Menu {
                        ForEach(CabinetPurpose.allCases) { p in
                            Button {
                                draft.purpose = p
                                commit()
                            } label: {
                                Label(p.label, systemImage: p.symbol)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(draft.purpose?.label ?? "Wybierz")
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                TextField("Nazwa szafki", text: value(\.name))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            if draft.purpose == .wardrobe {
                Text("Garderoba: dodaj drążek lub półki na ubrania w zakładce Wnętrze.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - wnętrze

    private var interiorEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            let used = draft.elements.map { $0.y + max($0.height, $0.kind == .shelf ? 18 : $0.height) }.max() ?? 0
            if used > bodyHeight() + 1 {
                Label("Elementy nie mieszczą się w korpusie — obniż półki albo zwiększ wysokość szafki.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    onOpenFront(!isOpen)
                } label: {
                    Label(isOpen ? "Zamknij front" : "Otwórz front",
                          systemImage: isOpen ? "rectangle.portrait.and.arrow.left" : "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("\(draft.elements.count) elementów")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                addMenu
                Button {
                    autoLayout()
                } label: {
                    Label("Ułóż", systemImage: "arrow.up.and.down.text.horizontal")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }

            if draft.elements.isEmpty {
                Text("Pusto — dodaj półkę albo szufladę i wybierz, co będzie w niej przechowywane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            }

            ForEach(draft.elements.sorted(by: { $0.y < $1.y })) { element in
                elementRow(element)
            }

            Text("Wybór asortymentu ustawia zalecaną wysokość i pokazuje modele towarów w 3D.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Półka") { addElement(.shelf) }
            Divider()
            Button("Szuflada N (66,5 mm)") { addDrawer(.n) }
            Button("Szuflada M (90,5 mm)") { addDrawer(.m) }
            Button("Szuflada K (128,5 mm)") { addDrawer(.k) }
        } label: {
            Label("Dodaj", systemImage: "plus")
                .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
    }

    private func elementRow(_ element: CabinetElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: element.kind == .drawer ? "tray.fill" : "rectangle.split.3x1")
                    .foregroundStyle(.cyan)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(element.kind == .drawer
                         ? "Szuflada \(element.drawer?.rawValue ?? "")"
                         : "Półka")
                        .font(.caption.weight(.semibold))
                    Text("y = \(Int(element.y)) mm · \(element.storage?.label ?? "brak asortymentu")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    ForEach(StorageKind.allCases) { kind in
                        Button {
                            setStorage(kind, for: element.id)
                        } label: {
                            Label("\(kind.label) · \(Int(kind.recommendedHeight)) mm", systemImage: kind.symbol)
                        }
                    }
                    Divider()
                    Button("— brak —") { setStorage(nil, for: element.id) }
                } label: {
                    Image(systemName: element.storage?.symbol ?? "questionmark.circle")
                        .font(.body)
                        .padding(7)
                        .background(.white.opacity(0.10), in: Circle())
                }

                Menu {
                    Button("Wyżej o 10 mm") { move(element.id, by: 10) }
                    Button("Niżej o 10 mm") { move(element.id, by: -10) }
                    Divider()
                    Button("Usuń", role: .destructive) { remove(element.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let kind = element.storage, element.kind == .drawer {
                Text("Zalecane: \(kind.label) — szuflada \(kind.drawerSystem.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.cyan.opacity(0.8))
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - stopka

    private var footer: some View {
        HStack(spacing: 10) {
            if onDelete != nil {
                Button {
                    showDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .padding(9)
                }
                .buttonStyle(.plain)
            }
            Button {
                onSave(draft)
                onClose()
            } label: {
                Label("Zapisz szafkę", systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: - operacje

    private func value<T>(_ keyPath: WritableKeyPath<Cabinet, T>) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0; commit() }
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func stepperRow(_ title: String, value: Binding<Double>,
                            range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            Text("\(Int(value.wrappedValue)) mm")
                .font(.caption.monospacedDigit())
                .frame(width: 78)
            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func icon(for type: CabinetType) -> String {
        switch type {
        case .base: "cabinet"
        case .wall: "cabinet.fill"
        case .tall: "door.left.hand.closed"
        case .panel: "rectangle"
        }
    }

    private func commit() {
        clampPosition()
        onLiveChange(draft)
    }

    private func clampPosition() {
        let rotated = draft.rotation == 90 || draft.rotation == 270
        let halfW = (rotated ? draft.depth : draft.width) / 2
        let halfD = (rotated ? draft.width : draft.depth) / 2
        let minX = -room.width / 2 + halfW
        let maxX = room.width / 2 - halfW
        let minZ = -room.depth / 2 + halfD
        let maxZ = room.depth / 2 - halfD
        if minX <= maxX { draft.x = min(max(draft.x, minX), maxX) }
        if minZ <= maxZ { draft.z = min(max(draft.z, minZ), maxZ) }
    }

    private func setType(_ type: CabinetType) {
        draft.type = type
        switch type {
        case .base:
            draft.plinth = draft.plinth == 0 ? 150 : draft.plinth
            draft.mountHeight = 0
        case .wall:
            draft.plinth = 0
            draft.mountHeight = draft.mountHeight == 0 ? 1500 : draft.mountHeight
        case .tall:
            draft.plinth = draft.plinth == 0 ? 150 : draft.plinth
            draft.mountHeight = 0
        case .panel:
            draft.plinth = 0
            draft.mountHeight = 0
        }
        commit()
    }

    private func apply(template t: Library.Template) {
        let fresh = Library.make(t)
        draft.name = fresh.name
        draft.type = fresh.type
        draft.width = fresh.width
        draft.height = fresh.height
        draft.depth = fresh.depth
        draft.plinth = fresh.plinth
        draft.mountHeight = fresh.mountHeight
        draft.elements = fresh.elements
        commit()
    }

    private func snapToWall() {
        let w = room.width
        let d = room.depth
        let margin: Double = 20
        let options: [(distance: Double, x: Double, z: Double, rotation: Double)] = [
            (abs(draft.z + d / 2), draft.x, -d / 2 + draft.depth / 2 + margin, 0),
            (abs(draft.z - d / 2), draft.x, d / 2 - draft.depth / 2 - margin, 180),
            (abs(draft.x + w / 2), -w / 2 + draft.depth / 2 + margin, draft.z, 90),
            (abs(draft.x - w / 2), w / 2 - draft.depth / 2 - margin, draft.z, 270),
        ]
        if let best = options.min(by: { $0.distance < $1.distance }) {
            draft.x = best.x
            draft.z = best.z
            draft.rotation = best.rotation
            commit()
        }
    }

    // MARK: - wnętrze: operacje

    private func bodyHeight() -> Double {
        draft.height - (draft.type == .base ? draft.plinth : 0)
    }

    private func addElement(_ kind: ElementKind) {
        let e = CabinetElement(kind: kind, y: 0, height: Standards.panel)
        draft.elements.append(e)
        autoLayout()
    }

    private func addDrawer(_ system: DrawerSystem) {
        let e = CabinetElement(kind: .drawer, y: 0, height: system.frontHeight, drawer: system)
        draft.elements.append(e)
        autoLayout()
    }

    private func setStorage(_ kind: StorageKind?, for id: UUID) {
        guard let i = draft.elements.firstIndex(where: { $0.id == id }) else { return }
        draft.elements[i].storage = kind
        if draft.elements[i].kind == .drawer, let kind {
            draft.elements[i].drawer = kind.drawerSystem
            draft.elements[i].height = kind.drawerSystem.frontHeight
        }
        autoLayout()
    }

    private func move(_ id: UUID, by delta: Double) {
        guard let i = draft.elements.firstIndex(where: { $0.id == id }) else { return }
        let limit = bodyHeight() - draft.elements[i].height
        draft.elements[i].y = min(max(0, draft.elements[i].y + delta), max(0, limit))
        commit()
    }

    private func remove(_ id: UUID) {
        draft.elements.removeAll { $0.id == id }
        commit()
    }

    /// Rozkłada elementy od dołu: szuflady wg systemu, półki wg zaleceń asortymentu.
    private func autoLayout() {
        let body = max(200, bodyHeight())
        var sorted = draft.elements.sorted { $0.y < $1.y }
        var cursor: Double = 0

        for i in sorted.indices {
            if sorted[i].kind == .drawer {
                let h = sorted[i].drawer?.frontHeight ?? max(66.5, sorted[i].height)
                sorted[i].height = h
                sorted[i].y = min(cursor, max(0, body - h))
                cursor = sorted[i].y + h
            } else {
                let gap = sorted[i].storage?.recommendedHeight ?? 280
                let y = min(cursor + gap - Standards.panel, max(0, body - Standards.panel))
                sorted[i].y = max(0, y)
                cursor = sorted[i].y + Standards.panel
            }
        }
        draft.elements = sorted
        commit()
    }
}
