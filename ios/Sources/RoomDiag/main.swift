// Diagnostyka detekcji pomieszczenia — uruchomienie: swift run RoomDiag
// Wypisuje, ile linii ścian i narożników znajduje algorytm na syntetycznym
// pomieszczeniu, żeby zlokalizować, na którym etapie detekcja się gubi.
import Foundation
import simd
import KitchenCore

func diagRoom(width: Float, depth: Float, height: Float, label: String) {
    var state: UInt64 = 7
    func rnd() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xFFFFFF) / Float(0x1000000) - 0.5
    }
    var cloud: [RoomModel.Sample] = []
    let halfW = width / 2, halfD = depth / 2
    for _ in 0..<Int(width * depth * 1200) {
        cloud.append(.init(position: SIMD3((rnd() + 0.5) * width - halfW, 0,
                                           (rnd() + 0.5) * depth - halfD), sigma: 0.002))
    }
    func wall(axis: Int, pos: Float, from: Float, to: Float) {
        let len = to - from
        for _ in 0..<Int(len * height * 1200) {
            let t = from + (rnd() + 0.5) * len
            let y = (rnd() + 0.5) * height
            let p = axis == 0 ? SIMD3(pos + rnd() * 0.002, y, t)
                              : SIMD3(t, y, pos + rnd() * 0.002)
            cloud.append(.init(position: p, sigma: 0.004))
        }
    }
    wall(axis: 1, pos: -halfD, from: -halfW, to: halfW)
    wall(axis: 1, pos: halfD, from: -halfW, to: halfW)
    wall(axis: 0, pos: -halfW, from: -halfD, to: halfD)
    wall(axis: 0, pos: halfW, from: -halfD, to: halfD)

    print("\n=== \(label): \(width)×\(depth)×\(height) m, \(cloud.count) pkt")

    guard let floorY = RoomModel.detectFloor(samples: cloud) else {
        print("  detectFloor: nil"); return
    }
    print(String(format: "  podłoga y = %.3f m", floorY))
    let ceilingY = RoomModel.detectCeiling(samples: cloud, floorY: floorY)
    print(String(format: "  sufit y = %@", ceilingY.map { String(format: "%.3f m", $0) } ?? "nil"))

    let options = RoomModel.Options()
    let band = cloud.filter {
        $0.position.y >= floorY - 0.03 && $0.position.y <= floorY + options.floorBand
    }
    print("  pas przy podłodze: \(band.count) pkt")
    let plan = band.map { SIMD2($0.position.x, $0.position.z) }

    let lines = RoomModel.detectWallLines(points: plan, options: options)
    print("  linie ścian: \(lines.count)")
    for l in lines {
        print(String(format: "    kąt %6.1f°  offset %7.3f  zakres %6.2f…%6.2f  wsparcie %d",
                     l.angleDeg, l.offset, l.tMin, l.tMax, l.support))
    }
    let merged = RoomModel.mergeLines(lines, options: options)
    print("  po scaleniu: \(merged.count)")
    for l in merged {
        print(String(format: "    kąt %6.1f°  offset %7.3f  zakres %6.2f…%6.2f  wsparcie %d",
                     l.angleDeg, l.offset, l.tMin, l.tMax, l.support))
    }
    if ProcessInfo.processInfo.environment["ROOM_DEBUG"] != nil {
        if let c = RoomModel.intersect(lines: merged, options: options) {
            print("  przecięcia: \(c.count)")
            for q in c { print(String(format: "    (%.3f, %.3f)", q.x, q.y)) }
            if let o = RoomModel.orderContour(corners: c, lines: merged) {
                print("  cykl: \(o.count)")
            } else {
                print("  cykl: nil")
            }
        } else {
            print("  przecięcia: nil")
        }
    }
    if let outline = RoomModel.roomOutline(points: plan, options: options) {
        print("  kontur: \(outline.count) narożników")
        for p in outline { print(String(format: "    (%.3f, %.3f)", p.x, p.y)) }
    } else {
        print("  kontur: nil")
    }
}

diagRoom(width: 4, depth: 3, height: 2.6, label: "prostokąt")
