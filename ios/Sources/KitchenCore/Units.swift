import Foundation

/// Jednostki i formatowanie.
///
/// ZASADA: cała domena liczy w **milimetrach** i trzyma pełną precyzję `Double`
/// (0,0001 mm to nasze ziarno — poniżej tego i tak nie ma sensu mierzyć).
/// Wyświetlamy bez ułamków, bo nikt nie czyta „600,0000 mm" — ale wyliczenia
/// nigdy nie są zaokrąglane w trakcie, tylko przy pokazywaniu.
public enum Units {

    /// Ziarno obliczeń: 0,0001 mm.
    public static let precision: Double = 0.0001

    /// Zaokrąglenie do ziarna (nie do całych milimetrów).
    public static func quantize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value / precision).rounded() * precision
    }

    /// Milimetry bez ułamków: `600`, `1234`, `-18`.
    public static func mm(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// Milimetry z separatorem tysięcy: `12 800`.
    public static func mmGrouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value.rounded())) ?? mm(value)
    }

    /// Metry z czterema miejscami: `1,2000 m` (przecinek dziesiętny).
    public static func m4(_ value: Double) -> String {
        String(format: "%.4f", value / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// Metry z dwoma miejscami — do nagłówków i podsumowań.
    public static func m2(_ value: Double) -> String {
        String(format: "%.2f", value / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// Powierzchnia: `10,80 m²`.
    public static func m2Area(_ areaMM2: Double) -> String {
        String(format: "%.2f", areaMM2 / 1_000_000).replacingOccurrences(of: ".", with: ",") + " m²"
    }

    /// Bezpieczne parsowanie wpisu użytkownika: „1 200,5" → 1200.5 (mm).
    public static func parseMM(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return quantize(value)
    }
}

/// Grubość płyty używana jako zaślepka przy ścianie.
public enum EndPanel {
    /// Płyta 18 mm — widoczna obrzeżem, dlatego jest osobnym elementem, a nie bokiem szafki.
    public static let thickness: Double = 18
    /// Wysunięcie przed lico korpusu, żeby obrzeże było widoczne z boku.
    public static let protrusion: Double = 20
}
