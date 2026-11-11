import Foundation
import simd
import KitchenCore

#if os(iOS)
import ARKit
import CoreVideo
#endif

/// Wątkobezpieczny stan fuzji głębi.
///
/// DLACZEGO OSOBNA KLASA, A NIE POLE W `RoomScanSession`:
/// klatki ARKit przychodzą na własnej kolejce (nigdy na MainActor), a UI czyta
/// statystyki z MainActor. Wspólny `DepthFusionState` pod lockiem jest jedynym
/// miejscem styku — sesja (MainActor) i delegat (kolejka ARKit) nie dzielą
/// żadnego innego stanu.
///
/// Fuzja trzyma do `maxVoxels` wokseli, żeby skan nie zjadł pamięci iPada:
/// przy 2 mln wokseli (8 mm) to ~150 MB w słowniku — bezpieczny zapas.
public final class DepthFusionStore: @unchecked Sendable {

    public struct Stats: Sendable {
        public var frames: Int
        public var voxels: Int
        public var samples: Int
        public var rejected: Int
        /// mediana σ z próbki wokseli (metry); 0 = brak danych
        public var medianSigma: Float
        /// obrys chmury fuzji (metry); `nil`, gdy fuzja jest pusta
        public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
        public var hasData: Bool { voxels > 0 }
    }

    private let lock = NSLock()
    private var state: DepthFusionState
    private var frames = 0
    private var lastTimestamp: Double = -.greatestFiniteMagnitude

    /// Czy przyjmować klatki (wyłącza się np. po zakończeniu skanu).
    public var enabled: Bool = true
    /// Minimalny odstęp między przyjmowanymi klatkami (s).
    /// 1/30 = maks. 30 klatek/s; LiDAR i tak nie daje więcej sensownego detalu,
    /// a fuzja 60 klatek/s zjada rdzeń bez zysku dokładności.
    public var minFrameInterval: Double = 1.0 / 30.0
    public var maxVoxels: Int = 2_000_000
    public var minConfidence: UInt8 = 1

    public init(cell: Float = DepthFusion.defaultCell) {
        self.state = DepthFusionState(cell: cell)
    }

    public var cell: Float {
        lock.lock(); defer { lock.unlock() }
        return state.cell
    }

    /// Rezerwuje znacznik czasu klatki. Zwraca `false`, gdy klatkę należy pominąć.
    ///
    /// Sprawdzenie MUSI być przed konwersją mapy głębi — konwersja alokuje
    /// ~350 kB na klatkę i przy 60 fps byłaby czystym marnotrawstwem.
    public func claim(timestamp: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return false }
        guard timestamp - lastTimestamp >= minFrameInterval else { return false }
        lastTimestamp = timestamp
        return true
    }

    /// Wrzuca skonwertowaną klatkę do fuzji. Zwraca liczbę przyjętych pomiarów.
    @discardableResult
    public func add(_ frame: DepthFrame) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return 0 }
        frames += 1
        return DepthFusion.add(
            frame: frame,
            into: &state,
            minConfidence: minConfidence,
            stride: 1,
            maxVoxels: maxVoxels
        )
    }

    /// Statystyki dla UI. Mediana σ liczona z próbki (co któryś woksel) —
    /// sortowanie 2 mln wartości co 0,4 s zablokowałoby skan.
    public func stats() -> Stats {
        lock.lock()
        let snapshot = (state: state, frames: frames)
        lock.unlock()

        var sigmas: [Float] = []
        sigmas.reserveCapacity(1024)
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let step = Swift.max(1, snapshot.state.voxels.count / 1024)
        var i = 0
        for (_, acc) in snapshot.state.voxels {
            let p = acc.position
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
            if i % step == 0, acc.weightSum > 0 { sigmas.append(acc.sigma) }
            i += 1
        }
        sigmas.sort()
        let median = sigmas.isEmpty ? 0 : sigmas[sigmas.count / 2]

        return Stats(
            frames: snapshot.frames,
            voxels: snapshot.state.voxelCount,
            samples: snapshot.state.samples,
            rejected: snapshot.state.rejected,
            medianSigma: median,
            bounds: snapshot.state.voxels.isEmpty ? nil : (lo, hi)
        )
    }

    /// Zamyka fuzję: zabiera stan i liczy chmurę. Wołać z wątku w tle —
    /// przy setkach tysięcy wokseli to setki milisekund.
    ///
    /// Stan jest PRZENOSZONY (nie kopiowany) pod lockiem, więc pamięć nie
    /// podwaja się w szczycie.
    public func finish(minSamples: Int = 1) -> FusedCloud? {
        lock.lock()
        var taken = state
        state = DepthFusionState(cell: taken.cell)
        let hadEnabled = enabled
        enabled = false
        lastTimestamp = -.greatestFiniteMagnitude
        lock.unlock()
        _ = hadEnabled

        return DepthFusion.fused(from: taken, minSamples: minSamples)
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        let cell = state.cell
        state = DepthFusionState(cell: cell)
        frames = 0
        lastTimestamp = -.greatestFiniteMagnitude
        enabled = true
    }
}

#if os(iOS)

/// Konwersja klatki ARKit na `DepthFrame` — jedyne miejsce z CoreVideo.
///
/// MAPA GŁĘBI, NIE SIATKA: siatka ARKit ma rozdzielczość ~5–10 cm i jest
/// wygładzona; mapa głębi LiDAR-a to 256×192 niezależnych pomiarów na klatkę.
/// Dlatego do dokładności bierzemy głębię, a siatkę zostawiamy jako fallback
/// i jako geometrię „zgrubną” do klasyfikacji powierzchni.
public enum ARDepthConverter {

    /// Konwertuje klatkę. Zwraca `nil`, gdy brak mapy głębi albo format jest
    /// nieobsługiwany — wołający po prostu pomija klatkę.
    ///
    /// - Parameter includeColor: czy próbkować kolor z obrazu kamery.
    ///   Kosztuje ~50 tys. odczytów na klatkę; wyłączyć, gdy liczy się CPU.
    public static func depthFrame(
        from frame: ARFrame,
        includeColor: Bool = true
    ) -> DepthFrame? {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }
        let depthBuffer = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let depthStride = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard width > 0, height > 0, let depthBase = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return nil
        }

        let format = CVPixelBufferGetPixelFormatType(depthBuffer)
        var depths = [Float](repeating: 0, count: width * height)
        switch format {
        case kCVPixelFormatType_DepthFloat16:
            for y in 0..<height {
                let row = depthBase.advanced(by: y * depthStride)
                    .assumingMemoryBound(to: Float16.self)
                for x in 0..<width {
                    depths[y * width + x] = Float(row[x])
                }
            }
        case kCVPixelFormatType_DepthFloat32:
            for y in 0..<height {
                let row = depthBase.advanced(by: y * depthStride)
                    .assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    depths[y * width + x] = row[x]
                }
            }
        default:
            return nil
        }

        // ufność: brak mapy = traktujemy jak średnią (LiDAR zawsze ją daje,
        // ale nie chcemy wywalić całej klatki z powodu braku jednego bufora)
        var confidence = [UInt8](repeating: 1, count: width * height)
        if let confBuffer = depthData.confidenceMap {
            CVPixelBufferLockBaseAddress(confBuffer, .readOnly)
            let confStride = CVPixelBufferGetBytesPerRow(confBuffer)
            if let confBase = CVPixelBufferGetBaseAddress(confBuffer) {
                for y in 0..<height {
                    let row = confBase.advanced(by: y * confStride)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        confidence[y * width + x] = Swift.min(2, row[x])
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(confBuffer, .readOnly)
        }

        // intrinsics opisują obraz kamery; mapa głębi ma inne wymiary,
        // ale to samo pole widzenia — skalujemy proporcjonalnie
        let intrinsics = frame.camera.intrinsics
        let imageW = Int(frame.camera.imageResolution.width.rounded())
        let imageH = Int(frame.camera.imageResolution.height.rounded())
        let scaled = DepthFusion.scaledIntrinsics(
            intrinsics[0][0], intrinsics[1][1], intrinsics[2][0], intrinsics[2][1],
            from: imageW, to: width,
            imageHeight: imageH, depthHeight: height
        )

        let colors: [SIMD3<UInt8>]? = includeColor
            ? sampleColors(from: frame.capturedImage, width: width, height: height)
            : nil

        return DepthFrame(
            depths: depths,
            confidence: confidence,
            width: width,
            height: height,
            cameraTransform: frame.camera.transform,
            fx: scaled.fx,
            fy: scaled.fy,
            cx: scaled.cx,
            cy: scaled.cy,
            colors: colors
        )
    }

    /// Kolor per piksel mapy głębi (najbliższy sąsiad z obrazu kamery).
    ///
    /// Obraz ARKit to YCbCr biplanar (plan Y pełny, plan CbCr o połowie
    /// rozdzielczości w obu osiach). Konwersja na RGB z pełnym zakresem
    /// lub wideo — zależnie od formatu bufora.
    private static func sampleColors(
        from pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> [SIMD3<UInt8>] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isFullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard isFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return [SIMD3<UInt8>](repeating: SIMD3<UInt8>(200, 200, 200), count: width * height)
        }

        let imageW = CVPixelBufferGetWidth(pixelBuffer)
        let imageH = CVPixelBufferGetHeight(pixelBuffer)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let yPlane = yBase.assumingMemoryBound(to: UInt8.self)
        let cPlane = cBase.assumingMemoryBound(to: UInt8.self)

        let sx = Float(imageW) / Float(width)
        let sy = Float(imageH) / Float(height)
        var out = [SIMD3<UInt8>](repeating: SIMD3<UInt8>(200, 200, 200), count: width * height)

        for y in 0..<height {
            let iy = Swift.min(imageH - 1, Int(Float(y) * sy))
            let cy = Swift.min(imageH / 2 - 1, iy / 2)
            for x in 0..<width {
                let ix = Swift.min(imageW - 1, Int(Float(x) * sx))
                let cx = Swift.min(imageW / 2 - 1, ix / 2)

                let luma = Float(yPlane[iy * yStride + ix])
                let cb = Float(cPlane[cy * cStride + cx * 2]) - 128
                let cr = Float(cPlane[cy * cStride + cx * 2 + 1]) - 128

                var r: Float, g: Float, b: Float
                if isFullRange {
                    r = luma + 1.402 * cr
                    g = luma - 0.344_136 * cb - 0.714_136 * cr
                    b = luma + 1.772 * cb
                } else {
                    let l = (luma - 16) * 1.164
                    r = l + 1.596 * cr
                    g = l - 0.813 * cr - 0.391 * cb
                    b = l + 2.018 * cb
                }
                out[y * width + x] = SIMD3<UInt8>(clamp8(r), clamp8(g), clamp8(b))
            }
        }
        return out
    }

    @inline(__always)
    private static func clamp8(_ v: Float) -> UInt8 {
        UInt8(Swift.max(0, Swift.min(255, v.rounded())))
    }
}

#endif
