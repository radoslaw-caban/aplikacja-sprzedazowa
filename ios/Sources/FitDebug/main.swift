import Foundation
import KitchenCore

func syntheticRoom(angleDeg: Double = 30, translate: SIMD3<Float> = SIMD3(5, 1.2, -3)) -> [SIMD3<Float>] {
    var pts: [SIMD3<Float>] = []
    let a = angleDeg * .pi / 180
    func rot(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let x = p.x * Float(cos(a)) + p.z * Float(sin(a))
        let z = -p.x * Float(sin(a)) + p.z * Float(cos(a))
        return SIMD3(x, p.y, z) + translate
    }
    var seed: UInt64 = 99
    func rnd() -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Float((seed >> 33) & 0xFFFF) / Float(0xFFFF)
    }
    for _ in 0..<20_000 { pts.append(rot(SIMD3(rnd() * 5, 0, rnd() * 4))) }          // podłoga
    for _ in 0..<12_000 { pts.append(rot(SIMD3(0, rnd() * 2.6, rnd() * 4))) }         // ściana x=0
    for _ in 0..<12_000 { pts.append(rot(SIMD3(rnd() * 5, rnd() * 2.6, 0))) }         // ściana z=0
    return pts
}

let pts = syntheticRoom()
let r = ScanFit.detect(points: pts)
print(String(format: "detekcja: kąt %.1f°, podłoga %.2f m, pokrycie %.2f, siła ścian %.1f",
             r.wallAngleDeg, r.floorY, r.floorCoverage, r.wallStrength))
if let pca = ScanFit.wallAnglePCA(points: pts, floorY: r.floorY) {
    print(String(format: "PCA kąt: %.1f°", pca))
}

let room = Room(width: 5000, depth: 4000, height: 2600)
let t = ScanFit.align(points: pts, result: r, room: room, currentScale: 1)
print(String(format: "transformacja: obrót %.1f°, offset (%.2f, %.2f, %.2f), skala %.2f",
             t.rotationDeg, t.offset.x, t.offset.y, t.offset.z, t.scale))

// gdzie wypadają ściany po wyrównaniu
var wallXs: [Float] = [], wallZs: [Float] = [], ys: [Float] = []
for p in pts {
    let q = t.apply(p)
    ys.append(q.y)
    if p.y - r.floorY > 0.3 { wallXs.append(q.x); wallZs.append(q.z) }
}
func peaks(_ v: [Float], bin: Float = 0.05, top: Int = 4) -> [(Float, Int)] {
    var lo = v.min()!, hi = v.max()!; lo -= bin; hi += bin
    let n = Int((hi - lo) / bin) + 2
    var h = [Int](repeating: 0, count: n)
    for x in v { let i = Int((x - lo) / bin); if i >= 0 && i < n { h[i] += 1 } }
    return h.enumerated().sorted { $0.element > $1.element }.prefix(top).map { (lo + (Float($0.offset) + 0.5) * bin, $0.element) }
}
print("podłoga: y min \(ys.min()!) max \(ys.max()!)")
print("szczyty X:", peaks(wallXs).map { String(format: "%.2f(%d)", $0.0, $0.1) })
print("szczyty Z:", peaks(wallZs).map { String(format: "%.2f(%d)", $0.0, $0.1) })
