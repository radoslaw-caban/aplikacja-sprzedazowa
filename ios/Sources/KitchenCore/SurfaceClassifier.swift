import Foundation
import simd

/// Klasyfikacja powierzchni skanu na podstawie geometrii.
///
/// Celowo NIE używamy `ARMeshGeometry.classification`:
///  - typ bufora klasyfikacji jest w ARKit niejednoznaczny w praktyce,
///  - klasyfikacja bywa pusta przy `sceneReconstruction = .mesh`,
///  - a to, czego naprawdę potrzebujemy — odróżnić podłogę, ścianę i sufit —
///    wynika wprost z geometrii.
///
/// KLUCZOWA DECYZJA: powierzchnie poziome rozdzielamy po WYSOKOŚCI, nie po
/// znaku normalnej. ARKit nie gwarantuje spójnego windingu trójkątów (zależy
/// od kierunku, z którego kamera zobaczyła powierzchnię), więc klasyfikacja po
/// `normal.y > 0` myliła podłogę z sufitem.
public enum SurfaceClassifier {

    /// Kolory palety skanu — czytelne na tle sceny i w pliku wynikowym.
    public static let floorColor = SIMD3<UInt8>(150, 115, 85)
    public static let wallColor = SIMD3<UInt8>(235, 235, 230)
    public static let ceilingColor = SIMD3<UInt8>(250, 250, 250)
    public static let otherColor = SIMD3<UInt8>(200, 200, 200)

    /// Powyżej tego |normal.y| trójkąt uznajemy za poziomy (0.75 ≈ 41°).
    public static let verticalNormalThreshold: Float = 0.75

    /// Klasyfikuje trójkąt na podstawie orientacji i wysokości.
    ///
    /// - Parameters:
    ///   - normal: normalna trójkąta (znak nieistotny dla powierzchni poziomych)
    ///   - centroidY: wysokość środka trójkąta w metrach (0 = poziom podłogi skanu)
    ///   - ceilingY: wykryta wysokość sufitu; `nil` = nieznana
    public static func color(
        normal: SIMD3<Float>,
        centroidY: Float,
        ceilingY: Float? = nil
    ) -> SIMD3<UInt8> {
        let ny = abs(normal.y)
        guard ny > verticalNormalThreshold else {
            // pionowa albo silnie pochyła — ściana lub mebel
            return wallColor
        }
        // pozioma: o wysokości decyduje Y, bo znak normalnej bywa odwrócony
        guard let top = ceilingY, top > 1.0 else {
            // bez znanej wysokości pomieszczenia nie da się rzetelnie
            // odróżnić sufitu — wysoko położone poziome traktujemy jako sufit
            return centroidY > 2.0 ? ceilingColor : floorColor
        }
        if centroidY >= top * 0.82 { return ceilingColor }
        if centroidY <= top * 0.22 { return floorColor }
        // pomiędzy: blat, parapet, górna płyta szafki — nie mylić z sufitem
        return floorColor
    }
}