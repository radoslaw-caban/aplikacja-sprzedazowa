import Foundation
import simd
import KitchenCore

#if os(iOS)
import ARKit
import UIKit
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

    /// Czy urządzenie w ogóle ma LiDAR / wspiera rekonstrukcję sceny.
    public static var isSupported: Bool {
        #if os(iOS)
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            || ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
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
        #endif
        isRunning = false
    }

    public func reset() {
        #if os(iOS)
        meshAnchors.removeAll()
        lastStatsUpdate = .distantPast
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
        ceilingHeight = nil
    }

    /// Czy jest co eksportować.
    public var hasScan: Bool {
        #if os(iOS)
        return !meshAnchors.isEmpty
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
        guard !meshAnchors.isEmpty else {
            estimatedPoints = 0
            coverageText = "—"
            boundsText = "—"
            ceilingHeight = nil
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
