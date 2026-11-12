import Foundation

/// Generator parametryczny — buduje bryły korpusu, frontów i wyposażenia w mm.
/// Logika jest przeniesiona 1:1 z wersji TypeScript (design/generator.ts).
public enum Generator {

    /// Bryły jednej szafki, w układzie lokalnym: środek w (0,0,0), y od podłogi, front w +Z.
    public static func build(_ c: Cabinet) -> [Box] {
        // Zaślepka: jedna płyta, bez korpusu, cokołu i frontu. Stoi przy ścianie
        // i ma być widoczna obrzeżem — dlatego jest grubości 18 mm.
        if c.type == .panel {
            return [
                Box(
                    id: "\(c.id):panel",
                    role: .side,
                    cabinetID: c.id,
                    size: SIMD3(c.width, c.height, c.depth),
                    position: SIMD3(0, c.height / 2, 0),
                    color: c.color
                )
            ]
        }

        var out: [Box] = []
        let p = Standards.panel
        let bodyH = c.type == .base ? max(0, c.height - c.plinth) : c.height
        let baseY = c.type == .base ? c.plinth : c.mountHeight

        // ---- cokół (cofnięty o setback, tylko szafki dolne i stojące) ----
        if c.type != .wall, c.plinth > 0 {
            let pd = c.depth - Standards.plinthSetback
            out.append(Box(
                id: "\(c.id):plinth",
                role: .plinth,
                cabinetID: c.id,
                size: SIMD3(c.width, c.plinth, max(0, pd)),
                position: SIMD3(0, c.plinth / 2, Standards.plinthSetback / 2),
                color: "#3a3a37"
            ))
        }

        // ---- boki ----
        for (i, sign) in [(-1.0), (1.0)].enumerated() {
            out.append(Box(
                id: "\(c.id):side:\(i)",
                role: .side,
                cabinetID: c.id,
                size: SIMD3(p, bodyH, c.depth),
                position: SIMD3(sign * (c.width / 2 - p / 2), baseY + bodyH / 2, 0),
                color: c.color
            ))
        }

        // ---- dno i wieniec ----
        let innerW = max(0, c.width - 2 * p)
        out.append(Box(
            id: "\(c.id):bottom",
            role: .bottom,
            cabinetID: c.id,
            size: SIMD3(innerW, p, c.depth),
            position: SIMD3(0, baseY + p / 2, 0),
            color: c.color
        ))
        out.append(Box(
            id: "\(c.id):top",
            role: .top,
            cabinetID: c.id,
            size: SIMD3(innerW, p, c.depth),
            position: SIMD3(0, baseY + bodyH - p / 2, 0),
            color: c.color
        ))

        // ---- plecy ----
        out.append(Box(
            id: "\(c.id):back",
            role: .back,
            cabinetID: c.id,
            size: SIMD3(c.width, bodyH, Standards.back),
            position: SIMD3(0, baseY + bodyH / 2, -c.depth / 2 + Standards.backInset),
            color: "#f2efe9"
        ))

        // ---- wyposażenie ----
        for e in c.elements {
            switch e.kind {
            case .shelf, .divider:
                out.append(Box(
                    id: "\(c.id):\(e.kind):\(e.id)",
                    role: e.kind == .shelf ? .shelf : .divider,
                    cabinetID: c.id,
                    size: SIMD3(innerW - 2, p, c.depth - Standards.backInset - 20),
                    position: SIMD3(0, baseY + e.y + p / 2, 0),
                    color: c.color
                ))
            case .drawer:
                out.append(Box(
                    id: "\(c.id):drawer:\(e.id)",
                    role: .drawerFront,
                    cabinetID: c.id,
                    size: SIMD3(innerW - 2 * Standards.gap, e.height, p),
                    position: SIMD3(0, baseY + e.y + e.height / 2, c.depth / 2 + p / 2),
                    color: c.color
                ))
            case .cutout:
                break
            }
        }

        // ---- wycięcia (blat / front / bok) ----
        for cut in c.cutouts ?? [] {
            let color = "#101418"
            switch cut.plane {
            case .top:
                let topY = c.type == .base
                    ? c.height + Standards.worktopThickness + 1
                    : baseY + bodyH + 1
                out.append(Box(
                    id: "\(c.id):cutout:\(cut.id)",
                    role: .cutout,
                    cabinetID: c.id,
                    size: SIMD3(cut.width, 2, cut.height),
                    position: SIMD3(cut.x, topY, cut.y),
                    color: color
                ))
            case .front:
                out.append(Box(
                    id: "\(c.id):cutout:\(cut.id)",
                    role: .cutout,
                    cabinetID: c.id,
                    size: SIMD3(cut.width, cut.height, 2),
                    position: SIMD3(cut.x, baseY + min(max(cut.y, cut.height / 2), bodyH - cut.height / 2),
                                    c.depth / 2 + 22),
                    color: color
                ))
            case .side:
                out.append(Box(
                    id: "\(c.id):cutout:\(cut.id)",
                    role: .cutout,
                    cabinetID: c.id,
                    size: SIMD3(2, cut.height, cut.width),
                    position: SIMD3(c.width / 2 + 1, baseY + min(max(cut.y, cut.height / 2), bodyH - cut.height / 2),
                                    cut.x),
                    color: color
                ))
            }
        }

        // ---- szafa przesuwna: panele w płaszczyźnie frontu ----
        if let panels = c.slidingPanels, panels > 1 {
            let pw = c.width / Double(panels) + 30
            for i in 0..<panels {
                let px = -c.width / 2 + (Double(i) + 0.5) * (c.width / Double(panels))
                out.append(Box(
                    id: "\(c.id):slide:\(i)",
                    role: .front,
                    cabinetID: c.id,
                    size: SIMD3(pw, bodyH - 2 * Standards.gap, Standards.panel),
                    position: SIMD3(px, baseY + bodyH / 2, c.depth / 2 + Standards.gap + Standards.panel / 2 + Double(i) * 18),
                    color: c.color
                ))
            }
        }

        // ---- front (pełne pokrycie korpusu, szczelina 3 mm) ----
        if c.slidingPanels == nil {
            let hasDrawers = c.elements.contains { $0.kind == .drawer }
            if !hasDrawers {
                let doors = max(1, min(2, c.doorCount ?? 1))
                if doors == 1 {
                    out.append(Box(
                        id: "\(c.id):front",
                        role: .front,
                        cabinetID: c.id,
                        size: SIMD3(
                            max(0, c.width - 2 * Standards.gap),
                            max(0, bodyH - 2 * Standards.gap),
                            p
                        ),
                        position: SIMD3(0, baseY + bodyH / 2, c.depth / 2 + Standards.gap + p / 2),
                        color: c.color
                    ))
                } else {
                    let gap = Standards.gap
                    let doorW = max(0, (c.width - gap * 3) / 2)
                    for i in 0..<2 {
                        let x = (doorW + gap) * (Double(i) - 0.5)
                        out.append(Box(
                            id: "\(c.id):front:\(i)",
                            role: .front,
                            cabinetID: c.id,
                            size: SIMD3(doorW, max(0, bodyH - 2 * gap), p),
                            position: SIMD3(x, baseY + bodyH / 2, c.depth / 2 + gap + p / 2),
                            color: c.color
                        ))
                    }
                }
            }
        }

        // ---- AGD i urządzenia (strefy zabudowy) ----
        if let appliances = c.appliances, !appliances.isEmpty {
            out.append(contentsOf: applianceBoxes(c, appliances))
        }

        return out
    }

    /// Bryły AGD w układzie lokalnym szafki. Rysowane 4 mm przed frontem,
    /// żeby nie znikały pod skrzydłem (brak z-fightingu).
    public static func applianceBoxes(_ c: Cabinet, _ kinds: [ApplianceKind]) -> [Box] {
        var out: [Box] = []
        let top = c.height + (c.type == .base ? Standards.worktopThickness : 0)
        let zFace = c.depth / 2 + Standards.gap + Standards.panel / 2 + 4
        let steel = "#b9bcc1"
        let dark = "#15181c"
        func add(_ kind: String, _ size: SIMD3<Double>, _ pos: SIMD3<Double>, _ color: String) {
            out.append(Box(id: "\(c.id):ag:\(kind):\(out.count)", role: .appliance,
                           cabinetID: c.id, size: size, position: pos, color: color))
        }
        for kind in kinds {
            switch kind {
            case .sink:
                let w = min(c.width - 120, 760), d = 430.0
                add("rim", SIMD3(w, 10, d), SIMD3(0, top + 5, 10), steel)
                add("bowl", SIMD3(w - 90, 160, d - 110), SIMD3(0, top - 80, 10), "#30363d")
                add("tap", SIMD3(26, 240, 26), SIMD3(0, top + 150, -c.depth / 2 + 110), steel)
                add("spout", SIMD3(24, 24, 200), SIMD3(0, top + 265, -c.depth / 2 + 210), steel)
            case .hob:
                let w = min(c.width - 60, 800), d = 480.0
                add("glass", SIMD3(w, 6, d), SIMD3(0, top + 3, 10), "#22262c")
                for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                    add("zone", SIMD3(160, 3, 160),
                        SIMD3(sx * w / 4.2, top + 7, sz * d / 4.6), "#3b4048")
                }
            case .oven:
                let y = c.plinth + (c.type == .tall ? 860 : 120)
                add("oven", SIMD3(min(560, c.width - 40), 590, 22), SIMD3(0, y + 295, zFace), dark)
                add("handle", SIMD3(500, 18, 30), SIMD3(0, y + 555, zFace + 20), steel)
            case .microwave:
                let y = c.plinth + (c.type == .tall ? 1490 : 480)
                add("micro", SIMD3(min(520, c.width - 60), 360, 20), SIMD3(0, y + 180, zFace), dark)
                add("handle", SIMD3(420, 16, 26), SIMD3(0, y + 350, zFace + 18), steel)
            case .fridge:
                let h = c.height - c.plinth - 20
                add("fridge", SIMD3(c.width - 20, h, 22), SIMD3(0, c.plinth + h / 2 + 10, zFace), "#c3c8ce")
                add("handleL", SIMD3(18, h * 0.55, 26), SIMD3(-c.width / 2 + 40, c.plinth + h * 0.55, zFace + 18), steel)
                add("handleR", SIMD3(18, h * 0.55, 26), SIMD3(c.width / 2 - 40, c.plinth + h * 0.55, zFace + 18), steel)
            case .hood:
                let w = min(c.width, 900)
                let canopyY = top + 650
                add("canopy", SIMD3(w, 70, 500), SIMD3(0, canopyY, -c.depth / 2 + 300), steel)
                add("chimney", SIMD3(280, 700, 260), SIMD3(0, canopyY + 380, -c.depth / 2 + 320), "#cfd2d6")
            case .dishwasher:
                let h = c.height - c.plinth - 10
                add("panel", SIMD3(c.width - 8, h, 20), SIMD3(0, c.plinth + h / 2, zFace), "#c9ccd1")
                add("strip", SIMD3(c.width - 16, 40, 24), SIMD3(0, c.height - 45, zFace + 12), "#8f939a")
            case .tv:
                let tw = min(c.width * 0.8, 1600)
                let th = tw * 0.5625
                add("screen", SIMD3(tw, th, 36), SIMD3(0, c.mountHeight + c.height + 700, -c.depth / 2 - 20), "#0b0d10")
                add("stand", SIMD3(180, 26, 120), SIMD3(0, c.mountHeight + c.height + 700 - th / 2, -c.depth / 2 - 20), steel)
            case .mirror:
                add("mirror", SIMD3(min(c.width - 40, 900), min(c.height - 20, 700), 18),
                    SIMD3(0, c.mountHeight + c.height / 2, c.depth / 2 + 10), "#a9c2cf")
            case .basin:
                add("basin", SIMD3(min(c.width - 100, 600), 130, 400), SIMD3(0, top + 65, 10), "#f2f1ec")
                add("tap", SIMD3(26, 220, 26), SIMD3(0, top + 170, -c.depth / 2 + 90), steel)
            case .washer:
                add("panel", SIMD3(c.width - 8, c.height - c.plinth - 20, 20),
                    SIMD3(0, c.height / 2, zFace), "#e4e2dd")
            case .bin:
                break
            }
        }
        return out
    }

    /// Stawia szafkę POD ŚCIANĄ, TYŁEM DO NIEJ, frontem do wnętrza pomieszczenia.
    ///
    /// ZASADA (wymóg produkcyjny): szafka stoi tyłem do ściany. Front korpusu
    /// jest w układzie lokalnym na +Z (`Generator.build`: elementy `.front`
    /// mają `z = +depth/2`), więc obrót dobieramy tak, żeby lokalne +Z
    /// wskazywało W GŁĄB pomieszczenia:
    ///
    ///   ściana 0 (północ, −Z) → obrót   0°  (przód w +Z, do środka)
    ///   ściana 1 (południe, +Z) → obrót 180° (przód w −Z, do środka)
    ///   ściana 2 (zachód, −X) → obrót  90°
    ///   ściana 3 (wschód, +X) → obrót 270°
    ///
    /// Gdyby zostawić obrót 0 dla każdej ściany, szafka na ścianie południowej
    /// stałaby frontem w ścianę — dokładnie ten błąd został zgłoszony.
    public static func placedAgainstWall(_ cabinet: Cabinet, wall: Int,
                                         room: Room) -> Cabinet {
        var c = cabinet
        let halfW = room.width / 2
        let halfD = room.depth / 2
        // odstęp ściany, żeby korpus nie wchodził w geometrię ściany
        let gap: Double = 5
        // przy szafkach wiszących dochodzi grubość korpusu — liczymy głębię
        let d = c.depth

        switch wall {
        case 0:  // północ: tył do −Z
            c.rotation = 0
            c.z = -halfD + gap + d / 2
        case 1:  // południe: tył do +Z
            c.rotation = 180
            c.z = halfD - gap - d / 2
        case 2:  // zachód: tył do −X
            c.rotation = 90
            c.x = -halfW + gap + d / 2
        default: // wschód: tył do +X
            c.rotation = 270
            c.x = halfW - gap - d / 2
        }
        return c
    }

    /// Dokłada szafkę w tym samym rzędzie co sąsiad (bez kolizji), zwraca nową pozycję.
    public static func placeNext(to existing: [Cabinet], new: Cabinet, tolerance: Double = 20) -> Cabinet? {
        guard let ref = existing.last else { return new }
        var candidate = new
        candidate.rotation = ref.rotation
        // UWAGA: przy obrocie 90°/270° szafka jest przekręcona, więc jej
        // szerokość biegnie wzdłuż Z, a nie X. Wcześniej sąsiad dokładał się
        // zawsze w X, więc na ścianach zachodniej i wschodniej szafki
        // wskakiwały na siebie.
        let rotated = abs(ref.rotation.truncatingRemainder(dividingBy: 180) - 90) < 1
        if rotated {
            candidate.z = ref.z + (ref.width + new.width) / 2
            candidate.x = ref.x
        } else {
            candidate.z = ref.z
            candidate.x = ref.x + (ref.width + new.width) / 2
        }
        let others = existing.filter { $0.id != new.id }
        if others.contains(where: { Collision.overlaps($0, candidate, tolerance: tolerance) }) { return nil }
        return candidate
    }
}
