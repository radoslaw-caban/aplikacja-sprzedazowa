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

    /// Kadr zewnętrzny: dom z podjazdem i otoczeniem, kamera 3/4 z góry.
    public static func exterior(room: Room) -> PreviewCamera {
        let w = Float(room.width / 1000)
        let d = Float(room.depth / 1000)
        let h = Float(room.height / 1000)
        let distance = max(w, d) * 2.6 + 12
        // Debug: KITCHEN_CAMERA=back pokazuje kadr od strony lasu
        // (weryfikacja skał i runa leśnego, których od frontu nie widać).
        if ProcessInfo.processInfo.environment["KITCHEN_CAMERA"] == "back" {
            return PreviewCamera(
                position: [distance * 0.55, h + 9, -(d / 2 + distance)],
                target: [0, h * 0.45, 0]
            )
        }
        return PreviewCamera(
            position: [-distance * 0.55, h + 9, d / 2 + distance],
            target: [0, h * 0.45, 0]
        )
    }

    /// Kadr z rzeczywistego obrysu geometrii: kamera cofnięta od zabudowy,
    /// na wysokości oczu, patrzy lekko z boku — jak zdjęcie kuchni, nie jak
    /// model w środku bryły.
    ///
    /// POPRAWKA: wcześniej odległość liczyła się tylko z promienia bryły
    /// (dla dwóch szafek ~1 m), więc kamera stała 2 m od frontu i zasłaniała
    /// ją rama szafki. Teraz jest dolna granica 3,4 m i minimalna wysokość
    /// oczu 1,45 m — kadr obejmuje blat i kawałek ściany.
    public static func fit(center: SIMD3<Float>, extents: SIMD3<Float>) -> PreviewCamera {
        let radius = max(extents.x, max(extents.y, extents.z)) / 2
        let distance = min(7.5, max(3.4, radius * 4.2 + 1.0))
        let eyeY = max(1.45, center.y + extents.y * 0.9)
        let side = distance * 0.28
        return PreviewCamera(
            position: [center.x + side, eyeY, center.z + distance],
            target: [center.x, max(0.55, center.y), center.z]
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
