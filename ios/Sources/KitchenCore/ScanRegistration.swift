import Foundation
import simd

/// Rejestracja skanu po punktach: użytkownik wskazuje dwa punkty na jednej ścianie,
/// podaje jej realną długość (opcjonalnie) i wyrównuje ją do osi pokoju.
public extension ScanTransform {

    enum Axis: String, Sendable {
        case x   // ściana biegnie wzdłuż X pokoju
        case z   // ściana biegnie wzdłuż Z pokoju
    }

    /// Nowa transformacja: obrót o `deltaDegrees` wokół Y, skala × `scaleFactor`,
    /// przy czym punkt `anchor` (we współrzędnych chmury) zostaje w miejscu.
    func rotated(by deltaDegrees: Double, scaleFactor: Double, keeping anchor: SIMD3<Float>) -> ScanTransform {
        let newRotation = rotationDeg + deltaDegrees
        let newScale = scale * scaleFactor

        // pozycja punktu zaczepienia pod nową transformacją (bez przesunięcia)
        let a = newRotation * .pi / 180
        let c = cos(a), s = sin(a)
        let x = Double(anchor.x) * newScale
        let z = Double(anchor.z) * newScale
        let rx = x * c + z * s
        let rz = -x * s + z * c
        let ry = Double(anchor.y) * newScale

        // przesunięcie tak, żeby punkt zaczepienia został tam, gdzie był
        let current = apply(anchor)
        return ScanTransform(
            scale: newScale,
            rotationDeg: newRotation,
            offset: SIMD3(
                Double(current.x) - rx,
                Double(current.y) - ry,
                Double(current.z) - rz
            )
        )
    }

    /// Wyrównanie ściany: dwa wskazane punkty (współrzędne chmury w metrach)
    /// traktujemy jako kierunek ściany w świecie; liczymy obrót, który ustawia
    /// ten kierunek wzdłuż osi X lub Z pokoju.
    func aligningWall(
        from p1: SIMD3<Float>,
        to p2: SIMD3<Float>,
        axis: Axis,
        realDistanceMeters: Double? = nil
    ) -> ScanTransform {
        let w1 = apply(p1)
        let w2 = apply(p2)
        let dx = Double(w2.x - w1.x)
        let dz = Double(w2.z - w1.z)
        guard abs(dx) > 1e-6 || abs(dz) > 1e-6 else { return self }

        // aktualny kąt kierunku w rzucie
        let currentAngle = atan2(dz, dx)
        let targetAngle: Double = axis == .x ? 0 : (dz >= 0 ? .pi / 2 : -.pi / 2)
        // apply() obraca w stronę przeciwną do kąta standardowego, stąd minus
        var delta = -(targetAngle - currentAngle) * 180 / .pi
        // normalizacja do [-180, 180]
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }

        // skala: realna długość / zmierzona (jeśli podana)
        var factor = 1.0
        if let real = realDistanceMeters {
            let measured = (dx * dx + dz * dz).squareRoot()
            if measured > 1e-6, real > 0 { factor = real / measured }
        }

        return rotated(by: delta, scaleFactor: factor, keeping: p1)
    }

    /// Odległość między dwoma punktami chmury po transformacji (metry).
    func distance(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Double {
        let a = apply(p1), b = apply(p2)
        let d = b - a
        return Double((d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
    }
}
