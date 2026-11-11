import Foundation
import simd

/// Moduł modelu pomieszczenia ze skanu — NIEZALEŻNY od reszty aplikacji.
///
/// Filozofia (wymóg produktowy): geometria nie może pochodzić z triangulacji.
/// Siatka ARKit jest tylko powierzchnią pomocniczą. Model powstaje tak:
///
///   1. **Narożniki** — z chmury wyznaczamy pionowe krawędzie (przecięcia ścian).
///   2. **Kontur** — narożniki łączymy w zamknięty wielokąt (obrys pomieszczenia).
///   3. **Ściany** — każdy odcinek konturu dostaje własną płaszczyznę dopasowaną
///      do punktów, więc ściana ma realne wygięcie i pion, a nie „prostokąt z pudełka".
///   4. Dopiero na taki model nakłada się siatkę i teksturę.
///
/// Cały ten plik jest czystą matematyką na tablicach — bez ARKit, bez RealityKit,
/// więc testuje się na macOS i można go włączyć do aplikacji, gdy będzie gotowy.
public enum RoomModel {

    // MARK: - typy

    /// Punkt pomiarowy: pozycja (metry, układ ARKit) + niepewność (metry).
    public struct Sample: Sendable {
        public var position: SIMD3<Float>
        public var sigma: Float

        public init(position: SIMD3<Float>, sigma: Float = 0.01) {
            self.position = position
            self.sigma = sigma
        }
    }

    /// Narożnik pomieszczenia: pozycja w planie (X, Z) i pionowa krawędź.
    public struct Corner: Sendable, Identifiable {
        public var id = UUID()
        /// pozycja w planie, metry
        public var x: Float
        public var z: Float
        /// dolna i górna wysokość pionowej krawędzi (metry, Y)
        public var yMin: Float
        public var yMax: Float
        /// kąt dwusiecznej narożnika (stopnie) — kierunek „na zewnątrz"
        public var bisectorDeg: Double
        /// pewność wykrycia 0…1
        public var confidence: Float

        public init(x: Float, z: Float, yMin: Float = 0, yMax: Float = 2.6,
                    bisectorDeg: Double = 0, confidence: Float = 1) {
            self.x = x
            self.z = z
            self.yMin = yMin
            self.yMax = yMax
            self.bisectorDeg = bisectorDeg
            self.confidence = confidence
        }

        public var plan: SIMD2<Float> { SIMD2(x, z) }
        public var height: Float { yMax - yMin }
    }

    /// Ściana: odcinek konturu + dopasowana płaszczyzna.
    ///
    /// Płaszczyzna jest opisana punktem i normalną — to pozwala policzyć
    /// odchyłkę dowolnego punktu i pokazać, jak bardzo ściana „ucieka"
    /// od prostej (wygięcie, pion).
    public struct Wall: Sendable, Identifiable {
        public var id = UUID()
        public var start: SIMD2<Float>
        public var end: SIMD2<Float>
        /// punkt na płaszczyźnie ściany (metry)
        public var planePoint: SIMD3<Float>
        /// normalna płaszczyzny (jednostkowa, pozioma)
        public var planeNormal: SIMD3<Float>
        /// odchyłka punktów od płaszczyzny: mediana i 95 percentyl (metry)
        public var residualMedian: Float
        public var residualP95: Float
        /// pion: nachylenie w mm na metr wysokości (0 = idealny pion)
        public var plumbMmPerM: Float
        /// liczba punktów użytych do dopasowania
        public var samples: Int

        public init(start: SIMD2<Float>, end: SIMD2<Float>,
                    planePoint: SIMD3<Float>, planeNormal: SIMD3<Float>,
                    residualMedian: Float = 0, residualP95: Float = 0,
                    plumbMmPerM: Float = 0, samples: Int = 0) {
            self.start = start
            self.end = end
            self.planePoint = planePoint
            self.planeNormal = planeNormal
            self.residualMedian = residualMedian
            self.residualP95 = residualP95
            self.plumbMmPerM = plumbMmPerM
            self.samples = samples
        }

        /// długość w planie (metry)
        public var length: Float { simd_length(end - start) }

        /// kierunek w planie (jednostkowy)
        public var direction: SIMD2<Float> {
            let d = end - start
            let l = simd_length(d)
            return l > 1e-6 ? d / l : SIMD2(1, 0)
        }

        /// odległość punktu od płaszczyzny (metry, ze znakiem)
        public func signedDistance(_ p: SIMD3<Float>) -> Float {
            simd_dot(p - planePoint, planeNormal)
        }
    }

    /// Otwór (okno/drzwi) wykryty na ścianie.
    public struct Opening: Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case window
            case door
        }
        public var id = UUID()
        public var wallIndex: Int
        public var kind: Kind
        /// pozycja wzdłuż ściany: od początku do początku otworu (metry)
        public var offset: Float
        public var width: Float
        /// dolna krawędź nad podłogą (metry) i wysokość otworu
        public var sill: Float
        public var height: Float

        public init(wallIndex: Int, kind: Kind, offset: Float, width: Float,
                    sill: Float, height: Float) {
            self.wallIndex = wallIndex
            self.kind = kind
            self.offset = offset
            self.width = width
            self.sill = sill
            self.height = height
        }
    }

    /// Gotowy model pomieszczenia.
    public struct Result: Sendable {
        public var corners: [Corner]
        public var walls: [Wall]
        public var openings: [Opening]
        /// wysokość pomieszczenia (metry)
        public var height: Float
        /// pole powierzchni podłogi (m²)
        public var area: Float
        /// średnia niepewność narożników (metry) — miara jakości modelu
        public var cornerSigma: Float

        public init(corners: [Corner], walls: [Wall], openings: [Opening],
                    height: Float, area: Float, cornerSigma: Float) {
            self.corners = corners
            self.walls = walls
            self.openings = openings
            self.height = height
            self.area = area
            self.cornerSigma = cornerSigma
        }

        public var isUsable: Bool { corners.count >= 3 && walls.count >= 3 }
    }

    /// Parametry detekcji — wszystkie w metrach.
    public struct Options: Sendable {
        /// grubość pasa przy podłodze, z którego bierzemy punkty do konturu
        public var floorBand: Float = 0.35
        /// grubość pasa przy suficie (do wykrycia pionu ścian)
        public var ceilingBand: Float = 0.30
        /// maksymalna odległość punktu od odcinka ściany, żeby go zaliczyć
        public var wallTolerance: Float = 0.04
        /// minimalna liczba punktów, żeby uznać narożnik
        public var minCornerSamples: Int = 40
        /// kąt (stopnie) — mniejsze różnice kierunków scalają odcinki w jedną ścianę
        public var mergeAngleDeg: Double = 8
        /// minimalna długość ściany (metry) — krótsze odcinki to szum
        public var minWallLength: Float = 0.25
        /// oczekiwana liczba ścian; 0 = wykryj automatycznie (kontur dowolny)
        public var expectedWalls: Int = 0

        public init() {}
    }
}
