import SwiftUI
import KitchenCore

/// Koszyk / wycena: co wchodzi w zamówienie, za ile i co klient ma już swoje.
///
/// ZASADA: pozycje z projektu są liczone automatycznie i oznaczone „z projektu".
/// Ręczne (dodane z cennika) są osobno. Pozycję oznaczoną „Już to mam" widać,
/// ale nie liczy się do kwoty — klient chce wiedzieć, co zostaje, a nie płacić
/// drugi raz za własną lodówkę.
struct CartSheet: View {
    @Bindable var model: AppModel
    var onClose: () -> Void

    /// Pozycje dodane ręcznie (poza projektem).
    @State private var manualLines: [Pricing.Line] = []
    /// Klucze pozycji oznaczonych „Już to mam" (id szafki lub id cennika).
    @State private var owned: Set<String> = []
    /// Kategoria w widoku cennika.
    @State private var catalogGroup: Pricing.Group = .cabinet
    @State private var showCatalog = false
    @State private var showVatBreakdown = false

    private var summary: CartSummary { currentSummary }

    /// Przelicza koszyk z aktualnego projektu.
    ///
    /// Długości blatów, cokołów i montażu bierzemy z biegów — to jedyne miejsce,
    /// gdzie program wie, ile faktycznie metrów zabudowy stoi na projekcie.
    private var currentSummary: CartSummary {
        let runs = Runs.compute(model.current.cabinets)
        let baseMetres = runs.filter(\.hasBase).reduce(0.0) { $0 + $1.length / 1000 }
        return CartBuilder.build(
            cabinets: model.current.cabinets,
            manualLines: manualLines,
            ownedSignatures: owned,
            worktopMetres: baseMetres,
            plinthMetres: baseMetres,
            assemblyMetres: baseMetres
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    totalsCard
                    if summary.lines.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.group) { bucket in
                            groupCard(bucket.group, lines: bucket.lines)
                        }
                    }
                    if !summary.owned.isEmpty {
                        ownedCard
                    }
                    catalogSection
                }
                .padding(14)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Wycena")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { onClose() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        applyToOrder()
                    } label: {
                        Label("Do zamówienia", systemImage: "arrow.up.doc")
                    }
                }
            }
        }
    }

    // MARK: - sekcje

    private var groups: [(group: Pricing.Group, lines: [Pricing.Line])] {
        summary.grouped(Pricing.catalogByID)
    }

    /// Kwoty — najważniejsza informacja, więc na górze.
    private var totalsCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAZEM BRUTTO")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(money(summary.grossTotal))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    showVatBreakdown.toggle()
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("netto \(money(summary.netTotal))")
                            .font(.caption.monospacedDigit())
                        Text("VAT \(money(summary.vatTotal))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if showVatBreakdown {
                Divider()
                VStack(spacing: 4) {
                    ForEach(summary.vatByRate, id: \.rate) { row in
                        HStack {
                            Text("VAT \(Int(row.rate))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(money(row.net)) → \(money(row.vat))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }

            if summary.ownedReferenceValue > 0 {
                Divider()
                HStack {
                    Label("Sprzęt klienta w zestawieniu", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(money(summary.ownedReferenceValue))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cart").font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Koszyk jest pusty").font(.headline)
            Text("Wstaw szafki na projekt albo dodaj pozycje z cennika poniżej. Wszystko, co stoi na projekcie, trafia tutaj automatycznie.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    /// Grupa pozycji (szafki, blaty, AGD…).
    private func groupCard(_ group: Pricing.Group, lines: [Pricing.Line]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: group.pictogram).font(.footnote)
                Text(group.label.uppercased())
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(money(lines.reduce(0) { $0 + $1.netValue }))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)

            ForEach(lines) { line in
                lineRow(line)
                if line.id != lines.last?.id { Divider().padding(.leading, 12) }
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Wiersz pozycji: nazwa, ilość, cena, przełącznik „Już to mam".
    private func lineRow(_ line: Pricing.Line) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(line.name)
                        .font(.callout)
                        .strikethrough(line.ownedByClient, color: .secondary)
                    if line.source == .fromProject {
                        Text("z projektu")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                // opis z cennika — handlowiec czyta to klientowi
                if let item = Pricing.catalogByID[line.itemID] {
                    Text(item.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if line.quantity != 1 {
                        Text("\(line.quantity.formatted()) szt.")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let d = line.dimensionMM, d > 0 {
                        Text("\(Int(d)) mm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(line.ownedByClient ? "—" : money(line.netValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(line.ownedByClient ? .secondary : .primary)

                // „Już to mam" — klient ma rzecz, nie płaci za nią
                Button {
                    toggleOwned(line)
                } label: {
                    Text(line.ownedByClient ? "Mam to" : "Już to mam")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(line.ownedByClient ? Color.green.opacity(0.22) : Color.secondary.opacity(0.14),
                                    in: Capsule())
                }
                .buttonStyle(.plain)

                if line.source == .manual {
                    Button {
                        manualLines.removeAll { $0.id == line.id }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    /// Co zostaje u klienta — porównanie stare z nowym, bez kwoty do zapłaty.
    private var ownedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Klient zostawia swoje", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(summary.owned) { line in
                HStack {
                    Text(line.name).font(.caption)
                    Spacer()
                    Text(money(line.referenceNetValue))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("Te pozycje nie są doliczone do wyceny — służą tylko do wizualizacji i zestawienia.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - cennik

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showCatalog.toggle() }
            } label: {
                HStack {
                    Label("Dodaj z cennika", systemImage: "plus.circle")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Image(systemName: showCatalog ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showCatalog {
                Picker("Kategoria", selection: $catalogGroup) {
                    ForEach(Pricing.Group.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(Pricing.catalog.filter { $0.group == catalogGroup }) { item in
                    Button {
                        addFromCatalog(item)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.group.pictogram)
                                .font(.footnote)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.callout)
                                Text(item.summary).font(.caption2).foregroundStyle(.secondary)
                                Text(item.purpose)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(money(item.unitPrice)).font(.caption.monospacedDigit())
                                Text(item.basis.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - pasek dolny

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(summary.billable.count) pozycji")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(money(summary.grossTotal))
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            Spacer()
            Button {
                applyToOrder()
                onClose()
            } label: {
                Label("Zapisz w zamówieniu", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(summary.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - akcje

    private func toggleOwned(_ line: Pricing.Line) {
        // klucz: dla szafki jej UUID, dla pozostałych id cennika
        let key = line.cabinetID?.uuidString ?? line.itemID
        if owned.contains(key) { owned.remove(key) } else { owned.insert(key) }
    }

    private func addFromCatalog(_ item: Pricing.Item) {
        let line = Pricing.line(from: item)
        manualLines.append(line)
    }

    /// Zapisuje wynik wyceny w zamówieniu — kwota i podsumowanie pozycji.
    private func applyToOrder() {
        model.status = "Wycena: \(money(summary.grossTotal)) · \(summary.billable.count) pozycji"
        model.applyCart(summary)
    }

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        return (f.string(from: NSNumber(value: value)) ?? "0") + " zł"
    }
}
