import Foundation
import RealityKit
import simd

/// Poziom szczegółów zależny od odległości od kamery.
///
/// Zasada: blisko — pełny model (tysiące kart liści), dalej — pień + kilka
/// kart sylwetki, bardzo daleko — nic (sylwetkę zastępuje pierścień lasu).
/// Działa na encjach nazwanych `lod-tree-N`, które mają dzieci `lod0`/`lod1`.
@MainActor
public enum DetailLOD {

    /// Dystans [m], do którego drzewo pokazuje pełny model.
    public static var fullDetailDistance: Float = 62
    /// Dystans [m], po którym drzewo jest całkiem ukryte.
    public static var hideDistance: Float = 420

    public enum Level: Int, Sendable {
        case full, proxy, hidden
    }

    /// Który poziom szczegółów dla danej odległości [m].
    public static func level(distance: Float) -> Level {
        if distance < fullDetailDistance { return .full }
        if distance < hideDistance { return .proxy }
        return .hidden
    }

    /// Przełącza poziomy szczegółów. Tanio: tylko porównania odległości
    /// i `isEnabled`, bez przebudowy sceny.
    public static func update(root: Entity, cameraPosition: SIMD3<Float>) {
        for tree in root.children {
            guard tree.name.hasPrefix("lod-tree-") else { continue }
            let distance = simd_length(tree.position(relativeTo: nil) - cameraPosition)

            let full = tree.children.first { $0.name == "lod0" }
            let proxy = tree.children.first { $0.name == "lod1" }

            switch level(distance: distance) {
            case .full:
                full?.isEnabled = true
                proxy?.isEnabled = false
            case .proxy:
                full?.isEnabled = false
                proxy?.isEnabled = true
            case .hidden:
                full?.isEnabled = false
                proxy?.isEnabled = false
            }
        }
    }

    /// Liczba drzew w każdym trybie — do diagnostyki i testów.
    public static func census(root: Entity, cameraPosition: SIMD3<Float>) -> (full: Int, proxy: Int, hidden: Int) {
        var full = 0, proxy = 0, hidden = 0
        for tree in root.children where tree.name.hasPrefix("lod-tree-") {
            let distance = simd_length(tree.position(relativeTo: nil) - cameraPosition)
            if distance < fullDetailDistance { full += 1 }
            else if distance < hideDistance { proxy += 1 }
            else { hidden += 1 }
        }
        return (full, proxy, hidden)
    }
}
