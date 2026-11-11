import Foundation
import simd

/// Gotowe plany domów do wyboru — punkt startowy, który się koryguje,
/// a nie rysuje od zera.
public struct PlanPreset: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public var name: String
    public var subtitle: String
    public var width: Double      // mm
    public var depth: Double      // mm
    public var height: Double
    /// dodatkowe punkty (dla planów typu L) — puste = prostokąt
    public var points: [SIMD2<Double>]

    public init(name: String, subtitle: String, width: Double, depth: Double, height: Double = 2600, points: [SIMD2<Double>] = []) {
        self.name = name
        self.subtitle = subtitle
        self.width = width
        self.depth = depth
        self.height = height
        self.points = points
    }

    public var areaM2: Double { width * depth / 1_000_000 }

    public func plan() -> FloorPlan {
        if points.isEmpty {
            return FloorPlan.rectangle(width: width, depth: depth, height: height)
        }
        return FloorPlan(points: points, closed: true, height: height)
    }
}

public enum PlanPresets {

    public static let all: [PlanPreset] = [
        PlanPreset(name: "Kuchnia 3,0 × 3,6", subtitle: "standard w bloku · 10,8 m²", width: 3000, depth: 3600),
        PlanPreset(name: "Kuchnia z jadalnią", subtitle: "otwarta · 18,2 m²", width: 4200, depth: 4340),
        PlanPreset(name: "Salon 5,2 × 6,4", subtitle: "dom jednorodzinny · 33,3 m²", width: 5200, depth: 6400),
        PlanPreset(name: "Mieszkanie 2 pokoje", subtitle: "48,6 m² · prostokąt", width: 6900, depth: 7050),
        PlanPreset(name: "Dom 120 m²", subtitle: "parter · 12,0 × 10,0 m", width: 12000, depth: 10000, height: 2900),
        PlanPreset(name: "Willa z tarasem", subtitle: "12,8 × 9,6 m · wys. 2,9 m", width: 12800, depth: 9600, height: 2900),
        PlanPreset(
            name: "Dom w kształcie L",
            subtitle: "11,0 × 9,0 m z wycięciem",
            width: 11000,
            depth: 9000,
            height: 2700,
            points: [
                SIMD2(-5500, -4500), SIMD2(5500, -4500), SIMD2(5500, -500),
                SIMD2(1500, -500), SIMD2(1500, 4500), SIMD2(-5500, 4500),
            ]
        ),
    ]
}
