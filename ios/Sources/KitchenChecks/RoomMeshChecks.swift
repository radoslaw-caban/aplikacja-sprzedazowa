// Testy siatki pomieszczenia (RoomMesh) — ściany z otworami, UV w metrach.
// Uruchomienie: swift run KitchenChecks  (sekcja „Siatka pomieszczenia")
import Foundation
import simd
import KitchenCore

func runRoomMeshChecks(_ r: Reporter) {
    print("\nSiatka pomieszczenia — ściany, otwory, UV, pole")

    // 1) pokój 5×4 m z oknem i drzwiami → siatka z prawdziwymi otworami
    do {
        let cloud = syntheticRoom(width: 5, depth: 4, height: 2.7,
                                  withWindow: true, withDoor: true)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("siatka: model powstał", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)

        r.check("siatka: 4 ściany + podłoga + sufit",
                mesh.surfaces.filter { $0.kind == .wall }.count == 4
                && mesh.surfaces.contains { $0.kind == .floor }
                && mesh.surfaces.contains { $0.kind == .ceiling },
                "ściany \(mesh.surfaces.filter { $0.kind == .wall }.count), "
                + "powierzchnie \(mesh.surfaces.count)")

        // pole ścian = obwód × wysokość − otwory
        let wallArea = mesh.surfaces.filter { $0.kind == .wall }.reduce(Float(0)) { $0 + $1.area }
        let perimeter = model.walls.reduce(Float(0)) { $0 + $1.length }
        let holesArea = model.openings.reduce(Float(0)) { $0 + $1.width * $1.height }
        let expected = perimeter * model.height - holesArea
        r.check("siatka: pole ścian = obwód×wys − otwory (±0,3 m²)",
                abs(wallArea - expected) < 0.3,
                String(format: "%.2f vs %.2f m² (otwory %.2f)", wallArea, expected, holesArea))

        // kluczowy test: otwór to DZIURA w geometrii, nie brak ściany.
        // Sprawdzamy, że w środku okna nie ma żadnego wierzchołka.
        if let window = model.openings.first(where: { $0.kind == .window }),
           let wall = model.walls.first(where: { $0.id == model.walls[max(0, window.wallIndex)].id }) {
            let dir = wall.direction
            let uCenter = window.offset + window.width / 2
            let floorY = model.corners.first?.yMin ?? 0
            let center = SIMD3(wall.start.x + dir.x * uCenter,
                               floorY + window.sill + window.height / 2,
                               wall.start.y + dir.y * uCenter)
            let inside = mesh.surfaces
                .filter { $0.kind == .wall }
                .flatMap(\.vertices)
                .contains { simd_length($0.position - center) < min(window.width, window.height) * 0.25 }
            r.check("siatka: w środku okna nie ma wierzchołków (dziura)", !inside)

            // ale wokół okna ściana JEST
            let around = mesh.surfaces.filter { $0.kind == .wall }
                .flatMap(\.vertices)
                .filter { simd_length($0.position - center) < 1.2 }
            r.check("siatka: wokół okna ściana istnieje", around.count >= 4,
                    "\(around.count) wierzchołków")
        }
    }

    // 2) UV w metrach — skala realna, nie rozciągnięta
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("UV: model powstał", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)
        guard let wall = mesh.surfaces.first(where: { $0.kind == .wall }) else {
            r.check("UV: jest ściana", false, "brak"); return
        }
        let us = wall.vertices.map(\.uv.x)
        let vs = wall.vertices.map(\.uv.y)
        let uSpan = (us.max() ?? 0) - (us.min() ?? 0)
        let vSpan = (vs.max() ?? 0) - (vs.min() ?? 0)
        // przy kaflu 1 m UV ma zakres równy wymiarowi w metrach
        r.check("UV: zakres w metrach = długość × wysokość ściany",
                abs(uSpan - wall.area / max(0.01, vSpan)) < 0.5,
                String(format: "u %.2f, v %.2f", uSpan, vSpan))
        r.check("UV: wysokość w UV ≈ 2,6 m (kafel 1 m)", abs(vSpan - 2.6) < 0.2,
                String(format: "%.2f", vSpan))
    }

    // 3) podłoga i sufit: pole = pole konturu, normalne w dobrym kierunku
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("podłoga: model powstał", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)

        if let floor = mesh.surfaces.first(where: { $0.kind == .floor }) {
            r.check("podłoga: pole ≈ 12 m²", abs(floor.area - 12) < 0.2,
                    String(format: "%.2f m²", floor.area))
            r.check("podłoga: normalna do góry", floor.vertices[0].normal.y > 0.9,
                    String(format: "ny = %.2f", floor.vertices[0].normal.y))
        } else { r.check("podłoga: istnieje", false, "brak") }

        if let ceiling = mesh.surfaces.first(where: { $0.kind == .ceiling }) {
            r.check("sufit: normalna w dół", ceiling.vertices[0].normal.y < -0.9,
                    String(format: "ny = %.2f", ceiling.vertices[0].normal.y))
            r.check("sufit: pole ≈ 12 m²", abs(ceiling.area - 12) < 0.2,
                    String(format: "%.2f m²", ceiling.area))
        } else { r.check("sufit: istnieje", false, "brak") }
    }

    // 4) bez otworów: jedna komórka na ścianę (siatka minimalna, nie tysiąc trójkątów)
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("minimalna siatka: model", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)
        let wallTris = mesh.surfaces.filter { $0.kind == .wall }.reduce(0) { $0 + $1.triangleCount }
        r.check("siatka: ściana bez otworu = 2 trójkąty × 4 ściany",
                wallTris == 8, "= \(wallTris)")
        r.check("siatka: rozmiar sensowny (nie tysiące trójkątów)",
                mesh.triangleCount < 100, "= \(mesh.triangleCount)")
    }

    // 5) kolory z chmury: mediana, odporna na odblaski
    do {
        var cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        // koloruj: podłoga brązowa, ściany jasne, kilka punktów-odblasków białych
        var colors: [SIMD3<UInt8>] = []
        colors.reserveCapacity(cloud.count)
        for (i, s) in cloud.enumerated() {
            let relY = s.position.y - (cloud.map(\.position.y).min() ?? 0)
            if relY < 0.05 {
                colors.append(SIMD3(120, 85, 60))          // podłoga
            } else if i % 500 == 0 {
                colors.append(SIMD3(255, 255, 255))        // odblask
            } else {
                colors.append(SIMD3(230, 228, 220))        // ściana
            }
        }
        let colored = PointCloud(positions: cloud.map(\.position), colors: colors)
        cloud = cloud.map { s in s }

        guard let model = RoomModel.build(from: cloud) else {
            r.check("kolory: model powstał", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)
        let result = RoomMesh.averageColors(mesh: mesh, cloud: colored)

        r.check("kolory: po jednym na powierzchnię", result.count == mesh.surfaces.count,
                "\(result.count) / \(mesh.surfaces.count)")

        // ściana ma być jasna (≈0,9), a nie biała (1,0) mimo odblasków
        if let wallColor = result.first(where: { $0.rgb.x > 0.7 }) {
            r.check("kolory: ściana jasna, ale nie przepalona odblaskami",
                    wallColor.rgb.x < 0.99 && wallColor.rgb.x > 0.6,
                    String(format: "r = %.2f", wallColor.rgb.x))
        } else {
            r.check("kolory: znaleziono jasną powierzchnię", false, "brak")
        }

        // podłoga ma być ciemniejsza od ściany
        if let floorColor = result.min(by: { $0.rgb.x < $1.rgb.x }) {
            r.check("kolory: podłoga ciemniejsza od ściany", floorColor.rgb.x < 0.75,
                    String(format: "r = %.2f", floorColor.rgb.x))
        }
    }

    // 6) chmura bez kolorów — neutralne, bez wyjątku
    do {
        let cloud = syntheticRoom(width: 4, depth: 3, height: 2.6)
        guard let model = RoomModel.build(from: cloud) else {
            r.check("bez kolorów: model", false, "nil"); return
        }
        let mesh = RoomMesh.build(model: model)
        let bare = PointCloud(positions: cloud.map(\.position))
        let result = RoomMesh.averageColors(mesh: mesh, cloud: bare)
        r.check("bez kolorów: neutralny szary, zero próbek",
                result.allSatisfy { $0.samples == 0 && abs($0.rgb.x - 0.8) < 0.01 },
                "\(result.count) powierzchni")
    }
}
