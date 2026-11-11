import SwiftUI
import KitchenCore

/// Kreator stref zabudowy w natywnej aplikacji.
/// Ściana wybierana z planu (Dom → klik ściany → „Strefa…") albo z listy tutaj.
/// Każda odpowiedź natychmiast przebudowuje zabudowę w projekcie (3D za arkuszem).
struct ZoneDesignerView: View {
    @Bindable var model: AppModel
    var initialWall: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var wallIndex: Int
    @State private var draftID: UUID?
    @State private var step = 0

    init(model: AppModel, initialWall: Int = 0) {
        self.model = model
        self.initialWall = initialWall
        _wallIndex = State(initialValue: max(0, initialWall))
    }

    private var plan: FloorPlan { model.currentPlan }
    private var zones: [Zone] { model.currentZones }
    private var draft: Zone? { zones.first { $0.id == draftID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    wallPicker
                    if let zone = draft {
                        wizard(zone)
                    } else {
                        library
                    }
                }
                .padding(16)
            }
            .background(.regularMaterial)
            .navigationTitle("Strefy zabudowy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            wallIndex = min(max(0, wallIndex), max(0, plan.wallCount - 1))
            #if DEBUG
            // weryfikacja bez dotykania ekranu: symulator + defaults demoZoneCook
            if UserDefaults.standard.bool(forKey: "demoZoneCook"), draftID == nil {
                let z = model.addZone(kind: .kitchenCook, wallIndex: wallIndex)
                draftID = z.id
            }
            #endif
        }
    }

    // MARK: - ściana

    private var wallPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ściana projektowa").font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(0..<max(1, plan.wallCount), id: \.self) { i in
                    Button(wallLabel(i)) {
                        wallIndex = i
                        draftID = nil
                        step = 0
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.rotate")
                    Text(wallLabel(wallIndex)).font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("Wybierz ścianę w planie (Dom → klik w ścianę → Strefa…) albo tutaj. Strefa wstawia gotową propozycję od razu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func wallLabel(_ index: Int) -> String {
        guard let w = plan.wall(index) else { return "Ściana \(index + 1)" }
        return "Ściana \(index + 1) · \(Int(w.length.rounded())) mm"
    }

    // MARK: - biblioteka stref

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !zones.isEmpty {
                Text("Strefy w projekcie").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(zones) { zone in
                    HStack(spacing: 10) {
                        Image(systemName: ZoneLibrary.spec(zone.kind).icon).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(zone.name).font(.callout)
                            Text("ściana \(zone.wallIndex + 1)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            draftID = zone.id
                            wallIndex = zone.wallIndex
                            step = 0
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            model.deleteZone(zone.id)
                            if draftID == zone.id { draftID = nil }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Divider()
            }

            Text("Wybierz rodzaj zabudowy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            ForEach(ZoneGroup.allCases, id: \.self) { group in
                let specs = ZoneLibrary.specs.filter { $0.group == group }
                if !specs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.label).font(.subheadline.weight(.semibold))
                        ForEach(specs, id: \.kind) { spec in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: spec.icon)
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(spec.short).font(.callout.weight(.semibold))
                                        Text(spec.description).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Wstaw") {
                                        let z = model.addZone(kind: spec.kind, wallIndex: wallIndex)
                                        draftID = z.id
                                        step = 0
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                DisclosureGroup("Zależności") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(spec.relations.enumerated()), id: \.offset) { _, r in
                                            Text("• \(r)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 34)
                                }
                                .font(.caption2)
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - kreator

    private func wizard(_ zone: Zone) -> some View {
        let spec = ZoneLibrary.spec(zone.kind)
        let answers = zone.typedAnswers
        let questions = ZoneLibrary.activeQuestions(zone.kind, answers: answers)
        let q = questions.indices.contains(step) ? questions[step] : nil
        let zplan = Zones.zonePlan(for: zone, in: plan)
        let sum = Zones.summary(model.current.cabinets, zone: zone)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.icon).font(.title2)
                    Text(zone.name).font(.headline)
                    Text("ściana \(zone.wallIndex + 1) · \(Int(zplan.start))–\(Int(zplan.start + zplan.width)) mm")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    model.deleteZone(zone.id)
                    draftID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            ProgressView(value: Double(min(step + 1, questions.count)), total: Double(max(1, questions.count)))
            Text("Pytanie \(min(step + 1, questions.count)) / \(max(1, questions.count))")
                .font(.caption2).foregroundStyle(.secondary)

            if let q {
                VStack(alignment: .leading, spacing: 10) {
                    Text(q.label).font(.callout.weight(.semibold))
                    if let help = q.help {
                        Text(help).font(.caption).foregroundStyle(.secondary)
                    }
                    if q.type == .choice {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Array(q.choices.enumerated()), id: \.offset) { _, ch in
                                let on = answers[q.id] == ch.value
                                Button {
                                    model.setZoneValue(zone.id, key: q.id, value: ch.value)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.label).font(.caption.weight(.semibold))
                                        if let hint = ch.hint {
                                            Text(hint).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(9)
                                    .background(on ? Color.accentColor.opacity(0.22) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(on ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: on ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { answers.number(q.id, 50) },
                                    set: { model.setZoneValue(zone.id, key: q.id, value: .number($0)) }
                                ),
                                in: q.min...q.max,
                                step: q.step
                            )
                            Text("\(Int(answers.number(q.id, 50)))\(q.unit)")
                                .font(.callout.monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                        }
                        if q.placement {
                            Text("Przesuń suwakiem — pozycja urządzenia na blacie aktualizuje się w 3D.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            summaryBox(zone: zone, plan: zplan, sum: sum)
            if !zplan.notes.isEmpty || !zplan.warnings.isEmpty { notesBox(zplan) }
            relationsBox(spec)

            HStack(spacing: 8) {
                Button("← Wstecz") { step = max(0, step - 1) }
                    .buttonStyle(.bordered)
                    .disabled(step == 0)
                Button(step < questions.count - 1 ? "Dalej →" : "Gotowe ✓") {
                    if step < questions.count - 1 { step += 1 } else { draftID = nil; step = 0 }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("↺ Propozycja") {
                    var fresh = Zones.makeZone(kind: zone.kind, wallIndex: zone.wallIndex)
                    fresh.id = zone.id
                    model.updateZone(fresh, persistNow: true)
                }
                .buttonStyle(.bordered)
            }
            .font(.callout)
        }
    }

    private func summaryBox(zone: Zone, plan: ZonePlan, sum: Zones.Summary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Propozycja na żywo").font(.caption.weight(.semibold))
            Text("\(sum.base) dolnych · \(sum.wall) górnych · \(sum.tall) wysokich · \(sum.fronts) frontów · \(sum.appliances) urządzeń · \(Int(sum.length)) mm")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func notesBox(_ plan: ZonePlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, w in
                Text("⚠ \(w)").font(.caption2).foregroundStyle(.red)
            }
            ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, n in
                Text("· \(n)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func relationsBox(_ spec: ZoneSpec) -> some View {
        DisclosureGroup("Zależności tej strefy") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(spec.relations.enumerated()), id: \.offset) { _, r in
                    Text("• \(r)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}
