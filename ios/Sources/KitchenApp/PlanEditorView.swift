import SwiftUI
import KitchenCore
import simd

/// Widok „Mapa": plan pomieszczenia trzema drogami —
/// **prostokąt** przeciągnięciem, **wymiary** wpisane z klawiatury, **kreski** punkt po punkcie.
///
/// ZASADA: plan jest źródłem prawdy dla bryły domu. Każda zmiana tutaj
/// przelicza pokój (szerokość × głębokość × wysokość), więc 3D od razu
/// odpowiada narysowanemu planowi.
struct PlanEditorView: View {
    @Binding var plan: FloorPlan
    /// wywoływane po każdej zmianie (zapis do projektu)
    var onChange: (FloorPlan) -> Void
    /// wywoływane po kliknięciu „Wstaw szafki" na zaznaczonej ścianie
    var onFillWall: ((Int) -> Void)? = nil
    /// wywoływane po kliknięciu „Strefa…" — auto-projekt zabudowy na ścianie
    var onZoneWall: ((Int) -> Void)? = nil
    /// tryb wybrany w pytaniu „jak określimy budynek?"
    var startMode: Mode? = nil
    /// od razu otwórz listę gotowych planów
    var startWithPresets: Bool = false
    /// od razu otwórz import planu z obrazu
    var startWithImport: Bool = false

    /// Sposób wprowadzania planu.
    enum Mode: String, CaseIterable, Identifiable {
        case rectangle = "Prostokąt"
        case dimensions = "Wymiary"
        case lines = "Kreski"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .rectangle: "rectangle.dashed"
            case .dimensions: "ruler"
            case .lines: "pencil.tip"
            }
        }
    }

    @State private var mode: Mode = .rectangle
    @State private var selectedWall: Int?
    @State private var lengthText: String = ""

    // rysowanie prostokąta przeciągnięciem
    @State private var dragStart: SIMD2<Double>?
    @State private var dragCurrent: SIMD2<Double>?

    // formularz wymiarów (mm jako tekst — łatwiej wpisywać)
    @State private var widthText = "3600"
    @State private var depthText = "3000"
    @State private var heightText = "2600"
    @State private var thicknessText = "120"

    /// Skok przyciągania przy rysowaniu (mm).
    private let snap: Double = 50

    // widok kartki: zbliżenie i przesunięcie
    @State private var zoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var showPresets = false
    @State private var showTakeoff = false
    @State private var showImport = false
    @State private var settings = AppSettings.load()

    // przesuwanie ściany palcem
    @State private var draggingWall: Int?
    @State private var lastDragMM: SIMD2<Double> = .zero
    @State private var lastDrag: CGSize = .zero
    /// dwa palce na ekranie = przesuwanie kartki (nie rysowanie)
    @State private var pinching = false
    /// wyjście do widoku 3D po przeciągnięciu za prawą krawędź
    var onOpen3D: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            modeBar

            GeometryReader { geo in
                let fit = PlanFit(plan: plan, size: geo.size, zoom: zoom, offset: panOffset)
                ZStack(alignment: .bottom) {
                    NotebookCanvas(plan: plan, fit: fit, selected: selectedWall, preview: previewRect,
                                   zoom: zoom, showPencil: settings.showPencil && zoom < 0.85)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(fit: fit, size: geo.size))
                        .simultaneousGesture(zoomGesture)
                        .onTapGesture { location in
                            guard mode == .lines else { return }
                            handleTap(at: location, fit: fit)
                        }

                    VStack(spacing: 10) {
                        if mode == .rectangle, previewRect == nil {
                            hint("Przeciągnij po planie od narożnika do narożnika.\nWymiary i pole pokazują się na bieżąco.")
                        }
                        if mode == .dimensions {
                            dimensionsPanel
                        }
                        lengthPanel
                    }
                    .padding(14)
                }
            }

            controls
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        .sheet(isPresented: $showPresets) {
            PlanPresetSheet { preset in
                plan = preset.plan()
                selectedWall = nil
                zoom = 1
                panOffset = .zero
                syncFields(from: plan)
            }
        }
        .sheet(isPresented: $showTakeoff) {
            TakeoffSheet(plan: plan, settings: settings)
        }
        .sheet(isPresented: $showImport) {
            PlanImportSheet { imported in
                plan = imported
                selectedWall = nil
                zoom = 1
                panOffset = .zero
                syncFields(from: plan)
            }
        }
        .onChange(of: plan) { _, new in
            syncFields(from: new)
            onChange(new)
        }
        .task {
            // hak diagnostyczny: zaznaczenie ściany bez dotykania ekranu
            if UserDefaults.standard.object(forKey: "demoWall") != nil {
                try? await Task.sleep(nanoseconds: 900_000_000)
                let index = UserDefaults.standard.integer(forKey: "demoWall")
                NSLog("[plan] demoWall=\(index), ścian=\(plan.wallCount), wall0=\(plan.wall(0) != nil)")
                if let wall = plan.wall(index) {
                    selectedWall = index
                    lengthText = String(Int(wall.length.rounded()))
                    if UserDefaults.standard.bool(forKey: "demoFill") {
                        onFillWall?(index)
                    }
                }
            }
        }
        .onAppear {
            syncFields(from: plan)
            // hak diagnostyczny: `defaults write ... planMode Wymiary` otwiera panel wymiarów
            if let startMode {
                mode = startMode
            } else if let saved = UserDefaults.standard.string(forKey: "planMode"), let savedMode = Mode(rawValue: saved) {
                mode = savedMode
            }
            if startWithPresets { showPresets = true }
            if startWithImport { showImport = true }
            // hak diagnostyczny: zbliżenie kartki z Ustawień (weryfikacja widoku notesu)
            if UserDefaults.standard.object(forKey: "planZoom") != nil {
                zoom = CGFloat(UserDefaults.standard.double(forKey: "planZoom"))
            }
            if let preset = UserDefaults.standard.string(forKey: "planPreset") {
                let values: [String: (Double, Double)] = [
                    "Kuchnia": (3000, 3600), "Salon": (5200, 6400),
                    "Łazienka": (2200, 2400), "Sypialnia": (3600, 4200),
                ]
                if let size = values[preset] {
                    applyDimensions(width: size.0, depth: size.1)
                }
            }
        }
    }

    // MARK: - nagłówek

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pomieszczenie").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                showPresets = true
            } label: {
                Label("Plany", systemImage: "square.grid.2x2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            Button {
                showImport = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            Button {
                onOpen3D?()
            } label: {
                Label("Przejdź do 3D", systemImage: "cube.transparent")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            Button {
                showTakeoff = true
            } label: {
                Label("Zestawienie", systemImage: "list.bullet.rectangle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            Spacer()
            if plan.closed {
                Label("zamknięty", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("rysuj kreskami", systemImage: "pencil.tip")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Wszystko w milimetrach — tak, jak się to podaje na produkcji.
    private var summary: String {
        let size = plan.size
        return "\(Units.mm(size.x)) × \(Units.mm(size.y)) mm · "
            + "\(Units.m2Area(plan.areaM2 * 1_000_000)) · "
            + "wys. \(Units.mm(plan.height)) mm · ściana \(Units.mm(plan.thickness)) mm"
    }

    // MARK: - wybór trybu

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { item in
                Button {
                    mode = item
                    selectedWall = nil
                    dragStart = nil
                    dragCurrent = nil
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.subheadline.weight(mode == item ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode == item ? Color.orange.opacity(0.22) : Color.white.opacity(0.06))
                )
                .foregroundStyle(mode == item ? Color.orange : Color.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - panel wymiarów

    private var dimensionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wymiary pomieszczenia").font(.subheadline.weight(.semibold))
                Spacer()
                Text("mm").font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                numberField("Szerokość", text: $widthText)
                Text("×").foregroundStyle(.secondary)
                numberField("Głębokość", text: $depthText)
                Text("×").foregroundStyle(.secondary)
                numberField("Wysokość", text: $heightText)
            }

            HStack(spacing: 10) {
                numberField("Ściana", text: $thicknessText)
                Spacer()
                Button {
                    applyDimensions()
                } label: {
                    Label("Utwórz", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
            }

            // gotowe wielkości — najczęstsze pomieszczenia
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    preset("Kuchnia", 3000, 3600)
                    preset("Salon", 5200, 6400)
                    preset("Łazienka", 2200, 2400)
                    preset("Sypialnia", 3600, 4200)
                    preset("Willa", 12800, 9600)
                }
            }

            Text("Przycisk „Utwórz” zastępuje plan prostokątem o tych wymiarach — środek zostaje.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func numberField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField("mm", text: text)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
                .onSubmit { applyDimensions() }
        }
    }

    private func preset(_ name: String, _ width: Double, _ depth: Double) -> some View {
        Button {
            widthText = String(Int(width))
            depthText = String(Int(depth))
            applyDimensions(width: width, depth: depth)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.caption.weight(.semibold))
                Text("\(Int(width)) × \(Int(depth))").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Wpisane wymiary → plan. Rozmiar zmieniamy wokół środka, więc pomieszczenie nie ucieka.
    private func applyDimensions(width: Double? = nil, depth: Double? = nil) {
        let width = max(500, width ?? parse(widthText))
        let depth = max(500, depth ?? parse(depthText))
        let height = parse(heightText).clamped(to: 2000...4000, fallback: 2600)
        let thickness = parse(thicknessText).clamped(to: 40...400, fallback: 120)

        let b = plan.bounds
        let cx = plan.points.isEmpty ? 0 : (b.min.x + b.max.x) / 2
        let cz = plan.points.isEmpty ? 0 : (b.min.y + b.max.y) / 2

        plan = FloorPlan.rectangle(
            x: cx - width / 2,
            z: cz - depth / 2,
            width: width,
            depth: depth,
            height: height,
            thickness: thickness
        )
        selectedWall = nil
        syncFields(from: plan)
    }

    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }) ?? 0
    }

    private func syncFields(from plan: FloorPlan) {
        let size = plan.size
        if size.x > 0 { widthText = String(Int(size.x.rounded())) }
        if size.y > 0 { depthText = String(Int(size.y.rounded())) }
        heightText = String(Int(plan.height.rounded()))
        thicknessText = String(Int(plan.thickness.rounded()))
    }

    // MARK: - rysowanie prostokąta

    private var previewRect: RectPreview? {
        guard mode == .rectangle, let start = dragStart, let current = dragCurrent else { return nil }
        let preview = FloorPlan.rectangle(from: start, to: current, snap: snap)
        let b = preview.bounds
        return RectPreview(
            min: b.min,
            max: b.max,
            width: b.max.x - b.min.x,
            depth: b.max.y - b.min.y
        )
    }

    /// Główny gest kartki:
    /// 1) złapanie ściany → przesuwanie prostopadłe (plan się rozszerza/zwęża),
    /// 2) tryb prostokąta → rysowanie nowego obrysu,
    /// 3) przy zbliżeniu → przesuwanie kartki.
    private func drawGesture(fit: PlanFit, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // 0) dwa palce na ekranie (szczypanie) → przesuwamy kartkę, nie rysujemy
                if pinching {
                    panOffset.width += value.translation.width - lastDrag.width
                    panOffset.height += value.translation.height - lastDrag.height
                    lastDrag = value.translation
                    return
                }

                // 1) ściana pod palcem?
                if draggingWall == nil, dragStart == nil {
                    let start = fit.planPoint(fromScreen: value.startLocation)
                    if let hit = plan.nearestWall(to: start), hit.distance <= fit.mmPerPoint * 26 {
                        draggingWall = hit.index
                        selectedWall = hit.index
                        lastDragMM = .zero
                    }
                }

                if let index = draggingWall {
                    let total = fit.planPoint(fromScreen: value.location)
                        - fit.planPoint(fromScreen: value.startLocation)
                    let delta = total - lastDragMM
                    lastDragMM = total
                    guard let wall = plan.wall(index) else { return }
                    let d = wall.b - wall.a
                    let length = simd_length(d)
                    guard length > 1e-6 else { return }
                    let normal = SIMD2<Double>(-d.y / length, d.x / length)
                    let shift = simd_dot(delta, normal)
                    if abs(shift) > 0.5 {
                        // przyciąganie do siatki 10 mm — palcem nie trafimy w 1 mm
                        plan.moveWall(index, by: Units.quantize((shift / 10).rounded() * 10))
                    }
                    return
                }

                guard mode == .rectangle else {
                    // tryb kresek: tylko przesuwanie kartki przy zbliżeniu
                    if zoom > 1.02 {
                        panOffset.width += value.translation.width - lastDrag.width
                        panOffset.height += value.translation.height - lastDrag.height
                        lastDrag = value.translation
                    }
                    return
                }

                if dragStart == nil { dragStart = fit.planPoint(fromScreen: value.startLocation) }
                dragCurrent = fit.planPoint(fromScreen: value.location)
            }
            .onEnded { value in
                // przeciągnięcie poza prawą krawędź kartki = przejście do 3D
                if value.startLocation.x > size.width * 0.62,
                   value.translation.width > 90,
                   abs(value.translation.height) < 160,
                   draggingWall == nil {
                    onOpen3D?()
                    return
                }

                if draggingWall != nil {
                    draggingWall = nil
                    lastDragMM = .zero
                    syncFields(from: plan)
                    lastDrag = .zero
                    return
                }

                lastDrag = .zero

                guard mode == .rectangle, let start = dragStart else { return }
                let end = fit.planPoint(fromScreen: value.location)
                defer {
                    dragStart = nil
                    dragCurrent = nil
                }
                // za małe przeciągnięcie = przypadkowy dotyk, plan zostaje
                guard abs(end.x - start.x) > 200, abs(end.y - start.y) > 200 else { return }
                plan = FloorPlan.rectangle(
                    from: start,
                    to: end,
                    snap: snap,
                    height: parse(heightText).clamped(to: 2000...4000, fallback: 2600),
                    thickness: parse(thicknessText).clamped(to: 40...400, fallback: 120)
                )
                selectedWall = nil
            }
    }

    /// Szczypanie: palce **na zewnątrz = przybliżenie**, do środka = oddalenie.
    /// (wcześniej było odwrotnie — stąd wrażenie, że zoom „działa na opak")
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinching = true
                let step = pow(Double(max(0.2, value.magnification)), settings.zoomSensitivity)
                zoom = min(4.0, max(0.45, zoom * CGFloat(step)))
            }
            .onEnded { _ in
                pinching = false
            }
    }

    // MARK: - gesty kreskami

    private func handleTap(at point: CGPoint, fit: PlanFit) {
        let planPoint = fit.planPoint(fromScreen: point)

        // 1) klik w istniejącą ścianę → wybór do edycji długości
        if let hit = plan.nearestWall(to: planPoint), hit.distance <= fit.mmPerPoint * 22 {
            selectedWall = hit.index
            if let w = plan.wall(hit.index) {
                lengthText = String(Int(w.length.rounded()))
            }
            return
        }

        // 2) klik w wolne miejsce → kolejny punkt planu
        selectedWall = nil
        guard !plan.closed else { return }
        plan.append(planPoint)
    }

    // MARK: - panel długości ściany

    private var lengthPanel: some View {
        Group {
            if let index = selectedWall, let wall = plan.wall(index) {
                VStack(spacing: 10) {
                    HStack {
                        Text("Ściana \(index + 1)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            selectedWall = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("mm", text: $lengthText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onSubmit { applyLength() }

                        Text("mm").font(.caption).foregroundStyle(.secondary)

                        Button("Ustaw") { applyLength() }
                            .buttonStyle(.borderedProminent)

                        Spacer()

                        ForEach([-100.0, -10.0, 10.0, 100.0], id: \.self) { delta in
                            Button("\(delta > 0 ? "+" : "")\(Int(delta))") {
                                setLength(wall.length + delta)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }

                    if onFillWall != nil {
                        wallFillRow(index: index, wall: wall)
                    }

                    HStack(spacing: 12) {
                        Text(String(format: "kąt %.1f°", wall.angleDeg))
                        Text(String(format: "od (%.0f, %.0f) do (%.0f, %.0f)",
                                    wall.a.x, wall.a.y, wall.b.x, wall.b.y))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    /// Podgląd rozstawu i przycisk „Wstaw szafki" — program sam dzieli ścianę.
    private func wallFillRow(index: Int, wall: (a: SIMD2<Double>, b: SIMD2<Double>, length: Double, angleDeg: Double)) -> some View {
        let preview = WallFill.fill(wallStart: wall.a, wallEnd: wall.b)
        return VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Image(systemName: "square.split.2x1")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zabudowa ściany").font(.caption.weight(.semibold))
                    Text(preview.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onZoneWall {
                    Button {
                        onZoneWall(index)
                    } label: {
                        Label("Strefa…", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    onFillWall?(index)
                } label: {
                    Label("Wstaw szafki", systemImage: "plus.square.on.square")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.cabinets.isEmpty)
            }
        }
    }

    private func applyLength() {
        setLength(parse(lengthText))
    }

    private func setLength(_ value: Double) {
        guard let index = selectedWall else { return }
        plan.setWallLength(index, to: value)
        if let w = plan.wall(index) {
            lengthText = String(Int(w.length.rounded()))
        }
    }

    // MARK: - pasek akcji

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                plan.removeLastPoint()
                selectedWall = nil
            } label: {
                Label("Cofnij punkt", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(plan.points.isEmpty)

            Button {
                if plan.closed { plan.open() } else if plan.points.count >= 3 { plan.closed = true }
                selectedWall = nil
            } label: {
                Label(plan.closed ? "Otwórz" : "Zamknij plan",
                      systemImage: plan.closed ? "lock.open" : "lock")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                applyDimensions()
            } label: {
                Label("Zastosuj wymiary", systemImage: "ruler.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                onOpen3D?()
            } label: {
                Label("Przejdź do projektu 3D", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
}

// MARK: - podgląd rysowanego prostokąta

struct RectPreview: Equatable {
    let min: SIMD2<Double>
    let max: SIMD2<Double>
    let width: Double
    let depth: Double
}

extension Double {
    /// Wartość ograniczona do zakresu; dla zera/śmieci wraca `fallback`.
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard isFinite, self > 0 else { return fallback }
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

// MARK: - transformacja plan ↔ ekran

/// Skala i przesunięcie dopasowane do widoku — wspólne dla rysowania i klikania.
struct PlanFit {
    let scale: Double        // punkty ekranu na milimetr
    let center: CGPoint      // gdzie leży (0,0) planu
    let size: CGSize

    init(plan: FloorPlan, size: CGSize, zoom: CGFloat = 1, offset: CGSize = .zero) {
        let b = plan.bounds
        let spanX = Swift.max(1000, b.max.x - b.min.x)
        let spanY = Swift.max(1000, b.max.y - b.min.y)
        let padding: Double = 140
        let sx = (Double(size.width) - padding * 2) / spanX
        let sy = (Double(size.height) - padding * 2) / spanY
        let base = Swift.max(0.0002, Swift.min(sx, sy))
        self.scale = base * Double(zoom)
        let planCenter = SIMD2<Double>((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2)
        self.center = CGPoint(
            x: size.width / 2 - planCenter.x * self.scale + offset.width,
            y: size.height / 2 - planCenter.y * self.scale + offset.height
        )
        self.size = size
    }

    var mmPerPoint: Double { 1 / scale }

    func screenPoint(_ p: SIMD2<Double>) -> CGPoint {
        CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale)
    }

    func planPoint(fromScreen p: CGPoint) -> SIMD2<Double> {
        SIMD2<Double>((Double(p.x) - center.x) / scale, (Double(p.y) - center.y) / scale)
    }
}

// MARK: - rysowanie planu

struct PlanCanvas: View {
    let plan: FloorPlan
    let fit: PlanFit
    let selected: Int?
    /// rysowany właśnie prostokąt (podgląd na żywo z wymiarami)
    var preview: RectPreview?

    var body: some View {
        Canvas { ctx, size in
            drawGrid(ctx: &ctx, size: size)
            drawWalls(ctx: &ctx)
            drawDimensions(ctx: &ctx)
            drawPreview(ctx: &ctx)
            drawPoints(ctx: &ctx)
        }
        .background(Color(red: 0.13, green: 0.14, blue: 0.15))
    }

    private func drawGrid(ctx: inout GraphicsContext, size: CGSize) {
        let stepMM: Double = 1000     // linia co 1 m
        let b = plan.bounds
        let startX = (b.min.x / stepMM).rounded(.down) * stepMM - stepMM
        let endX = (b.max.x / stepMM).rounded(.up) * stepMM + stepMM
        let startY = (b.min.y / stepMM).rounded(.down) * stepMM - stepMM
        let endY = (b.max.y / stepMM).rounded(.up) * stepMM + stepMM

        var grid = Path()
        var x = startX
        while x <= endX {
            let p = fit.screenPoint(SIMD2(x, startY))
            let q = fit.screenPoint(SIMD2(x, endY))
            grid.move(to: p)
            grid.addLine(to: q)
            x += stepMM
        }
        var y = startY
        while y <= endY {
            let p = fit.screenPoint(SIMD2(startX, y))
            let q = fit.screenPoint(SIMD2(endX, y))
            grid.move(to: p)
            grid.addLine(to: q)
            y += stepMM
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)

        // osie 0,0
        var axes = Path()
        axes.move(to: fit.screenPoint(SIMD2(startX, 0)))
        axes.addLine(to: fit.screenPoint(SIMD2(endX, 0)))
        axes.move(to: fit.screenPoint(SIMD2(0, startY)))
        axes.addLine(to: fit.screenPoint(SIMD2(0, endY)))
        ctx.stroke(axes, with: .color(.white.opacity(0.14)), lineWidth: 1)
    }

    private func drawWalls(ctx: inout GraphicsContext) {
        guard plan.wallCount > 0 else { return }
        let wallWidth = Swift.max(3.0, plan.thickness * fit.scale)

        // wypełnienie planu (podłoga)
        if plan.closed, plan.points.count >= 3 {
            var floor = Path()
            floor.move(to: fit.screenPoint(plan.points[0]))
            for p in plan.points.dropFirst() {
                floor.addLine(to: fit.screenPoint(p))
            }
            floor.closeSubpath()
            ctx.fill(floor, with: .color(Color(red: 0.24, green: 0.26, blue: 0.28).opacity(0.85)))
        }

        for i in 0..<plan.wallCount {
            guard let w = plan.wall(i) else { continue }
            var path = Path()
            path.move(to: fit.screenPoint(w.a))
            path.addLine(to: fit.screenPoint(w.b))
            let isSelected = selected == i
            ctx.stroke(
                path,
                with: .color(isSelected ? Color.orange : Color(red: 0.85, green: 0.87, blue: 0.88)),
                style: StrokeStyle(lineWidth: isSelected ? wallWidth + 4 : wallWidth, lineCap: .square)
            )
        }
    }

    private func drawDimensions(ctx: inout GraphicsContext) {
        for i in 0..<plan.wallCount {
            guard let w = plan.wall(i) else { continue }
            let mid = fit.screenPoint((w.a + w.b) / 2)
            let center = fit.screenPoint(SIMD2(
                (plan.bounds.min.x + plan.bounds.max.x) / 2,
                (plan.bounds.min.y + plan.bounds.max.y) / 2
            ))
            let dx = mid.x - center.x
            let dy = mid.y - center.y
            let len = max(1, sqrt(dx * dx + dy * dy))
            let offset = CGPoint(x: mid.x + dx / len * 26, y: mid.y + dy / len * 26)

            let label = String(format: "%.2f m", w.length / 1000)
            let text = Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(selected == i ? .orange : .white)
            ctx.draw(text, at: offset, anchor: .center)
        }
    }

    /// Podgląd rysowanego prostokąta: przerywana ramka + wymiary i pole w środku.
    private func drawPreview(ctx: inout GraphicsContext) {
        guard let preview else { return }
        let a = fit.screenPoint(preview.min)
        let b = fit.screenPoint(SIMD2(preview.max.x, preview.min.y))
        let c = fit.screenPoint(preview.max)
        let d = fit.screenPoint(SIMD2(preview.min.x, preview.max.y))

        var rect = Path()
        rect.move(to: a)
        rect.addLine(to: b)
        rect.addLine(to: c)
        rect.addLine(to: d)
        rect.closeSubpath()
        ctx.fill(rect, with: .color(.orange.opacity(0.12)))
        ctx.stroke(rect, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        let middle = CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2)
        let area = preview.width * preview.depth / 1_000_000
        let label = String(format: "%.2f × %.2f m\n%.2f m²",
                           preview.width / 1000, preview.depth / 1000, area)
        ctx.draw(
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.orange),
            at: middle,
            anchor: .center
        )
    }

    private func drawPoints(ctx: inout GraphicsContext) {
        guard !plan.closed else { return }
        for (index, p) in plan.points.enumerated() {
            let c = fit.screenPoint(p)
            let isFirst = index == 0
            let r: CGFloat = isFirst ? 7 : 5
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(isFirst ? .orange : .white))
        }
        // podpowiedź: zamknij klikając w pierwszy punkt
        if plan.points.count >= 3, let first = plan.points.first {
            let c = fit.screenPoint(first)
            let ring = Path(ellipseIn: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28))
            ctx.stroke(ring, with: .color(.orange.opacity(0.6)), lineWidth: 1.5)
        }
    }
}
