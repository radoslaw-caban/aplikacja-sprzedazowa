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

    /// Narastające granice całej siatki — z nich liczymy środek pomieszczenia.
    private var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    private var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    /// Punkt uznawany za wnętrze pomieszczenia.
    ///
    /// DLACZEGO NIE POZYCJA KAMERY: gdy użytkownik wyjdzie z pomieszczenia,
    /// cullowanie odwróciłoby się i ściany znów byłyby widoczne od zewnątrz —
    /// czyli problem wracał dokładnie wtedy, gdy się go zauważa. Środek
    /// narastających granic siatki jest stabilny i leży wewnątrz pomieszczenia
    /// niezależnie od tego, gdzie stoi iPad.
    var roomCenter: SIMD3<Float> {
        guard boundsMin.x <= boundsMax.x else { return .zero }
        return (boundsMin + boundsMax) / 2
    }

    /// Aktualizuje granice siatki o wierzchołki anchora (co N-ty — wystarczy).
    private func accumulateBounds(of anchor: ARMeshAnchor) {
        let mesh = anchor.geometry
        let count = mesh.vertices.count
        guard count > 0 else { return }
        let base = mesh.vertices.buffer.contents()
        let stride = mesh.vertices.stride
        let offset = mesh.vertices.offset
        let transform = anchor.transform
        let step = Swift.max(1, count / 400)
        for i in Swift.stride(from: 0, to: count, by: step) {
            let ptr = base.advanced(by: offset + stride * i)
            let v = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let world = transform * SIMD4<Float>(v, 1)
            let p = SIMD3<Float>(world.x, world.y, world.z)
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
            boundsMin = simd_min(boundsMin, p)
            boundsMax = simd_max(boundsMax, p)
        }
    }

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
        accumulateBounds(of: meshAnchor)
        node.geometry = Self.geometry(from: meshAnchor.geometry, inside: roomCenter)
        node.isHidden = !showMesh
        meshNodes[anchor.identifier] = node
        return node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        accumulateBounds(of: meshAnchor)
        node.geometry = Self.geometry(from: meshAnchor.geometry, inside: roomCenter)
        node.isHidden = !showMesh
        meshNodes[anchor.identifier] = node
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        meshNodes.removeValue(forKey: anchor.identifier)
    }

    /// Buduje SCNGeometry z ARMeshGeometry, szanując offset i stride buforów.
    ///
    /// - Parameter inside: punkt WEWNĄTRZ pomieszczenia (np. pozycja kamery).
    ///   Trójkąty są orientowane tak, żeby ich strona przednia była zwrócona
    ///   do tego punktu. ARKit nie gwarantuje spójnego kierunku trójkątów
    ///   (już raz nas to spotkało przy klasyfikacji powierzchni — podłoga
    ///   i sufit wychodziły zamienione), więc zamiast ufać kolejności
    ///   wierzchołków, liczymy ją sami z pozycji.
    static func geometry(from mesh: ARMeshGeometry,
                         inside: SIMD3<Float>? = nil) -> SCNGeometry? {
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
        // ORIENTACJA TRÓJKĄTÓW: strona przednia do wnętrza pomieszczenia.
        //
        // ARKit nie gwarantuje spójnego kierunku trójkątów, więc przy
        // `isDoubleSided = false` połowa ścian znikałaby losowo. Liczymy
        // orientację sami: jeśli wektor normalny trójkąta (iloczyn wektorowy)
        // wskazuje NA ZEWNĄTRZ (od punktu `inside`), zamieniamy dwa wierzchołki.
        // Dzięki temu cullMode działa przewidywalnie i ściany widziane od
        // zewnątrz nie zasłaniają obrazu kamery.
        if let inside = inside {
            for f in 0..<faceCount {
                let i0 = Int(indices[f * 3])
                let i1 = Int(indices[f * 3 + 1])
                let i2 = Int(indices[f * 3 + 2])
                guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else { continue }
                let p0 = SIMD3<Float>(vertices[i0].x, vertices[i0].y, vertices[i0].z)
                let p1 = SIMD3<Float>(vertices[i1].x, vertices[i1].y, vertices[i1].z)
                let p2 = SIMD3<Float>(vertices[i2].x, vertices[i2].y, vertices[i2].z)

                let centroid = (p0 + p1 + p2) / 3
                let geoNormal = simd_cross(p1 - p0, p2 - p0)
                let toInside = inside - centroid
                // normalna „na zewnątrz" = zgodna z kierunkiem od środka pomieszczenia
                if simd_dot(geoNormal, toInside) > 0 {
                    indices[f * 3 + 1] = Int32(i2)
                    indices[f * 3 + 2] = Int32(i1)
                }
            }
        }

        // primitiveCount jest wyliczany z liczby indeksów — nie ustawiamy go ręcznie
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        // PÓŁPRZEZROCZYSTA, ALE JEDNOSTRONNA.
        //
        // `isDoubleSided = true` powodowało, że ściana widziana od ZEWNĄTRZ (czyli
        // gdy stoisz poza pomieszczeniem albo patrzysz przez podłogę) była
        // renderowana tak samo jak od środka — siatka wyglądała jak szkło
        // i zasłaniała obraz kamery tym, co jest za nią.
        //
        // `cullMode = .front` zostawia tylko powierzchnie zwrócone DO KAMERY
        // wewnątrz pomieszczenia. ARKit buduje siatkę tak, że trójkąty mają
        // stronę wewnętrzną zgodną z normalną, więc stojąc w środku widzisz
        // ściany, a z zewnątrz widzisz przez nie (kamera widzi realny pokój).
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.35, green: 0.85, blue: 0.6, alpha: 1.0)
        material.isDoubleSided = false
        material.cullMode = .back
        material.transparency = 0.38
        material.writesToDepthBuffer = false
        geometry.materials = [material]

        return geometry
    }
}

#endif
