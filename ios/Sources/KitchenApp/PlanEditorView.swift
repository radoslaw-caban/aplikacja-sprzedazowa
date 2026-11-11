import SwiftUI
import KitchenCore
import simd

/// Widok „Mapa": plan domu rysowany kreskami, z klikalnymi ścianami
/// i edycją ich długości.
///
/// ZASADA: plan jest źródłem prawdy dla bryły domu. Każda zmiana tutaj
/// przelicza pokój (szerokość × głębokość × wysokość), więc 3D od razu
/// odpowiada narysowanemu planowi.
struct PlanEditorView: View {
    @Binding var plan: FloorPlan
    /// wywoływane po każdej zmianie (zapis do projektu)
    var onChange: (FloorPlan) -> Void

    @State private var selectedWall: Int?
    @State private var lengthText: String = ""
    @State private var editingLength = false

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                let fit = PlanFit(plan: plan, size: geo.size)
                ZStack(alignment: .bottom) {
                    PlanCanvas(plan: plan, fit: fit, selected: selectedWall)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleTap(at: value.location, fit: fit)
                                }
                        )
                    lengthPanel
                        .padding(14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            controls
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        .onChange(of: plan) { _, new in
            onChange(new)
        }
    }

    // MARK: - nagłówek

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan domu").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
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

    private var summary: String {
        let m2 = String(format: "%.1f", plan.areaM2)
        let walls = plan.wallCount
        let height = String(format: "%.2f", plan.height / 1000)
        return "\(walls) ścian · \(m2) m² · wys. \(height) m · obwód \(Int(plan.perimeter)) mm"
    }

    // MARK: - gesty

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

    // MARK: - panel długości

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

    private func applyLength() {
        let parsed = Double(lengthText.replacingOccurrences(of: ",", with: ".")) ?? 0
        setLength(parsed)
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
                plan = FloorPlan.rectangle(width: 12800, depth: 9600, height: plan.height)
                selectedWall = nil
            } label: {
                Label("Willa 12,8 × 9,6", systemImage: "square.dashed")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
}

// MARK: - transformacja plan ↔ ekran

/// Skala i przesunięcie dopasowane do widoku — wspólne dla rysowania i klikania.
struct PlanFit {
    let scale: Double        // punkty ekranu na milimetr
    let center: CGPoint      // gdzie leży (0,0) planu
    let size: CGSize

    init(plan: FloorPlan, size: CGSize) {
        let b = plan.bounds
        let spanX = Swift.max(1000, b.max.x - b.min.x)
        let spanY = Swift.max(1000, b.max.y - b.min.y)
        let padding: Double = 70
        let sx = (Double(size.width) - padding * 2) / spanX
        let sy = (Double(size.height) - padding * 2) / spanY
        self.scale = Swift.max(0.0008, Swift.min(sx, sy))
        let planCenter = SIMD2<Double>((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2)
        self.center = CGPoint(
            x: size.width / 2 - planCenter.x * scale,
            y: size.height / 2 - planCenter.y * scale
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

    var body: some View {
        Canvas { ctx, size in
            drawGrid(ctx: &ctx, size: size)
            drawWalls(ctx: &ctx)
            drawDimensions(ctx: &ctx)
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
            // etykieta odsunięta od ściany w stronę przeciwną do środka planu
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
