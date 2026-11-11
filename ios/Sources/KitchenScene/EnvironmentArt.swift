import Foundation
import CoreGraphics
import RealityKit
import KitchenScene

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Proceduralne tekstury i środowisko świetlne (IBL).
///
/// Bez pobierania plików: kolor + szum generowany w CoreGraphics, więc
/// aplikacja działa offline i waży tyle, ile kod.
public enum EnvironmentArt {

    // MARK: - pomocnicze

    static func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(ctx)
        return ctx.makeImage()
    }

    static func noise(_ ctx: CGContext, width: Int, height: Int, count: Int, alpha: CGFloat, size: ClosedRange<Int>) {
        for _ in 0..<count {
            let x = CGFloat.random(in: 0..<CGFloat(width))
            let y = CGFloat.random(in: 0..<CGFloat(height))
            let s = CGFloat(Int.random(in: size))
            let v = CGFloat.random(in: 0.7...1.0)
            ctx.setFillColor(CGColor(gray: v, alpha: alpha))
            ctx.fill(CGRect(x: x, y: y, width: s, height: s))
        }
    }

    // MARK: - tekstury

    /// Trawa: zielona baza + drobne źdźbła.
    public static func grass(seed: UInt64 = 1) -> TextureResource? {
        let size = 512
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.30, green: 0.42, blue: 0.22, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<9000 {
                let x = CGFloat.random(in: 0..<CGFloat(size))
                let y = CGFloat.random(in: 0..<CGFloat(size))
                let h = CGFloat.random(in: 2...9)
                let shade = CGFloat.random(in: 0.6...1.15)
                ctx.setStrokeColor(CGColor(red: 0.24 * shade, green: 0.40 * shade, blue: 0.18 * shade, alpha: 0.85))
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -2...2), y: y + h))
                ctx.strokePath()
            }
        }) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Kostka brukowa: siatka kostek z fugami.
    public static func cobble() -> TextureResource? {
        let size = 512
        let cell = 64
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.36, green: 0.36, blue: 0.35, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for row in 0..<(size / cell) {
                for col in 0..<(size / cell) {
                    let offset = row % 2 == 0 ? 0 : cell / 2
                    let x = col * cell + offset
                    let y = row * cell
                    let shade = CGFloat.random(in: 0.78...1.05)
                    ctx.setFillColor(CGColor(red: 0.46 * shade, green: 0.45 * shade, blue: 0.43 * shade, alpha: 1))
                    let inset: CGFloat = 3
                    ctx.fill(CGRect(x: CGFloat(x) + inset, y: CGFloat(y) + inset,
                                    width: CGFloat(cell) - inset * 2, height: CGFloat(cell) - inset * 2))
                }
            }
            self.noise(ctx, width: size, height: size, count: 4000, alpha: 0.10, size: 1...3)
        }) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Kora: pionowe smugi.
    public static func bark() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.26, green: 0.19, blue: 0.13, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<420 {
                let x = CGFloat.random(in: 0..<CGFloat(size))
                let shade = CGFloat.random(in: 0.6...1.2)
                ctx.setStrokeColor(CGColor(red: 0.20 * shade, green: 0.14 * shade, blue: 0.09 * shade, alpha: 0.9))
                ctx.setLineWidth(CGFloat.random(in: 1...3))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -4...4), y: CGFloat(size)))
                ctx.strokePath()
            }
        }) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    /// Tynk elewacji: jednolity z ziarnem.
    public static func plaster() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.88, green: 0.86, blue: 0.81, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            self.noise(ctx, width: size, height: size, count: 6000, alpha: 0.12, size: 1...3)
        }) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }

    // MARK: - środowisko (IBL)

    /// Equirectangular skybox: gradient nieba + słońce + pas mgły przy horyzoncie.
    public static func skyEquirect() -> CGImage? {
        let width = 1024, height = 512
        return makeImage(width: width, height: height, draw: { ctx in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                CGColor(red: 0.16, green: 0.34, blue: 0.62, alpha: 1),
                CGColor(red: 0.34, green: 0.55, blue: 0.80, alpha: 1),
                CGColor(red: 0.68, green: 0.78, blue: 0.86, alpha: 1),
                CGColor(red: 0.90, green: 0.90, blue: 0.86, alpha: 1),
                CGColor(red: 0.42, green: 0.44, blue: 0.38, alpha: 1),
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.34, 0.52, 0.62, 1]) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: height),
                    end: CGPoint(x: 0, y: 0),
                    options: []
                )
            }
            // słońce nisko nad horyzontem (ciepły rozbłysk)
            let sunX = CGFloat(width) * 0.72
            let sunY = CGFloat(height) * 0.58
            if let glow = CGGradient(colorsSpace: colorSpace, colors: [
                CGColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1.0),
                CGColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 0.35),
                CGColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 0.0),
            ] as CFArray, locations: [0, 0.25, 1]) {
                ctx.drawRadialGradient(
                    glow,
                    startCenter: CGPoint(x: sunX, y: sunY), startRadius: 2,
                    endCenter: CGPoint(x: sunX, y: sunY), endRadius: CGFloat(height) * 0.42,
                    options: []
                )
            }
        })
    }

    /// Zasób środowiska do świateł IBL (RealityKit bierze z niego odbicia i światło otoczenia).
    @MainActor
    public static func environmentResource() async -> EnvironmentResource? {
        guard let image = skyEquirect() else { return nil }
        return try? await EnvironmentResource(equirectangular: image)
    }
}
