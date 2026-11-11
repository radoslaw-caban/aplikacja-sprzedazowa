// Eksperyment: ile próbek realnie wpada do woksela i czy σ zgadza się z teorią.
// Uruchomienie: swift run KitchenChecks --sweep
import Foundation
import simd
import KitchenCore

/// Syntetyczna ściana prostopadła do osi kamery, z szumem Gaussa.
///
/// FIZYKA: ARKit podaje „distance from the plane of the camera" — odległość
/// wzdłuż osi Z, NIE długość promienia. Płaska ściana prostopadła do osi ma
/// więc identyczną głębokość na każdym pikselu.
func wallFrame(noise: Float, seed: UInt64, width: Int = 64, height: Int = 48,
               wallZ: Float = -2.0, confidence: UInt8 = 2) -> DepthFrame {
    var state = seed
    func rand() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let u1 = Float(state & 0xFFFFFF) / Float(0x1000000) + 1e-7
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let u2 = Float(state & 0xFFFFFF) / Float(0x1000000)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
    var depths = [Float](repeating: 0, count: width * height)
    let conf = [UInt8](repeating: confidence, count: width * height)
    let fx: Float = 200, fy: Float = 200
    let cx = Float(width) / 2, cy = Float(height) / 2
    for y in 0..<height {
        for x in 0..<width {
            depths[y * width + x] = (-wallZ) + rand() * noise
        }
    }
    return DepthFrame(
        depths: depths, confidence: conf, width: width, height: height,
        cameraTransform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1)),
        fx: fx, fy: fy, cx: cx, cy: cy, colors: nil
    )
}

func runSweep() {
    let pixelsPerFrame = 64 * 48
    print("Woksel a dokładność: ściana 2 m, szum 10 mm, wysoka ufność")
    print("Piksel mapy głębi = 1 cm poprzecznie (fx=200, d=2 m) → przy wokslu 8 mm")
    print("sąsiednie piksele trafiają do RÓŻNYCH wokseli, więc próbek/woksel jest mało.")
    print("")
    print("woksel | klatek | woksele | pkt/woksel |  σ zmierz. | σ teoria | błąd syst.")
    print("-------|--------|---------|------------|------------|----------|-----------")

    for cellMM in [4, 6, 8, 10, 12, 15, 20, 25] {
        for frames in [10, 40, 100] {
            var st = DepthFusionState(cell: Float(cellMM) / 1000)
            for i in 0..<frames {
                DepthFusion.add(frame: wallFrame(noise: 0.010, seed: UInt64(1000 + i * 7919)),
                                into: &st, minConfidence: 1)
            }
            guard let fused = DepthFusion.fused(from: st, minSamples: 2) else { continue }
            let zs = fused.positions.map { $0.z }
            let meanZ = zs.reduce(0, +) / Float(zs.count)
            let biasMM = abs(meanZ + 2.0) * 1000
            let perVoxel = Double(fused.samples) / Double(fused.count)
            // teoria: pojedynczy pomiar ma σ ≈ sqrt(σ_depth² + (d/fx)²)
            let singleSigma = DepthFusion.pointSigma(confidence: 2, depth: 2.0, fx: 200)
            let theory = singleSigma / Float(perVoxel).squareRoot()
            print(String(format: "%4d mm | %6d | %7d | %10.1f | %8.2f mm | %7.2f mm | %6.2f mm",
                         cellMM, frames, fused.count, perVoxel,
                         fused.medianSigma * 1000, theory * 1000, biasMM))
        }
        print("")
    }

    // Ile pikseli jednej klatki trafia do tego samego woksela?
    print("Gęstość próbek: piksele jednej klatki na woksel")
    for cellMM in [4, 6, 8, 10, 15, 20, 25] {
        var st = DepthFusionState(cell: Float(cellMM) / 1000)
        let n = DepthFusion.add(frame: wallFrame(noise: 0.010, seed: 42), into: &st, minConfidence: 1)
        let voxels = st.voxelCount
        print(String(format: "%4d mm: %5d pkt → %5d wokseli (%.2f pkt/woksel, pokrycie %.0f%% powierzchni)",
                     cellMM, n, voxels, Double(n) / Double(voxels),
                     100.0 * Double(voxels) / Double(pixelsPerFrame)))
    }
}
