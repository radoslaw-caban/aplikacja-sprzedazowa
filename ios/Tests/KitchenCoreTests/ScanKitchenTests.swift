import XCTest
import simd
@testable import KitchenCore

final class ScanKitchenTests: XCTestCase {

    /// Poziomy prostokąt (blat) jako dwa trójkąty, na wysokości `y`.
    private func slab(x0: Float, z0: Float, x1: Float, z1: Float, y: Float) -> [SIMD3<Float>] {
        let a = SIMD3<Float>(x0, y, z0)
        let b = SIMD3<Float>(x1, y, z0)
        let c = SIMD3<Float>(x1, y, z1)
        let d = SIMD3<Float>(x0, y, z1)
        return [a, b, c, a, c, d]
    }

    private func rotateY(_ tris: [SIMD3<Float>], deg: Float, around center: SIMD2<Float>) -> [SIMD3<Float>] {
        let r = deg * .pi / 180
        let c = cos(r), s = sin(r)
        return tris.map { p in
            let dx = p.x - center.x, dz = p.z - center.y
            return SIMD3(dx * c - dz * s + center.x, p.y, dx * s + dz * c + center.y)
        }
    }

    /// Kuchnia w L: bieg 3,90 m wzdłuż Z i 2,90 m wzdłuż X, blat 0,85 m, głębokość 0,60 m.
    private var lShape: [SIMD3<Float>] {
        slab(x0: 0.0, z0: 0.0, x1: 0.6, z1: 3.9, y: 0.85) +     // bieg wzdłuż Z
        slab(x0: 0.0, z0: 3.3, x1: 2.9, z1: 3.9, y: 0.85)       // bieg wzdłuż X (przy końcu)
    }

    func testDetectsTwoRunsInLShape() {
        let proposal = ScanKitchen.detect(triangles: lShape)

        XCTAssertEqual(proposal.runs.count, 2, "L-ka powinna dać dwa biegi, wykryto \(proposal.runs.count): \(proposal.runs.map { $0.lengthMM })")
        XCTAssertEqual(proposal.worktopHeightMM, 850, accuracy: 15)

        let lengths = proposal.runs.map { $0.lengthMM }.sorted()
        guard lengths.count >= 2 else {
            XCTFail("wykryto \(lengths) — oczekiwano dwóch biegnów")
            return
        }
        XCTAssertEqual(lengths[0], 2900, accuracy: 120, "krótszy bieg")
        XCTAssertEqual(lengths[1], 3900, accuracy: 120, "dłuższy bieg")

        for run in proposal.runs {
            XCTAssertEqual(run.depthMM, 600, accuracy: 120, "głębokość biegu \(run.depthMM)")
        }
    }

    func testModuleWidthsSumToRunLength() {
        let proposal = ScanKitchen.detect(triangles: lShape)
        for run in proposal.runs {
            let sum = run.modules.reduce(0) { $0 + $1.width }
            XCTAssertEqual(sum, run.lengthMM, accuracy: 1.0,
                           "suma modułów \(sum) ≠ długość biegu \(run.lengthMM)")
            for module in run.modules {
                XCTAssertGreaterThanOrEqual(module.width, 300, "moduł za wąski: \(module.width)")
                XCTAssertLessThanOrEqual(module.width, 1000, "moduł za szeroki: \(module.width)")
            }
        }
    }

    func testDetectsRotation() {
        let rotated = rotateY(lShape, deg: 30, around: SIMD2(1.5, 2.0))
        let proposal = ScanKitchen.detect(triangles: rotated)

        print("DIAG rotacja:", proposal.rotationDeg, "biegi:", proposal.runs.map { ($0.lengthMM, $0.depthMM, $0.angleDeg) }, "blat m2:", proposal.counterAreaM2)
        XCTAssertEqual(proposal.runs.count, 2, "obrócona L-ka też ma dać dwa biegi")
        // wykryty kąt może wyjść jako 30° lub 30°+90° (zależy, którą oś uzna za „wzdłuż")
        let normalized = proposal.rotationDeg.truncatingRemainder(dividingBy: 90)
        XCTAssertEqual(abs(normalized), 30, accuracy: 2.0,
                       "kąt obrotu \(proposal.rotationDeg)°")

        let lengths = proposal.runs.map { $0.lengthMM }.sorted()
        guard lengths.count >= 2 else { return }
        XCTAssertEqual(lengths[0], 2900, accuracy: 150)
        XCTAssertEqual(lengths[1], 3900, accuracy: 150)
    }

    func testEmptyGeometryReturnsEmptyProposal() {
        let proposal = ScanKitchen.detect(triangles: [])
        XCTAssertTrue(proposal.isEmpty)
        XCTAssertFalse(proposal.notes.isEmpty)
        XCTAssertEqual(proposal.worktopHeightMM, 0)
    }

    /// Ściany (pionowe) nie mogą udawać blatu.
    func testVerticalSurfacesAreIgnored() {
        let wall: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(0, 2.5, 0), SIMD3(3, 2.5, 0),
            SIMD3(0, 0, 0), SIMD3(3, 2.5, 0), SIMD3(3, 0, 0)
        ]
        let proposal = ScanKitchen.detect(triangles: wall)
        XCTAssertTrue(proposal.isEmpty)
    }

    func testModuleSplitIsEvenAndWithinLimits() {
        let options = ScanKitchen.Options()
        let modules = ScanKitchen.split(lengthMM: 3000, options: options)
        XCTAssertEqual(modules.count, 5)
        XCTAssertEqual(modules.reduce(0) { $0 + $1.width }, 3000, accuracy: 0.5)
        XCTAssertEqual(modules[0].width, 600, accuracy: 0.5)

        let uneven = ScanKitchen.split(lengthMM: 2117, options: options)
        XCTAssertEqual(uneven.reduce(0) { $0 + $1.width }, 2117, accuracy: 0.5)
        XCTAssertTrue(uneven.allSatisfy { $0.width >= 300 && $0.width <= 1000 })
    }

    func testDeterministicOnSameInput() {
        let first = ScanKitchen.detect(triangles: lShape)
        let second = ScanKitchen.detect(triangles: lShape)
        XCTAssertEqual(first.runs.map { $0.lengthMM }, second.runs.map { $0.lengthMM })
        XCTAssertEqual(first.rotationDeg, second.rotationDeg)
    }
}
