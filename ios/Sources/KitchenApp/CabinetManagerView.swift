import SwiftUI
import KitchenCore

struct CabinetManagerPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let model: AppModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            CabinetManagerView(model: model)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            CabinetManagerView(model: model)
        }
        #endif
    }
}

/// Edytor szafek bez trybu FPS: lista + panel (wymiary, położenie, typ,
/// przeznaczenie, wygląd frontu, drzwi, wnętrze, wycięcia).
struct CabinetManagerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var editorMode: CabinetEditorMode =
        UserDefaults.standard.string(forKey: "demoCabinetMode") == "interior" ? .interior : .body

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                list
                    .frame(width: 290)
                Divider()
                detail
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Szafki")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .onAppear {
                if selectedID == nil { selectedID = model.current.cabinets.first?.id }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List(selection: $selectedID) {
            Section("Szafki (\(model.current.cabinets.count))") {
                ForEach(model.current.cabinets) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(Int(c.width))×\(Int(c.height))×\(Int(c.depth)) · \(c.type.rawValue) · \(c.purpose?.label ?? "—")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(c.id)
                    .contextMenu {
                        Button {
                            duplicate(c)
                        } label: { Label("Duplikuj", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) {
                            delete(c.id)
                        } label: { Label("Usuń", systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(c.id) } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let c = selected {
            CabinetEditorPanel(
                cabinet: c,
                room: model.current.room,
                mode: editorMode,
                isOpen: false,
                canDrag: false,
                dragArmed: false,
                onArmDrag: { _ in },
                onLiveChange: { model.updateCabinet($0) },
                onSave: { model.updateCabinet($0) },
                onClose: { selectedID = nil },
                onDelete: { delete(c.id) },
                onDetach: { model.updateCabinet(c) },
                onOpenFront: { _ in },
                onModeChange: { editorMode = $0 }
            )
            .frame(width: 400)
            .padding(.trailing, 18)
            .id(c.id)
        } else {
            ContentUnavailableView("Wybierz szafkę", systemImage: "cabinet",
                                   description: Text("Z listy po lewej albo dodaj nową z biblioteki."))
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(Library.all) { t in
                Button {
                    add(t)
                } label: {
                    Text("\(t.name) · \(t.summary)")
                }
            }
        } label: {
            Label("Dodaj szafkę", systemImage: "plus")
        }
    }

    private var selected: Cabinet? {
        guard let selectedID else { return nil }
        return model.current.cabinets.first { $0.id == selectedID }
    }

    private func add(_ template: Library.Template) {
        var cabinet = Library.make(template)
        cabinet = Generator.placedAgainstWall(cabinet, wall: 0, room: model.current.room)
        var cabinets = model.current.cabinets
        cabinets.append(cabinet)
        model.updateCabinets(cabinets)
        selectedID = cabinet.id
    }

    private func duplicate(_ c: Cabinet) {
        var copy = c
        copy.id = UUID()
        copy.name += " — kopia"
        copy.x += c.width + 20
        copy.zoneID = nil
        copy.zoneRole = nil
        var cabinets = model.current.cabinets
        cabinets.append(copy)
        model.updateCabinets(cabinets)
        selectedID = copy.id
    }

    private func delete(_ id: UUID) {
        model.deleteCabinet(id)
        if selectedID == id { selectedID = nil }
    }
}
