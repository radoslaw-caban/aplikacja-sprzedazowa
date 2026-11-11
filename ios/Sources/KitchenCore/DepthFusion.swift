import Foundation
import simd

/// Pojedyncza klatka danych głębi z LiDAR-u, gotowa do fuzji.
///
/// Celowo NIE importuje ARKit ani CoreVideo — konwersja `ARDepthData` na ten
/// typ dzieje się w warstwie iOS. Dzięki temu cała matematyka (rzutowanie,
/// fuzja wokselowa, wyliczanie niepewności) jest testowalna na macOS.
public struct DepthFrame: Sendable {

    /// Pozycje 3D wszystkich pikseli mapy głębi w układzie ŚWIATA (metry).
    ///
    /// Potrzebne do budowy planu w trakcie skanowania: kontur liczy się
    /// z rzeczywistych punktów ścian, a nie z siatki ARKit (która jest
    /// wygładzona i ma komórki 5–10 cm).
    ///
    /// - Parameters:
    ///   - minDepth: bliżej niż to odrzucamy (LiDAR gubi ostrość < 25 cm)
    ///   - maxDepth: dalej niż to odrzucamy (poza zasięgiem sensownej dokładności)
    ///   - minConfidence: 0 = wszystko, 1 = średnia i wysoka, 2 = tylko wysoka
    /// - Returns: pozycje w metrach, w układzie świata ARKit
    public func positions(minDepth: Float = 0.25, maxDepth: Float = 5.0,
                          minConfidence: UInt8 = 1) -> [SIMD3<Float>] {
        guard width > 0, height > 0, depths.count >= width * height,
              fx > 0, fy > 0 else { return [] }
        let hasConfidence = confidence.count >= width * height
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(width * height / 2)

        for v in 0..<height {
            for u in 0..<width {
                let i = v * width + u
                let d = depths[i]
                guard d.isFinite, d >= minDepth, d <= maxDepth else { continue }
                if hasConfidence, confidence[i] < minConfidence { continue }
                // promień w układzie kamery: x w prawo, y w dół, z do przodu
                let x = (Float(u) - cx) / fx * d
                let y = (Float(v) - cy) / fy * d
                let local = SIMD4<Float>(x, y, d, 1)
                let world = cameraTransform * local
                out.append(SIMD3(world.x, world.y, world.z))
            }
        }
        return out
    }
    /// Głębokość w metrach, wiersz po wierszu (szerokość × wysokość).
    public var depths: [Float]
    /// Poziom ufności ARKit per piksel (0 = low, 1 = medium, 2 = high).
    public var confidence: [UInt8]
    public var width: Int
    public var height: Int

    /// Macierz kamery (świat ← kamera) w chwili klatki.
    public var cameraTransform: simd_float4x4
    /// Czy `depths`/`confidence` zawierają dane (pole wygodne dla wołających).
    /// Ogniskowa i punkt główny dla rozdzielczości MAPY GŁĘBI (nie obrazu).
    public var fx: Float
    public var fy: Float
    public var cx: Float
    public var cy: Float

    /// Kolory z obrazu kamery (RGB 0–255), opcjonalne.
    public var colors: [SIMD3<UInt8>]?

    public init(
        depths: [Float],
        confidence: [UInt8],
        width: Int,
        height: Int,
        cameraTransform: simd_float4x4,
        fx: Float,
        fy: Float,
        cx: Float,
        cy: Float,
        colors: [SIMD3<UInt8>]? = nil
    ) {
        self.depths = depths
        self.confidence = confidence
        self.width = width
        self.height = height
        self.cameraTransform = cameraTransform
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.colors = colors
    }
}

/// Fuzja klatek głębi w chmurę punktów.
///
/// DLACZEGO TAK, A NIE PRÓBKOWANIE SIATKI:
/// siatka ARKit (`ARMeshAnchor`) ma rozdzielczość ~5–10 cm — to jej natura,
/// wygładzona i zredukowana. Zmniejszanie kroku próbkowania nie dodaje detalu,
/// tylko interpoluje płaskie trójkąty. Prawdziwy detal jest w mapie głębi
/// LiDAR-a: 256×192 pomiarów na klatkę, kilkadziesiąt tysięcy na sekundę.
///
/// METODA: każdy piksel głębi rzutujemy na punkt świata i wrzucamy do siatki
/// wokseli. Woksel pamięta ŚREDNIĄ WAŻONĄ pozycji, gdzie waga = 1/σ².
/// To nie jest wygładzanie — to uśrednianie niezależnych pomiarów tego samego
/// fragmentu powierzchni, więc szum maleje jak 1/√N:
///
///     σ_wynik = 1 / √(Σ 1/σᵢ²)
///
/// Po 50 klatkach z σ = 1 cm schodzimy do ~1,4 mm na woksel. Dlatego tryb
/// dokładny trzeba „przeskanować" dłużej — i dlatego jest naprawdę dokładniejszy.
public enum DepthFusion {

    /// Bok woksela fuzji w metrach. 0.012 = 12 mm.
    ///
    /// To NIE jest ziarno dokładności wyniku (to daje σ_wynik = σ/√N) — to
    /// ziarno GRUPOWANIA pomiarów. Musi być większe niż rozstaw pikseli mapy
    /// głębi w przestrzeni, inaczej każdy piksel trafia do własnego woksela
    /// i uśrednianie w ogóle nie zachodzi.
    ///
    /// ZMIERZONE (sweep na symulowanej ścianie, `swift run KitchenChecks --sweep`):
    /// piksel mapy głębi przy 2 m to ~1 cm poprzecznie, więc:
    ///  - 4–10 mm: dokładnie 1,00 pkt/woksel — brak fuzji, σ stoi na 3–8 mm,
    ///  - 12 mm: 8–30 pkt/woksel, σ 2,4 mm po 100 klatkach, błąd syst. 0,6 mm,
    ///  - 15 mm: 8–53 pkt/woksel, σ 2,0 mm, błąd syst. 1,3 mm,
    ///  - 20–25 mm: σ 1,3–1,4 mm, ale tylko 33–51% pokrycia i widoczna
    ///    „kostka" na powierzchniach pochyłych.
    ///
    /// 12 mm to najlepszy kompromis: realne uśrednianie, pełne pokrycie,
    /// błąd systematyczny poniżej pół milimetra.
    public static let defaultCell: Float = 0.012

    /// Minimalna głębokość sensownego pomiaru (m). Bliżej — to już obiektyw/kurz.
    public static let minDepth: Float = 0.25
    /// Maksymalna głębokość (m). Dalej LiDAR wyraźnie traci dokładność.
    public static let maxDepth: Float = 5.0

    /// Szacowana niepewność pomiaru (m) dla poziomu ufności ARKit.
    ///
    /// Wartości z charakterystyki LiDAR-u Apple: przy dobrej ufności na
    /// dystansie do ~2 m błąd to ok. 5 mm, przy średniej rzędu 1,5 cm.
    /// Dla niskiej niepewności pomiar i tak odrzucamy.
    public static func depthSigma(confidence: UInt8, depth: Float) -> Float {
        let base: Float = confidence >= 2 ? 0.004 : 0.012
        // błąd rośnie z odległością (mniejsza liczba fotonów na piksel)
        let distanceTerm = 1.0 + Swift.max(0, depth - 1.0) * 0.5
        return base * distanceTerm
    }

    /// Rośnie z odległością: ten sam piksel na dalszej powierzchni ma większą
    /// łatę, a więc większy błąd poprzeczny. `1/fx` to kąt jednego piksela.
    public static func lateralSigma(depth: Float, fx: Float) -> Float {
        guard fx > 0 else { return 0 }
        return depth / fx
    }

    /// Łączna niepewność 3D jednego pomiaru (m).
    public static func pointSigma(confidence: UInt8, depth: Float, fx: Float) -> Float {
        let d = depthSigma(confidence: confidence, depth: depth)
        let l = lateralSigma(depth: depth, fx: fx)
        return (d * d + l * l).squareRoot()
    }

    /// Rzutuje piksel głębi na punkt w przestrzeni świata.
    ///
    /// Konwencja ARKit: przestrzeń kamery jest prawoskrętna, +X w prawo,
    /// +Y w górę, a kamera patrzy w **-Z**. Głębokość z LiDAR-u to dodatnia
    /// odległość wzdłuż osi patrzenia, więc `z_cam = -depth`. Wiersz obrazu
    /// rośnie w dół, stąd negacja `y`.
    public static func worldPoint(
        x: Int,
        y: Int,
        depth: Float,
        fx: Float,
        fy: Float,
        cx: Float,
        cy: Float,
        transform: simd_float4x4
    ) -> SIMD3<Float> {
        let xCam = (Float(x) - cx) * depth / fx
        let yCam = -(Float(y) - cy) * depth / fy
        let zCam = -depth
        let w = transform * SIMD4<Float>(xCam, yCam, zCam, 1)
        return SIMD3<Float>(w.x, w.y, w.z)
    }

    /// Skalowanie intrinsics z rozdzielczości obrazu na rozdzielczość mapy głębi.
    ///
    /// `ARCamera.intrinsics` opisują obraz kamery (np. 1920×1440), a mapa głębi
    /// ma 256×192. Oba mają to samo pole widzenia, więc parametry skalują się
    /// proporcjonalnie.
    public static func scaledIntrinsics(
        _ fx: Float, _ fy: Float, _ cx: Float, _ cy: Float,
        from imageWidth: Int, to depthWidth: Int,
        imageHeight: Int, depthHeight: Int
    ) -> (fx: Float, fy: Float, cx: Float, cy: Float) {
        guard imageWidth > 0, imageHeight > 0 else { return (fx, fy, cx, cy) }
        let sx = Float(depthWidth) / Float(imageWidth)
        let sy = Float(depthHeight) / Float(imageHeight)
        return (fx * sx, fy * sy, cx * sx, cy * sy)
    }
}

/// Akumulator jednego woksela: średnia ważona pozycji i koloru.
///
/// Trzymamy sumy, nie średnie — dzięki temu nowy pomiar to kilka dodawań,
/// a wynik liczymy raz na końcu.
public struct VoxelAccumulator: Sendable {
    /// ile pomiarów wpadło do tego woksela (do odsiewu wokseli widzianych raz)
    public var count: Int = 0
    /// suma wag (1/σ²)
    public var weightSum: Float = 0
    public var px: Float = 0
    public var py: Float = 0
    public var pz: Float = 0
    public var r: Float = 0
    public var g: Float = 0
    public var b: Float = 0
    public var colorWeight: Float = 0

    public init() {}

    /// Dokłada pomiar. `sigma` w metrach, `weight = 1/σ²`.
    public mutating func add(position: SIMD3<Float>, sigma: Float, color: SIMD3<UInt8>?) {
        let s = Swift.max(sigma, 1e-4)
        let w = 1.0 / (s * s)
        count += 1
        weightSum += w
        px += position.x * w
        py += position.y * w
        pz += position.z * w
        if let c = color {
            r += Float(c.x) * w
            g += Float(c.y) * w
            b += Float(c.z) * w
            colorWeight += w
        }
    }

    /// Pozycja wynikowa (średnia ważona).
    public var position: SIMD3<Float> {
        guard weightSum > 0 else { return .zero }
        return SIMD3(px / weightSum, py / weightSum, pz / weightSum)
    }

    /// Niepewność wyniku: 1/√(Σw). To jest ta liczba, która maleje z liczbą klatek.
    public var sigma: Float {
        guard weightSum > 0 else { return .greatestFiniteMagnitude }
        return 1.0 / weightSum.squareRoot()
    }

    public var color: SIMD3<UInt8>? {
        guard colorWeight > 0 else { return nil }
        func clamp(_ v: Float) -> UInt8 {
            UInt8(Swift.max(0, Swift.min(255, (v / colorWeight).rounded())))
        }
        return SIMD3(clamp(r), clamp(g), clamp(b))
    }
}

/// Stan narastającej fuzji — trzymany między klatkami.
public struct DepthFusionState: Sendable {
    /// woksel → akumulator; klucz to spakowane indeksy komórki
    public var voxels: [Int64: VoxelAccumulator] = [:]
    public var cell: Float
    /// liczba przyjętych pomiarów (nie wokseli)
    public var samples: Int = 0
    /// liczba odrzuconych (za daleko / niska ufność / brak danych)
    public var rejected: Int = 0

    public init(cell: Float = DepthFusion.defaultCell) {
        self.cell = cell
    }

    public var voxelCount: Int { voxels.count }

    /// Spakowany klucz woksela. 21 bitów na oś = ±1 mln komórek,
    /// czyli ±8 km przy wokslu 8 mm — z zapasem na każdy skan.
    @inline(__always)
    public static func key(_ ix: Int32, _ iy: Int32, _ iz: Int32) -> Int64 {
        let a = Int64(ix & 0x1F_FFFF)
        let b = Int64(iy & 0x1F_FFFF)
        let c = Int64(iz & 0x1F_FFFF)
        return (a << 42) | (b << 21) | c
    }
}

/// Wynik fuzji map głębi: punkty w metrach + niepewność per punkt.
///
/// `medianSigma` to metryka jakości skanu — pojedynczy pomiar LiDAR-u ma
/// 4–15 mm, a fuzja N pomiarów zbija to do σ/√N. W UI pokazujemy medianę,
/// bo średnia zawyża wynik przez punkty z niską ufnością na krawędziach.
public struct FusedCloud: Sendable {
    public var positions: [SIMD3<Float>]     // metry, układ ARKit (worldAlignment = .gravity)
    public var colors: [SIMD3<UInt8>]
    public var sigma: [Float]                // niepewność per punkt (metry)
    public var samples: Int                  // przyjęte pomiary (nie woksele)
    public var voxels: Int
    public var medianSigma: Float
    public var meanSigma: Float

    public init(
        positions: [SIMD3<Float>],
        colors: [SIMD3<UInt8>],
        sigma: [Float],
        samples: Int,
        voxels: Int,
        medianSigma: Float,
        meanSigma: Float
    ) {
        self.positions = positions
        self.colors = colors
        self.sigma = sigma
        self.samples = samples
        self.voxels = voxels
        self.medianSigma = medianSigma
        self.meanSigma = meanSigma
    }

    public var count: Int { positions.count }

    /// Chmura w formacie reszty appki (metry — tak jak `MeshSampler.sample`).
    ///
    /// Przekazuje `sigma` do chmury: bez tego niepewność policzona w fuzji
    /// ginęła przy eksporcie i odbiorca pliku nie miał jak odsiać słabych
    /// punktów — a to jest główna wartość tej metody.
    public var cloud: PointCloud {
        PointCloud(positions: positions, colors: colors, uncertainty: sigma)
    }

    /// „1,2 mm · 412 tys. pkt" — do statusu w UI.
    public var qualityText: String {
        String(format: "%.1f mm", medianSigma * 1000)
    }
}

public extension DepthFusion {

    /// Wrzuca jedną klatkę do stanu fuzji.
    ///
    /// - Parameters:
    ///   - frame: klatka głębi (metry, ufność, intrinsics dla mapy głębi)
    ///   - state: stan narastający (mutowany w miejscu)
    ///   - minConfidence: 2 = tylko wysoka, 1 = wysoka i średnia
    ///   - stride: co który piksel brać (1 = wszystkie; 2 = pół, szybciej)
    ///   - maxVoxels: twardy limit pamięci
    /// - Returns: liczba przyjętych pomiarów w tej klatce
    @discardableResult
    static func add(
        frame: DepthFrame,
        into state: inout DepthFusionState,
        minConfidence: UInt8 = 1,
        stride: Int = 1,
        maxVoxels: Int = 3_000_000
    ) -> Int {
        guard frame.width > 0, frame.height > 0,
              frame.depths.count >= frame.width * frame.height,
              frame.confidence.count >= frame.width * frame.height else { return 0 }

        let cell = state.cell
        let step = Swift.max(1, stride)
        var accepted = 0

        for y in Swift.stride(from: 0, to: frame.height, by: step) {
            for x in Swift.stride(from: 0, to: frame.width, by: step) {
                let i = y * frame.width + x
                let d = frame.depths[i]
                let conf = frame.confidence[i]

                // odsiew: brak danych, za blisko, za daleko, niska ufność
                guard d.isFinite, d > minDepth, d < maxDepth, conf >= minConfidence else {
                    state.rejected += 1
                    continue
                }

                let p = worldPoint(
                    x: x, y: y, depth: d,
                    fx: frame.fx, fy: frame.fy, cx: frame.cx, cy: frame.cy,
                    transform: frame.cameraTransform
                )
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite else {
                    state.rejected += 1
                    continue
                }

                let sigma = pointSigma(confidence: conf, depth: d, fx: frame.fx)
                let ix = Int32((p.x / cell).rounded())
                let iy = Int32((p.y / cell).rounded())
                let iz = Int32((p.z / cell).rounded())
                let k = DepthFusionState.key(ix, iy, iz)

                if var acc = state.voxels[k] {
                    acc.add(position: p, sigma: sigma, color: frame.colors?[i])
                    state.voxels[k] = acc
                } else {
                    guard state.voxels.count < maxVoxels else { continue }
                    var acc = VoxelAccumulator()
                    acc.add(position: p, sigma: sigma, color: frame.colors?[i])
                    state.voxels[k] = acc
                }
                accepted += 1
            }
        }
        state.samples += accepted
        return accepted
    }

    /// Wynik fuzji: punkty w METRACH, kolory i niepewność per punkt.
    ///
    /// Osobny typ, bo `PointCloud` (konwencja reszty appki: geometria szafek
    /// w mm, chmury skanów w m) nie mieści niepewności — a to ona jest
    /// produktem tej metody i to ona trafia do metryki jakości skanu.
    ///
    /// `minSamples` odsiewa woksele widziane raz — pojedynczy pomiar to szum,
    /// nie geometria. To jedna z przyczyn, dla których tryb dokładny wymaga
    /// przejścia pomieszczenia w kilku ujęciach.
    ///
    /// - Returns: `nil`, gdy nie ma czego zwracać (pusta fuzja)
    static func fused(
        from state: DepthFusionState,
        minSamples: Int = 1
    ) -> FusedCloud? {
        let minN = Swift.max(1, minSamples)
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<UInt8>] = []
        var sigmas: [Float] = []
        positions.reserveCapacity(state.voxels.count)
        colors.reserveCapacity(state.voxels.count)
        sigmas.reserveCapacity(state.voxels.count)

        for (_, acc) in state.voxels {
            guard acc.count >= minN, acc.weightSum > 0 else { continue }
            positions.append(acc.position)
            colors.append(acc.color ?? SIMD3<UInt8>(200, 200, 200))
            sigmas.append(acc.sigma)
        }
        guard !positions.isEmpty else { return nil }

        var sorted = sigmas
        sorted.sort()
        let median = sorted[sorted.count / 2]
        let mean = sigmas.reduce(0, +) / Float(sigmas.count)

        return FusedCloud(
            positions: positions,
            colors: colors,
            sigma: sigmas,
            samples: state.samples,
            voxels: state.voxels.count,
            medianSigma: median,
            meanSigma: mean
        )
    }
}
