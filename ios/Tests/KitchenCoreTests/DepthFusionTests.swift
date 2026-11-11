import XCTest
import simd
@testable import KitchenCore

/// Testy fuzji map głębi LiDAR-a.
///
/// Sens tych testów: fuzja ma być MECHANICZNIE sprawdzona, zanim wejdzie na
/// iPada. Na urządzeniu nie da się zmierzyć, czy błąd spadł z 5 mm do 1 mm
/// bez wzorca — a tutaj mamy dokładnie znaną scenę (płaska ściana w -Z)
/// i deterministyczny szum, więc wynik jest porównywalny z teorią σ/√N.
final class DepthFusionTests: XCTestCase {

    // MARK: - pomocnicze

    /// Deterministyczny generator (LCG) — test nie może zależeć od `random()`.
    private struct LCG {
        var state: UInt64
        mutating func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let v = Double(state >> 11) / Double(1 << 53)   // [0,1)
            return Float(v * 2 - 1)                        // [-1,1)
        }
    }

    private func frame(
        width: Int = 16,
        height: Int = 12,
        depth: Float,
        confidence: UInt8 = 2,
        fx: Float = 200,
        fy: Float = 200,
        cx: Float? = nil,
        cy: Float? = nil,
        transform: simd_float4x4 = matrix_identity_float4x4
    ) -> DepthFrame {
        DepthFrame(
            depths: [Float](repeating: depth, count: width * height),
            confidence: [UInt8](repeating: confidence, count: width * height),
            width: width,
            height: height,
            cameraTransform: transform,
            fx: fx,
            fy: fy,
            cx: cx ?? Float(width) / 2,
            cy: cy ?? Float(height) / 2
        )
    }

    // MARK: - rzutowanie piksela na świat

    func testCentrePixelProjectsStraightAhead() {
        let p = DepthFusion.worldPoint(
            x: 8, y: 6, depth: 2.0,
            fx: 200, fy: 200, cx: 8, cy: 6,
            transform: matrix_identity_float4x4
        )
        XCTAssertEqual(p.x, 0, accuracy: 1e-5)
        XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        // kamera ARKit patrzy w -Z
        XCTAssertEqual(p.z, -2.0, accuracy: 1e-5)
    }

    func testPixelOffsetScalesByDepthOverFocal() {
        // piksel 10 w prawo od osi, f = 200 → x = 10 * 2 / 200 = 0,1 m
        let p = DepthFusion.worldPoint(
            x: 18, y: 6, depth: 2.0,
            fx: 200, fy: 200, cx: 8, cy: 6,
            transform: matrix_identity_float4x4
        )
        XCTAssertEqual(p.x, 0.1, accuracy: 1e-5)
        XCTAssertEqual(p.z, -2.0, accuracy: 1e-5)

        // wiersz rośnie w dół obrazu, a oś Y świata w górę → wartość ujemna
        let q = DepthFusion.worldPoint(
            x: 8, y: 16, depth: 2.0,
            fx: 200, fy: 200, cx: 8, cy: 6,
            transform: matrix_identity_float4x4
        )
        XCTAssertEqual(q.y, -0.1, accuracy: 1e-5)
    }

    func testCameraTransformIsApplied() {
        // kamera przesunięta o 1 m w +X i obrócona o 180° wokół Y
        var t = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        t.columns.0 = SIMD4<Float>(-1, 0, 0, 0)
        t.columns.2 = SIMD4<Float>(0, 0, -1, 0)
        t.columns.3 = SIMD4<Float>(1, 0, 0, 1)

        let p = DepthFusion.worldPoint(
            x: 8, y: 6, depth: 2.0,
            fx: 200, fy: 200, cx: 8, cy: 6,
            transform: t
        )
        // lokalnie (0,0,-2) → obrót daje (0,0,2) → przesunięcie +1 w X
        XCTAssertEqual(p.x, 1.0, accuracy: 1e-5)
        XCTAssertEqual(p.z, 2.0, accuracy: 1e-5)
    }

    func testIntrinsicsScaleToDepthResolution() {
        // obraz 1920×1440, mapa głębi 256×192 → skala 0,133
        let s = DepthFusion.scaledIntrinsics(
            1600, 1600, 960, 720,
            from: 1920, to: 256,
            imageHeight: 1440, depthHeight: 192
        )
        XCTAssertEqual(s.fx, 1600 * 256.0 / 1920.0, accuracy: 1e-4)
        XCTAssertEqual(s.cx, 960 * 256.0 / 1920.0, accuracy: 1e-4)
        XCTAssertEqual(s.cy, 720 * 192.0 / 1440.0, accuracy: 1e-4)
        // punkt główny zostaje w środku mapy głębi
        XCTAssertEqual(s.cx, 128, accuracy: 1e-4)
        XCTAssertEqual(s.cy, 96, accuracy: 1e-4)
    }

    // MARK: - odsiew pomiarów

    func testRejectsOutOfRangeAndLowConfidence() {
        var state = DepthFusionState()
        let tooClose = frame(depth: 0.1)
        let tooFar = frame(depth: 6.0)
        let lowConf = frame(depth: 2.0, confidence: 0)
        let noData = DepthFrame(
            depths: [Float](repeating: .nan, count: 16 * 12),
            confidence: [UInt8](repeating: 2, count: 16 * 12),
            width: 16, height: 12,
            cameraTransform: matrix_identity_float4x4,
            fx: 200, fy: 200, cx: 8, cy: 6
        )

        XCTAssertEqual(DepthFusion.add(frame: tooClose, into: &state), 0)
        XCTAssertEqual(DepthFusion.add(frame: tooFar, into: &state), 0)
        XCTAssertEqual(DepthFusion.add(frame: lowConf, into: &state), 0)
        XCTAssertEqual(DepthFusion.add(frame: noData, into: &state), 0)
        XCTAssertEqual(state.samples, 0)
        XCTAssertEqual(state.voxelCount, 0)
        XCTAssertEqual(state.rejected, 4 * 16 * 12)
    }

    func testLowConfidenceAcceptedWhenRequested() {
        var state = DepthFusionState()
        let low = frame(depth: 2.0, confidence: 0)
        XCTAssertEqual(DepthFusion.add(frame: low, into: &state, minConfidence: 0), 192)
        XCTAssertEqual(state.voxelCount, 192)
    }

    func testStrideSkipsPixels() {
        var full = DepthFusionState()
        var half = DepthFusionState()
        DepthFusion.add(frame: frame(depth: 2.0), into: &full, stride: 1)
        DepthFusion.add(frame: frame(depth: 2.0), into: &half, stride: 2)
        XCTAssertEqual(full.samples, 192)
        // co drugi piksel w obu osiach: 8 kolumn × 6 wierszy
        XCTAssertEqual(half.samples, 48)
    }

    func testVoxelKeyIsUnique() {
        var seen = Set<Int64>()
        for x in Int32(-3)...Int32(3) {
            for y in Int32(-3)...Int32(3) {
                for z in Int32(-3)...Int32(3) {
                    seen.insert(DepthFusionState.key(x, y, z))
                }
            }
        }
        XCTAssertEqual(seen.count, 7 * 7 * 7)
        XCTAssertNotEqual(DepthFusionState.key(-1, 0, 0), DepthFusionState.key(0, -1, 0))
    }

    // MARK: - sedno: fuzja zmniejsza szum

    func testFusionReducesNoiseLikeRootN() {
        // płaska ściana 2 m przed kamerą, 60 klatek z szumem ±5 mm
        var rng = LCG(state: 42)
        let noiseSigma: Float = 0.005
        let frames = 60
        var state = DepthFusionState()

        for _ in 0..<frames {
            var depths = [Float](repeating: 0, count: 16 * 12)
            for i in 0..<depths.count {
                // szum ±5 mm (jednorodny ~ σ = 0,005 m / √3, wystarczy do testu relacji)
                depths[i] = 2.0 + rng.next() * noiseSigma
            }
            let f = DepthFrame(
                depths: depths,
                confidence: [UInt8](repeating: 2, count: depths.count),
                width: 16, height: 12,
                cameraTransform: matrix_identity_float4x4,
                fx: 200, fy: 200, cx: 8, cy: 6
            )
            DepthFusion.add(frame: f, into: &state)
        }

        guard let fused = DepthFusion.fused(from: state) else {
            return XCTFail("fuzja powinna dać punkty")
        }

        // Tożsamość, na której stoi cała metoda: σ_woksela = 1/√(Σ 1/σᵢ²).
        // Uwaga na realny efekt: piksele mapy głębi (10 mm przy 2 m, f = 200)
        // i woksel 8 mm NIE są współmierne, więc jeden piksel rozjeżdża się na
        // 2–3 sąsiednie woksele i liczba pomiarów na woksel jest ~3× mniejsza
        // niż liczba klatek. Dlatego teorio nie liczymy „sigmaOne/√frames",
        // a „sigmaOne/√mediana_pomiarów" — inaczej test kłóciłby się z fizyką.
        let sigmaOne = DepthFusion.pointSigma(confidence: 2, depth: 2.0, fx: 200)
        let counts = state.voxels.values.map(\.count).sorted()
        let medianCount = counts[counts.count / 2]
        let expected = sigmaOne / Float(medianCount).squareRoot()

        XCTAssertEqual(fused.medianSigma, expected, accuracy: expected * 0.2)
        XCTAssertLessThan(fused.medianSigma, sigmaOne,
                          "fuzja musi dać wynik lepszy niż pojedynczy pomiar")
        XCTAssertEqual(fused.samples, frames * 16 * 12)
        XCTAssertGreaterThan(fused.count, 100)

        // geometria: każdy punkt blisko płaszczyzny z = -2 (w granicach woksela)
        for p in fused.positions {
            XCTAssertEqual(p.z, -2.0, accuracy: 0.02)
        }
    }

    func testFusionIsUnbiasedOnAverage() {
        // Kwantyzacja do woksela obcina rozkład szumu w każdej komórce, więc
        // POJEDYNCZY punkt może być przesunięty o kilka mm (do pół woksela).
        // Ale średnia po całej powierzchni nie może być przesunięta — właśnie
        // to decyduje o tym, czy pomiar ściany w kuchni jest prawdziwy.
        var rng = LCG(state: 7)
        var state = DepthFusionState()
        let frames = 200

        for _ in 0..<frames {
            var depths = [Float](repeating: 0, count: 16 * 12)
            for i in 0..<depths.count { depths[i] = 2.0 + rng.next() * 0.005 }
            let f = DepthFrame(
                depths: depths,
                confidence: [UInt8](repeating: 2, count: depths.count),
                width: 16, height: 12,
                cameraTransform: matrix_identity_float4x4,
                fx: 200, fy: 200, cx: 8, cy: 6
            )
            DepthFusion.add(frame: f, into: &state)
        }

        guard let fused = DepthFusion.fused(from: state) else {
            return XCTFail("fuzja powinna dać punkty")
        }
        // znakowany błąd głębokości: (-z) - 2
        let signed = fused.positions.map { -$0.z - 2.0 }.reduce(0, +) / Float(fused.count)
        XCTAssertEqual(signed, 0, accuracy: 5e-4,
                       "średnie przesunięcie powierzchni musi być < 0,5 mm")

        // a rozrzut pojedynczych wokseli ma zmieścić się w połowie woksela
        let worst = fused.positions.map { abs(-$0.z - 2.0) }.max() ?? 0
        XCTAssertLessThan(worst, DepthFusion.defaultCell,
                          "pojedynczy woksel nie może odjechać dalej niż o woksel")
    }

    func testMinSamplesFiltersVoxelsSeenOnce() {
        var state = DepthFusionState()
        DepthFusion.add(frame: frame(depth: 2.0), into: &state)
        let once = DepthFusion.fused(from: state, minSamples: 2)
        XCTAssertNil(once, "po jednej klatce żaden woksel nie ma 2 pomiarów")

        DepthFusion.add(frame: frame(depth: 2.0), into: &state)
        let twice = DepthFusion.fused(from: state, minSamples: 2)
        XCTAssertNotNil(twice)
        XCTAssertGreaterThan(twice!.count, 100)
    }

    func testVoxelLimitIsRespected() {
        var state = DepthFusionState()
        DepthFusion.add(frame: frame(depth: 2.0), into: &state, maxVoxels: 10)
        XCTAssertEqual(state.voxelCount, 10)
    }

    func testEmptyFusionReturnsNil() {
        XCTAssertNil(DepthFusion.fused(from: DepthFusionState()))
    }

    func testFusedCloudProducesPointCloudInMetres() {
        var state = DepthFusionState()
        DepthFusion.add(frame: frame(depth: 2.0), into: &state)
        guard let fused = DepthFusion.fused(from: state) else {
            return XCTFail("fuzja powinna dać punkty")
        }
        let cloud = fused.cloud
        XCTAssertEqual(cloud.count, fused.count)
        XCTAssertEqual(cloud.colors?.count, fused.count)
        // metry, nie mm: obrys ~kilkadziesiąt cm, nie tysiące
        let size = cloud.bounds.max - cloud.bounds.min
        XCTAssertLessThan(size.x, 1.0)
        XCTAssertLessThan(size.y, 1.0)
        XCTAssertEqual(cloud.bounds.max.z, -2.0 + 0.01, accuracy: 0.02)
    }

    func testQualityTextIsMillimetres() {
        var state = DepthFusionState()
        DepthFusion.add(frame: frame(depth: 2.0), into: &state)
        let fused = DepthFusion.fused(from: state)!
        // σ pojedynczego pomiaru to ~11,7 mm — tekst ma to pokazać w mm
        XCTAssertTrue(fused.qualityText.hasSuffix(" mm"), fused.qualityText)
        let value = Float(fused.qualityText.replacingOccurrences(of: " mm", with: "")) ?? 0
        XCTAssertEqual(value, fused.medianSigma * 1000, accuracy: 0.1)
    }
}
