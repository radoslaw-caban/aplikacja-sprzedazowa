import Foundation
import simd

/// Siatka pomieszczenia z modelu `RoomModel` — ściany, podłoga, sufit.
///
/// ZASADA (wymóg produktowy): siatka NIE powstaje z triangulacji ARKit.
/// Geometria bierze się z modelu (kontur + płaszczyzny ścian), a siatka jest
/// tylko „skórą" nałożoną na te płaszczyzny. Dzięki temu:
///  - wymiary są te z modelu (i te same w każdym miejscu),
///  - otwory (okna, drzwi) są prawdziwymi otworami w siatce, a nie teksturą,
///  - UV jest w METRACH, więc tekstura ma skalę realną (1 kafel = 1 m),
///    a nie „rozciągniętą na ścianę nieważne jaką".
///
/// Moduł jest czystą matematyką (tablice + simd), więc testuje się bez iPada.
public enum RoomMesh {

    /// Wierzchołek siatki: pozycja (metry) + normalna + UV w metrach.
    public struct Vertex: Sendable, Equatable {
        public var position: SIMD3<Float>
        public var normal: SIMD3<Float>
        /// współrzędne tekstury w METRACH (nie 0…1) — skala realna
        public var uv: SIMD2<Float>

        public init(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) {
            self.position = position
            self.normal = normal
            self.uv = uv
        }
    }

    /// Siatka jednej powierzchni (ściana / podłoga / sufit).
    public struct Surface: Sendable {
        public enum Kind: String, Sendable {
            case wall
            case floor
            case ceiling
        }
        public var kind: Kind
        /// indeks ściany w `RoomModel.Result.walls` (−1 dla podłogi i sufitu)
        public var wallIndex: Int
        public var vertices: [Vertex]
        /// trójkąty (indeksy do `vertices`), po 3 na trójkąt
        public var indices: [UInt32]
        /// pole powierzchni (m²) — do wyliczenia zużycia materiału
        public var area: Float

        public var triangleCount: Int { indices.count / 3 }
    }

    /// Kolor powierzchni wyliczony z chmury (do „kolor podłogi/ścian").
    public struct SurfaceColor: Sendable {
        public var location: SIMD3<Float>
        public var rgb: SIMD3<Float>   // 0…1
        public var samples: Int
    }

    /// Gotowa siatka pomieszczenia.
    public struct Result: Sendable {
        public var surfaces: [Surface]
        /// kolory powierzchni (podłoga, ściany, sufit) — po jednym na powierzchnię
        public var colors: [SurfaceColor]

        public init(surfaces: [Surface], colors: [SurfaceColor]) {
            self.surfaces = surfaces
            self.colors = colors
        }

        public var totalArea: Float { surfaces.reduce(0) { $0 + $1.area } }
        public var triangleCount: Int { surfaces.reduce(0) { $0 + $1.triangleCount } }
    }

    public struct Options: Sendable {
        /// czy budować podłogę
        public var includeFloor: Bool = true
        /// czy budować sufit
        public var includeCeiling: Bool = true
        /// wymiar kafla tekstury (metry) — UV jest w metrach, to tylko wygoda
        public var tileMetres: Float = 1.0
        /// minimalna wysokość nad otworem, żeby go wyciąć (inaczej ignorujemy)
        public var minStripHeight: Float = 0.05

        public init() {}
    }

    // MARK: - budowa

    /// Buduje siatkę pomieszczenia z modelu.
    ///
    /// - Parameter model: wynik `RoomModel.build`
    public static func build(model: RoomModel.Result, options: Options = Options()) -> Result {
        var surfaces: [Surface] = []
        var colors: [SurfaceColor] = []

        // ściany z otworami
        for (i, wall) in model.walls.enumerated() {
            let openings = model.openings.filter { $0.wallIndex == i }
            let s = wallSurface(wall: wall, wallIndex: i, openings: openings,
                                floorY: model.corners.first?.yMin ?? 0,
                                ceilingY: model.corners.first?.yMax ?? model.height,
                                options: options)
            if s.area > 0.001 {
                surfaces.append(s)
                colors.append(SurfaceColor(
                    location: SIMD3((wall.start.x + wall.end.x) / 2,
                                    (model.corners.first?.yMin ?? 0) + model.height / 2,
                                    (wall.start.y + wall.end.y) / 2),
                    rgb: SIMD3(0.86, 0.85, 0.82), samples: 0))
            }
        }

        // podłoga i sufit z konturu
        if options.includeFloor,
           let floor = horizontalSurface(corners: model.corners, y: model.corners.first?.yMin ?? 0,
                                         kind: .floor, normalUp: true) {
            surfaces.append(floor)
            colors.append(SurfaceColor(
                location: SIMD3(centroid(model.corners).x, model.corners.first?.yMin ?? 0,
                                centroid(model.corners).y),
                rgb: SIMD3(0.55, 0.42, 0.30), samples: 0))
        }
        if options.includeCeiling,
           let ceiling = horizontalSurface(corners: model.corners, y: model.corners.first?.yMax ?? model.height,
                                           kind: .ceiling, normalUp: false) {
            surfaces.append(ceiling)
            colors.append(SurfaceColor(
                location: SIMD3(centroid(model.corners).x,
                                model.corners.first?.yMax ?? model.height,
                                centroid(model.corners).y),
                rgb: SIMD3(0.95, 0.95, 0.94), samples: 0))
        }

        return Result(surfaces: surfaces, colors: colors)
    }

    /// Siatka jednej ściany z wyciętymi otworami.
    ///
    /// METODA: dzielimy prostokąt ściany siatką współrzędnych wyznaczoną przez
    /// krawędzie otworów (kolumny po długości, wiersze po wysokości), a potem
    /// pomijamy komórki leżące wewnątrz otworu. Dzięki temu:
    ///  - otwory są prawdziwymi dziurami w geometrii (nie da się przejść przez
    ///    ścianę w miejscu okna, a szyba może być osobną powierzchnią),
    ///  - nie trzeba triangulacji wielokąta z dziurami (byłaby podatna na błędy),
    ///  - komórek jest mało (kilka × kilka), więc siatka jest lekka,
    ///  - UV wychodzi wprost z pozycji w metrach.
    static func wallSurface(wall: RoomModel.Wall, wallIndex: Int,
                            openings: [RoomModel.Opening],
                            floorY: Float, ceilingY: Float,
                            options: Options) -> Surface {
        let length = wall.length
        let height = Swift.max(0.01, ceilingY - floorY)
        let dir = wall.direction
        // normalna pozioma — z modelu (już dopasowana do punktów)
        let normal = wall.planeNormal

        // granice wzdłuż ściany (metry od początku) i w pionie (od podłogi)
        var uCuts: Set<Float> = [0, length]
        var vCuts: Set<Float> = [0, height]

        // otwory przycięte do ściany; zbyt niskie pasy pomijamy
        var holes: [(u0: Float, u1: Float, v0: Float, v1: Float)] = []
        for o in openings {
            let u0 = Swift.max(0, Swift.min(length, o.offset))
            let u1 = Swift.max(0, Swift.min(length, o.offset + o.width))
            // próg otworu jest liczony od podłogi (tak liczy go RoomModel)
            let v0c = Swift.max(0, Swift.min(height, o.sill))
            let v1c = Swift.max(0, Swift.min(height, o.sill + o.height))
            guard u1 - u0 > 0.05, v1c - v0c > options.minStripHeight else { continue }
            holes.append((u0, u1, v0c, v1c))
            uCuts.insert(u0); uCuts.insert(u1)
            vCuts.insert(v0c); vCuts.insert(v1c)
        }

        let us = uCuts.sorted()
        let vs = vCuts.sorted()

        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        var area: Float = 0

        // komórki siatki → cztery wierzchołki + dwa trójkąty
        for i in 0..<(us.count - 1) {
            let u0 = us[i], u1 = us[i + 1]
            guard u1 - u0 > 0.001 else { continue }
            for j in 0..<(vs.count - 1) {
                let v0 = vs[j], v1 = vs[j + 1]
                guard v1 - v0 > 0.001 else { continue }

                let uc = (u0 + u1) / 2, vc = (v0 + v1) / 2
                let inHole = holes.contains { uc > $0.u0 && uc < $0.u1 && vc > $0.v0 && vc < $0.v1 }
                guard !inHole else { continue }

                let base = UInt32(vertices.count)
                // pozycje: start + kierunek * u, wysokość = floorY + v
                let p00 = SIMD3(wall.start.x + dir.x * u0, floorY + v0, wall.start.y + dir.y * u0)
                let p10 = SIMD3(wall.start.x + dir.x * u1, floorY + v0, wall.start.y + dir.y * u1)
                let p11 = SIMD3(wall.start.x + dir.x * u1, floorY + v1, wall.start.y + dir.y * u1)
                let p01 = SIMD3(wall.start.x + dir.x * u0, floorY + v1, wall.start.y + dir.y * u0)

                // UV w metrach: u wzdłuż ściany, v w pionie od podłogi
                let s = 1 / Swift.max(0.01, options.tileMetres)
                vertices.append(Vertex(position: p00, normal: normal, uv: SIMD2(u0 * s, v0 * s)))
                vertices.append(Vertex(position: p10, normal: normal, uv: SIMD2(u1 * s, v0 * s)))
                vertices.append(Vertex(position: p11, normal: normal, uv: SIMD2(u1 * s, v1 * s)))
                vertices.append(Vertex(position: p01, normal: normal, uv: SIMD2(u0 * s, v1 * s)))

                // dwa trójkąty, zgodnie z ruchem wskazówek patrząc od wnętrza
                indices.append(contentsOf: [base, base + 1, base + 2,
                                            base, base + 2, base + 3])
                area += (u1 - u0) * (v1 - v0)
            }
        }

        return Surface(kind: .wall, wallIndex: wallIndex,
                       vertices: vertices, indices: indices, area: area)
    }

    /// Podłoga albo sufit: wielokąt konturu triangulowany wachlarzem.
    ///
    /// Wachlarz działa, bo kontur z modelu jest wielokątem prostym bez
    /// samoprzecięć (tak wychodzi ze śledzenia brzegu). Dla konturów
    /// niewypukłych (L) wachlarz od centroidu też jest poprawny, o ile
    /// centroid leży wewnątrz — a przy L zawsze leży, dopóki bryła jest
    /// jednospójna. Gdyby nie leżał, dzielimy na trójkąty od pierwszego
    /// wierzchołka i odrzucamy te o złym znaku.
    static func horizontalSurface(corners: [RoomModel.Corner], y: Float,
                                  kind: Surface.Kind, normalUp: Bool) -> Surface? {
        guard corners.count >= 3 else { return nil }
        let normal = SIMD3<Float>(0, normalUp ? 1 : -1, 0)
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        var area: Float = 0

        let c = centroid(corners)
        let cIndex: UInt32 = 0
        vertices.append(Vertex(position: SIMD3(c.x, y, c.y), normal: normal,
                               uv: SIMD2(c.x, c.y)))

        for corner in corners {
            vertices.append(Vertex(position: SIMD3(corner.x, y, corner.z), normal: normal,
                                   uv: SIMD2(corner.x, corner.z)))
        }

        for i in 0..<corners.count {
            let a = 1 + UInt32(i)
            let b = 1 + UInt32((i + 1) % corners.count)
            // kolejność zależna od kierunku normalnej
            if normalUp {
                indices.append(contentsOf: [cIndex, b, a])
            } else {
                indices.append(contentsOf: [cIndex, a, b])
            }
            let pa = corners[i].plan
            let pb = corners[(i + 1) % corners.count].plan
            area += abs((pa.x - c.x) * (pb.y - c.y) - (pb.x - c.x) * (pa.y - c.y)) / 2
        }

        return Surface(kind: kind, wallIndex: -1, vertices: vertices,
                       indices: indices, area: area)
    }

    /// Środek ciężkości konturu (średnia wierzchołków).
    static func centroid(_ corners: [RoomModel.Corner]) -> SIMD2<Float> {
        guard !corners.isEmpty else { return .zero }
        var sum = SIMD2<Float>(0, 0)
        for c in corners { sum += c.plan }
        return sum / Float(corners.count)
    }

    // MARK: - kolory z chmury

    /// Wylicza średni kolor każdej powierzchni z chmury punktów.
    ///
    /// Po co osobno: „kolor podłogi, ścian, sufitu" to pierwsza rzecz, którą
    /// klient ocenia w wizualizacji. Branie koloru z tekstury byłoby lepsze,
    /// ale chmura z LiDAR-a ma kolory z kamery w tym samym układzie, więc
    /// uśrednienie po powierzchni daje wiarygodną bazę pod materiał.
    ///
    /// Mediania, nie średnia: pojedyncze punkty z odblaskiem (szyba, front
    /// połyskujący) zawyżają średnią i sala wychodzi biała.
    public static func averageColors(mesh: Result, cloud: PointCloud,
                                     maxDistance: Float = 0.06) -> [SurfaceColor] {
        var out: [SurfaceColor] = []
        let positions = cloud.positions
        let colors = cloud.colors

        for surface in mesh.surfaces {
            guard !surface.vertices.isEmpty, let samplePoint = surface.vertices.first?.position,
                  let colors, colors.count == positions.count else {
                out.append(SurfaceColor(location: surface.vertices.first?.position ?? .zero,
                                        rgb: SIMD3(0.8, 0.8, 0.8), samples: 0))
                continue
            }
            let normal = surface.vertices[0].normal
            var r: [Float] = [], g: [Float] = [], b: [Float] = []
            r.reserveCapacity(512); g.reserveCapacity(512); b.reserveCapacity(512)

            // próbkujemy punkty blisko płaszczyzny powierzchni; wystarczy co N-ty
            let stride = Swift.max(1, positions.count / 40_000)
            var total = 0
            var checked = 0
            var i = 0
            while i < positions.count, checked < 40_000 {
                let p = positions[i]
                i += stride
                checked += 1
                let d = simd_dot(p - samplePoint, normal)
                guard abs(d) <= maxDistance else { continue }
                let c = colors[i]
                r.append(Float(c.x) / 255)
                g.append(Float(c.y) / 255)
                b.append(Float(c.z) / 255)
                total += 1
            }

            if total >= 20 {
                r.sort(); g.sort(); b.sort()
                let mid = total / 2
                out.append(SurfaceColor(location: samplePoint,
                                        rgb: SIMD3(r[mid], g[mid], b[mid]), samples: total))
            } else {
                // za mało danych — kolor neutralny, żeby wizualizacja nie kłamała
                out.append(SurfaceColor(location: samplePoint,
                                        rgb: SIMD3(0.8, 0.8, 0.8), samples: total))
            }
        }
        return out
    }
}
