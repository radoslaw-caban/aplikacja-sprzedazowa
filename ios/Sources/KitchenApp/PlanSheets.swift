import SwiftUI
import KitchenCore

/// Lista gotowych planów — wybieramy i korygujemy, zamiast rysować od zera.
struct PlanPresetSheet: View {
    var onPick: (PlanPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var visible: [PlanPreset] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return PlanPresets.all }
        return PlanPresets.all.filter { $0.name.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List(visible) { preset in
                Button {
                    onPick(preset)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(preset.name).font(.callout.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.1f m²", preset.areaM2))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text("\(Units.mm(preset.width)) × \(Units.mm(preset.depth)) mm · wys. \(Units.mm(preset.height)) mm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Szukaj planu")
            .navigationTitle("Gotowe plany")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
    }
}

/// Zestawienie materiałów liczone z planu.
struct TakeoffSheet: View {
    let plan: FloorPlan
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = Takeoff.compute(
            plan: plan,
            windowCount: settings.windowCount,
            doorCount: settings.doorCount,
            coats: settings.paintCoats
        )
        return NavigationStack {
            List {
                section("Podłoga i sufit") {
                    line("Powierzchnia podłogi", String(format: "%.2f m²", t.floorAreaM2))
                    line("Sufit", String(format: "%.2f m²", t.ceilingAreaM2))
                    line("Listwy przypodłogowe", String(format: "%.2f m", t.skirtingMeters))
                }
                section("Malowanie") {
                    line("Ściany bez otworów", String(format: "%.1f m²", t.wallAreaM2))
                    line("Ściany z otworami", String(format: "%.1f m²", t.wallAreaWithOpeningsM2))
                    line("Farba (\(settings.paintCoats) warstwy)", String(format: "%.1f l", t.paintLiters))
                    line("Grunt", String(format: "%.1f l", t.primerLiters))
                }
                section("Stolarka do zamówienia") {
                    ForEach(t.windows, id: \.self) { text in
                        Text(text).font(.caption)
                    }
                    ForEach(t.doors, id: \.self) { text in
                        Text(text).font(.caption)
                    }
                }
                section("Ściany") {
                    line("Obwód", String(format: "%.2f m", t.perimeterMeters))
                    line("Wysokość", "\(Units.mm(plan.height)) mm")
                    line("Grubość", "\(Units.mm(plan.thickness)) mm")
                    line("Ścian", "\(plan.wallCount)")
                }
            }
            .navigationTitle("Zestawienie materiałów")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section(title) { content() }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
