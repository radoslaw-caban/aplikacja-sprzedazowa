import SwiftUI
import UniformTypeIdentifiers
import CatalogCore

struct CatalogRootView: View {
    @Bindable var model: CatalogViewModel
    @State private var isDropTarget = false
    @State private var showNewManufacturer = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            HSplitView {
                productList
                    .frame(minWidth: 270, idealWidth: 300, maxWidth: 380)
                ProductDetail(model: model, product: model.selected)
                    .frame(minWidth: 620)
            }
        }
        .background(Color(red: 0.055, green: 0.075, blue: 0.115))
        .overlay(dropOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                model.beginImport(urls)
            }
            return true
        }
        .sheet(isPresented: $model.showImportSheet) {
            ImportSheet(model: model)
        }
        .sheet(isPresented: $showNewManufacturer) {
            NewManufacturerSheet(model: model, isPresented: $showNewManufacturer)
        }
    }

    // MARK: - nagłówek

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Katalog produktów")
                    .font(.system(size: 17, weight: .semibold))
                Text(model.store.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $model.filter) {
                ForEach(CatalogViewModel.StatusFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 430)
            .onChange(of: model.filter) { _, _ in model.reload() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Szukaj: nazwa, SKU, producent", text: $model.search)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            Button {
                showNewManufacturer = true
            } label: {
                Label("Producent", systemImage: "building.2")
            }
            .buttonStyle(.bordered)

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(red: 0.075, green: 0.10, blue: 0.15))
    }

    // MARK: - lista

    private var productList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.filtered) { product in
                        Button {
                            model.selection = product.id
                        } label: {
                            row(product)
                        }
                        .buttonStyle(.plain)
                        .background(model.selection == product.id
                                    ? Color.white.opacity(0.09)
                                    : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(8)
            }
            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.25))
            }
        }
        .background(Color(red: 0.065, green: 0.085, blue: 0.125))
    }

    private func row(_ product: CatalogProduct) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.statusColor(product.status))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text("\(model.manufacturerName(product.manufacturerID)) · \(product.sku)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(product.status == .approved ? product.pricing.retailText : product.status.label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: - upuszczanie modelu

    private var dropOverlay: some View {
        Group {
            if isDropTarget {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 12) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 46))
                        Text("Upuść model, żeby dodać produkt")
                            .font(.system(size: 16, weight: .semibold))
                        Text("GLB, OBJ, STL — konwersja i miniatura zrobią się same")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - szczegóły produktu

struct ProductDetail: View {
    @Bindable var model: CatalogViewModel
    var product: CatalogProduct?

    @State private var draft: CatalogProduct?
    @State private var margin: Double = 30
    @State private var rejection = ""
    @State private var showReject = false

    var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Wybierz produkt albo przeciągnij model do okna")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: product?.id) { _, _ in
            draft = product
            margin = product?.pricing.marginPercent ?? 30
            rejection = ""
        }
        .onChange(of: model.products) { _, _ in
            draft = product
        }
    }

    private func content(_ item: CatalogProduct) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(item)
                legalForm(item)
                pricingForm(item)
                dependencies(item)
                actions(item)
            }
            .padding(22)
        }
    }

    // MARK: sekcje

    private func hero(_ item: CatalogProduct) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.18, blue: 0.27),
                                                  Color(red: 0.07, green: 0.10, blue: 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = model.thumbnailURL(item), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit().padding(10)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "cube").font(.system(size: 26))
                        Text("brak miniatury").font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 230, height: 200)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.system(size: 20, weight: .semibold))
                HStack(spacing: 8) {
                    if let url = model.logoURL(item.manufacturerID), let logo = NSImage(contentsOf: url) {
                        Image(nsImage: logo).resizable().scaledToFit().frame(height: 18).frame(maxWidth: 110)
                    }
                    Text(model.manufacturerName(item.manufacturerID))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("SKU \(item.sku) · \(item.category.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(Int(item.width)) × \(Int(item.depth)) × \(Int(item.height)) mm")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                HStack(spacing: 8) {
                    statusPill(item.status)
                    Text(item.legal.basis.label).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Miniatura") { model.makeThumbnail(item) }
                        .buttonStyle(.bordered)
                    Button("Odsłoń w Finderze") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.productDir(item.id)])
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func statusPill(_ status: ProductStatus) -> some View {
        Text(status.label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(model.statusColor(status).opacity(0.22), in: Capsule())
            .foregroundStyle(model.statusColor(status))
    }

    private func legalForm(_ item: CatalogProduct) -> some View {
        section("Legalność") {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Podstawa geometrii").font(.system(size: 10)).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { draft?.legal.basis ?? .unknown },
                        set: { value in draft?.legal.basis = value; commit() }
                    )) {
                        ForEach(LegalBasis.allCases, id: \.self) { basis in
                            Text(basis.label).tag(basis)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ryzyko wzoru").font(.system(size: 10)).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { draft?.legal.designRisk ?? .medium },
                        set: { value in draft?.legal.designRisk = value; commit() }
                    )) {
                        ForEach(DesignRisk.allCases, id: \.self) { risk in
                            Text(risk.label).tag(risk)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dokument pochodzenia").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("np. Karta DEANTE Arnika 2 (2026-03)",
                              text: Binding(
                                get: { draft?.legal.provenance?.document ?? "" },
                                set: { value in
                                    draft?.legal.provenance = Provenance(document: value,
                                                                         reference: draft?.legal.provenance?.reference ?? "")
                                    commit()
                                }
                              ))
                    .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Referencja (plik/URL)").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("file:///…/karta.pdf",
                              text: Binding(
                                get: { draft?.legal.provenance?.reference ?? "" },
                                set: { value in
                                    draft?.legal.provenance = Provenance(document: draft?.legal.provenance?.document ?? "",
                                                                         reference: value)
                                    commit()
                                }
                              ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Notatka prawna (wymagana przy ryzyku wysokim)").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("np. opinia: bryła funkcjonalna, brak naruszenia wzoru",
                          text: Binding(
                            get: { draft?.legal.note ?? "" },
                            set: { value in draft?.legal.note = value; commit() }
                          ))
                .textFieldStyle(.roundedBorder)
            }

            let report = model.review(item)
            if !report.blockers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(report.blockers) { blocker in
                        HStack(spacing: 6) {
                            Image(systemName: blocker.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(blocker.severity == .blocking
                                                 ? Color(red: 0.85, green: 0.33, blue: 0.31)
                                                 : Color(red: 0.85, green: 0.63, blue: 0.23))
                            Text(blocker.message).font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func pricingForm(_ item: CatalogProduct) -> some View {
        section("Ceny i marża (nasza decyzja)") {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cena zakupu (gr)").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("32000", value: Binding(
                        get: { draft?.pricing.costGrosze ?? 0 },
                        set: { value in draft?.pricing.costGrosze = value; commit() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marża \(Int(margin))%").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: $margin, in: 0...80, step: 1, onEditingChanged: { editing in
                        if !editing { applyMargin() }
                    })
                    .frame(width: 260)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Detal").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(previewRetail(item))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private func previewRetail(_ item: CatalogProduct) -> String {
        let cost = draft?.pricing.costGrosze ?? item.pricing.costGrosze
        let value = Int((Double(cost) * (1 + margin / 100)).rounded())
        return Pricing.money(value, item.pricing.currency)
    }

    private func dependencies(_ item: CatalogProduct) -> some View {
        section("Opis zależności (\(item.dependencies.count))") {
            if item.dependencies.isEmpty {
                Text("Brak reguł — dla tej kategorii nie ma domyślnych zależności.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.dependencies) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: rule.hard ? "bolt.fill" : "info.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(rule.hard ? Color(red: 0.36, green: 0.55, blue: 0.94) : .secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.title).font(.system(size: 11))
                                Text(rule.note).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func actions(_ item: CatalogProduct) -> some View {
        HStack(spacing: 12) {
            if item.status == .draft || item.status == .rejected {
                Button("Zgłoś do zatwierdzenia") { model.submit(item) }
                    .buttonStyle(.borderedProminent)
            }
            if item.status == .submitted {
                Button {
                    model.approve(item, margin: margin)
                } label: {
                    Label("Zatwierdź z marżą \(Int(margin))%", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.22, green: 0.62, blue: 0.44))
            }
            if item.status == .submitted || item.status == .draft {
                Button("Odrzuć…") { showReject = true }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.80, green: 0.33, blue: 0.31))
            }
            Spacer()
            if item.status == .approved {
                Text("W oficjalnej bibliotece · \(item.pricing.retailText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.55))
            }
        }
        .padding(.top, 6)
        .alert("Powód odrzucenia", isPresented: $showReject) {
            TextField("np. brak dokumentu pochodzenia", text: $rejection)
            Button("Odrzuć", role: .destructive) { model.reject(item, reason: rejection) }
            Button("Anuluj", role: .cancel) {}
        }
    }

    // MARK: pomoc

    private func commit() {
        guard let draft else { return }
        model.save(draft)
    }

    private func applyMargin() {
        guard var draft else { return }
        draft.pricing.marginPercent = margin
        model.save(draft)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - import modelu

struct ImportSheet: View {
    @Bindable var model: CatalogViewModel
    @State private var name = ""
    @State private var sku = ""
    @State private var manufacturerID = ""
    @State private var category: ProductCategory = .accessory
    @State private var cost = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nowy produkt")
                .font(.system(size: 16, weight: .semibold))
            Text(model.pendingImport.map { $0.lastPathComponent }.joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Nazwa").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Zlew Arnikа 2", text: $name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("SKU").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("ARNIKA2", text: $sku).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Producent").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("", selection: $manufacturerID) {
                        Text("— wybierz —").tag("")
                        ForEach(model.manufacturers) { manufacturer in
                            Text(manufacturer.name).tag(manufacturer.id)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Kategoria").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("", selection: $category) {
                        ForEach(ProductCategory.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Cena zakupu (gr)").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("32000", value: $cost, format: .number).textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Anuluj") { model.showImportSheet = false }
                Button("Dodaj i zrób miniaturę") {
                    guard let url = model.pendingImport.first else { return }
                    let finalName = name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
                    let finalSKU = sku.isEmpty ? finalName : sku
                    let mfr = manufacturerID.isEmpty ? (model.manufacturers.first?.id ?? "inny") : manufacturerID
                    model.importModel(at: url, name: finalName, sku: finalSKU,
                                      manufacturerID: mfr, category: category, costGrosze: cost)
                    model.showImportSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.manufacturers.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            if let url = model.pendingImport.first {
                name = url.deletingPathExtension().lastPathComponent
                sku = name.uppercased().replacingOccurrences(of: " ", with: "")
            }
            manufacturerID = model.manufacturers.first?.id ?? ""
        }
    }
}

struct NewManufacturerSheet: View {
    @Bindable var model: CatalogViewModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var logo: URL?
    @State private var trademark = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nowy producent").font(.system(size: 16, weight: .semibold))
            TextField("Nazwa producenta", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button("Wybierz logo…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .svg]
                    if panel.runModal() == .OK { logo = panel.url }
                }
                Text(logo?.lastPathComponent ?? "brak logo (kafelek bez znaku)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Toggle("Zgoda na używanie znaku w katalogu (umowa/aneks)", isOn: $trademark)
                .font(.system(size: 11))
            HStack {
                Spacer()
                Button("Anuluj") { isPresented = false }
                Button("Dodaj") {
                    model.addManufacturer(name: name, logo: logo, trademarkApproved: trademark)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
