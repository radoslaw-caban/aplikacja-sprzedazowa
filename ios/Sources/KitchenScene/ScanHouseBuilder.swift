import Foundation
import RealityKit
import KitchenCore

#if os(iOS)
import UIKit
public typealias ScanColor = UIColor
#else
import AppKit
public typealias ScanColor = NSColor
#endif

/// Dom zbudowany z planu wyprowadzonego ze SKANU (chmura punktów X9).
///
/// Wymiary i położenie ścian pochodzą z danych (`ScanPlan`), nie z generatora:
/// obrys, wysokość i odcinki ścian wewnętrznych są zmierzone w chmurze.
/// Ten builder tylko zamienia je na geometrię — grubości i wysokości
/// elementów (tynk, strop, okna) to jedyne wartości dobrane tutaj.
@MainActor
public enum ScanHouseBuilder {

    /// Grubość ściany zewnętrznej (m) — mierzona w chmurze była ~0,25.
    public static let exteriorThickness: Float = 0.25
    /// Grubość ścianki działowej (m).
    public static let partitionThickness: Float = 0.10
    /// Grubość stropu/podłogi (m).
    public static let slabThickness: Float = 0.22

    public static func entity(plan: ScanPlan, includeCeiling: Bool = true, ghostWalls: Bool = false) -> Entity {
        let root = Entity()
        root.name = "scan-house"

        let w = plan.width
        let d = plan.depth
        let h = plan.height

        // MARK: materiały
        var plaster = PhysicallyBasedMaterial()
        if ghostWalls {
            // tryb kontroli: ściany półprzezroczyste, żeby widzieć chmurę
            // przez elewację i ocenić dopasowanie punktów do płaszczyzn
            plaster.baseColor = .init(tint: ScanColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 0.18))
            plaster.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        } else {
            plaster.baseColor = .init(tint: ScanColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1))
        }
        plaster.roughness = .init(floatLiteral: 0.85)
        plaster.metallic = .init(floatLiteral: 0)

        var floorMaterial = PhysicallyBasedMaterial()
        if let wood = EnvironmentArt.photoTexture("wood_diff") {
            floorMaterial.baseColor = .init(tint: ScanColor(white: 0.95, alpha: 1), texture: .init(wood))
            floorMaterial.textureCoordinateTransform = .init(offset: .zero, scale: SIMD2<Float>(8, 8))
        } else {
            floorMaterial.baseColor = .init(tint: ScanColor(red: 0.62, green: 0.50, blue: 0.36, alpha: 1))
        }
        floorMaterial.roughness = .init(floatLiteral: 0.6)

        var slab = plaster
        slab.baseColor = .init(tint: ScanColor(white: 0.86, alpha: 1))

        // MARK: podłoga i strop
        let floorSlab = ModelEntity(
            mesh: .generateBox(width: w, height: slabThickness, depth: d),
            materials: [floorMaterial]
        )
        floorSlab.position = [0, -slabThickness / 2, 0]
        floorSlab.name = "scan-floor"
        root.addChild(floorSlab)

        let ceiling = ModelEntity(
            mesh: .generateBox(width: w, height: slabThickness, depth: d),
            materials: [slab]
        )
        ceiling.position = [0, h + slabThickness / 2, 0]
        ceiling.name = "scan-ceiling"
        if includeCeiling { root.addChild(ceiling) }

        // MARK: ściany zewnętrzne — CIĄGŁE, z otworami okien i drzwiami
        //
        // Wcześniej ściana była sklejana z „kawałków wokół okien" i zostawiała
        // przerwy (dziury w elewacji). Teraz idziemy wzdłuż ściany i pomiędzy
        // otworami stawiamy pełne segmenty — geometria nie może mieć luk.
        let sill: Float = 0.95
        let head: Float = 2.15
        let windowWidth: Float = 1.40
        let margin: Float = 0.90

        struct Opening {
            let start: Float
            let end: Float
            let bottom: Float
            let top: Float
            let isDoor: Bool
        }

        // szyby: przezroczyste, żeby otwór był oknem, a nie dziurą
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: ScanColor(red: 0.80, green: 0.88, blue: 0.92, alpha: 0.18))
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.20))
        glass.roughness = .init(floatLiteral: 0.05)
        glass.metallic = .init(floatLiteral: 0.10)

        var doorMaterial = PhysicallyBasedMaterial()
        doorMaterial.baseColor = .init(tint: ScanColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1))
        doorMaterial.roughness = .init(floatLiteral: 0.5)

        func windows(count: Int, length: Float) -> [Opening] {
            guard count > 0 else { return [] }
            let used = Float(count) * windowWidth
            let gap = (length - used) / Float(count + 1)
            var out: [Opening] = []
            for i in 0..<count {
                let start = -length / 2 + gap + Float(i) * (windowWidth + gap)
                out.append(Opening(start: start, end: start + windowWidth,
                                   bottom: sill, top: head, isDoor: false))
            }
            return out
        }

        func buildWall(center: SIMD3<Float>, length: Float, alongX: Bool, openings: [Opening]) {
            let thickness = exteriorThickness
            // ściana przedłużona o grubość — narożniki muszą się spotkać
            let fullLength = length + thickness

            func solid(from: Float, to: Float, bottom: Float, top: Float) {
                let width = to - from
                guard width > 0.02, top - bottom > 0.02 else { return }
                let box = ModelEntity(
                    mesh: .generateBox(width: alongX ? width : thickness,
                                       height: top - bottom,
                                       depth: alongX ? thickness : width),
                    materials: [plaster]
                )
                let shift = alongX
                    ? SIMD3<Float>((from + to) / 2, (bottom + top) / 2, 0)
                    : SIMD3<Float>(0, (bottom + top) / 2, (from + to) / 2)
                box.position = center + shift
                box.name = "scan-wall-exterior"
                root.addChild(box)
            }

            let sorted = openings.sorted { $0.start < $1.start }
            var cursor = -fullLength / 2
            for opening in sorted {
                if opening.start > cursor { solid(from: cursor, to: opening.start, bottom: 0, top: h) }
                if opening.bottom > 0.02 { solid(from: opening.start, to: opening.end, bottom: 0, top: opening.bottom) }
                if opening.top < h - 0.02 { solid(from: opening.start, to: opening.end, bottom: opening.top, top: h) }
                cursor = opening.end
            }
            if cursor < fullLength / 2 { solid(from: cursor, to: fullLength / 2, bottom: 0, top: h) }

            // wypełnienie otworów: szyba albo skrzydło drzwi
            for opening in sorted {
                let width = opening.end - opening.start
                let height = opening.top - opening.bottom
                let pane = ModelEntity(
                    mesh: .generateBox(width: alongX ? width : 0.06,
                                       height: height,
                                       depth: alongX ? 0.06 : width),
                    materials: [opening.isDoor ? doorMaterial : glass]
                )
                let shift = alongX
                    ? SIMD3<Float>((opening.start + opening.end) / 2, (opening.bottom + opening.top) / 2, 0)
                    : SIMD3<Float>(0, (opening.bottom + opening.top) / 2, (opening.start + opening.end) / 2)
                pane.position = center + shift
                pane.name = opening.isDoor ? "scan-door" : "scan-window"
                root.addChild(pane)
            }
        }

        // tył i boki: okna; przód: okna + drzwi wejściowe w osi
        buildWall(center: [0, 0, -d / 2 + exteriorThickness / 2], length: w, alongX: true,
                  openings: windows(count: 3, length: w))
        buildWall(center: [-w / 2 + exteriorThickness / 2, 0, 0], length: d, alongX: false,
                  openings: windows(count: 2, length: d))
        buildWall(center: [w / 2 - exteriorThickness / 2, 0, 0], length: d, alongX: false,
                  openings: windows(count: 2, length: d))

        var frontOpenings = windows(count: 2, length: w)
        frontOpenings.append(Opening(start: -0.55, end: 0.55, bottom: 0, top: 2.10, isDoor: true))
        buildWall(center: [0, 0, d / 2 - exteriorThickness / 2], length: w, alongX: true,
                  openings: frontOpenings)

        // MARK: zabudowa kuchenna z chmury
        //
        // Wykryte w skanie odcinki to fronty szafek (tam chmura ma setki
        // punktów na metr), a nie ściany działowe. Rysujemy je jako korpusy
        // 0,6 m głębokości i 0,9 m wysokości z blatem — wnętrze pokrywa się
        // wtedy z tym, co realnie zmierzono.
        var cabinetBody = PhysicallyBasedMaterial()
        cabinetBody.baseColor = .init(tint: ScanColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1))
        cabinetBody.roughness = .init(floatLiteral: 0.45)

        var worktopMaterial = PhysicallyBasedMaterial()
        worktopMaterial.baseColor = .init(tint: ScanColor(red: 0.22, green: 0.23, blue: 0.24, alpha: 1))
        worktopMaterial.roughness = .init(floatLiteral: 0.30)
        worktopMaterial.metallic = .init(floatLiteral: 0.15)

        let cabinetDepth: Float = 0.60
        let cabinetHeight: Float = 0.90

        for (index, run) in (plan.cabinets ?? []).enumerated() {
            let length = run.length
            guard length > 0.4 else { continue }
            let mid = (run.from + run.to) / 2

            let body = ModelEntity(
                mesh: .generateBox(width: run.axis == "x" ? cabinetDepth : length,
                                   height: cabinetHeight,
                                   depth: run.axis == "x" ? length : cabinetDepth,
                                   cornerRadius: 0.012),
                materials: [cabinetBody]
            )
            body.position = run.axis == "x"
                ? SIMD3<Float>(run.pos, cabinetHeight / 2, mid)
                : SIMD3<Float>(mid, cabinetHeight / 2, run.pos)
            body.name = "scan-cabinet-\(index)"
            root.addChild(body)

            let top = ModelEntity(
                mesh: .generateBox(width: run.axis == "x" ? cabinetDepth + 0.04 : length,
                                   height: 0.04,
                                   depth: run.axis == "x" ? length : cabinetDepth + 0.04),
                materials: [worktopMaterial]
            )
            top.position = run.axis == "x"
                ? SIMD3<Float>(run.pos, cabinetHeight + 0.02, mid)
                : SIMD3<Float>(mid, cabinetHeight + 0.02, run.pos)
            top.name = "scan-worktop-\(index)"
            root.addChild(top)
        }

        return root
    }
}
