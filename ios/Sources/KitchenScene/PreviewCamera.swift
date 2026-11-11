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

        // kamerę stawiamy na zewnątrz obrytu skanu, żeby widzieć całość,
        // ale nie dalej niż 2× jego najdłuższy bok
        let span = max(spanX, spanZ)
        let px = cx + spanX * 0.25
        let pz = cz + span * 0.95
        let target = SIMD3<Float>(cx, max(b.min.y + 0.9, b.min.y), cz)
        return PreviewCamera(position: [px, eyeY, pz], target: target)
    }

    /// Kadr z rzeczywistego obrysu geometrii: kamera na zewnątrz bryły,
    /// na wysokości oczu, patrzy w środek.
    public static func fit(center: SIMD3<Float>, extents: SIMD3<Float>) -> PreviewCamera {
        let radius = max(extents.x, max(extents.y, extents.z)) / 2
        let distance = radius * 2.2 + 0.6
        let eyeY = center.y + radius * 0.35
        return PreviewCamera(
            position: [center.x, eyeY, center.z + distance],
            target: center
        )
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
