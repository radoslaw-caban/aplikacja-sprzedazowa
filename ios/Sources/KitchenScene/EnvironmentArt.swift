import Foundation
import CoreGraphics
import ImageIO
import RealityKit

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

    @MainActor
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

    @MainActor
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
    /// Tekstura fotograficzna z paczki (Poly Haven, CC0).
    @MainActor
    public static func photoTexture(_ name: String, semantic: TextureResource.Semantic = .color) -> TextureResource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg",
                                        subdirectory: "Textures") ?? Bundle.main.url(forResource: name, withExtension: "jpg") else {
            return nil
        }
        return try? TextureResource.load(contentsOf: url, withName: name, options: .init(semantic: semantic))
    }

    @MainActor
    public static func grass(seed: UInt64 = 1) -> TextureResource? {
        if let photo = photoTexture("grass_diff") { return photo }
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
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Kostka brukowa: siatka kostek z fugami.
    @MainActor
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
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Kora: pionowe smugi.
    @MainActor
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
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Tynk elewacji: jednolity z ziarnem.
    @MainActor
    public static func plaster() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.88, green: 0.86, blue: 0.81, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            self.noise(ctx, width: size, height: size, count: 6000, alpha: 0.12, size: 1...3)
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Beton fundamentu: szary, z kruszywem i śladami szalunku.
    ///
    /// Fundament musi być widoczny jako inny materiał niż elewacja — inaczej
    /// dom „pływa" na trawie i nie wiadomo, gdzie kończy się budynek.
    @MainActor
    public static func concrete() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.52, green: 0.51, blue: 0.49, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // kruszywo
            for _ in 0..<7000 {
                let x = CGFloat.random(in: 0..<CGFloat(size))
                let y = CGFloat.random(in: 0..<CGFloat(size))
                let s = CGFloat.random(in: 1...3.5)
                let v = CGFloat.random(in: 0.42...0.72)
                ctx.setFillColor(CGColor(red: v, green: v * 0.99, blue: v * 0.96, alpha: 0.5))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
            }
            // ciemniejsze zacieki przy dole (wilgoć)
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                CGColor(red: 0.3, green: 0.3, blue: 0.28, alpha: 0.0),
                CGColor(red: 0.3, green: 0.3, blue: 0.28, alpha: 0.35),
            ] as CFArray, locations: [0.55, 1]) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size) * 0.5),
                                       end: CGPoint(x: 0, y: 0), options: [])
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Asfalt drogi: ciemny, drobnoziarnisty, z jaśniejszymi smugami zużycia.
    @MainActor
    public static func asphalt() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<12000 {
                let x = CGFloat.random(in: 0..<CGFloat(size))
                let y = CGFloat.random(in: 0..<CGFloat(size))
                let v = CGFloat.random(in: 0.18...0.42)
                ctx.setFillColor(CGColor(red: v, green: v, blue: v * 1.05, alpha: 0.55))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
            // smugi po kołach
            ctx.setStrokeColor(CGColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 0.35))
            ctx.setLineWidth(6)
            for x in [CGFloat(size) * 0.3, CGFloat(size) * 0.7] {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -3...3), y: CGFloat(size)))
                ctx.strokePath()
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Chmura: miękka biała plama z przezroczystym brzegiem.
    ///
    /// Alfa jest kluczowa — bez niej chmura to biała kartka na niebie.
    /// Kilka nałożonych kół o losowej alfa daje kłębiasty obrys.
    @MainActor
    public static func cloud() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<48 {
                let cx = CGFloat.random(in: CGFloat(size) * 0.2...CGFloat(size) * 0.8)
                let cy = CGFloat.random(in: CGFloat(size) * 0.3...CGFloat(size) * 0.7)
                let r = CGFloat.random(in: CGFloat(size) * 0.06...CGFloat(size) * 0.17)
                let a = CGFloat.random(in: 0.35...0.8)
                guard let blob = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    CGColor(red: 1, green: 1, blue: 1, alpha: a),
                    CGColor(red: 0.98, green: 0.98, blue: 1, alpha: a * 0.5),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                ] as CFArray, locations: [0, 0.55, 1]) else { continue }
                ctx.drawRadialGradient(blob, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Gęsta trawa: kępy źdźbeł z przezroczystym tłem — do billboardów.
    ///
    /// Sama tekstura podłoża nie daje wrażenia „gęstej trawy": z bliska widać
    /// płaski dywan. Dopiero kępy postawione w terenie dają wysokość i ruch
    /// światła jak na połoninie.
    @MainActor
    public static func grassBlades() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
            // kilkadziesiąt źdźbeł, gęsto u dołu
            for _ in 0..<70 {
                let x = CGFloat.random(in: 6...CGFloat(size) - 6)
                let h = CGFloat.random(in: CGFloat(size) * 0.45...CGFloat(size) * 0.95)
                let curl = CGFloat.random(in: -14...14)
                let shade = CGFloat.random(in: 0.55...1.0)
                ctx.setStrokeColor(CGColor(red: 0.42 * shade, green: 0.62 * shade, blue: 0.20 * shade, alpha: 1))
                ctx.setLineWidth(CGFloat.random(in: 1.6...3.2))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addQuadCurve(to: CGPoint(x: x + curl, y: h),
                                 control: CGPoint(x: x + curl * 1.6, y: h * 0.55))
                ctx.strokePath()
            }
            // żółte kwiaty — Bieszczady w czerwcu
            for _ in 0..<10 {
                let x = CGFloat.random(in: 10...CGFloat(size) - 10)
                let y = CGFloat.random(in: CGFloat(size) * 0.55...CGFloat(size) * 0.9)
                ctx.setFillColor(CGColor(red: 0.95, green: 0.87, blue: 0.35, alpha: 0.95))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Kępa liści: kilkadziesiąt drobnych listków na przezroczystym tle.
    /// Taka karta na końcu gałęzi czyta się jak korona — z bliska widać liście,
    /// z daleka masę zieleni z prześwitami.
    @MainActor
    public static func leafCluster() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<90 {
                let cx = CGFloat.random(in: CGFloat(size) * 0.15...CGFloat(size) * 0.85)
                let cy = CGFloat.random(in: CGFloat(size) * 0.15...CGFloat(size) * 0.85)
                let w = CGFloat.random(in: 10...26)
                let h = w * CGFloat.random(in: 0.55...0.95)
                let g = CGFloat.random(in: 0.55...1.0)
                ctx.setFillColor(CGColor(red: 0.24 + g * 0.22, green: 0.42 + g * 0.38, blue: 0.16 + g * 0.20, alpha: 1))
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: CGFloat.random(in: 0...6.28))
                ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                ctx.restoreGState()
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Kępa igliwia: cienkie, ciemne igły rozchodzące się z punktu.
    @MainActor
    public static func needleCluster() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
            let cx = CGFloat(size) / 2
            let cy = CGFloat(size) / 2
            for _ in 0..<220 {
                let angle = CGFloat.random(in: 0...6.28)
                let len = CGFloat.random(in: CGFloat(size) * 0.18...CGFloat(size) * 0.48)
                let g = CGFloat.random(in: 0.70...1.0)
                ctx.setStrokeColor(CGColor(red: 0.16 * g, green: 0.40 * g, blue: 0.20 * g, alpha: 1))
                ctx.setLineWidth(CGFloat.random(in: 1.2...2.4))
                ctx.move(to: CGPoint(x: cx + cos(angle) * 6, y: cy + sin(angle) * 6))
                ctx.addLine(to: CGPoint(x: cx + cos(angle) * len, y: cy + sin(angle) * len))
                ctx.strokePath()
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Kępa z kwiatami: źdźbła + kolorowe główki (biało-żółte, jak na połoninie).
    @MainActor
    public static func flowerCluster() -> TextureResource? {
        let size = 256
        guard let image = makeImage(width: size, height: size, draw: { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
            // źdźbła
            for _ in 0..<50 {
                let x = CGFloat.random(in: 8...CGFloat(size) - 8)
                let h = CGFloat.random(in: CGFloat(size) * 0.5...CGFloat(size) * 0.95)
                ctx.setStrokeColor(CGColor(red: 0.42, green: 0.60, blue: 0.22, alpha: 1))
                ctx.setLineWidth(CGFloat.random(in: 1.4...2.6))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -10...10), y: h))
                ctx.strokePath()
            }
            // główki kwiatów
            for _ in 0..<40 {
                let x = CGFloat.random(in: 10...CGFloat(size) - 10)
                let y = CGFloat.random(in: CGFloat(size) * 0.45...CGFloat(size) * 0.95)
                let r = CGFloat.random(in: 2.5...5.5)
                let roll = CGFloat.random(in: 0...1)
                let color: CGColor
                if roll < 0.55 {
                    color = CGColor(red: 0.98, green: 0.96, blue: 0.86, alpha: 1)      // biel
                } else if roll < 0.85 {
                    color = CGColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1)      // żółć
                } else {
                    color = CGColor(red: 0.74, green: 0.40, blue: 0.72, alpha: 1)      // fiolet
                }
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Tekstura koron lasu na wzgórzach: kępy ciemnej zieleni z prześwitami.
    ///
    /// Płaski kolor na tle czyta się jak zielona ściana. Dopiero drobna
    /// tekstura koron (kilkaset kół o różnej jasności) daje wrażenie, że to las
    /// pokrywający zbocze — tak jak na zdjęciach połonin.
    @MainActor
    public static func forestCanopy() -> TextureResource? {
        let width = 512, height = 128
        guard let image = makeImage(width: width, height: height, draw: { ctx in
            ctx.setFillColor(CGColor(red: 0.11, green: 0.20, blue: 0.13, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // korony drzew: gęste, drobne, o zmiennej jasności
            for _ in 0..<2600 {
                let x = CGFloat.random(in: 0..<CGFloat(width))
                let y = CGFloat.random(in: 0..<CGFloat(height))
                let r = CGFloat.random(in: 1.5...5.0)
                let g = CGFloat.random(in: 0.16...0.40)
                let b = CGFloat.random(in: 0.10...0.24)
                ctx.setFillColor(CGColor(red: 0.06 + g * 0.35, green: g, blue: b, alpha: 0.95))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            // pasy „łęgów" — jaśniejsze smugi w dolinach
            for _ in 0..<40 {
                let x = CGFloat.random(in: 0..<CGFloat(width))
                let w = CGFloat.random(in: 6...22)
                let alpha = CGFloat.random(in: 0.05...0.14)
                ctx.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.42, alpha: alpha))
                ctx.fill(CGRect(x: x, y: 0, width: w, height: CGFloat(height) * 0.55))
            }
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Panorama z pliku zdjęciowego, zszyta BEZ SZWU: obraz + jego lustrzane
    /// odbicie. Dzięki temu krawędź tekstury wypada w miejscu, gdzie obraz
    /// i odbicie są identyczne — na walcu nie widać łączenia.
    /// Wczytanie zdjęcia z bundle — przez ścieżkę pliku, bo `Bundle.url(forResource:)`
    /// nie znajduje plików wewnątrz referencji folderu na wszystkich systemach.
    @MainActor
    static func loadCGImage(named name: String) -> CGImage? {
        let path = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Textures")
            ?? Bundle.main.path(forResource: name, ofType: "jpg")
        guard let path else { return nil }
        #if os(iOS)
        return UIImage(contentsOfFile: path)?.cgImage
        #else
        return NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    @MainActor
    public static func panorama(fromImageNamed name: String) -> TextureResource? {
        guard let image = loadCGImage(named: name) else {
            print("[env] panorama: nie wczytano pliku \(name).jpg")
            return nil
        }

        // Przycinamy niebo ze zdjęcia: nasze niebo rysuje skybox, a jeśli
        // panorama wnosi własne chmury, na horyzoncie widać „drugie niebo".
        let cropTop = CGFloat(image.height) * 0.26
        let cropped = image.cropping(to: CGRect(x: 0, y: cropTop,
                                                width: CGFloat(image.width),
                                                height: CGFloat(image.height) - cropTop)) ?? image

        // SKALA: każda kopia 2048 px szerokości. Większa tekstura (8k x 2.8k)
        // przekracza limit i RealityKit jej nie wczyta — panorama wtedy
        // w ogóle się nie rysuje.
        let copyWidth = 2048
        let copyHeight = max(256, Int(Double(copyWidth) * Double(cropped.height) / Double(cropped.width)))
        guard let ctx = CGContext(
            data: nil, width: copyWidth * 2, height: copyHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // ORIENTACJA: rysujemy wprost — RealityKit mapuje teksturę tak, że
        // wiersz zerowy obrazu odpowiada dołowi walca (horyzont wypada nisko).
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: copyWidth, height: copyHeight))

        // druga kopia: lustrzane odbicie w poziomie (zszycie bez szwu)
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(copyWidth * 2), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: copyWidth, height: copyHeight))
        ctx.restoreGState()

        guard let panorama = ctx.makeImage() else { return nil }
        let texture = try? TextureResource(image: panorama, withName: nil, options: .init(semantic: .color))
        print("[env] panorama: \(copyWidth * 2)x\(copyHeight), tekstura:", texture != nil)
        return texture
    }

    /// Miękki, okrągły cień kontaktowy (AO) pod obiektami. Siatka terenu nie ma
    /// ambient occlusion, więc bez tego drzewa i auto „lewitują" nad trawą.
    @MainActor
    public static func softShadow() -> TextureResource? {
        let size = 128
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let center = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        let radius = Double(size) / 2
        // kilka warstw o coraz mniejszej alfie — smoothstep zamiast twardej krawędzi
        for i in stride(from: 12, through: 1, by: -1) {
            let t = Double(i) / 12
            let alpha = 0.055 + (1 - t) * 0.02
            ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.02, alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: center.x - radius * t, y: center.y - radius * t,
                                       width: radius * 2 * t, height: radius * 2 * t))
        }
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    /// Mgła: poziomy gradient bieli — kładziony na pasmach i w dolinach.
    @MainActor
    public static func hazeGradient() -> TextureResource? {
        let height = 128
        guard let image = makeImage(width: 1, height: height, draw: { ctx in
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                CGColor(red: 0.92, green: 0.95, blue: 0.96, alpha: 0.55),
                CGColor(red: 0.88, green: 0.92, blue: 0.94, alpha: 0.85),
            ] as CFArray, locations: [0, 0.55, 1]) else { return }
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: CGFloat(height)), options: [])
        }) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }

    // MARK: - środowisko (IBL)

    /// Equirectangular skybox: gradient nieba + słońce + pas mgły przy horyzoncie.
    @MainActor
    public static func skyEquirect() -> CGImage? {
        let width = 1024, height = 512
        return makeImage(width: width, height: height, draw: { ctx in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                // połonina: mocny błękit u góry, biel przy horyzoncie
                CGColor(red: 0.16, green: 0.38, blue: 0.70, alpha: 1),
                CGColor(red: 0.34, green: 0.58, blue: 0.84, alpha: 1),
                CGColor(red: 0.66, green: 0.80, blue: 0.92, alpha: 1),
                CGColor(red: 0.90, green: 0.93, blue: 0.94, alpha: 1),
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
