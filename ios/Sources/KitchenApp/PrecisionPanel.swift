import SwiftUI
import KitchenCore

/// PRECYZJA PROJEKTU — gęstość siatki i pomiar „na oko".
///
/// Nazwa „Pomiar na oko" jest celowa: realne pomiary robią skanery (Trimble X9,
/// LiDAR iPada), a to jest pomiar TEORETYCZNY z planu. Nie udajemy, że jest
/// dokładny — dlatego mówimy o tym wprost, zamiast sugerować precyzję,
/// której narzędzie nie ma.
///
/// Gęstość siatki jest jednocześnie:
///  - krokiem przyciągania kursora (precyzja wstawiania),
///  - ziarnem dokładności pomiarów,
///  - ziarnem zapisu współrzędnych.
public enum Precision: Double, CaseIterable, Sendable, Identifiable {
    case mm1 = 1
    case mm2 = 2
    case mm5 = 5
    case mm10 = 10
    case mm20 = 20
    case mm50 = 50
    case cm10 = 100
    case cm20 = 200
    case cm50 = 500
    case m1 = 1000

    public var id: Double { rawValue }

    /// Wartość w milimetrach.
    public var mm: Double { rawValue }

    /// Etykieta do panelu: „1 mm", „50 cm", „1 m".
    public var label: String {
        if rawValue < 10 { return "\(Int(rawValue)) mm" }
        if rawValue < 1000 { return "\(Int(rawValue / 10)) cm" }
        return "\(Int(rawValue / 1000)) m"
    }

    /// Najbliższa precyzja dla wartości w mm (do wczytania z zapisu).
    public static func nearest(_ mm: Double) -> Precision {
        allCases.min(by: { abs($0.mm - mm) < abs($1.mm - mm) }) ?? .mm10
    }

    /// Czy przy tej precyzji siatka milimetrowe jest w ogóle sensowna.
    /// Poniżej 10 mm rysujemy linie co 10× i 100×, bo 1 mm na 30 m to szum.
    public var gridMinor: Double { max(rawValue, 100) }
    public var gridMajor: Double { gridMinor * 10 }

    /// Dokładność pomiaru deklarowana użytkownikowi (± połowa kroku).
    public var toleranceText: String {
        let t = rawValue / 2
        if t < 10 { return "±\(Int(t)) mm" }
        if t < 1000 { return "±\(Int(t / 10)) cm" }
        return "±\(String(format: "%.1f", t / 1000)) m"
    }
}

/// Pomiar wykonany narzędziem „Pomiar na oko" — odcinek na planie.
public struct EyeMeasure: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var from: SIMD2<Double>   // mm, plan (X, Z)
    public var to: SIMD2<Double>

    public init(id: UUID = UUID(), from: SIMD2<Double>, to: SIMD2<Double>) {
        self.id = id
        self.from = from
        self.to = to
    }

    /// Długość w mm (rzut poziomy).
    public var length: Double {
        let dx = to.x - from.x
        let dz = to.y - from.y
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Kąt względem osi X w stopniach (0…180).
    public var angleDeg: Double {
        let dx = to.x - from.x
        let dz = to.y - from.y
        let a = atan2(dz, dx) * 180 / .pi
        return a < 0 ? a + 180 : a
    }

    /// Długość zaokrąglona do precyzji — to jest liczba, którą użytkownik widzi.
    public func displayLength(_ p: Precision) -> String {
        let snapped = (length / p.mm).rounded() * p.mm
        if snapped < 10 { return "\(Int(snapped)) mm" }
        if snapped < 1000 { return "\(String(format: "%.1f", snapped / 10)) cm" }
        return "\(String(format: "%.2f", snapped / 1000)) m"
    }
}

/// PANEL PRECYZJI — mały, w prawym dolnym rogu.
///
/// Pokazuje trzy rzeczy, których użytkownik potrzebuje w trakcie rysowania:
///  1. aktualną precyzję (i pozwala ją zmienić),
///  2. ostatni pomiar „na oko",
///  3. parametry wpisywane w dowolnym narzędziu.
///
/// Świadomie mały i w rogu: to narzędzie pomocnicze, nie panel sterowania.
struct PrecisionPanel: View {
    @Binding var precision: Precision
    /// ostatni pomiar (nil = brak)
    var measure: EyeMeasure?
    /// parametry z aktualnie używanego narzędzia — wyświetlane pod pomiarem
    var toolParams: [(String, String)] = []
    /// czy panel jest zwinięty do samej plakietki
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if collapsed {
                badge
            } else {
                expanded
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: collapsed)
    }

    // MARK: zwinięty

    private var badge: some View {
        Button {
            collapsed = false
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ruler")
                    .font(.system(size: 10, weight: .semibold))
                Text(precision.label)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: rozwinięty

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Divider().opacity(0.25)
            precisionRow
            if let measure {
                measureRow(measure)
            }
            if !toolParams.isEmpty {
                paramsRows
            }
            hint
        }
        .padding(10)
        .frame(width: 214)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "ruler")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Pomiar na oko")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Button {
                collapsed = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var precisionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Precyzja")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(precision.toleranceText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // poziomy pasek: gęstość siatki od 1 mm do 1 m
            HStack(spacing: 3) {
                ForEach(Precision.allCases) { p in
                    Button {
                        precision = p
                        Haptics.tap()
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(p == precision
                                  ? Color.accentColor
                                  : Color.primary.opacity(0.18))
                            .frame(height: p == precision ? 16 : 10)
                    }
                    .buttonStyle(.plain)
                    .help(p.label)
                }
            }
            .frame(height: 16)
            Text(precision.label)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }

    private func measureRow(_ m: EyeMeasure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Ostatni pomiar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(m.angleDeg))°")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(m.displayLength(precision))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
        }
    }

    private var paramsRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().opacity(0.2)
            ForEach(Array(toolParams.enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.0)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pair.1)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
        }
    }

    private var hint: some View {
        Text("Pomiar teoretyczny z planu. Realne pomiary: skaner i LiDAR.")
            .font(.system(size: 9))
            .foregroundStyle(.secondary.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }
}
