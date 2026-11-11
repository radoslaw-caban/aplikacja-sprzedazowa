import Foundation
import simd

public extension DepthFrame {

    /// Punkty świata z mapy głębi (co `step` pikseli).
    ///
    /// Potrzebne do konturu planu na żywo: mapa głębi jest gęsta (256 × 192),
    /// a siatka ARKit ma komórki 5–10 cm, więc z siatki kontur pojawia się
    /// dopiero po minucie skanowania.
    func positions(step: Int = 2, maxDepth: Float = 8) -> [SIMD3<Float>] {
        let stride = Swift.max(1, step)
        guard width > 0, height > 0, depths.count >= width * height else { return [] }
        var out: [SIMD3<Float>] = []
        out.reserveCapacity((width / stride) * (height / stride))

        let rotation = simd_float3x3(
            SIMD3(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z),
            SIMD3(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
            SIMD3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        )
        let translation = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let depth = depths[y * width + x]
                if depth > 0.05, depth < maxDepth {
                    // piksel → promień w układzie kamery (oś −Z do przodu)
                    let px = (Float(x) - cx) / Swift.max(1e-3, fx)
                    let py = (Float(y) - cy) / Swift.max(1e-3, fy)
                    let camera = SIMD3<Float>(px * depth, py * depth, -depth)
                    out.append(rotation * camera + translation)
                }
                x += stride
            }
            y += stride
        }
        return out
    }
}
