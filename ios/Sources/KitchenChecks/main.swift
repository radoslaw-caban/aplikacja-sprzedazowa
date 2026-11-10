import Foundation
import KitchenCore

/// Samokontrola bez Xcode: te same warunki co testy jednostkowe.
/// Uruchomienie: `swift run KitchenChecks` — kod wyjścia 1, gdy coś nie przejdzie.

final class Reporter {
    var checks = 0
    var failures = 0

    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks += 1
        if condition {
            print("  ✓ \(name)")
        } else {
            failures += 1
            print("  ✗ \(name) \(detail)")
        }
    }
}

func near(_ a: Double, _ b: Double, _ eps: Double = 0.001) -> Bool { abs(a - b) <= eps }

func runChecks() {
    let r = Reporter()

    print("Standardy produkcyjne")
    r.check("płyta 18 mm", Standards.panel == 18)
    r.check("szafka dolna 720 mm", Standards.baseHeight == 720)
    r.check("głębokość 560 mm", Standards.baseDepth == 560)
    r.check("blat 38 mm", Standards.worktopThickness == 38)
    r.check("LEGRABOX K = 128.5", DrawerSystem.k.frontHeight == 128.5)

    print("\nBlat i cokół")
    let cabinet = Library.make(Library.base[0])
    let runs = Runs.compute([cabinet])
    r.check("jeden bieg", runs.count == 1)
    r.check("górna krawędź korpusu 720", near(runs[0].bodyTop, 720), "= \(runs[0].bodyTop)")

    let worktop = Runs.worktops(runs)
    r.check("jeden blat na bieg", worktop.count == 1)
    r.check("blat leży na korpusie (y = 739)", near(worktop[0].position.y, 739), "= \(worktop[0].position.y)")
    r.check("nawis 20 mm z każdej strony", near(worktop[0].size.x, 640), "= \(worktop[0].size.x)")

    let plinth = Runs.plinths(runs)
    r.check("cokół 150 mm", near(plinth[0].size.y, 150))
    r.check("cokół cofnięty (głębokość 500)", near(plinth[0].size.z, 500), "= \(plinth[0].size.z)")
    r.check("cokół przesunięty do tyłu o 20", near(plinth[0].position.z, 20), "= \(plinth[0].position.z)")

    print("\nKorpus i front")
    let boxes = Generator.build(cabinet)
    r.check("dwa boki", boxes.filter { $0.role == .side }.count == 2)
    r.check("dno", boxes.contains { $0.role == .bottom })
    r.check("wieniec", boxes.contains { $0.role == .top })
    r.check("plecy", boxes.contains { $0.role == .back })
    if let front = boxes.first(where: { $0.role == .front }) {
        r.check("front pokrywa korpus 564 mm", near(front.size.y, 564), "= \(front.size.y)")
        r.check("front wyśrodkowany (y = 435)", near(front.position.y, 435), "= \(front.position.y)")
    } else {
        r.check("front istnieje", false)
    }

    print("\nSzuflady")
    // korpus bez wyposażenia — czysta szufladowa kolumna
    let empty = Cabinet(name: "Test szuflad", type: .base, width: 600, height: 720, depth: 560, plinth: 150)
    var c = empty
    var ys: [Double] = []
    for _ in 0..<4 {
        guard let next = Collision.addDrawer(c, system: .k) else { break }
        c = next
        ys.append(c.elements.last!.y)
    }
    r.check("wysokości 0 / 128.5 / 257 / 385.5", ys == [0, 128.5, 257, 385.5], "= \(ys)")

    var c2 = cabinet
    var count = 0
    while count < 10, let next = Collision.addDrawer(c2, system: .k) {
        c2 = next
        count += 1
    }
    r.check("w korpusie 570 mm mieszczą się 4 szuflady K", count == 4, "= \(count)")

    print("\nKolizje i dokładanie")
    let a = Library.make(Library.base[0], at: 0, z: 0)
    var b = Library.make(Library.base[0], at: 300, z: 0)
    r.check("nakładanie wykryte", Collision.overlaps(a, b))
    b.x = 600
    r.check("styk bez nakładania", !Collision.overlaps(a, b))

    let first = Library.make(Library.base[0], at: -1200, z: -2200)
    if let second = Generator.placeNext(to: [first], new: Library.make(Library.base[0])) {
        r.check("nowa szafka w rzędzie (x = -600)", near(second.x, -600), "= \(second.x)")
        r.check("ten sam wiersz (z = -2200)", near(second.z, -2200), "= \(second.z)")
    } else {
        r.check("dokładanie w rzędzie", false, "zwróciło nil")
    }

    let passed = r.checks - r.failures
    print("\n\(passed)/\(r.checks) warunków spełnionych")
    if r.failures > 0 {
        print("NIEPOWODZENIE: \(r.failures)")
        exit(1)
    }
    print("OK")
}

runChecks()
