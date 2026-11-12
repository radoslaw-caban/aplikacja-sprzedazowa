import Foundation
import simd

/// Automatyczne wypełnienie ściany szafkami.
///
/// ZASADA (twarda, z produkcji): między ścianami stoją **zaślepki 18 mm**,
/// a pomiędzy nimi szafki o **równych szerokościach**. Nie „600, 600, 400",
/// tylko 600 / 600 / 600 — różnicę z dzielenia rozrzucamy po milimetrze,
/// żeby suma zgadzała się co do 0,0001 mm z długością ściany.
public enum WallFill {

    /// Wynik rozstawienia: szafki + dwie zaślepki.
    public struct Result: Sendable {
        public var cabinets: [Cabinet]
        public var panels: [Cabinet]
        /// szerokość jednej szafki po wyrównaniu (mm)
        public var width: Double
        /// ile miejsca zajmuje zabudowa razem z zaślepkami
        public var runLength: Double
        public var note: String
    }

    /// - Parameters:
    ///   - wallStart / wallEnd: końce ściany w planie (mm, X/Z)
    ///   - cabinetHeight: wysokość całkowita szafki (z cokołem)
    ///   - depth: głębokość korpusu (mm)
    ///   - plinth: wysokość cokołu (mm)
    ///   - targetWidth: preferowana szerokość szafki — dzielnik dobieramy tak,
    ///     żeby wynik był najbliżej tej wartości
    ///   - inset: odstęp zabudowy od końca ściany (domyślnie 0 — zaślepka licuje ze ścianą)
    public static func fill(
        wallStart: SIMD2<Double>,
        wallEnd: SIMD2<Double>,
        cabinetHeight: Double = Standards.baseHeight,
        depth: Double = Standards.baseDepth,
        plinth: Double = Standards.plinthHeight,
        targetWidth: Double = 600,
        inset: Double = 0,
        namePrefix: String = "Szafka",
        color: String = "#c8bca9",
        panelColor: String = "#c8bca9"
    ) -> Result {
        let delta = wallEnd - wallStart
        let length = simd_length(delta)
        guard length > 200 else {
            return Result(cabinets: [], panels: [], width: 0, runLength: 0,
                          note: "Ściana jest za krótka (\(Units.mm(length)) mm)")
        }

        // kierunek wzdłuż ściany i normalna do wnętrza (na lewo od kierunku)
        let along = delta / length
        let inward = SIMD2<Double>(-along.y, along.x)

        let panel = EndPanel.thickness
        let usable = Units.quantize(length - inset * 2 - panel * 2)
        guard usable >= 150 else {
            return Result(cabinets: [], panels: [], width: 0, runLength: length,
                          note: "Po odjęciu zaślepek zostaje \(Units.mm(max(0, usable))) mm — za mało na szafkę")
        }

        // dzielnik: tyle szafek, żeby szerokość była najbliżej `targetWidth`
        let count = max(1, Int((usable / max(100, targetWidth)).rounded()))
        let baseWidth = Units.quantize(usable / Double(count))

        // reszta z dzielenia rozrzucona po 0,0001 mm, żeby suma była dokładna
        var widths = [Double](repeating: baseWidth, count: count)
        let remainder = Units.quantize(usable - baseWidth * Double(count))
        if abs(remainder) > Units.precision {
            let step = remainder / Double(count)
            for i in 0..<count {
                widths[i] = Units.quantize(baseWidth + step)
            }
        }

        var cabinets: [Cabinet] = []
        var panels: [Cabinet] = []

        // oś obrotu szafek: front patrzy do wnętrza (rotation 0 = front w +Z)
        let rotation = (atan2(inward.x, inward.y) * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let rotationDeg = rotation < 0 ? rotation + 360 : rotation

        // pozycje: od startu ściany, za zaślepką
        var cursor = inset + panel
        for (index, width) in widths.enumerated() {
            let center = Units.quantize(cursor + width / 2)
            let point = wallStart + along * center + inward * (depth / 2)
            cabinets.append(
                Cabinet(
                    name: "\(namePrefix) \(index + 1)",
                    type: .base,
                    width: width,
                    height: cabinetHeight,
                    depth: depth,
                    plinth: plinth,
                    x: Units.quantize(point.x),
                    z: Units.quantize(point.y),
                    rotation: Units.quantize(rotationDeg),
                    color: color
                )
            )
            cursor = Units.quantize(cursor + width)
        }

        // zaślepki: płyty 18 mm na obu końcach ściany, wysunięte o 20 mm
        let panelDepth = depth + EndPanel.protrusion
        for (index, atStart) in [true, false].enumerated() {
            let center = atStart ? Units.quantize(inset + panel / 2)
                                 : Units.quantize(length - inset - panel / 2)
            let point = wallStart + along * center + inward * (panelDepth / 2)
            panels.append(
                Cabinet(
                    name: "Zaślepka \(index + 1)",
                    type: .panel,
                    width: panel,
                    height: cabinetHeight,
                    depth: panelDepth,
                    plinth: 0,
                    x: Units.quantize(point.x),
                    z: Units.quantize(point.y),
                    rotation: Units.quantize(rotationDeg),
                    color: panelColor
                )
            )
        }

        let runLength = Units.quantize(panel * 2 + widths.reduce(0, +) + inset * 2)
        // pokazujemy szerokość z jednym miejscem, gdy nie jest całkowita:
        // 5 × 592,8 mm = 2964 mm, a nie mylące „5 × 593"
        let widthText = abs(baseWidth - baseWidth.rounded()) < 0.05
            ? Units.mm(baseWidth)
            : String(format: "%.1f", baseWidth).replacingOccurrences(of: ".", with: ",")
        let note = "\(count) × \(widthText) mm + 2 × 18 mm = \(Units.mm(runLength)) mm (ściana \(Units.mm(length)) mm)"
        return Result(cabinets: cabinets, panels: panels, width: baseWidth, runLength: runLength, note: note)
    }

    /// To samo, ale prosto z planu — po indeksie ściany.
    public static func fill(plan: FloorPlan, wallIndex: Int, targetWidth: Double = 600, cabinetType: CabinetType = .base) -> Result {
        guard let wall = plan.wall(wallIndex) else {
            return Result(cabinets: [], panels: [], width: 0, runLength: 0, note: "Brak ściany \(wallIndex)")
        }
        let height = cabinetType == .wall ? Standards.wallDepth + 300 : Standards.baseHeight
        // Wynik zwracamy w układzie **sceny** (środek pomieszczenia w 0,0),
        // bo tam trafiają szafki z biblioteki. Plan może być narysowany gdziekolwiek.
        let b = plan.bounds
        let cx = (b.min.x + b.max.x) / 2
        let cz = (b.min.y + b.max.y) / 2
        var result = fill(
            wallStart: wall.a,
            wallEnd: wall.b,
            cabinetHeight: cabinetType == .wall ? 720 : height,
            depth: cabinetType == .wall ? Standards.wallDepth : Standards.baseDepth,
            plinth: cabinetType == .wall ? 0 : Standards.plinthHeight,
            targetWidth: targetWidth
        )
        if abs(cx) > 0.5 || abs(cz) > 0.5 {
            func centered(_ c: Cabinet) -> Cabinet {
                var copy = c
                copy.x = Units.quantize(c.x - cx)
                copy.z = Units.quantize(c.z - cz)
                return copy
            }
            result.cabinets = result.cabinets.map(centered)
            result.panels = result.panels.map(centered)
        }
        return result
    }
}
