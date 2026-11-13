import SwiftUI
import KitchenCore

/// Tło intro: REALNA chmura punktów (ze skanu) na czarnym tle.
///
/// DLACZEGO NIE PROCEDURALNA SFERA: wcześniej rysowaliśmy tu sztuczną sferę
/// z 900 kropek (`PointCloudBackdrop`). Wyglądała jak abstrakcja, a nie jak
/// skan pomieszczenia — czyli pokazywała coś, czego aplikacja nie robi.
/// Teraz rysujemy prawdziwą chmurę `dom-chmura.ply` (7,4 MB, ta sama, której
/// używa widok 3D), więc ekran powitalny pokazuje realny efekt pracy.
///
/// RYSOWANIE: punkty rzutowane izometrycznie na płaszczyznę ekranu i rysowane
/// jako kropki w Canvas. Obrót jest powolny (jeden obrót na ~24 s), żeby tło
/// nie rozpraszało. Chmura jest wczytywana RAZ (`task`) i trzymana w pamięci —
/// parsowanie 7 MB przy każdym odświeżeniu klatki zabiłoby płynność.
struct ScanBackdrop: View {
    /// Nazwa pliku w bundlu (bez rozszerzenia).
    var resourceName: String = "dom-chmura"

    @State private var points: [SIMD3<Float>] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                guard !points.isEmpty else { return }
                let t = timeline.date.timeIntervalSinceReferenceDate

                // obrót wokół osi pionowej — powolny, żeby nie rozpraszać
                let angle = t * 0.26
                // lekki przechył, żeby było widać bryłę, a nie samą linię
                let tilt: Float = -0.35

                // środek chmury i skala dopasowana do ekranu
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let scale = min(size.width, size.height) * 0.95

                let ca = cos(angle), sa = sin(angle)
                let ct = cos(tilt), st = sin(tilt)

                var dot = Path()
                for p in points {
                    // obrót wokół Y (pion)
                    var x = Float(p.x) * Float(ca) - Float(p.z) * Float(sa)
                    var z = Float(p.x) * Float(sa) + Float(p.z) * Float(ca)
                    var y = Float(p.y)
                    // przechył wokół X
                    let y2 = y * Float(ct) - z * Float(st)
                    z = y * Float(st) + z * Float(ct)
                    y = y2

                    // rzut perspektywiczny: im dalej, tym mniejsze
                    let depth = 3.2 + z
                    guard depth > 0.2 else { continue }
                    let k = Float(scale) * 0.10 / depth
                    let px = center.x + CGFloat(x * k)
                    let py = center.y - CGFloat(y * k)
                    guard px > -20, px < size.width + 20, py > -20, py < size.height + 20 else { continue }

                    // wielkość kropki z odległości — bliżej = większa
                    let r = CGFloat(max(0.7, min(2.2, 1.6 - Double(z) * 0.25)))
                    dot.addEllipse(in: CGRect(x: px, y: py, width: r, height: r))
                }
                context.fill(dot, with: .color(.white.opacity(0.85)))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task {
            // Wczytywanie RAZ, W TLE.
            //
            // UWAGA (naprawiony błąd): parsowanie PLY (7,4 MB) na wątku głównym
            // zawieszało aplikację na kilka sekund przy starcie — ekran
            // powitalny nie reagował na dotyk. Praca idzie więc do zadania
            // w tle, a wynik wraca na aktor główny.
            if points.isEmpty {
                let name = resourceName
                let loaded = await Task.detached(priority: .utility) {
                    Self.loadPoints(named: name)
                }.value
                points = loaded
            }
        }
    }

    /// Czyta chmurę PLY i zwraca maksymalnie ~12 tys. punktów.
    ///
    /// Tyle wystarcza, żeby na ekranie 12" wyglądało to jak gęsty skan, a rysuje
    /// się w jednej klatce bez zauważalnego kosztu. 7 MB / 200 tys. punktów
    /// rysowane w całości dawałoby ~10 kl./s na samym tle.
    /// `nonisolated` — parsowanie PLY musi działać poza aktorem głównym,
    /// bo to najdroższa operacja w całym ekranie (7,4 MB pliku).
    nonisolated static func loadPoints(named name: String) -> [SIMD3<Float>] {
        var url: URL?
        if let bundled = Bundle.main.url(forResource: name, withExtension: "ply") {
            url = bundled
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            for candidate in ["../app/public/\(name).ply",
                              "app/public/\(name).ply",
                              "ios/../app/public/\(name).ply"] {
                let candidateURL = cwd.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    url = candidateURL
                    break
                }
            }
        }
        guard let url, let cloud = try? PLYParser.parse(contentsOf: url), cloud.count > 0 else {
            return []
        }

        // decymacja + wyśrodkowanie, żeby chmura obracała się wokół swojego środka
        let target = 12_000
        let stride = max(1, cloud.count / target)
        let b = cloud.bounds
        let center = (b.min + b.max) / 2
        // największy wymiar do normalizacji skali
        let span = max(max(b.max.x - b.min.x, b.max.y - b.min.y), b.max.z - b.min.z)
        let k: Float = span > 0 ? 1 / span : 1

        var out: [SIMD3<Float>] = []
        out.reserveCapacity(cloud.count / stride + 1)
        var i = 0
        while i < cloud.count {
            let p = cloud.positions[i] - center
            out.append(SIMD3(p.x * k, (p.y - (b.max.y - b.min.y) / 2 * 0) * k, p.z * k))
            i += stride
        }
        return out
    }
}
