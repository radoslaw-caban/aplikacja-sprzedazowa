// Diagnostyka detekcji pomieszczenia — uruchomienie: swift run RoomDiag
import Foundation
import simd
import KitchenCore

func makeCloud(width: Float, depth: Float, height: Float, seed: UInt64 = 7,
               bow: Float = 0, withWindow: Bool = false, withDoor: Bool = false,
               density: Float = 1200) -> [RoomModel.Sample] {
    var state = seed
    func rnd() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(state & 0xFFFFFF) / Float(0x1000000) - 0.5
    }
    var cloud: [RoomModel.Sample] = []
    let halfW = width / 2, halfD = depth / 2
    for _ in 0..<Int(width * depth * density) {
        cloud.append(.init(position: SIMD3((rnd() + 0.5) * width - halfW, 0,
                                           (rnd() + 0.5) * depth - halfD), sigma: 0.002))
    }
    func wall(axis: Int, pos: Float, from: Float, to: Float) {
        let len = to - from
        for _ in 0..<Int(len * height * density) {
            let t = from + (rnd() + 0.5) * len
            let y = (rnd() + 0.5) * height
            let u = (t - from) / Swift.max(0.001, len)
            let bowValue = bow * (1 - pow(2 * u - 1, 2))
            let p = axis == 0 ? SIMD3(pos + bowValue + rnd() * 0.002, y, t)
                              : SIMD3(t, y, pos + bowValue + rnd() * 0.002)
            if withDoor, axis == 1, pos < 0, t > -0.45, t < 0.45, y < 2.05 { continue }
            if withWindow, axis == 1, pos < 0, t > 0.5, t < 1.7, y > 0.9, y < 2.1 { continue }
            cloud.append(.init(position: p, sigma: 0.004))
        }
    }
    wall(axis: 1, pos: -halfD, from: -halfW, to: halfW)
    wall(axis: 1, pos: halfD, from: -halfW, to: halfW)
    wall(axis: 0, pos: -halfW, from: -halfD, to: halfD)
    wall(axis: 0, pos: halfW, from: -halfD, to: halfD)
    return cloud
}

func report(_ label: String, _ model: RoomModel.Result?) {
    guard let m = model else { print("\n\(label): NIL"); return }
    print("\n\(label)")
    print(String(format: "  narożniki %d, ściany %d, otwory %d",
                 m.corners.count, m.walls.count, m.openings.count))
    print(String(format: "  wysokość %.2f m, pole %.2f m²", m.height, m.area))
    let lengths = m.walls.map(\.length).sorted()
    print("  długości: " + lengths.map { String(format: "%.2f", $0) }.joined(separator: ", "))
    for p in m.corners { print(String(format: "    (%.3f, %.3f)", p.x, p.z)) }
}

let options = RoomModel.Options()

report("prostokąt 4×3", RoomModel.build(from: makeCloud(width: 4, depth: 3, height: 2.6)))

report("prostokąt 4,2×3,4 wygięta ściana 3 cm",
       RoomModel.build(from: makeCloud(width: 4.2, depth: 3.4, height: 2.6, bow: 0.03)))

report("prostokąt 5×4 z oknem i drzwiami",
       RoomModel.build(from: makeCloud(width: 5, depth: 4, height: 2.7,
                                       withWindow: true, withDoor: true)))
