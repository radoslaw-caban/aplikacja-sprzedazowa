import Foundation
import CatalogCore
import SceneKit
import AppKit

/// Render miniatury modelu bez otwierania okna — wspólny dla CLI i aplikacji katalogu.
public enum ThumbnailRenderer {

    public static let defaultSize: CGFloat = 512

    /// Rysuje siatkę na przezroczystym tle i zapisuje PNG.
    @MainActor
    public static func render(mesh: TriMesh, to url: URL, size: CGFloat = defaultSize) throws {
        guard let bounds = mesh.bounds else { throw MeshError.corrupt("pusta siatka") }

        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let indices = mesh.indices.map { Int32($0) }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedWhite: 0.84, alpha: 1)
        material.metalness.contents = 0.18
        material.roughness.contents = 0.52
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.pivot = SCNMatrix4MakeTranslation(CGFloat(bounds.center.x), CGFloat(bounds.center.y), CGFloat(bounds.center.z))
        scene.rootNode.addChildNode(node)

        let maxDim = max(bounds.size.x, max(bounds.size.y, bounds.size.z))
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.005
        camera.zFar = 200
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance = CGFloat(max(0.35, maxDim * 2.15))
        cameraNode.position = SCNVector3(distance * 0.75, distance * 0.5, distance * 0.95)
        cameraNode.look(at: SCNVector3Zero, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.eulerAngles = SCNVector3(-0.9, 0.75, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 420
        fill.eulerAngles = SCNVector3(-0.35, -1.9, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 280
        scene.rootNode.addChildNode(ambient)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let image = renderer.snapshot(atTime: 0,
                                      with: CGSize(width: size, height: size),
                                      antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw MeshError.corrupt("nie udało się wyrenderować miniatury")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
    }

    /// Wczytuje model z zasobu produktu i rysuje miniaturę obok `product.json`.
    @MainActor
    @discardableResult
    public static func renderThumbnail(for product: inout CatalogProduct,
                                       store: CatalogStore) throws -> URL {
        guard let asset = product.modelAsset else { throw MeshError.corrupt("brak modelu") }
        let source = store.assetURL(product, asset: asset)
        let mesh = try MeshIO.load(url: source)
        let target = store.productDir(product.id).appendingPathComponent("thumb.png")
        try render(mesh: mesh, to: target)
        product.thumbnail = "thumb.png"
        product.updatedAt = Date()
        return target
    }
}
