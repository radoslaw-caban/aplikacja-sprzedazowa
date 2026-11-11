import Foundation
import RealityKit
import KitchenCore

#if os(iOS)
import UIKit
public typealias CloudColor = UIColor
#else
import AppKit
public typealias CloudColor = NSColor
#endif

/// Chmura punktów ze skanu, ustawiona DOKŁADNIE w układzie zbudowanego domu.
///
/// Służy do sprawdzenia dopasowania: ściany z `ScanPlan` muszą pokrywać się
/// z rzeczywistymi punktami. Transformacja jest ta sama, której użył
/// `tools/scan_to_plan.py` — pion chmury (Z) trafia w Y sceny, plan jest
/// wyśrodkowany na `center` i oparty na poziomie `floor`.
@MainActor
public enum ScanCloudOverlay {

    /// Plik ze skanem dołączony do aplikacji (fallback: katalog repo).
    public static func bundledCloudURL() -> URL? {
        if let url = Bundle.main.url(forResource: "dom-chmura", withExtension: "ply") {
            return url
        }
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("dom-chmura.ply") {
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in ["../app/public/dom-chmura.ply", "app/public/dom-chmura.ply"] {
            let url = cwd.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Wczytuje chmurę i przelicza ją do układu sceny (metry).
    /// Zwraca nil, jeśli pliku nie ma albo parser nie da rady.
    public static func loadSceneCloud(plan: ScanPlan, maxPoints: Int = 260_000) -> PointCloud? {
        guard let url = bundledCloudURL(),
              let data = try? Data(contentsOf: url),
              let cloud = try? PLYParser.parse(data: data) else { return nil }

        let scale = cloud.unitScaleToMeters
        let decimated = cloud.decimated(maxPoints: maxPoints)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(decimated.count)
        for p in decimated.positions {
            positions.append(plan.scenePoint(p * scale))
        }
        let colors = decimated.colors
        return PointCloud(positions: positions, colors: colors)
    }

    /// Encja chmury w układzie domu — bez dodatkowego centrowania.
    public static func entity(plan: ScanPlan, maxPoints: Int = 260_000) -> Entity {
        let root = Entity()
        root.name = "scan-overlay"
        guard let cloud = loadSceneCloud(plan: plan, maxPoints: maxPoints) else { return root }

        // Własna siatka "points": PointCloudRenderer.pointMesh ustawia krok
        // wierzchołka na 12 B, a SIMD3<Float> w Swift ma 16 B — stąd asercja
        // przy wiązaniu bufora i crash. Tu krok jest wzięty z MemoryLayout.
        let points = cloud.positions
        let stride = MemoryLayout<SIMD3<Float>>.stride
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = points.count
        descriptor.indexCapacity = points.count
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0)
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: stride)
        ]

        guard let lowLevel = try? LowLevelMesh(descriptor: descriptor) else { return root }
        lowLevel.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let bound = raw.bindMemory(to: SIMD3<Float>.self)
            for i in 0..<points.count { bound[i] = points[i] }
        }
        lowLevel.withUnsafeMutableIndices { raw in
            let idx = raw.bindMemory(to: UInt32.self)
            for i in 0..<points.count { idx[i] = UInt32(i) }
        }
        var lo = points[0], hi = points[0]
        for p in points {
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        lowLevel.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0, indexCount: points.count,
                              topology: .point, materialIndex: 0,
                              bounds: BoundingBox(min: lo, max: hi))
        ])
        guard let mesh = try? MeshResource(from: lowLevel) else { return root }

        var material = UnlitMaterial()
        material.color = .init(tint: CloudColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        material.faceCulling = .none

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "scan-points"
        root.addChild(entity)
        return root
    }
}
