import Foundation
import simd

/// Zestawienie materiałów z planu — to, co trzeba zamówić.
///
/// Liczone z obrysu i wysokości, bez zgadywania: podłoga z pola, farba
/// z powierzchni ścian (minus otwory), listwy z obwodu minus drzwi.
public struct Takeoff: Sendable, Equatable {

    public var floorAreaM2: Double
    public var ceilingAreaM2: Double
    public var wallAreaM2: Double          // bez otworów
    public var wallAreaWithOpeningsM2: Double
    public var skirtingMeters: Double
    public var perimeterMeters: Double
    public var paintLiters: Double
    public var primerLiters: Double
    public var windowCount: Int
    public var doorCount: Int
    public var windowAreaM2: Double
    public var doorAreaM2: Double
    /// Propozycja wymiarów stolarki do zamówienia.
    public var windows: [String]
    public var doors: [String]

    /// - Parameters:
    ///   - coats: ile warstw farby (producent podaje wydajność na jedną warstwę)
    ///   - coverage: m² z litra na warstwę (typowa farba akrylowa 10–12)
    public static func compute(
        plan: FloorPlan,
        windowCount: Int = 2,
        doorCount: Int = 1,
        windowSize: SIMD2<Double> = SIMD2(1200, 1400),
        doorSize: SIMD2<Double> = SIMD2(900, 2100),
        coats: Int = 2,
        coverage: Double = 11
    ) -> Takeoff {
        let floorMM2 = plan.closed ? plan.area : 0
        let floorM2 = floorMM2 / 1_000_000

        let perimeter = plan.perimeter / 1000
        let height = plan.height / 1000
        let grossWall = perimeter * height

        // otwory liczymy raz, nie na ścianę
        let openings = Double(windowCount) * (windowSize.x * windowSize.y) / 1_000_000
            + Double(doorCount) * (doorSize.x * doorSize.y) / 1_000_000
        let netWall = max(0, grossWall - openings)

        let paint = netWall * Double(max(1, coats)) / max(0.1, coverage)
        // listwy: obwód minus szerokości drzwi
        let skirting = max(0, perimeter - Double(doorCount) * (doorSize.x / 1000))

        let windows = (0..<windowCount).map { index in
            String(format: "Okno %d: %d × %d mm (PVC, 3 szyby)", index + 1,
                   Int(windowSize.x), Int(windowSize.y))
        }
        let doors = (0..<doorCount).map { index in
            String(format: "Drzwi %d: %d × %d mm (skrzydło + ościeżnica)", index + 1,
                   Int(doorSize.x), Int(doorSize.y))
        }

        return Takeoff(
            floorAreaM2: floorM2,
            ceilingAreaM2: floorM2,
            wallAreaM2: netWall,
            wallAreaWithOpeningsM2: grossWall,
            skirtingMeters: skirting,
            perimeterMeters: perimeter,
            paintLiters: paint,
            primerLiters: netWall / max(0.1, coverage),
            windowCount: windowCount,
            doorCount: doorCount,
            windowAreaM2: Double(windowCount) * (windowSize.x * windowSize.y) / 1_000_000,
            doorAreaM2: Double(doorCount) * (doorSize.x * doorSize.y) / 1_000_000,
            windows: windows,
            doors: doors
        )
    }
}
