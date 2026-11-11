import Foundation
import simd

/// Materializacja stref: ściana planu + odpowiedzi → rzeczywiste szafki w mm.
/// Geometria ściany jest liczona tak samo jak w `WallFill` (front do wnętrza).
public enum Zones {

    public static func makeZone(kind: ZoneKind, wallIndex: Int) -> Zone {
        Zone(kind: kind, wallIndex: wallIndex,
             answers: ZoneLibrary.defaults(kind), name: ZoneLibrary.spec(kind).label)
    }

    public static func context(_ plan: FloorPlan, wallIndex: Int) -> ZoneContext? {
        guard let w = plan.wall(wallIndex) else { return nil }
        let b = plan.bounds
        return ZoneContext(
            wallLength: w.length,
            wallHeight: max(2000, plan.height),
            roomWidth: max(1000, b.max.x - b.min.x),
            roomDepth: max(1000, b.max.y - b.min.y)
        )
    }

    public static func zonePlan(for zone: Zone, in plan: FloorPlan) -> ZonePlan {
        guard let ctx = context(plan, wallIndex: zone.wallIndex) else {
            return ZonePlan(warnings: ["Ściana \(zone.wallIndex + 1) nie istnieje w planie."])
        }
        return ZonePlanner.plan(zone.kind, zone.typedAnswers, ctx)
    }

    /// Szafki jednej strefy w układzie świata (mm).
    public static func cabinets(for zone: Zone, plan: FloorPlan) -> [Cabinet] {
        guard let wall = plan.wall(zone.wallIndex), wall.length > 100 else { return [] }
        let zonePlan = zonePlan(for: zone, in: plan)
        let delta = wall.b - wall.a
        let along = delta / wall.length
        let inward = SIMD2<Double>(-along.y, along.x)
        let rad = atan2(inward.x, inward.y)
        var rotation = rad * 180 / .pi
        if rotation < 0 { rotation += 360 }
        let island = zone.kind == .kitchenIsland
        let extra: Double = island ? 1100 : 0

        return zonePlan.parts.map { part in
            let t = zonePlan.start + part.at + part.width / 2
            let point = wall.a + along * t + inward * (part.depth / 2 + extra)
            let height: Double = part.type == .base ? part.plinth + part.height : part.height
            let cab = Cabinet(
                name: part.label,
                type: part.type,
                width: part.width,
                height: height,
                depth: part.depth,
                plinth: part.type == .wall ? 0 : part.plinth,
                x: point.x,
                z: point.y,
                rotation: rotation,
                mountHeight: part.mountHeight,
                elements: elements(for: part, height: height),
                color: color(for: part),
                zoneID: zone.id,
                zoneRole: part.feature ?? part.role,
                appliances: part.appliances.isEmpty ? nil : part.appliances,
                slidingPanels: part.slidingPanels,
                worktopDepth: part.worktopDepth,
                worktopShift: part.worktopShift
            )
            // front rysuje Generator: szuflady z elementów, skrzydło gdy brak szuflad;
            // AGD (piekarnik, lodówka, zmywarka) ma własny panel w Generator.appliances
            return cab
        }
    }

    private static func color(for part: ZonePart) -> String {
        switch part.type {
        case .wall: return "#d8d2c8"
        case .tall: return "#cfc7ba"
        case .base: return "#c8bca9"
        case .panel: return "#c8bca9"
        }
    }

    private static func elements(for part: ZonePart, height: Double) -> [CabinetElement] {
        var out: [CabinetElement] = []
        let bodyH = max(200, height - part.plinth)
        if !part.drawers.isEmpty {
            let sum = part.drawers.reduce(0, +)
            var y: Double = 0
            for h in part.drawers {
                let hh = (h / max(1, sum)) * bodyH
                let system: DrawerSystem = hh > 150 ? .k : hh > 100 ? .m : .n
                out.append(CabinetElement(kind: .drawer, y: y, height: hh, drawer: system))
                y += hh
            }
        }
        switch part.interior {
        case .shelf:
            out.append(CabinetElement(kind: .shelf, y: bodyH * (part.type == .wall ? 0.5 : 0.55),
                                      height: Standards.panel))
        case .pantry:
            let n = max(2, Int(bodyH / 350))
            for k in 1...n {
                out.append(CabinetElement(kind: .shelf, y: bodyH * Double(k) / Double(n + 1),
                                          height: Standards.panel))
            }
        case .glass:
            for f in [0.28, 0.5, 0.72] {
                out.append(CabinetElement(kind: .shelf, y: bodyH * f, height: Standards.panel))
            }
        case .rail:
            out.append(CabinetElement(kind: .shelf, y: bodyH * 0.72, height: Standards.panel))
            out.append(CabinetElement(kind: .shelf, y: bodyH * 0.38, height: Standards.panel))
        case .none:
            break
        }
        return out
    }

    /// Przebudowa wszystkich stref: szafki stref odtwarzane od zera,
    /// szafki ręczne (bez zoneID / osierocone) zostają nietknięte.
    public static func rebuilt(_ existing: [Cabinet], zones: [Zone], plan: FloorPlan) -> [Cabinet] {
        // ręczne = bez zoneID; szafki usuniętych stref też znikają (sieroty)
        let manual = existing.filter { $0.zoneID == nil }
        let generated = zones.flatMap { cabinets(for: $0, plan: plan) }
        return manual + generated
    }

    /// Szafka odpowiedzialna za element (do kadrowania / inspekcji).
    public static func featureCabinet(_ cabinets: [Cabinet], zone: Zone, feature: String?) -> Cabinet? {
        let own = cabinets.filter { $0.zoneID == zone.id }
        guard let feature, feature != "zone" else { return own.first }
        return own.first { $0.zoneRole == feature } ?? own.first
    }

    public struct Summary: Sendable {
        public var base: Int
        public var tall: Int
        public var wall: Int
        public var fronts: Int
        public var appliances: Int
        public var length: Double
    }

    public static func summary(_ cabinets: [Cabinet], zone: Zone) -> Summary {
        let own = cabinets.filter { $0.zoneID == zone.id }
        return Summary(
            base: own.filter { $0.type == .base }.count,
            tall: own.filter { $0.type == .tall }.count,
            wall: own.filter { $0.type == .wall }.count,
            fronts: own.reduce(0) { $0 + ($1.elements.contains { $0.kind == .drawer } ? $1.elements.filter { $0.kind == .drawer }.count : 1) },
            appliances: own.reduce(0) { $0 + ($1.appliances?.count ?? 0) },
            length: own.filter { $0.type != .wall }.reduce(0) { $0 + $1.width }
        )
    }
}
