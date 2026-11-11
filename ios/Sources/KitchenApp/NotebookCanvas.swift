import SwiftUI
import KitchenCore
import simd

/// Plan narysowany **ołówkiem na kartce z notesu**: kremowy papier, linie
/// w kropki, wymiary jak na planach architektonicznych, a przy oddaleniu
/// widać całą kartkę i leżący obok ołówek.
struct NotebookCanvas: View {
    let plan: FloorPlan
    let fit: PlanFit
    let selected: Int?
    var preview: RectPreview?
    /// zbliżenie kartki (1 = dopasowana, <0,85 = widok notesu)
    var zoom: CGFloat = 1
    var showPencil: Bool = true

    var body: some View {
        Canvas { ctx, size in
            drawDesk(ctx: &ctx, size: size)
            drawPaper(ctx: &ctx, size: size)
            drawPlan(ctx: &ctx, size: size)
            drawDimensions(ctx: &ctx)
            drawPreview(ctx: &ctx)
            if showPencil { drawPencil(ctx: &ctx, size: size) }
        }
        .background(Color(red: 0.16, green: 0.15, blue: 0.13))
    }

    // MARK: - biurko i papier

    private func drawDesk(ctx: inout GraphicsContext, size: CGSize) {
        // pełne, nieprzezroczyste tło — przez kartkę nie może prześwitywać scena 3D
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.17, green: 0.16, blue: 0.14)))
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.05), Color.black.opacity(0.25)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)))
    }

    /// Kartka: zawsze w tym samym miejscu ekranu i zawsze widoczna w całości,
    /// niezależnie od zbliżenia — dlatego liczymy jej prostokąt z `plan.bounds`
    /// przeskalowanego marginesem.
    private var paperRect: CGRect {
        let b = plan.bounds
        let marginMM: Double = Swift.max(600, Swift.max(b.max.x - b.min.x, b.max.y - b.min.y) * 0.16)
        let a = fit.screenPoint(SIMD2(b.min.x - marginMM, b.min.y - marginMM))
        let c = fit.screenPoint(SIMD2(b.max.x + marginMM, b.max.y + marginMM))
        return CGRect(x: a.x, y: a.y, width: c.x - a.x, height: c.y - a.y)
    }

    private func drawPaper(ctx: inout GraphicsContext, size: CGSize) {
        let rect = paperRect
        let paper = Path(roundedRect: rect, cornerRadius: 6)

        // cień pod kartką
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 6, dy: 8), cornerRadius: 6),
                 with: .color(.black.opacity(0.28)))
        ctx.fill(paper, with: .color(Color(red: 0.97, green: 0.95, blue: 0.89)))

        // delikatna siatka papieru milimetrowego (co 1 m planu)
        var grid = Path()
        let stepMM: Double = 1000
        let b = plan.bounds
        var x = (b.min.x / stepMM).rounded(.down) * stepMM - stepMM * 2
        let endX = (b.max.x / stepMM).rounded(.up) * stepMM + stepMM * 2
        while x <= endX {
            let p = fit.screenPoint(SIMD2(x, b.min.y - 2000))
            let q = fit.screenPoint(SIMD2(x, b.max.y + 2000))
            grid.move(to: p); grid.addLine(to: q)
            x += stepMM
        }
        var y = (b.min.y / stepMM).rounded(.down) * stepMM - stepMM * 2
        let endY = (b.max.y / stepMM).rounded(.up) * stepMM + stepMM * 2
        while y <= endY {
            let p = fit.screenPoint(SIMD2(b.min.x - 2000, y))
            let q = fit.screenPoint(SIMD2(b.max.x + 2000, y))
            grid.move(to: p); grid.addLine(to: q)
            y += stepMM
        }
        // WAŻNE: clip na kopii kontekstu — inaczej obcina cały dalszy rysunek
        // (ołówek obok kartki i wszelkie adnotacje poza kartką znikały)
        var sheet = ctx
        sheet.clip(to: paper)
        sheet.stroke(grid, with: .color(Color(red: 0.55, green: 0.62, blue: 0.72).opacity(0.18)), lineWidth: 0.7)

        // linia marginesu jak w notesie
        let marginX = rect.minX + 34
        var margin = Path()
        margin.move(to: CGPoint(x: marginX, y: rect.minY))
        margin.addLine(to: CGPoint(x: marginX, y: rect.maxY))
        sheet.stroke(margin, with: .color(Color(red: 0.78, green: 0.42, blue: 0.40).opacity(0.35)), lineWidth: 1)

        // perforacja (dziurki) przy lewej krawędzi
        for i in 0..<max(3, Int(rect.height / 160)) {
            let cy = rect.minY + 60 + CGFloat(i) * 160
            guard cy < rect.maxY - 30 else { break }
            let hole = Path(ellipseIn: CGRect(x: rect.minX + 14, y: cy, width: 9, height: 9))
            sheet.fill(hole, with: .color(.black.opacity(0.22)))
        }
    }

    // MARK: - rysunek planu (ołówkiem)

    private func drawPlan(ctx: inout GraphicsContext, size: CGSize) {
        guard plan.wallCount > 0 else { return }
        let graphite = Color(red: 0.20, green: 0.20, blue: 0.22)
        // grubość ściany (120 mm) NIE jest grubością kreski — inaczej plan wygląda
        // jak czarny pas. Kreska ołówka ma stałą grubość, a grubość ściany pokazuje wymiar.
        let wallWidth: CGFloat = selected == nil ? 2.0 : 2.6

        // lekkie wypełnienie wnętrza — jak ołówkiem cieniowane
        if plan.closed, plan.points.count >= 3 {
            var floor = Path()
            floor.move(to: fit.screenPoint(plan.points[0]))
            for p in plan.points.dropFirst() { floor.addLine(to: fit.screenPoint(p)) }
            floor.closeSubpath()
            ctx.fill(floor, with: .color(Color(red: 0.62, green: 0.60, blue: 0.56).opacity(0.18)))
        }

        for i in 0..<plan.wallCount {
            guard let w = plan.wall(i) else { continue }
            var path = Path()
            path.move(to: fit.screenPoint(w.a))
            path.addLine(to: fit.screenPoint(w.b))
            let isSelected = selected == i
            // dwie kreski obok siebie = ślad ołówka
            ctx.stroke(path, with: .color(isSelected ? Color.orange : graphite),
                       style: StrokeStyle(lineWidth: isSelected ? wallWidth + 2 : wallWidth, lineCap: .round))
            ctx.stroke(path, with: .color((isSelected ? Color.orange : graphite).opacity(0.35)),
                       style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [2, 3]))
        }
    }

    /// Wymiary architektoniczne: łańcuch z kreskami i liczbą przy ścianie,
    /// a gabaryty (szerokość/głębokość) raz, na zewnątrz obrysu.
    private func drawDimensions(ctx: inout GraphicsContext) {
        let b = plan.bounds
        let center = fit.screenPoint(SIMD2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2))
        let ink = Color(red: 0.30, green: 0.28, blue: 0.26)

        // przy prostym prostokącie gabaryty wystarczą — etykiety ścian dublowałyby je
        let showWallLabels = !plan.isSimpleRectangle || selected != nil
        for i in 0..<plan.wallCount where showWallLabels || selected == i {
            guard let w = plan.wall(i) else { continue }
            let mid = fit.screenPoint((w.a + w.b) / 2)
            var dx = mid.x - center.x
            var dy = mid.y - center.y
            let len = max(1, sqrt(dx * dx + dy * dy))
            dx /= len; dy /= len
            let offset: CGFloat = 26
            let labelPoint = CGPoint(x: mid.x + dx * offset, y: mid.y + dy * offset)

            // kreska wymiarowa prostopadła do ściany, krótka
            let d = w.b - w.a
            let nlen = max(1e-6, simd_length(d))
            let nx = CGFloat(-d.y / nlen), ny = CGFloat(d.x / nlen)
            var tick = Path()
            tick.move(to: CGPoint(x: labelPoint.x - nx * 10 - dx * 0, y: labelPoint.y - ny * 10))
            tick.addLine(to: CGPoint(x: labelPoint.x + nx * 10, y: labelPoint.y + ny * 10))
            ctx.stroke(tick, with: .color(ink.opacity(0.45)), lineWidth: 0.9)

            ctx.draw(
                Text(Units.mm(w.length))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(selected == i ? .orange : ink),
                at: labelPoint,
                anchor: .center
            )
        }

        // gabaryty: szerokość pod obrysem, głębokość po prawej — z kreskami końcowymi
        let width = b.max.x - b.min.x
        let depth = b.max.y - b.min.y
        let widthY = fit.screenPoint(b.max).y + 54
        let leftX = fit.screenPoint(b.min).x
        let rightX = fit.screenPoint(b.max).x
        var widthLine = Path()
        widthLine.move(to: CGPoint(x: leftX, y: widthY))
        widthLine.addLine(to: CGPoint(x: rightX, y: widthY))
        for x in [leftX, rightX] {
            widthLine.move(to: CGPoint(x: x, y: widthY - 6))
            widthLine.addLine(to: CGPoint(x: x, y: widthY + 6))
        }
        ctx.stroke(widthLine, with: .color(ink.opacity(0.6)), lineWidth: 1)
        ctx.draw(Text(Units.mm(width))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(ink),
                 at: CGPoint(x: (leftX + rightX) / 2, y: widthY + 14), anchor: .center)

        let depthX = rightX + 46
        let topY = fit.screenPoint(b.min).y
        let bottomY = fit.screenPoint(b.max).y
        var depthLine = Path()
        depthLine.move(to: CGPoint(x: depthX, y: topY))
        depthLine.addLine(to: CGPoint(x: depthX, y: bottomY))
        for y in [topY, bottomY] {
            depthLine.move(to: CGPoint(x: depthX - 6, y: y))
            depthLine.addLine(to: CGPoint(x: depthX + 6, y: y))
        }
        ctx.stroke(depthLine, with: .color(ink.opacity(0.6)), lineWidth: 1)
        ctx.draw(Text(Units.mm(depth))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(ink),
                 at: CGPoint(x: depthX + 18, y: (topY + bottomY) / 2), anchor: .center)
    }

    private func drawPreview(ctx: inout GraphicsContext) {
        guard let preview else { return }
        let a = fit.screenPoint(preview.min)
        let c = fit.screenPoint(preview.max)
        var rect = Path()
        rect.addRect(CGRect(x: a.x, y: a.y, width: c.x - a.x, height: c.y - a.y))
        ctx.stroke(rect, with: .color(.orange), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
        let label = "\(Units.mm(preview.width)) × \(Units.mm(preview.depth)) mm"
        ctx.draw(Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.orange),
                 at: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2), anchor: .center)
    }

    /// Ołówek leżący obok kartki — widoczny tylko w widoku notesu.
    private func drawPencil(ctx: inout GraphicsContext, size: CGSize) {
        let rect = paperRect
        // ołówek leży NA biurku obok kartki — pozycję ograniczamy do widoku,
        // inaczej przy wąskim ekranie rysuje się poza kadrem
        let start = CGPoint(
            x: Swift.min(size.width - 240, rect.maxX - 150),
            y: Swift.min(size.height - 60, rect.maxY + 26)
        )
        let end = CGPoint(x: Swift.min(size.width - 24, start.x + 190), y: Swift.min(size.height - 20, start.y + 96))
        guard end.x > start.x, end.y > start.y else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)

        // korpus ołówka
        var body = Path()
        body.move(to: start)
        body.addLine(to: end)
        ctx.stroke(body, with: .color(Color(red: 0.90, green: 0.72, blue: 0.22)), lineWidth: 10)
        ctx.stroke(body, with: .color(.black.opacity(0.20)), lineWidth: 2)

        // ostrze (grafit)
        var tip = Path()
        let tipStart = CGPoint(x: start.x - cos(angle) * 30, y: start.y - sin(angle) * 30)
        tip.move(to: start)
        tip.addLine(to: tipStart)
        ctx.stroke(tip, with: .color(Color(red: 0.32, green: 0.30, blue: 0.28)), lineWidth: 7)

        // gumka
        var eraser = Path()
        eraser.move(to: end)
        eraser.addLine(to: CGPoint(x: end.x + cos(angle) * 16, y: end.y + sin(angle) * 16))
        ctx.stroke(eraser, with: .color(Color(red: 0.90, green: 0.58, blue: 0.56)), lineWidth: 11)
    }

}
