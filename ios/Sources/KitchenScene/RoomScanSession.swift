import Foundation
import simd
import KitchenCore

#if os(iOS)
import ARKit
import UIKit
import AVFoundation
#endif

/// Przechwytywanie skanu pomieszczenia z LiDAR-u (ARKit scene reconstruction).
///
/// Architektura: cała logika, którą da się sprawdzić bez urządzenia, siedzi
/// w `KitchenCore` (`MeshSampler`, `SurfaceClassifier`, `ScanPLYWriter`).
/// Tutaj jest wyłącznie cienka warstwa ARKit — sesja, delegat i zbieranie
/// trójkątów. Dzięki temu logika jest testowalna na macOS, a ten plik to
/// jedyne miejsce wymagające iPada.
///
/// KLUCZOWA DECYZJA: nie akumulujemy punktów w trakcie skanowania.
/// ARKit wywołuje `didUpdate anchors` wielokrotnie dla tego samego anchora,
/// więc dokładanie punktów przy każdej aktualizacji dublowałoby geometrię
/// (ta sama ściana policzona dziesiątki razy). Trzymamy AKTUALNY zestaw
/// siatek, a chmurę próbkujemy RAZ — przy zakończeniu skanu.
@MainActor
public final class RoomScanSession: NSObject, ObservableObject {

    // MARK: - stan dla UI

    @Published public private(set) var trackingState: String = "—"
    @Published public private(set) var meshAnchorCount = 0
    @Published public private(set) var estimatedPoints = 0
    @Published public private(set) var coverageText: String = "—"
    @Published public private(set) var boundsText: String = "—"
    @Published public private(set) var isRunning = false

    /// Ile klatek głębi weszło do fuzji oraz ile wokseli już mamy.
    @Published public private(set) var depthFrames = 0
    @Published public private(set) var fusedVoxels = 0
    /// Mediana niepewności fuzji („1,8 mm") — realna miara dokładności skanu.
    @Published public private(set) var precisionText: String = "—"

    /// Tryb skanowania (pełny / krawędzie).
    @Published public var mode: ScanMode = .full
    /// Latarka włączona — mocno poprawia skan w słabo oświetlonych kuchniach.
    @Published public private(set) var torchOn = false
    /// Czy urządzenie w ogóle ma latarkę (iPad Pro 11" M2 ma; nie każdy iPad ma).
    @Published public private(set) var hasTorch = false


    /// Kontur rozpoznany na żywo — do rysowania linii na podglądzie.
    @Published public private(set) var liveOutline: [SIMD2<Float>] = []
    /// Ile wokseli planu już zebrano (diagnostyka trybu krawędzi).
    @Published public private(set) var planPoints = 0
    /// Pole powierzchni z rozpoznanego na żywo konturu („8,94 m²").
    @Published public private(set) var outlineAreaText: String = "—"

    /// Zbieranie planu w trakcie skanowania (kontur na żywo).
    public nonisolated let planTracker = RoomPlanTracker()

    /// Fuzja map głębi — celowo poza MainActor, bo klatki przychodzą z kolejki ARKit.
    public nonisolated let depthStore = DepthFusionStore()

    /// Czy urządzenie w ogóle ma LiDAR / wspiera rekonstrukcję sceny.
    public static var isSupported: Bool {
        #if os(iOS)
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            || ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        #else
        false
        #endif
    }

    /// Tryb skanowania — czym ma się skupić aplikacja.
    ///
    /// Jedno pomieszczenie skanuje się raz, a potem model buduje się z tego
    /// samego zbioru punktów, więc „tryb" zmienia TYLKO sposób zbierania
    /// i to, co widać na ekranie. Nie zmienia wyniku końcowego.
    public enum ScanMode: String, CaseIterable, Sendable {
        /// pełny skan — geometria, kolor, tekstura
        case full
        /// tylko narożniki i linie ścian: pomiar i rzut
        case edges

        public var title: String {
            switch self {
            case .full: "Pełny skan"
            case .edges: "Krawędzie i narożniki"
            }
        }

        public var hint: String {
            switch self {
            case .full:
                "Przejdź powoli całe pomieszczenie — ściany, podłogę i sufit. Zbieram geometrię, kolor i materiał."
            case .edges:
                "Prowadź iPada wzdłuż linii ścian, na wysokości narożników (ok. 1,2 m). Kolorowe linie pokazują rozpoznany obrys — dopóki się nie domknie, obejdź brakujący fragment."
            }
        }
    }

    /// Czy jest mapa głębi (LiDAR). Na iPhone'ach/iPadach bez LiDAR ARKit
    /// potrafi dać „sceneDepth" z stereo — też się nada, ale tylko LiDAR ma
    /// sensowną dokładność, więc tryb dokładny włączamy wyłącznie z LiDAR-em.
    public static var supportsDepthFusion: Bool {
        #if os(iOS)
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #else
        false
        #endif
    }

    /// Krok próbkowania siatki (metry). 0.02 = punkt co 2 cm.
    public var sampleStep: Float = MeshSampler.defaultStep
    /// Limit punktów w chmurze wynikowej.
    public var maxPoints: Int = 2_000_000
    /// Wysokość sufitu wykryta z obrysy skanu (metry); nil = nieznana.
    private(set) var ceilingHeight: Float?

    /// znacznik czasu ostatniego odświeżenia statystyk — wspólny dla obu platform,
    /// bo `refreshStats` jest wołane także w kompilacji na macOS (bez ARKit)
    private var lastStatsUpdate = Date.distantPast

    #if os(iOS)
    public let session = ARSession()
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    #endif

    public override init() { super.init() }

    /// Wsparcie na tym urządzeniu — dla UI, żeby ukryć przycisk.
    public var isAvailable: Bool { Self.isSupported }

    // MARK: - cykl życia sesji

    public func start() {
        #if os(iOS)
        guard Self.isSupported else {
            trackingState = "Brak LiDAR na tym urządzeniu"
            return
        }
        let cfg = ARWorldTrackingConfiguration()
        cfg.worldAlignment = .gravity

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            cfg.sceneReconstruction = .meshWithClassification
        } else {
            cfg.sceneReconstruction = .mesh
        }
        cfg.planeDetection = [.horizontal, .vertical]
        // środowisko wyłączone: obciąża GPU, a do geometrii nic nie wnosi
        cfg.environmentTexturing = .none
        // latarka: ARKit nie steruje sprzętową lampą, robi to AVCaptureDevice.
        // Włączamy, gdy użytkownik tego chce — w ciemnej kuchni bez tego
        // mapa głębi ma dziury (LiDAR potrzebuje światła odbitego).
        hasTorch = Self.detectTorch()
        planTracker.reset()
        // mapa głębi LiDAR-a: z niej powstaje dokładna chmura (DepthFusion).
        // Koszt jest znikomy, a bez tego ARKit w ogóle nie wypełnia sceneDepth.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            cfg.frameSemantics.insert(.sceneDepth)
        }

        depthStore.reset()
        session.delegate = self
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        #else
        trackingState = "Tylko na iPadzie"
        #endif
    }

    public func stop() {
        #if os(iOS)
        session.pause()
        setTorch(false)
        #endif
        isRunning = false
    }

    // MARK: - latarka

    /// Włącza/wyłącza latarkę.
    ///
    /// Latarka to NIE element ARKit — ARKit tylko czyta kamerę. Sprzętową lampę
    /// ustawia się przez `AVCaptureDevice.torchMode` na urządzeniu kamery.
    ///
    /// Po co: LiDAR mierzy światło odbite, więc w ciemnej kuchni mapa głębi ma
    /// dziury (szczególnie pod szafkami i w narożnikach). Doświetlenie lampą
    /// wyraźnie poprawia pokrycie — kosztem tego, że błyszczące fronty odbijają
    /// światło wprost do czujnika i w tych miejscach pomiar nadal wypada.
    /// Czy jest lampa błyskowa (bez tego przycisk latarki nie ma sensu).
    public static func detectTorch() -> Bool {
        #if os(iOS)
        return AVCaptureDevice.default(for: .video)?.hasTorch ?? false
        #else
        return false
        #endif
    }

    public func setTorch(_ on: Bool) {
        #if os(iOS)
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            torchOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            if on {
                // poziom 0,6 — pełna moc przepala bliskie ściany i daje odblaski
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel * 0.6)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
        #else
        torchOn = false
        #endif
    }

    /// Przełącza latarkę.
    public func toggleTorch() { setTorch(!torchOn) }

    public func reset() {
        #if os(iOS)
        meshAnchors.removeAll()
        lastStatsUpdate = .distantPast
        depthStore.reset()
        if let cfg = session.configuration as? ARWorldTrackingConfiguration {
            session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        } else {
            start()
        }
        #endif
        meshAnchorCount = 0
        estimatedPoints = 0
        coverageText = "—"
        boundsText = "—"
        depthFrames = 0
        fusedVoxels = 0
        precisionText = "—"
        ceilingHeight = nil
        liveOutline = []
        planPoints = 0
        outlineAreaText = "—"
        planFrameCounter = 0
        planTracker.reset()
    }

    /// licznik klatek dla trackera planu (dzielenie modulo w delegate)
    nonisolated(unsafe) private var planFrameCounter: UInt64 = 0
    /// poziom podłogi przyjęty dla trackera (aktualizowany ze statystyk)
    nonisolated(unsafe) public private(set) var trackedFloorY: Float = 0

    /// czy jest co eksportować.
    public var hasScan: Bool {
        #if os(iOS)
        if !meshAnchors.isEmpty { return true }
        return depthStore.stats().hasData
        #else
        return false
        #endif
    }

    // MARK: - budowa chmury

    /// Buduje chmurę punktów z aktualnych siatek.
    ///
    /// MUSI wykonać się na MainActor — buforów Metal z ARKit nie wolno czytać
    /// z innego wątku. Próbkowanie (czysta matematyka) można puścić w tło,
    /// dlatego rozdzielone jest na dwie funkcje: `collectTriangles()` tutaj
    /// i `MeshSampler.sample(...)` wywoływane przez wołającego w tle.
    public func collectTriangles() -> [ScanTriangle] {
        #if os(iOS)
        var out: [ScanTriangle] = []
        for (_, anchor) in meshAnchors {
            let mesh = anchor.geometry
            let vertexCount = mesh.vertices.count
            let faceCount = mesh.faces.count
            guard vertexCount > 0, faceCount > 0 else { continue }
            guard vertexCount <= Int(UInt32.max) else { continue }

            let access = MeshGeometryAccess(vertices: mesh.vertices)
            let transform = anchor.transform
            let faces = mesh.faces

            for f in 0..<faceCount {
                let idx = faces.faceIndices(at: f)
                guard idx.0 < UInt32(vertexCount),
                      idx.1 < UInt32(vertexCount),
                      idx.2 < UInt32(vertexCount) else { continue }

                let a = access.world(at: idx.0, transform: transform)
                let b = access.world(at: idx.1, transform: transform)
                let c = access.world(at: idx.2, transform: transform)
                guard a.x.isFinite, b.x.isFinite, c.x.isFinite else { continue }

                // kolor z geometrii, nie z ARMeshClassification (patrz SurfaceClassifier)
                let n = MeshSampler.normal(a, b, c)
                let centroidY = (a.y + b.y + c.y) / 3
                let color = n.map {
                    SurfaceClassifier.color(normal: $0, centroidY: centroidY, ceilingY: ceilingHeight)
                } ?? SurfaceClassifier.otherColor
                out.append(ScanTriangle(a: a, b: b, c: c, color: color))
            }
        }
        return out
        #else
        return []
        #endif
    }

    /// Statystyki dla UI — bez budowania całej chmury (zbyt drogie co klatkę).
    private func refreshStats(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStatsUpdate) > 0.4 else { return }
        lastStatsUpdate = now

        #if os(iOS)
        meshAnchorCount = meshAnchors.count

        // fuzja głębi ma pierwszeństwo w statystykach: to ona daje wynik
        let depth = depthStore.stats()
        depthFrames = depth.frames
        fusedVoxels = depth.voxels
        precisionText = depth.hasData ? String(format: "%.1f mm", depth.medianSigma * 1000) : "—"

        guard !meshAnchors.isEmpty else {
            // brak siatki, ale jest głębia — pokazujemy przynajmniej to
            if let b = depth.bounds {
                let s = b.max - b.min
                boundsText = String(format: "%.2f × %.2f × %.2f m", s.x, s.y, s.z)
                ceilingHeight = (s.y > 2.0 && s.y < 4.5) ? b.max.y : nil
            }
            estimatedPoints = depth.voxels
            coverageText = "—"
            if !depth.hasData {
                boundsText = "—"
                ceilingHeight = nil
            }
            return
        }

        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var totalArea: Double = 0
        let cell = Double(Swift.max(sampleStep, 0.005))

        for (_, anchor) in meshAnchors {
            let mesh = anchor.geometry
            let access = MeshGeometryAccess(vertices: mesh.vertices)
            let count = mesh.vertices.count

            // obrys: wystarczy co któryś wierzchołek
            let vs = Swift.max(1, count / 200)
            for i in Swift.stride(from: 0, to: count, by: vs) {
                let p = access.world(at: UInt32(i), transform: anchor.transform)
                if p.x.isFinite && p.y.isFinite && p.z.isFinite {
                    lo = simd_min(lo, p)
                    hi = simd_max(hi, p)
                }
            }

            // pole powierzchni: co któryś trójkąt × krok
            let faces = mesh.faces
            let fs = Swift.max(1, faces.count / 400)
            for f in Swift.stride(from: 0, to: faces.count, by: fs) {
                let idx = faces.faceIndices(at: f)
                guard idx.0 < UInt32(count), idx.1 < UInt32(count), idx.2 < UInt32(count) else { continue }
                let a = access.world(at: idx.0, transform: anchor.transform)
                let b = access.world(at: idx.1, transform: anchor.transform)
                let c = access.world(at: idx.2, transform: anchor.transform)
                let ar = Double(simd_length(simd_cross(b - a, c - a)) * 0.5)
                if ar.isFinite { totalArea += ar * Double(fs) }
            }
        }

        if lo.x <= hi.x {
            let s = hi - lo
            boundsText = String(format: "%.2f × %.2f × %.2f m", s.x, s.y, s.z)
            // sensowna wysokość pomieszczenia to 2.0–4.5 m
            ceilingHeight = (s.y > 2.0 && s.y < 4.5) ? hi.y : nil
        }
        coverageText = String(format: "%.1f m²", totalArea)
        estimatedPoints = Int(totalArea / (cell * cell))

        // kontur na żywo: tracker liczy w tle, my tylko odbieramy gotowy wynik
        if let snap = planTracker.refreshIfNeeded(minInterval: 1.2) {
            liveOutline = snap.outline
            planPoints = snap.points
            if snap.area > 0.5 {
                outlineAreaText = String(format: "%.2f m²", snap.area)
            }
        } else if liveOutline.isEmpty {
            planPoints = planTracker.pointCount
        }
        #endif
    }
}

#if os(iOS)

/// Dostęp do surowych buforów siatki ARKit.
///
/// `ARGeometrySource` to bufor Metal — trzeba czytać przez wskaźnik
/// z uwzględnieniem `offset` i `stride`. Bez tego odczyt „w locie" daje
/// śmieci, a przy `stride` != 12 (typowe dla ARKit) indeksowanie wprost
/// trafia w złe bajty.
private struct MeshGeometryAccess {
    let base: UnsafeMutableRawPointer
    let offset: Int
    let stride: Int

    init(vertices: ARGeometrySource) {
        self.base = vertices.buffer.contents()
        self.offset = vertices.offset
        self.stride = vertices.stride
    }

    func world(at index: UInt32, transform: simd_float4x4) -> SIMD3<Float> {
        let ptr = base.advanced(by: offset + stride * Int(index))
        let v = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        let w = transform * SIMD4<Float>(v.x, v.y, v.z, 1)
        return SIMD3<Float>(w.x, w.y, w.z)
    }
}

private extension ARGeometryElement {
    /// Odczyt trzech indeksów trójkąta. `bytesPerIndex` bywa 2 lub 4 bajty.
    func faceIndices(at index: Int) -> (UInt32, UInt32, UInt32) {
        let step = bytesPerIndex
        let ptr = buffer.contents().advanced(by: index * step * 3)
        if step == 4 {
            let p = ptr.assumingMemoryBound(to: UInt32.self)
            return (p[0], p[1], p[2])
        } else {
            let p = ptr.assumingMemoryBound(to: UInt16.self)
            return (UInt32(p[0]), UInt32(p[1]), UInt32(p[2]))
        }
    }
}

// MARK: - ARSessionDelegate

extension RoomScanSession: ARSessionDelegate {

    nonisolated public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Fuzja mapy głębi — dokładnie tu, bo to jedyne miejsce, gdzie ARKit
        // daje `sceneDepth`. Bramka `claim` odsiewa klatki szybciej niż 30/s:
        // konwersja kosztuje ~350 kB alokacji i 50 tys. odczytów koloru.
        if depthStore.claim(timestamp: frame.timestamp),
           let depthFrame = ARDepthConverter.depthFrame(from: frame) {
            depthStore.add(depthFrame)
        }

        // Kontur na żywo: karmimy tracker punktami mapy głębi (co ~5 klatkę).
        // Bierzemy je właśnie stąd, a nie z siatki, bo mapa głębi jest gęsta
        // (256×192 na klatkę) i ma realną geometrię ścian — z siatki ARKit
        // (komórki 5–10 cm) kontur byłby widoczny dopiero po minucie.
        planFrameCounter &+= 1
        if planFrameCounter % 5 == 0,
           let depthFrame = ARDepthConverter.depthFrame(from: frame) {
            planTracker.add(points: depthFrame.positions(step: 2), floorY: trackedFloorY)
        }

        let state: String
        switch frame.camera.trackingState {
        case .normal: state = "OK"
        case .notAvailable: state = "brak śledzenia"
        case .limited(let reason):
            switch reason {
            case .initializing: state = "start kamery…"
            case .excessiveMotion: state = "za szybko"
            case .insufficientFeatures: state = "za mało szczegółów"
            case .relocalizing: state = "wznawianie"
            @unknown default: state = "ograniczone"
            }
        @unknown default: state = "?"
        }
        Task { @MainActor in
            self.trackingState = state
            self.refreshStats()
        }
    }

    nonisolated public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        storeMeshAnchors(anchors)
    }

    nonisolated public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        storeMeshAnchors(anchors)
    }

    nonisolated public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier }
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            for id in ids { self.meshAnchors.removeValue(forKey: id) }
            self.refreshStats(force: true)
        }
    }

    /// Podmienia siatki w słowniku — nowsza wersja anchora wypiera starszą.
    /// Dzięki temu chmura liczy się zawsze z najświeższego stanu sceny,
    /// a nie z historii wszystkich klatek.
    private nonisolated func storeMeshAnchors(_ anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        Task { @MainActor in
            for anchor in meshes {
                self.meshAnchors[anchor.identifier] = anchor
            }
            self.refreshStats()
        }
    }
}

#endif
