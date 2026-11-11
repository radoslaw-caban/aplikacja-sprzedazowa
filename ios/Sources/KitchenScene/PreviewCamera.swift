import Foundation
import KitchenCore
import simd

/// Parametry kamery podglądu — jedno źródło prawdy dla renderu i dla klikania w skan.
public struct PreviewCamera: Sendable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var verticalFOVDegrees: Float

    public init(position: SIMD3<Float>, target: SIMD3<Float>, verticalFOVDegrees: Float = 55) {
        self.position = position
        self.target = target
        self.verticalFOVDegrees = verticalFOVDegrees
    }

    /// Kadr: jeśli jest skan, kadrujemy na jego obrys; inaczej na pokój.
    /// Kamera zawsze zostaje wewnątrz pomieszczenia (inaczej widok zasłania ściana).
    public static func make(
        room: Room,
        scanBounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil
    ) -> PreviewCamera {
        let roomHalfX = Float(room.width / 2000) - 0.45
        let roomHalfZ = Float(room.depth / 2000) - 0.45
        let roomHeight = Float(room.height / 1000)

        guard let b = scanBounds else {
            return PreviewCamera(
                position: [0, 1.65, Float(room.depth / 2000) * 0.62],
                target: [0, 1.0, -Float(room.depth / 2000) * 0.6]
            )
        }

        let cx = (b.min.x + b.max.x) / 2
        let cz = (b.min.z + b.max.z) / 2
        let spanX = b.max.x - b.min.x
        let spanZ = b.max.z - b.min.z
        let eyeY = min(roomHeight - 0.3, max(1.6, b.min.y + (b.max.y - b.min.y) * 0.55))

        let px = max(-roomHalfX, min(roomHalfX, cx + spanX * 0.30))
        let pz = max(-roomHalfZ, min(roomHalfZ, cz + spanZ * 0.55))
        let target = SIMD3<Float>(cx, max(b.min.y + 0.9, b.min.y), cz)
        return PreviewCamera(position: [px, eyeY, pz], target: target)
    }

    /// Promień z kamery przez punkt ekranu (0…1) — do trafiania w chmurę.
    public func ray(normalizedPoint p: CGPoint, aspect: Float) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        VoxelGrid.ray(
            cameraPosition: position,
            lookAt: target,
            verticalFOVDegrees: verticalFOVDegrees,
            aspect: aspect,
            normalizedPoint: p
        )
    }
}
