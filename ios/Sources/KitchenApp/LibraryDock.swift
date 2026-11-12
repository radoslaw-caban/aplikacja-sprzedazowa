import SwiftUI
import UniformTypeIdentifiers
import KitchenCore

/// Wysuwana z lewej biblioteka / edytor.
///
/// Nic nie jest zaznaczone → biblioteka (kategorie na zakładkach przy krawędzi).
/// Klik w element w 3D → panel zamienia się w edytor tego elementu.
/// Wyjście: ESC (Mac) albo gest przesunięcia w lewo / X (iPad).
struct LibraryDock: View {
    @Bindable var model: AppModel
    @Binding var open: Bool

    @State private var category: DockCategory = .cabinets
    @State private var importing = false
    @State private var importError: String?
    @State private var flash = false
    @State private var userModels = UserModelStore.shared.models
    @State private var settings = AppSettings.load()

    private let panelWidth: CGFloat = 408
    private let tabWidth: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            tabs
            if open {
                panel
                    .frame(width: panelWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 54)
        .padding(.leading, 4)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: open)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.selectedCabinetID)
        .onChange(of: model.selectedCabinetID) { _, new in
            if new != nil { open = true }
        }
        .onAppear {
            settings = AppSettings.load()
            if category == .models { userModels = UserModelStore.shared.models }
            if let name = UserDefaults.standard.string(forKey: "demoSelectElement"), !name.isEmpty,
               let c = model.current.cabinets.first(where: {
                   $0.name.localizedCaseInsensitiveContains(name)
               }) {
                model.selectedCabinetID = c.id
            }
        }
        .onChange(of: open) { _, _ in settings = AppSettings.load() }
        .modifier(EscapeCloseModifier {
            if model.selectedCabinetID != nil { model.selectedCabinetID = nil }
            else { open = false }
        })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var failures: [String] = []
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do { try UserModelStore.shared.importModel(from: url) }
                    catch { failures.append(url.lastPathComponent) }
                }
                userModels = UserModelStore.shared.models
                importError = failures.isEmpty ? nil : "Nie udało się: \(failures.joined(separator: ", "))"
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    // MARK: - zakładki przy krawędzi

    private var tabs: some View {
        VStack(spacing: 6) {
            ForEach(DockCategory.allCases) { cat in
                Button {
                    category = cat
                    open = true
                    if model.selectedCabinetID != nil { model.selectedCabinetID = nil }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: cat.icon).font(.system(size: 15, weight: .semibold))
                        Text(cat.short).font(.system(size: 7, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(category == cat && open ? .black : .primary)
                    .frame(width: tabWidth, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(category == cat && open ? Color.cyan.opacity(0.85) : Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .help(cat.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    // MARK: - panel

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            if let id = model.selectedCabinetID,
               let cabinet = model.cabinet(id: id) {
                CabinetEditorPanel(
                    cabinet: cabinet,
                    room: model.current.room,
                    mode: .body,
                    isOpen: false,
                    canDrag: false,
                    dragArmed: false,
                    onArmDrag: { _ in },
                    onLiveChange: { model.updateCabinet($0) },
                    onSave: { model.updateCabinet($0) },
                    onClose: { model.selectedCabinetID = nil },
                    onDelete: {
                        model.deleteCabinet(id)
                        model.selectedCabinetID = nil
                    },
                    onDetach: { model.updateCabinet(cabinet) },
                    onOpenFront: { _ in },
                    onModeChange: { _ in }
                )
                .frame(width: 380)
                .frame(maxHeight: .infinity)
            } else {
                categoryContent
                    .frame(maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(magicBorder)
        .shadow(color: .black.opacity(0.35), radius: 22, x: 6, y: 6)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -70 && model.selectedCabinetID != nil {
                        model.selectedCabinetID = nil
                    }
                }
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.selectedCabinetID == nil ? category.icon : "slider.horizontal.3")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedCabinetID == nil ? category.title : "Edycja elementu")
                    .font(.callout.weight(.semibold))
                if let id = model.selectedCabinetID,
                   let c = model.cabinet(id: id) {
                    Text(c.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Wybierz element w 3D albo kategorię").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if model.selectedCabinetID != nil {
                    model.selectedCabinetID = nil
                } else {
                    open = false
                }
            } label: {
                Image(systemName: model.selectedCabinetID != nil ? "xmark.circle.fill" : "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(12)
    }

    // MARK: - kategorie

    @ViewBuilder
    private var categoryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch category {
                case .cabinets:
                    cabinetsLibrary
                case .finishes:
                    finishesLibrary
                case .hinges:
                    hingesLibrary
                case .accessories:
                    accessoriesLibrary
                case .models:
                    modelsLibrary
                }
            }
            .padding(12)
        }
    }

    private var cabinetsLibrary: some View {
        ForEach(Library.all) { t in
            Button {
                addCabinet(t)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cabinet.fill").foregroundStyle(.cyan).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.caption.weight(.semibold))
                        Text(t.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(.cyan)
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var finishesLibrary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(CabinetFinishes.all) { finish in
                Button {
                    applyFinish(finish)
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: finish.fallbackColor))
                            .frame(height: 54)
                            .overlay(
                                Text(finish.name)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.7))
                                    .padding(2)
                            )
                        Text(finish.name).font(.system(size: 9)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hingesLibrary: some View {
        ForEach(HingeType.allCases) { h in
            Button {
                applyHinge(h)
            } label: {
                HStack {
                    Image(systemName: h.symbol).foregroundStyle(.cyan).frame(width: 24)
                    Text(h.label).font(.caption)
                    Spacer()
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var accessoriesLibrary: some View {
        ForEach(CabinetAccessoryKind.allCases) { kind in
            Button {
                addAccessory(kind)
            } label: {
                HStack {
                    Image(systemName: kind.symbol).foregroundStyle(.cyan).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.label).font(.caption.weight(.semibold))
                        Text("y = \(Int(kind.defaultY)) mm").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(.cyan)
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var modelsLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wrzucanie modeli: przycisk poniżej otwiera Pliki (iCloud, AirDrop, pendrive). Obsługiwane .glb i .gltf. Model trafia do Documents/Modele i jest widoczny w tej liście.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                importing = true
            } label: {
                Label("Wgraj modele z Plików", systemImage: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            if let importError {
                Text(importError).font(.caption2).foregroundStyle(.orange)
            }

            ForEach(userModels) { m in
                HStack {
                    Image(systemName: "cube").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name).font(.caption.weight(.semibold))
                        Text(m.fileName).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        UserModelStore.shared.delete(m.id)
                        userModels = UserModelStore.shared.models
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if userModels.isEmpty {
                Text("Brak własnych modeli.").font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - akcje

    private func flashMagic() {
        guard settings.magicEffects else { return }
        withAnimation(.easeOut(duration: 0.15)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeInOut(duration: 0.5)) { flash = false }
        }
    }

    private func addCabinet(_ template: Library.Template) {
        var c = Library.make(template)
        c.texture = CabinetFinishes.defaultFinish.fileName
        c = Generator.placedAgainstWall(c, wall: 0, room: model.current.room)
        var cabinets = model.current.cabinets
        cabinets.append(c)
        model.updateCabinets(cabinets)
        model.selectedCabinetID = c.id
        flashMagic()
    }

    private func applyFinish(_ finish: CabinetFinish) {
        guard let id = model.selectedCabinetID,
              var c = model.cabinet(id: id) else { return }
        c.texture = finish.fileName
        model.updateCabinet(c)
        flashMagic()
    }

    private func applyHinge(_ hinge: HingeType) {
        guard let id = model.selectedCabinetID,
              var c = model.cabinet(id: id) else { return }
        c.hinge = hinge
        model.updateCabinet(c)
        flashMagic()
    }

    private func addAccessory(_ kind: CabinetAccessoryKind) {
        guard let id = model.selectedCabinetID,
              var c = model.cabinet(id: id) else { return }
        var list = c.accessories ?? []
        list.append(CabinetAccessory(kind: kind))
        c.accessories = list
        model.updateCabinet(c)
        flashMagic()
    }

    // MARK: - magiczna ramka

    @ViewBuilder
    private var magicBorder: some View {
        if settings.magicEffects {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    AngularGradient(colors: [.cyan, .purple, .pink, .gold, .cyan],
                                    center: .center),
                    lineWidth: flash ? 3 : 1.2
                )
                .blur(radius: flash ? 2.5 : 0.6)
                .opacity(flash ? 1 : 0.45)
                .overlay {
                    if flash {
                        TimelineView(.animation) { timeline in
                            Canvas { ctx, size in
                                let t = timeline.date.timeIntervalSinceReferenceDate
                                for i in 0..<26 {
                                    let seed = Double(i) * 12.9898
                                    let x = (sin(seed + t * 2.1) * 0.5 + 0.5) * size.width
                                    let y = (cos(seed * 1.7 + t * 1.7) * 0.5 + 0.5) * size.height
                                    let r = 1.2 + (sin(seed + t * 5) * 0.5 + 0.5) * 2
                                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                             with: .color(i % 2 == 0 ? .white : .yellow))
                                }
                            }
                        }
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
        }
    }
}

private struct EscapeCloseModifier: ViewModifier {
    var onClose: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onExitCommand(perform: onClose)
        #else
        content
        #endif
    }
}

private enum DockCategory: String, CaseIterable, Identifiable {
    case cabinets, finishes, hinges, accessories, models
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cabinets: "Biblioteka szafek"
        case .finishes: "Wykończenia"
        case .hinges: "Zawiasy"
        case .accessories: "Akcesoria"
        case .models: "Modele 3D"
        }
    }
    var short: String {
        switch self {
        case .cabinets: "SZAFKI"
        case .finishes: "FRONTY"
        case .hinges: "ZAWIA"
        case .accessories: "AKCES"
        case .models: "MODELE"
        }
    }
    var icon: String {
        switch self {
        case .cabinets: "cabinet.fill"
        case .finishes: "paintpalette.fill"
        case .hinges: "door.left.hand.closed"
        case .accessories: "basket.fill"
        case .models: "cube.fill"
        }
    }
}

private extension Color {
    static let gold = Color(red: 0.98, green: 0.83, blue: 0.35)
}
