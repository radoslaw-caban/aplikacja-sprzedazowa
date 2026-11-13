import SwiftUI
import UniformTypeIdentifiers
import KitchenCore
// UIKit tylko na iOS — bez tego warunku pakiet nie kompiluje się na macOS
// (ten sam wzorzec co w ContractSheet i DocumentsView).
#if canImport(UIKit)
import UIKit
#endif

/// Wysuwana z lewej biblioteka / edytor.
///
/// Nic nie jest zaznaczone → biblioteka (kategorie na zakładkach przy krawędzi).
/// Klik w element w 3D → panel zamienia się w edytor tego elementu.
/// Wyjście: ESC (Mac) albo gest przesunięcia w lewo / X (iPad).
struct LibraryDock: View {
    @Bindable var model: AppModel
    @Binding var open: Bool
    /// Otwiera pełny kreator stref (z wyborem ściany) — biblioteka nie
    /// zgaduje ściany, bo strefa bez ściany nie ma sensu.
    var onOpenZoneDesigner: () -> Void = {}

    @State private var category: DockCategory = .cabinets
    @State private var importing = false
    @State private var importError: String?
    @State private var flash = false
    @State private var userModels = UserModelStore.shared.models
    @State private var settings = AppSettings.load()
    @State private var sparklePoint: CGPoint = .zero
    @State private var sparkleAlive = false

    private let panelWidth: CGFloat = 408
    private let tabWidth: CGFloat = 38

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
            userModels = UserModelStore.shared.models
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

    /// Zakładki kategorii przy krawędzi ekranu.
    ///
    /// Zasada wizualna: wybrana kategoria ma tło w swoim kolorze i obwódkę
    /// w ciemniejszym odcieniu tego samego koloru; pozostałe są „cofnięte" —
    /// bez tła i obwódki, przygaszone. Panel jest jasny (materiał), więc tekst
    /// aktywnej zakładki jest w ciemnym odcieniu kategorii, nie biały —
    /// biały na pastelu byłby nieczytelny.
    private var tabs: some View {
        VStack(spacing: 5) {
            ForEach(DockCategory.allCases) { cat in
                let on = category == cat && open
                Button {
                    if category != cat { Haptics.tap() }
                    category = cat
                    open = true
                    if model.selectedCabinetID != nil { model.selectedCabinetID = nil }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(cat.short)
                            .font(.system(size: 7, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? cat.ink : Color.primary.opacity(0.45))
                    .frame(width: tabWidth, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(on ? cat.tint.opacity(0.55) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(on ? cat.ink : Color.clear, lineWidth: 1.6)
                    )
                }
                .buttonStyle(.plain)
                .help(cat.title)
            }
            Spacer(minLength: 0)
        }
        // Przesuwanie wzdłuż krawędzi po zakładkach: kategoria zmienia się
        // płynnie, a haptyka stuka przy KAŻDYM przejściu na sąsiednią —
        // to daje wrażenie „magii wokół palca" bez zalewania silnika wibracji.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let step = 58.0
                    let idx = Int((value.location.y / step).rounded(.down))
                    let clamped = min(max(idx, 0), DockCategory.allCases.count - 1)
                    let target = DockCategory.allCases[clamped]
                    guard target != category else { return }
                    category = target
                    open = true
                    if model.selectedCabinetID != nil { model.selectedCabinetID = nil }
                    Haptics.tap()
                    sparkle(at: value.location)
                }
        )
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .padding(.top, 6)
        // Tło pod całym paskiem: bez niego nieaktywne zakładki są
        // przezroczyste i przebija przez nie scena 3D (błękit nieba czyta
        // się wtedy jak kolor kategorii). Szkło ujednolica tło.
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .overlay {
            if sparkleAlive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, category.tint.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)
                    .position(sparklePoint)
                    .scaleEffect(sparkleAlive ? 1.25 : 0.4)
                    .opacity(sparkleAlive ? 0.9 : 0)
                    .allowsHitTesting(false)
            }
        }
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
                .foregroundStyle(category.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedCabinetID == nil ? category.title : "Edycja elementu")
                    .font(.callout.weight(.semibold))
                if let id = model.selectedCabinetID,
                   let c = model.cabinet(id: id) {
                    Text(c.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(category.hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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

    /// Wspólna karta: JEDNA obwódka w kolorze kategorii spina całą listę,
    /// a pozostałe kategorie są cofnięte — kontur jednoznacznie wskazuje wybór.
    @ViewBuilder
    private var categoryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch category {
                case .zones:      zonesLibrary
                case .cabinets:   cabinetsLibrary
                case .decor:      decorLibrary
                case .lights:     lightsLibrary
                case .appliances: appliancesLibrary
                }
            }
            .padding(10)
        }
        // Obwódka na ScrollView, nie na treści: rama obejmuje CAŁĄ kartę
        // i nie ucieka przy przewijaniu długiej listy.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(category.ink.opacity(0.55), lineWidth: 1.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    // MARK: strefy użytkowe i przyłącza

    private var zonesLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Strefy funkcjonalne z przyłączami. Strefa przypina się do ściany planu i generuje zabudowę.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !model.currentZones.isEmpty {
                sectionTitle("Strefy w projekcie")
                ForEach(model.currentZones) { z in
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(category.ink)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(z.name).font(.caption.weight(.semibold))
                            Text("ściana \(z.wallIndex + 1)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if z.draft == true {
                            Text("podgląd")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(category.ink)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(category.tint.opacity(0.35),
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                sectionTitle("Nowa strefa")
            }

            ForEach(ZoneKind.allCases, id: \.rawValue) { kind in
                Button {
                    onOpenZoneDesigner()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(category.ink)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zoneLabel(kind)).font(.caption.weight(.semibold))
                            Text(zoneGroupLabel(kind)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(category.ink)
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func zoneLabel(_ k: ZoneKind) -> String {
        switch k {
        case .kitchenCook: "Strefa gotowania"
        case .kitchenClean: "Strefa zlewu"
        case .kitchenTall: "Strefa wysokiej zabudowy"
        case .kitchenIsland: "Wyspa kuchenna"
        case .wardrobeHinged: "Szafa na zawiasach"
        case .wardrobeSliding: "Szafa przesuwna"
        case .livingTV: "Strefa TV"
        case .bathroom: "Łazienka"
        }
    }

    private func zoneGroupLabel(_ k: ZoneKind) -> String {
        switch k {
        case .kitchenCook, .kitchenClean, .kitchenTall, .kitchenIsland: "Kuchnia"
        case .wardrobeHinged, .wardrobeSliding: "Sypialnia"
        case .livingTV: "Salon"
        case .bathroom: "Łazienka"
        }
    }

    // MARK: szafki

    private var cabinetsLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Korpusy")
            ForEach(Library.all) { t in
            Button {
                addCabinet(t)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cabinet.fill")
                        .foregroundStyle(category.ink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.caption.weight(.semibold))
                        Text(t.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(category.ink)
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            }

            sectionTitle("Wykończenia frontów")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(CabinetFinishes.all) { finish in
                    Button { applyFinish(finish) } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: finish.fallbackColor))
                                .frame(height: 50)
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

            sectionTitle("Zawiasy")
            ForEach(HingeType.allCases) { h in
                Button { applyHinge(h) } label: {
                    HStack {
                        Image(systemName: h.symbol).foregroundStyle(category.ink).frame(width: 24)
                        Text(h.label).font(.caption)
                        Spacer()
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Nagłówek sekcji wewnątrz kategorii — małą kapitaliką, w kolorze kategorii.
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(category.ink.opacity(0.75))
            .padding(.top, 2)
    }

    // MARK: elementy dekoracyjne

    private var decorLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Wyposażenie wnętrza")
            ForEach(CabinetAccessoryKind.allCases) { kind in
                Button {
                    addAccessory(kind)
                } label: {
                    HStack {
                        Image(systemName: kind.symbol)
                            .foregroundStyle(category.ink)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.label).font(.caption.weight(.semibold))
                            Text("y = \(Int(kind.defaultY)) mm").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(category.ink)
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            sectionTitle("Własne modele 3D")
            modelsSection
        }
    }

    // MARK: oświetlenie

    private var lightsLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oprawy dodają się do zaznaczonej szafki jako element oświetlenia.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(LightTemplate.all) { t in
                Button {
                    addLight(t)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: t.hex))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.label).font(.caption.weight(.semibold))
                            Text(t.hint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(t.temp)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: AGD

    private var appliancesLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Urządzenia wstawiają się do zaznaczonej szafki. Wymiary zgodne z zabudową EU.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(ApplianceItem.all) { a in
                Button {
                    addAppliance(a.kind)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundStyle(category.ink)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.label).font(.caption.weight(.semibold))
                            Text(a.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(a.w))×\(Int(a.h))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: wykończenia

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

    // MARK: zawiasy

    private var hingesLibrary: some View {
        ForEach(HingeType.allCases) { h in
            Button {
                applyHinge(h)
            } label: {
                HStack {
                    Image(systemName: h.symbol)
                        .foregroundStyle(category.ink)
                        .frame(width: 24)
                    Text(h.label).font(.caption)
                    Spacer()
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: modele 3D

    @ViewBuilder
    private var modelsSection: some View {
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
                    .background(category.tint.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            if let importError {
                Text(importError).font(.caption2).foregroundStyle(.orange)
            }

            ForEach(userModels) { m in
                HStack {
                    Image(systemName: "cube").foregroundStyle(category.ink)
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
        Haptics.success()
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

    /// AGD trafia do zaznaczonej szafki. Bez zaznaczenia — komunikat, nie ciche nic.
    private func addAppliance(_ kind: ApplianceKind) {
        guard let id = model.selectedCabinetID,
              var c = model.cabinet(id: id) else {
            model.status = "Najpierw zaznacz szafkę, do której wstawić AGD"
            Haptics.warning()
            return
        }
        var list = c.appliances ?? []
        guard !list.contains(kind) else {
            model.status = "To urządzenie już jest w tej szafce"
            Haptics.warning()
            return
        }
        list.append(kind)
        c.appliances = list
        model.updateCabinet(c)
        flashMagic()
    }

    /// Oświetlenie jako element szafki (taśma LED w korpusie).
    private func addLight(_ t: LightTemplate) {
        guard let id = model.selectedCabinetID,
              var c = model.cabinet(id: id) else {
            model.status = "Najpierw zaznacz szafkę dla oświetlenia"
            Haptics.warning()
            return
        }
        var list = c.accessories ?? []
        list.append(CabinetAccessory(kind: .led))
        c.accessories = list
        model.updateCabinet(c)
        model.status = "Dodano: \(t.label) (\(t.temp))"
        flashMagic()
    }

    // MARK: - magia wokół palca

    /// Krótka iskra w miejscu dotknięcia — wizualne dopełnienie haptyki.
    /// Trzymana w jednym stanie i wygaszana po 0.4 s, więc nie spamuje
    /// sceny (jedna iskra naraz, nie sto).
    private func sparkle(at p: CGPoint) {
        guard settings.magicEffects else { return }
        sparklePoint = p
        withAnimation(.easeOut(duration: 0.4)) { sparkleAlive = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.2)) { sparkleAlive = false }
        }
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

// MARK: - kategorie

/// Kategorie biblioteki — kolejność od góry i kolor przypadający na kategorię.
///
/// Paleta: stonowane, ciepłe pastele o zbliżonej jasności i nasyceniu.
/// Wszystkie czytelne na ciemnym tle, żaden nie „krzyczy".
/// Kolor jest jeden i ten sam w trzech miejscach: obwódka zakładki,
/// obwódka karty z listą, akcent ikon i nagłówka.
private enum DockCategory: String, CaseIterable, Identifiable {
    case zones, cabinets, decor, lights, appliances

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zones: "Strefy użytkowe i przyłącza"
        case .cabinets: "Szafki"
        case .decor: "Elementy dekoracyjne"
        case .lights: "Oświetlenie"
        case .appliances: "AGD"
        }
    }

    var short: String {
        switch self {
        case .zones: "STREFY"
        case .cabinets: "SZAFKI"
        case .decor: "DEKOR"
        case .lights: "ŚWIATŁO"
        case .appliances: "AGD"
        }
    }

    var icon: String {
        switch self {
        case .zones: "square.grid.2x2"
        case .cabinets: "cabinet.fill"
        case .decor: "sparkles"
        case .lights: "lightbulb.fill"
        case .appliances: "square.grid.3x3.fill"
        }
    }

    var hint: String {
        switch self {
        case .zones: "Strefy funkcjonalne z przyłączami"
        case .cabinets: "Korpusy, wykończenia i zawiasy"
        case .decor: "Półki, szuflady, kosze, własne modele"
        case .lights: "Taśmy LED i oprawy podszafkowe"
        case .appliances: "Zlew, płyta, piekarnik, lodówka, okap"
        }
    }

    /// Kolor kategorii — stonowany, ciepły, o zbliżonej jasności do pozostałych.
    /// Używany jako TŁO aktywnej zakładki i delikatny akcent w karcie.
    var tint: Color {
        switch self {
        case .zones: Color(red: 0.82, green: 0.60, blue: 0.60)      // pudrowy róż
        case .cabinets: Color(red: 0.62, green: 0.72, blue: 0.62)   // szałwia
        case .decor: Color(red: 0.69, green: 0.65, blue: 0.81)      // lawenda
        case .lights: Color(red: 0.86, green: 0.70, blue: 0.54)     // morela
        case .appliances: Color(red: 0.58, green: 0.68, blue: 0.78) // przygaszony błękit
        }
    }

    /// Ciemniejszy odcień tego samego koloru — na tekst i obwódkę.
    /// Panel biblioteki jest jasny (materiał), więc pastele same z siebie
    /// nie mają kontrastu; ten wariant jest czytelny i zachowuje barwę kategorii.
    var ink: Color {
        switch self {
        case .zones: Color(red: 0.55, green: 0.28, blue: 0.31)
        case .cabinets: Color(red: 0.27, green: 0.42, blue: 0.28)
        case .decor: Color(red: 0.36, green: 0.30, blue: 0.52)
        case .lights: Color(red: 0.58, green: 0.36, blue: 0.14)
        case .appliances: Color(red: 0.22, green: 0.36, blue: 0.50)
        }
    }
}

// MARK: - haptyka

/// Haptyka iPada — jedno miejsce, żeby nie rozsypać się po widokach.
///
/// Respektuje przełącznik „Haptyka" w Ustawieniach: ktoś może chcieć
/// wibrację bez dźwięku (np. w słuchawkach) albo odwrotnie — ciszę bez
/// wibracji na spotkaniu. Dlatego te dwa kanały są rozdzielone.
@MainActor
enum Haptics {
    /// Cache przełącznika haptyki.
    ///
    /// `AppSettings.load()` dekoduje JSON z UserDefaults przy KAŻDYM wywołaniu.
    /// Przy przesuwaniu palcem po kategoriach `tap()` leci kilkadziesiąt razy
    /// na sekundę — dekodowanie w pętli gestu to realne jąkanie na iPadzie.
    /// Dlatego czytamy raz i unieważniamy po zmianie ustawień.
    private static var cachedEnabled: Bool?

    /// Unieważnia cache — wołać po zamknięciu panelu Ustawień.
    static func invalidateSettings() {
        cachedEnabled = nil
    }

    private static var enabled: Bool {
        if let cachedEnabled { return cachedEnabled }
        let value = AppSettings.load().hapticsEnabled
        cachedEnabled = value
        return value
    }

    static func tap() {
        #if os(iOS)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        #if os(iOS)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if os(iOS)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - dane AGD i oświetlenia

/// Urządzenia AGD z realnymi wymiarami zabudowy (EU).
/// Wymiary w mm, zgodne ze standardem 600 mm zabudowy.
struct ApplianceItem: Identifiable {
    let kind: ApplianceKind
    let label: String
    let w: Double
    let h: Double
    let note: String

    var id: String { kind.rawValue }

    static let all: [ApplianceItem] = [
        ApplianceItem(kind: .sink, label: "Zlew", w: 600, h: 500,
                      note: "Podblatowy / wpuszczany, szlif 600"),
        ApplianceItem(kind: .hob, label: "Płyta grzewcza", w: 580, h: 510,
                      note: "Indukcyjna 4 pola, szlif 580×510"),
        ApplianceItem(kind: .oven, label: "Piekarnik", w: 595, h: 595,
                      note: "Zabudowa 60 cm, nisza 600×600"),
        ApplianceItem(kind: .microwave, label: "Mikrofala", w: 595, h: 380,
                      note: "Zabudowa 60 cm, nisza 600×390"),
        ApplianceItem(kind: .fridge, label: "Lodówka", w: 560, h: 1780,
                      note: "Słupkowa, wysokość zabudowy 1780"),
        ApplianceItem(kind: .hood, label: "Okap", w: 600, h: 500,
                      note: "Podszafkowy 60 cm, wylot Ø150"),
        ApplianceItem(kind: .dishwasher, label: "Zmywarka", w: 600, h: 815,
                      note: "Do zabudowy, 60 cm"),
    ]
}

/// Oprawy oświetleniowe — temperatury zgodne z praktyką (ciepłe 2700–3000 K).
struct LightTemplate: Identifiable {
    let label: String
    let hint: String
    let hex: String
    let temp: String

    var id: String { label }

    static let all: [LightTemplate] = [
        LightTemplate(label: "Taśma LED pod szafką",
                      hint: "Profil aluminiowy 16×8 mm, pod górnymi szafkami",
                      hex: "#fff3d6", temp: "3000 K"),
        LightTemplate(label: "Taśma LED w cokole",
                      hint: "Profil wpuszczany w cokół, efekt unoszenia",
                      hex: "#ffe9c4", temp: "2700 K"),
        LightTemplate(label: "Oprawa podszafkowa",
                      hint: "LED punktowy pod szafką górną",
                      hex: "#fff8e7", temp: "3000 K"),
        LightTemplate(label: "Oprawa sufitowa",
                      hint: "Panel lub plafon, światło ogólne",
                      hex: "#fffdf5", temp: "4000 K"),
        LightTemplate(label: "Kinkiet ścienny",
                      hint: "Oprawa na ścianie, światło akcentowe",
                      hex: "#ffeccc", temp: "2700 K"),
    ]
}

private extension Color {
    static let gold = Color(red: 0.98, green: 0.83, blue: 0.35)
}
