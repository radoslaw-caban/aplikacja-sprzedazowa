import SwiftUI
import KitchenCore

/// PIASKOWNICA — pole robocze do swobodnego stawiania obiektów.
///
/// Zasada: wszystko można dodać z biblioteki i wszystko można edytować,
/// łącznie z dźwiękiem obiektu. Po wybraniu pozycji z biblioteki kursor
/// zmienia się w rękę, która wskazuje palcem miejsce wstawienia:
///  - obiekt naturalny → ręka Boga, pstryknięcie palcami + iskry,
///  - obiekt wykonany przez człowieka → ręka fachowca z narzędziem,
///    więc od razu widać, kto za to odpowiada.
struct SandboxView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// co aktualnie „trzyma" kursor (nil = nic nie wstawiamy)
    @State private var armed: SandboxKind?
    /// hak diagnostyczny: obiekt uzbrojony przy starcie
    var initialArmed: SandboxKind? = nil
    /// pozycja kursora w przestrzeni widoku
    @State private var cursorPoint: CGPoint = .zero
    /// faza pstryknięcia 0…1
    @State private var snapPhase: Double = 0
    /// zaznaczony obiekt do edycji
    @State private var editingID: UUID?
    /// kategoria biblioteki
    @State private var category: SandboxCategory = .terrain
    @State private var showLibrary = false

    private let audio = SandboxAudio.shared

    var body: some View {
        ZStack(alignment: .leading) {
            // --- pole robocze ---
            workspace

            // --- kursor ---
            if armed != nil {
                SandboxCursor(
                    point: cursorPoint,
                    trade: armed?.trade,
                    snapPhase: snapPhase,
                    tint: Color(hex: armed?.defaultColor ?? "#ffffff")
                )
                .position(cursorPoint)
                .allowsHitTesting(false)
            }

            // --- biblioteka ---
            if showLibrary {
                library
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // --- edytor obiektu ---
            if let id = editingID, let obj = model.currentSandbox.first(where: { $0.id == id }) {
                editorOverlay(for: obj)
            }
        }
        .background(Color(red: 0.93, green: 0.92, blue: 0.90))
        .overlay(alignment: .top) { topBar }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showLibrary)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: armed)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: editingID)
        .onAppear {
            // Uzbrojenie: z parametru albo z haka diagnostycznego.
            // Hak czytamy TU, a nie w App — @State w arkuszu startuje
            // wcześniej niż rodzic zdąży ustawić wartość.
            if let initialArmed {
                armed = initialArmed
            } else if let demo = UserDefaults.standard.string(forKey: "demoArmed"),
                      let kind = SandboxKind(rawValue: demo) {
                armed = kind
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // kursor startuje na środku planszy — tam, gdzie wzrok użytkownika
            if cursorPoint == .zero, size.width > 0 {
                cursorPoint = CGPoint(x: size.width * 0.62, y: size.height * 0.48)
            }
        }
    }

    // MARK: - pole robocze

    /// Skala planszy: ile pikseli na metr. Przy 0,5 px/mm mieści się
    /// ~24 m szerokości na iPadzie — cała działka jest widoczna bez przewijania.
    /// Wcześniej plansza była sztywno 2400×1800 px, więc jej środek (gdzie
    /// lądują obiekty) wypadał POZA ekranem i nic nie było widać.
    private var workspace: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let pxPerMm: CGFloat = 0.05   // 1 m = 50 px

            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#dfe6ec"), Color(hex: "#e8e2d6")],
                    startPoint: .top, endPoint: .bottom
                )

                // siatka co 1 m, wyróżnione co 5 m
                Canvas { ctx, size in
                    let step = 1000 * pxPerMm      // 1 m
                    let major = step * 5
                    var i = 0
                    var x = cx.truncatingRemainder(dividingBy: step)
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        let isMajor = abs((x - cx).truncatingRemainder(dividingBy: major)) < 1
                        ctx.stroke(p,
                                   with: .color(.black.opacity(isMajor ? 0.12 : 0.05)),
                                   lineWidth: isMajor ? 1 : 0.5)
                        x += step
                        i += 1
                    }
                    var y = cy.truncatingRemainder(dividingBy: step)
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        let isMajor = abs((y - cy).truncatingRemainder(dividingBy: major)) < 1
                        ctx.stroke(p,
                                   with: .color(.black.opacity(isMajor ? 0.12 : 0.05)),
                                   lineWidth: isMajor ? 1 : 0.5)
                        y += step
                    }
                    // osie przez środek (punkt 0,0 piaskownicy)
                    var ox = Path()
                    ox.move(to: CGPoint(x: cx, y: 0))
                    ox.addLine(to: CGPoint(x: cx, y: size.height))
                    ctx.stroke(ox, with: .color(.black.opacity(0.18)), lineWidth: 1)
                    var oy = Path()
                    oy.move(to: CGPoint(x: 0, y: cy))
                    oy.addLine(to: CGPoint(x: size.width, y: cy))
                    ctx.stroke(oy, with: .color(.black.opacity(0.18)), lineWidth: 1)
                }

                // obiekty: mm → px, środek ekranu = (0,0)
                ForEach(model.currentSandbox) { obj in
                    objectCard(obj)
                        .position(
                            x: cx + CGFloat(obj.position.x) * pxPerMm,
                            y: cy + CGFloat(obj.position.z) * pxPerMm
                        )
                }

                if model.currentSandbox.isEmpty && armed == nil {
                    emptyHint
                }
            }
            .overlay(gestureLayer(cx: cx, cy: cy, pxPerMm: pxPerMm))
        }
    }

    /// Warstwa gestów: kursor idzie za palcem, puszczenie wstawia obiekt.
    /// Przeciąganie (a nie tap) jest celowe — ręka musi „prowadzić" obiekt,
    /// zanim go postawi, inaczej nie wiadomo, gdzie trafi.
    private func gestureLayer(cx: CGFloat, cy: CGFloat, pxPerMm: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        cursorPoint = v.location
                    }
                    .onEnded { v in
                        cursorPoint = v.location
                        if armed != nil {
                            place(at: v.location, cx: cx, cy: cy, pxPerMm: pxPerMm)
                        }
                    }
            )
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Piaskownica jest pusta")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Wybierz obiekt z biblioteki po lewej, a kursor zmieni się w rękę.\nDotknij pola, żeby wstawić.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func objectCard(_ obj: SandboxObject) -> some View {
        let tint = obj.kind.trade.map { Color(hex: $0.tintHex) } ?? Color(hex: obj.color)
        let selected = editingID == obj.id
        return Button {
            editingID = obj.id
            audio.play(obj.sound, volume: obj.soundVolume)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: obj.kind.trade?.tool ?? "leaf.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(obj.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(7)
            .frame(width: 78, height: 58)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? tint : .black.opacity(0.12),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - biblioteka

    private var library: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                libraryHeader
                Divider().opacity(0.2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(SandboxCategory.allCases) { cat in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(cat.label.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)

                                ForEach(cat.items) { kind in
                                    kindRow(kind)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: 268)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.leading, 8)
            .padding(.vertical, 8)

            Spacer(minLength: 0)
        }
        .padding(.top, 52)
    }

    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Piaskownica").font(.callout.weight(.semibold))
                Text(armed.map { "Wstawiasz: \($0.label)" } ?? "Wybierz obiekt")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showLibrary = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private func kindRow(_ kind: SandboxKind) -> some View {
        let isArmed = armed == kind
        let tint = kind.trade.map { Color(hex: $0.tintHex) } ?? Color(hex: kind.defaultColor)
        return Button {
            armed = kind
            Haptics.tap()
            // dźwięk podglądowy — od razu słychać, co to będzie
            audio.play(kind.defaultSound, volume: 0.6)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.trade?.tool ?? "leaf.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(kind.trade?.label ?? "natura")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isArmed {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.caption2)
                        .foregroundStyle(tint)
                }
            }
            .padding(8)
            .background(
                isArmed ? tint.opacity(0.18) : Color.white.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isArmed ? tint : .clear, lineWidth: 1.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - pasek górny

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                if armed != nil {
                    armed = nil
                } else {
                    showLibrary.toggle()
                }
            } label: {
                Image(systemName: armed != nil ? "xmark" : "sidebar.left")
                    .font(.callout.weight(.semibold))
                    .padding(9)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            if armed != nil {
                HStack(spacing: 6) {
                    Image(systemName: armed?.trade?.tool ?? "hand.point.up.left.fill")
                        .font(.caption2)
                    Text(armed?.label ?? "")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\(model.currentSandbox.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    model.clearSandbox()
                    editingID = nil
                    Haptics.warning()
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                        .padding(9)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.currentSandbox.isEmpty)
                .opacity(model.currentSandbox.isEmpty ? 0.35 : 1)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .padding(9)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - edytor

    private func editorOverlay(for obj: SandboxObject) -> some View {
        HStack {
            Spacer()
            SandboxObjectEditor(
                object: Binding(
                    get: { model.currentSandbox.first(where: { $0.id == obj.id }) ?? obj },
                    set: { model.updateSandboxObject($0) }
                ),
                onChange: { model.updateSandboxObject($0) },
                onDelete: {
                    model.deleteSandboxObject(obj.id)
                    editingID = nil
                },
                onClose: { editingID = nil }
            )
            .frame(width: 330)
            .padding(.trailing, 12)
            .padding(.vertical, 60)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - wstawianie

    /// Wstawia obiekt w miejscu dotknięcia.
    ///
    /// Pstryknięcie: natura → iskry i dźwięk pstryknięcia; robota ludzka →
    /// dźwięk narzędzia. Kursor zostaje aktywny, więc można stawiać serię.
    private func place(at point: CGPoint, cx: CGFloat, cy: CGFloat, pxPerMm: CGFloat) {
        guard let kind = armed else { return }

        // punkt ekranu → pozycja w świecie piaskownicy (mm), środek = (0,0)
        let worldX = Double((point.x - cx) / pxPerMm)
        let worldZ = Double((point.y - cy) / pxPerMm)

        var obj = SandboxObject(kind: kind, position: SIMD3(worldX, 0, worldZ))
        obj.grounded = true
        model.addSandboxObject(obj)
        editingID = nil

        // dźwięk i efekt
        if kind.isNatural {
            audio.snap(volume: 0.85)             // pstryknięcie palcami
            audio.play(kind.defaultSound, volume: 0.55)
            animateSnap()
        } else {
            audio.play(kind.defaultSound, volume: 0.8)
        }
        Haptics.success()
    }

    /// Animacja pstryknięcia: 0 → 1 → 0 w ~0,35 s.
    private func animateSnap() {
        snapPhase = 0.001
        withAnimation(.easeOut(duration: 0.18)) { snapPhase = 0.6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.17)) { snapPhase = 0 }
        }
    }
}
