import SwiftUI
import KitchenCore

/// Edytor wycięć w szafkach: blat (zlew, płyta), front (uchwyt, wentylacja),
/// bok (przepust kablowy). Zmiany zapisują się od razu w projekcie.
struct CutoutPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let model: AppModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            CutoutEditorView(model: model)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            CutoutEditorView(model: model)
        }
        #endif
    }
}

struct CutoutEditorView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                cabinetList
                    .frame(width: 270)
                Divider()
                detail
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Wycięcia w szafkach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .onAppear {
                if selectedID == nil { selectedID = model.current.cabinets.first?.id }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cabinetList: some View {
        List(selection: $selectedID) {
            Section("Szafki (\(model.current.cabinets.count))") {
                ForEach(model.current.cabinets) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(Int(c.width))×\(Int(c.height))×\(Int(c.depth)) mm · \(c.cutouts?.count ?? 0) wycięć")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(c.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let cabinet {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(cabinet)

                    if (cabinet.cutouts ?? []).isEmpty {
                        ContentUnavailableView("Brak wycięć",
                                               systemImage: "scissors",
                                               description: Text("Dodaj zlew, płytę, uchwyt albo przepust kablowy."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }

                    ForEach(cabinet.cutouts ?? []) { cut in
                        cutoutCard(cut, in: cabinet)
                    }

                    addMenu(cabinet)
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Wybierz szafkę", systemImage: "cabinet")
        }
    }

    private func header(_ c: Cabinet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.name).font(.title3.weight(.semibold))
            Text("\(Int(c.width)) × \(Int(c.height)) × \(Int(c.depth)) mm · \(c.type.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func cutoutCard(_ cut: CabinetCutout, in c: Cabinet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: cut.purpose.symbol)
                    .foregroundStyle(.cyan)
                    .frame(width: 26)
                Text(cut.purpose.label).font(.headline)
                Spacer()
                Button(role: .destructive) {
                    update(c) { cabinet in
                        cabinet.cutouts?.removeAll { $0.id == cut.id }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Picker("Płaszczyzna", selection: planeBinding(cut.id, in: c)) {
                    ForEach(CutoutPlane.allCases) { p in
                        Label(p.label, systemImage: p.symbol).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)

                Picker("Przeznaczenie", selection: purposeBinding(cut.id, in: c)) {
                    ForEach(CutoutPurpose.allCases) { p in
                        Label(p.label, systemImage: p.symbol).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    numberRow("X", value: doubleBinding(cut.id, in: c, \.x), range: -c.width / 2...c.width / 2, step: 10)
                    numberRow("Y", value: doubleBinding(cut.id, in: c, \.y), range: -500...c.height, step: 10)
                }
                GridRow {
                    numberRow("Szerokość", value: doubleBinding(cut.id, in: c, \.width), range: 20...c.width, step: 10)
                    numberRow("Wysokość", value: doubleBinding(cut.id, in: c, \.height), range: 10...c.height, step: 10)
                }
                GridRow {
                    numberRow("Promień", value: doubleBinding(cut.id, in: c, \.cornerRadius), range: 0...100, step: 5)
                    Text("")
                }
            }

            Text(hint(for: cut))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addMenu(_ c: Cabinet) -> some View {
        Menu {
            ForEach(CutoutPurpose.allCases) { purpose in
                Button {
                    add(purpose, to: c)
                } label: {
                    Label("\(purpose.label) · \(Int(purpose.defaultSize.width))×\(Int(purpose.defaultSize.height)) mm",
                          systemImage: purpose.symbol)
                }
            }
        } label: {
            Label("Dodaj wycięcie", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            Text("\(Int(value.wrappedValue))").font(.caption.monospacedDigit()).frame(width: 52)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - dane

    private var cabinet: Cabinet? {
        guard let selectedID else { return nil }
        return model.current.cabinets.first { $0.id == selectedID }
    }

    private func update(_ c: Cabinet, _ mutate: (inout Cabinet) -> Void) {
        guard var latest = model.current.cabinets.first(where: { $0.id == c.id }) else { return }
        mutate(&latest)
        model.updateCabinet(latest)
    }

    private func index(_ id: UUID, in c: Cabinet) -> Int? {
        (c.cutouts ?? []).firstIndex { $0.id == id }
    }

    private func doubleBinding(_ id: UUID, in c: Cabinet,
                               _ keyPath: WritableKeyPath<CabinetCutout, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard let i = index(id, in: c) else { return 0 }
                return c.cutouts?[i][keyPath: keyPath] ?? 0
            },
            set: { new in
                update(c) { cabinet in
                    if let i = cabinet.cutouts?.firstIndex(where: { $0.id == id }) {
                        cabinet.cutouts?[i][keyPath: keyPath] = new
                    }
                }
            }
        )
    }

    private func planeBinding(_ id: UUID, in c: Cabinet) -> Binding<CutoutPlane> {
        Binding(
            get: { c.cutouts?.first { $0.id == id }?.plane ?? .front },
            set: { new in
                update(c) { cabinet in
                    if let i = cabinet.cutouts?.firstIndex(where: { $0.id == id }) {
                        cabinet.cutouts?[i].plane = new
                    }
                }
            }
        )
    }

    private func purposeBinding(_ id: UUID, in c: Cabinet) -> Binding<CutoutPurpose> {
        Binding(
            get: { c.cutouts?.first { $0.id == id }?.purpose ?? .other },
            set: { new in
                update(c) { cabinet in
                    guard let i = cabinet.cutouts?.firstIndex(where: { $0.id == id }) else { return }
                    let preset = CabinetCutout.make(new, in: cabinet)
                    cabinet.cutouts?[i].purpose = new
                    cabinet.cutouts?[i].plane = preset.plane
                    cabinet.cutouts?[i].width = preset.width
                    cabinet.cutouts?[i].height = preset.height
                    cabinet.cutouts?[i].y = preset.y
                    cabinet.cutouts?[i].cornerRadius = preset.cornerRadius
                }
            }
        )
    }

    private func add(_ purpose: CutoutPurpose, to c: Cabinet) {
        update(c) { cabinet in
            var list = cabinet.cutouts ?? []
            list.append(CabinetCutout.make(purpose, in: cabinet))
            cabinet.cutouts = list
        }
    }

    private func hint(for cut: CabinetCutout) -> String {
        switch cut.plane {
        case .top:
            return "X = po szerokości, Y = po głębokości blatu. Wycięcie rysowane jest na górnej powierzchni."
        case .front:
            return "X = po szerokości, Y = od dolnej krawędzi korpusu. Wycięcie rysowane na froncie."
        case .side:
            return "X = po głębokości, Y = od dolnej krawędzi. Wycięcie rysowane na prawym boku."
        }
    }
}
