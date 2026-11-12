import RealityKit
import KitchenCore
import simd
import CoreGraphics

/// Geometria wkładów szuflad: maty, stojaki na talerze, segregatory sztućców,
/// organizery kubków/szkłanek, blach, słoików, butelek i pokrywek.
///
/// Wszystko budowane z prostych brył w **metrach**, w układzie szuflady:
/// `x` wzdłuż szerokości (0 = środek), `y` od dna szuflady do góry,
/// `z` od frontu (−) do tyłu (+). Zero tekstur — kolory z katalogu.
public enum DrawerInsertBuilder {

    /// Buduje wkład dopasowany do światła szuflady.
    /// - Parameters:
    ///   - insert: wpis katalogu
    ///   - innerWidth/innerDepth: światło szuflady w mm
    ///   - available: wysokość użytkowa nad dnem w mm
    @MainActor
    public static func entity(insert: DrawerInsert,
                              innerWidth: Double,
                              innerDepth: Double,
                              available: Double) -> Entity? {
        let width = Float(insert.fittedWidth(innerWidth: innerWidth)) / 1000
        let depth = Float(insert.fittedDepth(innerDepth: innerDepth)) / 1000
        guard width > 0.05, depth > 0.05 else { return nil }

        let root = Entity()
        root.name = "insert-\(insert.id)"

        var plastic = PhysicallyBasedMaterial()
        plastic.baseColor = .init(tint: color(insert.colorHex))
        plastic.roughness = .init(floatLiteral: 0.55)
        plastic.metallic = .init(floatLiteral: 0.02)

        var felt = PhysicallyBasedMaterial()
        felt.baseColor = .init(tint: color("#4a4f57"))
        felt.roughness = .init(floatLiteral: 0.95)

        func box(_ w: Float, _ h: Float, _ d: Float, at position: SIMD3<Float>,
                 _ material: PhysicallyBasedMaterial, corner: Float = 0.002) -> ModelEntity {
            let mesh = MeshFactory.texturedBox(width: w, height: h, depth: d, tile: 1)
                ?? .generateBox(width: w, height: h, depth: d, cornerRadius: corner)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            return entity
        }

        let baseThickness: Float = 0.006

        switch insert.kind {
        case .mat:
            root.addChild(box(width * 0.98, 0.002, depth * 0.98,
                              at: [0, 0.001, 0], felt, corner: 0.001))

        case .plateRack:
            // dno + dwa rzędy kołków, między nimi talerze pionowo
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))
            let columns = max(3, insert.columns)
            let step = width / Float(columns)
            let plateRadius = min(depth * 0.42, 0.14)
            for index in 0..<columns {
                let x = -width / 2 + step * (Float(index) + 0.5)
                // talerz: cienki walec stojący pionowo (oś X)
                let plate = ModelEntity(
                    mesh: .generateCylinder(height: 0.008, radius: plateRadius),
                    materials: [plastic]
                )
                plate.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                plate.position = [x, Float(baseThickness) + plateRadius * 0.92, 0]
                root.addChild(plate)
            }

        case .cutleryTray:
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))
            addGrid(root: root, width: width, depth: depth, height: 0.045,
                    columns: max(2, insert.columns), rows: max(1, insert.rows),
                    thickness: 0.006, material: plastic, baseY: baseThickness)
            // sztućce: po kilka cienkich prętów w każdej przegródce
            let columns = max(2, insert.columns), rows = max(1, insert.rows)
            let cellW = width / Float(columns), cellD = depth / Float(rows)
            for row in 0..<rows {
                for col in 0..<columns {
                    let cx = -width / 2 + cellW * (Float(col) + 0.5)
                    let cz = -depth / 2 + cellD * (Float(row) + 0.5)
                    for k in -1...1 {
                        let prong = ModelEntity(
                            mesh: .generateBox(width: 0.008, height: 0.003, depth: cellD * 0.62),
                            materials: [plastic]
                        )
                        prong.position = [cx + Float(k) * 0.02, baseThickness + 0.002, cz]
                        root.addChild(prong)
                    }
                }
            }

        case .cupOrganizer, .glassOrganizer, .jarHolder:
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))
            let columns = max(2, insert.columns), rows = max(1, insert.rows)
            addGrid(root: root, width: width, depth: depth, height: Float(insert.height) / 1000 * 0.75,
                    columns: columns, rows: rows, thickness: 0.006, material: plastic, baseY: baseThickness)
            // naczynia w kieszeniach: kubki niższe, szklanki wyższe, słoiki pełniejsze
            let cellW = width / Float(columns), cellD = depth / Float(rows)
            let radius: Float = insert.kind == .jarHolder ? 0.042 : (insert.kind == .glassOrganizer ? 0.035 : 0.04)
            let cupHeight: Float = insert.kind == .glassOrganizer ? 0.1 : (insert.kind == .jarHolder ? 0.09 : 0.075)
            for row in 0..<rows {
                for col in 0..<columns {
                    let cx = -width / 2 + cellW * (Float(col) + 0.5)
                    let cz = -depth / 2 + cellD * (Float(row) + 0.5)
                    let cup = ModelEntity(
                        mesh: .generateCylinder(height: cupHeight, radius: min(radius, cellW * 0.3)),
                        materials: [plastic]
                    )
                    cup.position = [cx, baseThickness + cupHeight / 2, cz]
                    root.addChild(cup)
                }
            }

        case .bakingTrayHolder:
            // pionowe sloty: dwie ścianki + blachy wsunięte między nie
            let slots = max(3, insert.columns)
            let slotW = width / Float(slots)
            for index in 0..<slots {
                let x = -width / 2 + slotW * (Float(index) + 0.5)
                let tray = ModelEntity(
                    mesh: .generateBox(width: 0.006, height: min(Float(insert.height) / 1000 * 0.9, 0.4), depth: depth * 0.9),
                    materials: [plastic]
                )
                tray.position = [x, Float(insert.height) / 1000 * 0.45, 0]
                root.addChild(tray)
            }
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))

        case .bottleRack:
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))
            let count = max(2, insert.columns)
            let step = width / Float(count)
            let radius = min(0.042, step * 0.35)
            for index in 0..<count {
                let x = -width / 2 + step * (Float(index) + 0.5)
                // butelka leżąca: walec wzdłuż Z
                let bottle = ModelEntity(
                    mesh: .generateCylinder(height: depth * 0.82, radius: radius),
                    materials: [plastic]
                )
                bottle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                bottle.position = [x, Float(baseThickness) + radius, 0]
                root.addChild(bottle)
            }

        case .lidRack:
            root.addChild(box(width, baseThickness, depth, at: [0, baseThickness / 2, 0], plastic))
            let count = max(3, insert.columns)
            let step = width / Float(count)
            for index in 0..<count {
                let x = -width / 2 + step * (Float(index) + 0.5)
                let lid = ModelEntity(
                    mesh: .generateCylinder(height: 0.006, radius: min(0.09, step * 0.42)),
                    materials: [plastic]
                )
                lid.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                lid.position = [x, Float(baseThickness) + 0.06, 0]
                root.addChild(lid)
            }
        }

        return root.children.isEmpty ? nil : root
    }

    // MARK: - przegrody

    @MainActor
    private static func addGrid(root: Entity, width: Float, depth: Float, height: Float,
                                columns: Int, rows: Int, thickness: Float,
                                material: PhysicallyBasedMaterial, baseY: Float) {
        func wall(_ w: Float, _ h: Float, _ d: Float, at position: SIMD3<Float>) {
            let mesh = MeshFactory.texturedBox(width: w, height: h, depth: d, tile: 1)
                ?? .generateBox(width: w, height: h, depth: d, cornerRadius: 0.001)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            root.addChild(entity)
        }
        // przegrody poprzeczne (wzdłuż Z)
        for index in 1..<max(2, columns) {
            let x = -width / 2 + width / Float(columns) * Float(index)
            wall(thickness, height, depth, at: [x, baseY + height / 2, 0])
        }
        // przegrody wzdłużne (wzdłuż X)
        if rows > 1 {
            for index in 1..<rows {
                let z = -depth / 2 + depth / Float(rows) * Float(index)
                wall(width, height, thickness, at: [0, baseY + height / 2, z])
            }
        }
    }

    private static func color(_ hex: String) -> PlatformColor {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return .white }
        return PlatformColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                             green: CGFloat((value >> 8) & 0xFF) / 255,
                             blue: CGFloat(value & 0xFF) / 255,
                             alpha: 1)
    }
}
