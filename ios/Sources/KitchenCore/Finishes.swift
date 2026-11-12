import Foundation

/// Wykończenie szafki. Wszystkie warianty są teksturami (fornir, laminat,
/// lakier, beton, metal) — nie ma już jednolitych kolorów frontów.
public struct CabinetFinish: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// nazwa pliku bez rozszerzenia w `Resources/Textures/Finishes`
    public let fileName: String
    /// kolor zapasowy, gdyby tekstury nie było w bundle
    public let fallbackColor: String

    public init(id: String, name: String, fileName: String, fallbackColor: String) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.fallbackColor = fallbackColor
    }
}

public enum CabinetFinishes {
    public static let all: [CabinetFinish] = [
        CabinetFinish(id: "dab-naturalny", name: "Dąb naturalny",
                      fileName: "finish_dab_naturalny", fallbackColor: "#d6b892"),
        CabinetFinish(id: "dab-bielony", name: "Dąb bielony",
                      fileName: "finish_dab_bielony", fallbackColor: "#e2d7c6"),
        CabinetFinish(id: "orzech", name: "Orzech",
                      fileName: "finish_orzech", fallbackColor: "#6c4e34"),
        CabinetFinish(id: "wisnia", name: "Wiśnia",
                      fileName: "finish_wisnia", fallbackColor: "#965c3c"),
        CabinetFinish(id: "biel-matowa", name: "Biel matowa",
                      fileName: "finish_biel_matowa", fallbackColor: "#f2efe8"),
        CabinetFinish(id: "grafit", name: "Grafit matowy",
                      fileName: "finish_grafit_matowy", fallbackColor: "#3e4144"),
        CabinetFinish(id: "bez-piaskowy", name: "Beż piaskowy",
                      fileName: "finish_bez_piaskowy", fallbackColor: "#cebea6"),
        CabinetFinish(id: "oliwka", name: "Oliwka",
                      fileName: "finish_oliwka", fallbackColor: "#707a60"),
        CabinetFinish(id: "beton", name: "Beton jasny",
                      fileName: "finish_beton_jasny", fallbackColor: "#b2b0aa"),
        CabinetFinish(id: "aluminium", name: "Aluminium szczotkowane",
                      fileName: "finish_aluminium", fallbackColor: "#b0b4b8"),
    ]

    public static let defaultFinish = all[0]

    public static func finish(for name: String?) -> CabinetFinish {
        all.first { $0.fileName == name || $0.name == name } ?? defaultFinish
    }
}
