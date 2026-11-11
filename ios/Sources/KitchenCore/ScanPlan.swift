import Foundation

/// Plan domu wyprowadzony z chmury punktów (skan Trimble X9).
///
/// Liczby NIE są wymyślone: `tools/scan_to_plan.py` wykrywa w chmurze
/// podłogę i sufit (najostrzejsze piki histogramu pionu), obrys w poziomie
/// oraz płaszczyzny ścian, a wynik zapisuje do JSON w `Resources/Scans`.
public struct ScanPlan: Codable, Sendable {

    public struct Wall: Codable, Sendable {
        /// "x" = ściana prostopadła do X (stała współrzędna x), "y" = do Y.
        public let axis: String
        /// Współrzędna prostopadła do ściany (m, lokalnie, dom w środku).
        public let pos: Float
        /// Początek i koniec odcinka wzdłuż ściany (m).
        public let from: Float
        public let to: Float

        public var length: Float { to - from }
    }

    public let source: String
    public let points: Int
    public let height: Float
    public let width: Float
    public let depth: Float
    public let walls: [Wall]

    public init(source: String, points: Int, height: Float, width: Float, depth: Float, walls: [Wall]) {
        self.source = source
        self.points = points
        self.height = height
        self.width = width
        self.depth = depth
        self.walls = walls
    }

    /// Wczytuje plan z pliku JSON.
    public static func load(from url: URL) -> ScanPlan? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScanPlan.self, from: data)
    }

    /// Plan dołączony do aplikacji (bundle), z fallbackiem na katalog repo —
    /// tak samo jak `ModelLibrary` szuka modeli.
    public static func bundled() -> ScanPlan? {
        if let url = Bundle.main.url(forResource: "dom-chmura-plan", withExtension: "json") {
            return load(from: url)
        }
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Scans"),
           let plan = load(from: dir.appendingPathComponent("dom-chmura-plan.json")) {
            return plan
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in ["Resources/Scans/dom-chmura-plan.json",
                          "ios/Resources/Scans/dom-chmura-plan.json"] {
            let url = cwd.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return load(from: url)
            }
        }
        return nil
    }
}
