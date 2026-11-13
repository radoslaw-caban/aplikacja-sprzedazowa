import SwiftUI
import KitchenCore

/// SIATKA PLANSZY — osobny widok, żeby nie przerysowywała się przy każdym ruchu palca.
///
/// Powód wydzielenia: siatka rysuje setki linii w `Canvas`. Gdy była częścią
/// `SandboxView`, każda zmiana `spotFree` (a ta zmienia się przy KAŻDYM ruchu
/// kursora) przerysowywała całe drzewo widoku razem z siatką. Na iPadzie to
/// widoczne jąkanie przy przesuwaniu obiektu po planszy.
///
/// `Equatable` + brak zależności od stanu kursora = SwiftUI pomija przerysowanie,
/// dopóki nie zmieni się rozmiar albo przesunięcie środka.
nonisolated struct SandboxGrid: View, Equatable {
    let size: CGSize
    let center: CGPoint
    /// pikseli na milimetr
    let pxPerMm: CGFloat
    /// gęstość siatki w mm (z panelu precyzji)
    let gridMM: Double

    static func == (a: SandboxGrid, b: SandboxGrid) -> Bool {
        a.size == b.size && a.center == b.center
            && a.pxPerMm == b.pxPerMm && a.gridMM == b.gridMM
    }

    var body: some View {
        Canvas { ctx, _ in
            let step = max(8, gridMM * pxPerMm)      // nie rysuj gęściej niż 8 px
            let major = step * 5
            let cx = center.x
            let cy = center.y

            // linie pionowe
            var x = cx.truncatingRemainder(dividingBy: step)
            while x < size.width {
                let isMajor = abs((x - cx).truncatingRemainder(dividingBy: major)) < 1
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p,
                           with: .color(.black.opacity(isMajor ? 0.12 : 0.05)),
                           lineWidth: isMajor ? 1 : 0.5)
                x += step
            }

            // linie poziome
            var y = cy.truncatingRemainder(dividingBy: step)
            while y < size.height {
                let isMajor = abs((y - cy).truncatingRemainder(dividingBy: major)) < 1
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
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
        .frame(width: size.width, height: size.height)
    }
}
