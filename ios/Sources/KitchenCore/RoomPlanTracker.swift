import Foundation
import simd

/// Zbiera plan pomieszczenia W TRAKCIE skanowania i wyznacza kontur na żywo.
///
/// To warstwa między chmurą a `RoomModel`: dostaje punkty z siatki ARKit
/// i co jakiś czas liczy uproszczony kontur, który UI rysuje jako kolorowe linie.
///
/// DECYZJE (i dlaczego):
///  - **dla każdego woksela XZ trzymamy NAJWYŻSZY punkt** — te same ściany są
///    widziane setki razy, więc bez odsiewania zbiór rósłby liniowo z czasem.
///    Trzymanie najwyższego punktu w wokselu ma dodatkową zaletę: pasmo pod
///    sufitem dostajemy za darmo, bo najwyższe punkty nad każdym miejscem
///    podłogi to właśnie górna część ścian. Nadproża są ciągłe, więc kontur
///    nie rwie się na drzwiach (przy podłodze rwie się zawsze).
///  - **kontur liczymy w tle i tylko co ~1 s** — pełna detekcja to siatka
///    zajętości + śledzenie brzegu, czyli dziesiątki ms; co klatkę nie ma sensu.
///
/// Klasa jest bezpieczna wątkowo (lock) — `RoomScanSession` woła ją z kolejki ARKit.
public final class RoomPlanTracker: @unchecked Sendable {

    public struct Options: Sendable {
        /// bok woksela odsiewającego duplikaty (metry)
        public var voxel: Float = 0.05
        /// maksymalna liczba wokseli (ochrona pamięci)
        public var maxCells: Int = 60_000
        /// minimalna liczba punktów, żeby liczyć kontur
        public var minPoints: Int = 300
        /// grubość pasma pod najwyższym punktem, z którego bierzemy kontur
        public var bandThickness: Float = 0.45

        public init() {}
    }

    public struct Snapshot: Sendable {
        /// kontur w planie (metry), zamknięty
        public var outline: [SIMD2<Float>]
        /// pole powierzchni z konturu (m²)
        public var area: Float
        /// liczba wokseli planu
        public var points: Int
        /// poziom, na którym wyznaczono kontur (metry)
        public var level: Float

        public var corners: [SIMD2<Float>] { outline }
        public var isUsable: Bool { outline.count >= 3 }
    }

    private let options: Options
    private let lock = NSLock()

    /// woksel XZ → najwyższy punkt w tym wokselu
    private var cells: [SIMD2<Int32>: SIMD3<Float>] = [:]
    private var lastSnapshot = Snapshot(outline: [], area: 0, points: 0, level: 0)
    private var lastUpdate = Date.distantPast

    public init(options: Options = Options()) {
        self.options = options
    }

    public func reset() {
        lock.lock()
        cells.removeAll(keepingCapacity: true)
        lastSnapshot = Snapshot(outline: [], area: 0, points: 0, level: 0)
        lastUpdate = .distantPast
        lock.unlock()
    }

    /// Dodaje punkty z jednej klatki (pozycje świata w metrach).
    ///
    /// - Parameter floorY: poziom podłogi — punkty podłogi odrzucamy, bo leżą
    ///   w tym samym pasie co dolna część ścian i pogarszają kontur.
    public func add(points: [SIMD3<Float>], floorY: Float) {
        guard !points.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        for p in points {
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
            guard p.y > floorY + 0.15 else { continue }
            let key = SIMD2(Int32((p.x / options.voxel).rounded()),
                            Int32((p.z / options.voxel).rounded()))
            if let existing = cells[key] {
                if p.y > existing.y { cells[key] = p }
            } else {
                guard cells.count < options.maxCells else { continue }
                cells[key] = p
            }
        }
    }

    public var pointCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cells.count
    }

    /// Liczy kontur, jeśli jest z czego i minęło dość czasu od poprzedniego.
    ///
    /// Obliczenia robimy POZA lockiem (kopia danych pod lockiem), żeby nie
    /// blokować kolejki ARKit na czas siatki zajętości.
    public func refreshIfNeeded(minInterval: TimeInterval = 1.0) -> Snapshot? {
        lock.lock()
        guard cells.count >= options.minPoints else {
            lock.unlock()
            return nil
        }
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= minInterval else {
            lock.unlock()
            return nil
        }
        lastUpdate = now
        let stored = Array(cells.values)
        lock.unlock()

        // pasmo pod najwyższym punktem: nadproża są ciągłe, więc kontur się domyka
        guard let top = stored.map(\.y).max() else { return nil }
        let band = stored.filter { $0.y >= top - options.bandThickness }
        guard band.count >= 50 else { return nil }

        let plan = band.map { SIMD2($0.x, $0.z) }
        guard let outline = RoomModel.roomOutline(points: plan, options: RoomModel.Options()),
              outline.count >= 3 else { return nil }

        let snapshot = Snapshot(outline: outline, area: RoomModel.polygonArea(outline),
                                points: stored.count, level: top)

        lock.lock()
        lastSnapshot = snapshot
        lock.unlock()
        return snapshot
    }

    public var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return lastSnapshot
    }
}
