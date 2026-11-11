import SwiftUI
import ARKit
import SceneKit

#if os(iOS)

/// Podgląd kamery AR z siatką rekonstrukcji rysowaną przez nas.
///
/// UWAGA: `ARSCNDebugOptions.showSceneUnderstanding` zostało USUNIĘTE
/// z ARKit (iOS 26/27 SDK ma tylko `showWorldOrigin` i `showFeaturePoints`).
/// Dlatego budujemy SCNGeometry wprost z `ARMeshAnchor` w delegate —
/// widać realną siatkę pomieszczenia, a nie tylko punkty cech ARKit.
struct RoomScanPreview: UIViewRepresentable {
    let session: ARSession
    var showMesh: Bool = true
    /// Kontur pomieszczenia rozpoznany na żywo (plan, XZ w metrach).
    var outline: [SIMD2<Float>] = []

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 60
        // punkty cech są tanie i dają natychmiastowy sygnał „coś widzę"
        view.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
        context.coordinator.showMesh = showMesh
        for (_, node) in context.coordinator.meshNodes {
            node.isHidden = !showMesh
        }
        // kontur rysujemy na wysokości oczu, żeby był widoczny w podglądzie:
        // geometria jest w planie (y = 0), a kamera patrzy poziomo
        context.coordinator.updateOutline(outline, in: uiView)
    }

    func makeCoordinator() -> MeshCoordinator {
        MeshCoordinator(showMesh: showMesh)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: MeshCoordinator) {
        uiView.session.pause()
        uiView.delegate = nil
    }
}

/// Rysuje i aktualizuje siatkę rekonstrukcji w scenie.
///
/// ARKit dostarcza `ARMeshAnchor` przyrostowo: najpierw `didAdd`, potem
/// `didUpdate` z poprawioną geometrią. Podmieniamy geometrię noda, nie
/// dodajemy nowego — inaczej scena zapełnia się duplikatami i migocze.
final class MeshCoordinator: NSObject, ARSCNViewDelegate {
    var showMesh: Bool
    private(set) var meshNodes: [UUID: SCNNode] = [:]
    /// node z konturem (jeden, przebudowywany przy zmianie)
    private var outlineNode: SCNNode?

    init(showMesh: Bool) {
        self.showMesh = showMesh
    }

    /// Rysuje kontur pomieszczenia jako zamkniętą linię.
    ///
    /// Kontur jest w planie (y = 0), ale na podłodze byłby niewidoczny, bo
    /// kamera patrzy poziomo. Podnosimy go do 1,0 m — na wysokość pasa, gdzie
    /// użytkownik i tak prowadzi iPada, więc linie są widoczne na tle ścian.
    func updateOutline(_ outline: [SIMD2<Float>], in view: ARSCNView) {
        outlineNode?.removeFromParentNode()
        outlineNode = nil
        guard outline.count >= 3 else { return }

        let level: Float = 1.0
        var verts: [SCNVector3] = outline.map {
            SCNVector3($0.x, level, $0.y)
        }
        // zamknij pętlę
        if let first = verts.first { verts.append(first) }

        let source = SCNGeometrySource(vertices: verts)
        var indices: [Int32] = []
        for i in 0..<(verts.count - 1) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "room-outline"
        // linie zawsze na wierzchu — inaczej chowają się w siatce
        node.renderingOrder = 100
        material.readsFromDepthBuffer = false
        view.scene.rootNode.addChildNode(node)
        outlineNode = node
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
        let node = SCNNode()
        node.name = "mesh-\(anchor.identifier)"
        node.geometry = Self.geometry(from: meshAnchor.geometry)
        node.isHidden = !showMesh
        meshNodes[anchor.identifier] = node
        return node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        node.geometry = Self.geometry(from: meshAnchor.geometry)
        node.isHidden = !showMesh
        meshNodes[anchor.identifier] = node
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        meshNodes.removeValue(forKey: anchor.identifier)
    }

    /// Buduje SCNGeometry z ARMeshGeometry, szanując offset i stride buforów.
    static func geometry(from mesh: ARMeshGeometry) -> SCNGeometry? {
        let vertexCount = mesh.vertices.count
        guard vertexCount > 0, mesh.faces.count > 0 else { return nil }

        var vertices = [SCNVector3](repeating: SCNVector3Zero, count: vertexCount)
        let vBase = mesh.vertices.buffer.contents()
        let vStride = mesh.vertices.stride
        let vOffset = mesh.vertices.offset
        for i in 0..<vertexCount {
            let ptr = vBase.advanced(by: vOffset + vStride * i)
            let v = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            vertices[i] = SCNVector3(v.x, v.y, v.z)
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)

        var normals = [SCNVector3](repeating: SCNVector3Zero, count: vertexCount)
        let nBase = mesh.normals.buffer.contents()
        let nStride = mesh.normals.stride
        let nOffset = mesh.normals.offset
        for i in 0..<vertexCount {
            let ptr = nBase.advanced(by: nOffset + nStride * i)
            let n = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            normals[i] = SCNVector3(n.x, n.y, n.z)
        }
        let normalSource = SCNGeometrySource(normals: normals)

        let faceCount = mesh.faces.count
        let bytesPerIndex = mesh.faces.bytesPerIndex
        let facesBase = mesh.faces.buffer.contents()
        var indices = [Int32](repeating: 0, count: faceCount * 3)
        for f in 0..<faceCount {
            let base = facesBase.advanced(by: f * bytesPerIndex * 3)
            for k in 0..<3 {
                let idx: UInt32
                if bytesPerIndex == 4 {
                    idx = base.advanced(by: k * 4).assumingMemoryBound(to: UInt32.self).pointee
                } else {
                    idx = UInt32(base.advanced(by: k * 2).assumingMemoryBound(to: UInt16.self).pointee)
                }
                indices[f * 3 + k] = Int32(idx)
            }
        }
        // primitiveCount jest wyliczany z liczby indeksów — nie ustawiamy go ręcznie
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        // półprzezroczysty: siatka pokazuje pokrycie, nie zasłania kamery
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.35, green: 0.85, blue: 0.6, alpha: 1.0)
        material.isDoubleSided = true
        material.transparency = 0.38
        material.writesToDepthBuffer = false
        geometry.materials = [material]

        return geometry
    }
}

#endif
