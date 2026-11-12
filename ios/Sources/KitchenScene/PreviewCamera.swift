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

    /// Kadr dopasowany do bryły zabudowy (lub strefy): kamera staje w pokoju
    /// naprzeciw mebla, w odległości, przy której cały mebel mieści się w kadrze.
    ///
    /// Wcześniej kamera celowała w środek wszystkich szafek, więc przy zabudowie
    /// na jednej ścianie stała bokiem albo poza pokojem.
    public static func fitting(center: SIMD3<Float>, extents: SIMD3<Float>,
                               room: Room, verticalFOVDegrees: Float = 47) -> PreviewCamera {
        let halfW = Float(room.width / 1000) / 2
        let halfD = Float(room.depth / 1000) / 2
        let roomH = Float(room.height / 1000)

        // im większa zabudowa, tym dalej trzeba stanąć (FOV pionowy → poziomy z proporcji 4:3)
        let fovH = verticalFOVDegrees * .pi / 180 * 1.25
        let needX = (extents.x / 2) / max(0.1, tan(fovH / 2))
        let needY = (extents.y / 2) / max(0.1, tan(verticalFOVDegrees * .pi / 180 / 2))
        // NIE wciskamy kamery na siłę do pokoju: przy długim biegu trzeba stanąć
        // dalej, a ściany i tak stają się przezroczyste, gdy zasłaniają widok.
        let distance = max(2.2, max(needX, needY) * 1.15 + 0.6)

        // stoimy „naprzeciw" zabudowy: od środka pokoju w stronę jego wnętrza,
        // lekko z boku, żeby widać było także boki
        var eye = SIMD3<Float>(center.x * 0.25, min(roomH - 0.25, max(1.55, center.y + 0.3)),
                               center.z * 0.25)
        eye.x = max(-halfW * 1.2, min(halfW * 1.2, eye.x))
        eye.z = max(-halfD * 1.2, min(halfD * 1.2, eye.z))
        // odsuwamy kamerę od mebla wzdłuż osi Z (do środka pokoju)
        let dir = SIMD3<Float>(center.x, 0, center.z)
        let dirLen = max(0.001, simd_length(SIMD2(dir.x, dir.z)))
        let inward = SIMD3<Float>(-dir.x / dirLen, 0, -dir.z / dirLen)
        var pos = eye + inward * distance
        // lekko z boku, żeby widać było także boki zabudowy (kadr 3/4)
        let side = SIMD3<Float>(-inward.z, 0, inward.x)
        pos += side * (distance * 0.18)
        let limit = max(halfW, halfD) * 4
        pos.x = max(-limit, min(limit, pos.x))
        pos.z = max(-limit, min(limit, pos.z))
        pos.y = eye.y

        let target = SIMD3<Float>(center.x, max(0.55, center.y), center.z)
        return PreviewCamera(position: pos, target: target)
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
