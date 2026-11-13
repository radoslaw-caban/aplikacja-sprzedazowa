import Foundation

/// KOLIZJE I INTERAKCJE OBIEKTÓW PIASKOWNICY.
///
/// Dwie rzeczy w jednym module, bo są nierozdzielne: kolizja bez interakcji
/// to tylko blokada, a interakcja bez kolizji to dźwięk w próżni.
///
/// Zasady:
///  - obiekty się **nie przenikają** (bryła otaczająca AABB w rzucie + wysokość),
///  - wynik dotknięcia zależy od PARY obiektów — drzewo o drzewo to szum liści,
///    kamień o kamień to stuk, a kamień o szkło to brzęk,
///  - pary mają ustalony dźwięk, więc wynik jest przewidywalny i testowalny.
public enum SandboxPhysics {

    // MARK: - bryły otaczające

    /// Bryła otaczająca obiektu w przestrzeni (mm).
    public struct AABB: Sendable, Equatable {
        public var min: SIMD3<Double>
        public var max: SIMD3<Double>

        public var size: SIMD3<Double> { max - min }
        public var center: SIMD3<Double> { (min + max) / 2 }

        public init(min: SIMD3<Double>, max: SIMD3<Double>) {
            self.min = min
            self.max = max
        }
    }

    /// Bryła otaczająca obiektu — uwzględnia obrót wokół Y.
    ///
    /// Obrót liczymy przez rozwinięcie AABB na obrócony prostokąt (nie pełny
    /// OBB) — dla obiektów o osiach zbliżonych do świata to wystarcza,
    /// a jest wielokrotnie tańsze przy setkach obiektów.
    public static func bounds(of o: SandboxObject) -> AABB {
        let s = o.effectiveSize
        let halfW = s.x / 2
        let halfD = s.z / 2
        let rad = o.rotationY * .pi / 180
        let c = abs(cos(rad))
        let sn = abs(sin(rad))
        // rzut obróconego prostokąta na osie świata
        let ex = halfW * c + halfD * sn
        let ez = halfW * sn + halfD * c
        let cx = o.position.x
        let cz = o.position.z
        let y0 = o.position.y
        return AABB(
            min: SIMD3(cx - ex, y0, cz - ez),
            max: SIMD3(cx + ex, y0 + s.y, cz + ez)
        )
    }

    // MARK: - kolizja

    /// Czy dwa obiekty kolidują (z opcjonalnym marginesem styku).
    ///
    /// `tolerance` > 0 pozwala na styk bez kolizji — dwa obiekty postawione
    /// dokładnie obok siebie nie mogą być traktowane jak nachodzące.
    public static func collides(_ a: SandboxObject, _ b: SandboxObject,
                                tolerance: Double = 1) -> Bool {
        let ba = bounds(of: a)
        let bb = bounds(of: b)
        return ba.min.x < bb.max.x - tolerance && bb.min.x < ba.max.x - tolerance
            && ba.min.z < bb.max.z - tolerance && bb.min.z < ba.max.z - tolerance
            && ba.min.y < bb.max.y - tolerance && bb.min.y < ba.max.y - tolerance
    }

    /// Wszystkie obiekty kolidujące z kandydatem (poza nim samym).
    public static func collisions(of candidate: SandboxObject,
                                  in objects: [SandboxObject],
                                  tolerance: Double = 1) -> [SandboxObject] {
        objects.filter { $0.id != candidate.id && collides(candidate, $0, tolerance: tolerance) }
    }

    /// Czy kandydat stoi w wolnym miejscu.
    public static func canPlace(_ candidate: SandboxObject,
                                in objects: [SandboxObject],
                                tolerance: Double = 1) -> Bool {
        collisions(of: candidate, in: objects, tolerance: tolerance).isEmpty
    }

    /// Najbliższe wolne miejsce w pobliżu `candidate` (mm).
    ///
    /// Przeszukuje spiralnie w krokach `step` — tak, żeby przy „stuknięciu"
    /// w zajęte miejsce obiekt odsunął się obok, a nie zniknął.
    public static func nearestFreeSpot(for candidate: SandboxObject,
                                       in objects: [SandboxObject],
                                       step: Double = 100,
                                       maxRings: Int = 12) -> SandboxObject? {
        if canPlace(candidate, in: objects) { return candidate }

        for ring in 1...maxRings {
            let r = Double(ring) * step
            // 8 kierunków + rosnący promień
            let dirs: [(Double, Double)] = [
                (1, 0), (-1, 0), (0, 1), (0, -1),
                (0.707, 0.707), (-0.707, 0.707), (0.707, -0.707), (-0.707, -0.707),
            ]
            for (dx, dz) in dirs {
                var moved = candidate
                moved.position.x += dx * r
                moved.position.z += dz * r
                if canPlace(moved, in: objects) { return moved }
            }
        }
        return nil
    }

    // MARK: - interakcje

    /// Co się dzieje, gdy dwa obiekty się zetkną.
    public enum Interaction: Sendable, Equatable {
        /// nic się nie dzieje (np. dwie rośliny)
        case none
        /// dźwięk i ewentualnie wizualny efekt
        case sound(SandboxSound)
        /// dźwięk + obiekt się przewraca/przesuwa
        case knock(SandboxSound)
        /// dźwięk + obiekt jest zniszczony (szkło)
        case shatter(SandboxSound)

        public var sound: SandboxSound? {
            switch self {
            case .none: nil
            case .sound(let s), .knock(let s), .shatter(let s): s
            }
        }
    }

    /// Wynik zetknięcia pary obiektów.
    ///
    /// Reguły oparte na materiale, nie na nazwie obiektu — dzięki temu
    /// nowy obiekt w bibliotece od razu ma sensowne zachowanie, bo ma rodzaj.
    public static func interaction(_ a: SandboxObject, _ b: SandboxObject) -> Interaction {
        let ma = material(a.kind)
        let mb = material(b.kind)
        let pair = ordered(ma, mb)

        // Kolejność NIE ma znaczenia: para jest normalizowana alfabetycznie,
        // więc przypadki muszą być zapisane dokładnie w tej kolejności:
        // creature < foliage < glass < metal < soil < stone < water < wood.
        // Bez tego `(.stone, .glass)` nigdy nie trafiał, bo po normalizacji
        // para to `(.glass, .stone)` — i wpadała w `default`.
        switch pair {
        // --- creature ---
        case (.creature, .creature): return .sound(.chirp)
        case (.creature, .foliage): return .sound(.chirp)
        case (.creature, .glass): return .sound(.tap)
        case (.creature, .metal): return .sound(.tap)
        case (.creature, .soil): return .sound(.rustle)
        case (.creature, .stone): return .sound(.tap)
        case (.creature, .water): return .sound(.swish)
        case (.creature, .wood): return .sound(.tap)

        // --- foliage ---
        case (.foliage, .foliage): return .sound(.leaves)
        case (.foliage, .glass): return .sound(.rustle)
        case (.foliage, .metal): return .sound(.rustle)
        case (.foliage, .soil): return .sound(.rustle)
        case (.foliage, .stone): return .sound(.rustle)
        case (.foliage, .water): return .sound(.rustle)
        case (.foliage, .wood): return .sound(.leaves)

        // --- glass ---
        case (.glass, .glass): return .shatter(.crunch)
        case (.glass, .metal): return .shatter(.crunch)
        case (.glass, .soil): return .sound(.thud)
        case (.glass, .stone): return .shatter(.crunch)      // kamień w szybę: tłuczenie
        case (.glass, .water): return .shatter(.crunch)
        case (.glass, .wood): return .shatter(.crunch)

        // --- metal ---
        case (.metal, .metal): return .sound(.metal)
        case (.metal, .soil): return .knock(.knock)
        case (.metal, .stone): return .knock(.metal)
        case (.metal, .water): return .sound(.swish)
        case (.metal, .wood): return .knock(.knock)

        // --- soil ---
        case (.soil, .soil): return .sound(.thud)
        case (.soil, .stone): return .sound(.thud)
        case (.soil, .water): return .sound(.swish)
        case (.soil, .wood): return .sound(.thud)

        // --- stone ---
        case (.stone, .stone): return .knock(.stone)
        case (.stone, .water): return .sound(.crunch)
        case (.stone, .wood): return .knock(.wood)

        // --- water ---
        case (.water, .water): return .sound(.swish)
        case (.water, .wood): return .sound(.swish)

        // --- wood ---
        case (.wood, .wood): return .knock(.wood)

        // zabezpieczenie: nowy materiał bez reguły nie może dać ciszy
        default: return .sound(.tap)
        }
    }

    /// Materiał obiektu — decyduje o interakcji, nie nazwa.
    public enum Material: Sendable, Equatable {
        case stone, wood, metal, glass, foliage, soil, creature, water
    }

    public static func material(_ kind: SandboxKind) -> Material {
        switch kind {
        case .terrainFlat, .terrainHill, .terrainMound, .terrainTrench,
             .soil, .gravel, .sandPile:
            .soil
        case .boulder, .rockSmall:
            .stone
        case .tree, .bush, .grassTuft, .flower, .hedge:
            .foliage
        case .animalSmall, .animalLarge, .person:
            .creature
        case .pavingTile, .foundation, .wallSegment:
            .stone
        case .fence, .gate, .planter, .bench, .doorFrame:
            .wood
        // Okno to SZYBA, nie rama: przy zderzeniu liczy się tłuczenie,
        // nie stuk drewna. Rama jest tylko opakowaniem.
        case .windowFrame:
            .glass
        case .roofPanel:
            .metal
        case .pipeRun:
            .metal
        case .paintPatch, .floorPatch, .tilePatch, .wallpaperPatch:
            .wood
        }
    }

    /// Normalizacja pary — kolejność alfabetyczna, żeby A+B i B+A dały to samo.
    private static func ordered(_ a: Material, _ b: Material) -> (Material, Material) {
        // materiały mają kolejność deklaracji; porównujemy po nazwie przypadku
        String(describing: a) <= String(describing: b) ? (a, b) : (b, a)
    }

    // MARK: - dotknięcie przez użytkownika

    /// Reakcja obiektu na dotknięcie palcem (bez drugiego obiektu).
    ///
    /// To osobny przypadek od kolizji: użytkownik dotyka obiektu i chce
    /// usłyszeć, z czego jest zrobiony.
    public static func tapSound(_ kind: SandboxKind) -> SandboxSound {
        switch material(kind) {
        case .stone: .stone
        case .wood: .wood
        case .metal: .metal
        case .glass: .crunch
        case .foliage: .rustle
        case .soil: .thud
        case .creature: .chirp
        case .water: .swish
        }
    }
}
