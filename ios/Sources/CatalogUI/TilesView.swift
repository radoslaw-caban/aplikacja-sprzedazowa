import SwiftUI
import CatalogCore

#if canImport(AppKit)
import AppKit
public typealias CatalogImage = NSImage
#else
import UIKit
public typealias CatalogImage = UIImage
#endif

/// Kafelki biblioteki: **miniatura modelu**, pod nią **oficjalne logo producenta**
/// i nazwa produktu. Moduł jest samodzielny — ten widok nie jest jeszcze
/// podpięty do głównej aplikacji.
public struct CatalogTilesView: View {
    public let store: CatalogStore
    public var entries: [CatalogStore.LibraryEntry]
    public var columns: Int

    public init(store: CatalogStore, entries: [CatalogStore.LibraryEntry], columns: Int = 4) {
        self.store = store
        self.entries = entries
        self.columns = columns
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
                      spacing: 16) {
                ForEach(entries, id: \.id) { entry in
                    CatalogTile(store: store, entry: entry)
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.055, green: 0.078, blue: 0.12))
    }
}

public struct CatalogTile: View {
    public let store: CatalogStore
    public let entry: CatalogStore.LibraryEntry

    public init(store: CatalogStore, entry: CatalogStore.LibraryEntry) {
        self.store = store
        self.entry = entry
    }

    private var thumbnailURL: URL? {
        guard let path = entry.thumbnailPath else { return nil }
        let url = store.productDir(entry.id).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var logoURL: URL? {
        guard let logo = entry.logoPath else { return nil }
        let url = store.manufacturersDir.appendingPathComponent(logo)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.14, green: 0.19, blue: 0.28),
                                        Color(red: 0.07, green: 0.10, blue: 0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = thumbnailURL, let image = CatalogImage(contentsOf: url) {
                    imageView(image)
                        .padding(14)
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.92, blue: 0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let url = logoURL, let logo = CatalogImage(contentsOf: url) {
                        imageView(logo)
                            .frame(maxWidth: 78, maxHeight: 20)
                    }
                    Text(entry.manufacturerName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))
                }

                HStack {
                    Text("zakup \(entry.costText)")
                    Spacer()
                    Text("detal \(entry.retailText)").foregroundStyle(.white)
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))

                if !entry.dependencies.isEmpty {
                    Text(entry.dependencies.map { $0.effects.map { $0.shortLabel }.joined(separator: " · ") }
                        .joined(separator: " / "))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.36, green: 0.55, blue: 0.94))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .background(Color(red: 0.086, green: 0.12, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(red: 0.14, green: 0.19, blue: 0.27), lineWidth: 1))
    }

    @ViewBuilder
    private func imageView(_ image: CatalogImage) -> some View {
        #if canImport(AppKit)
        Image(nsImage: image).resizable().scaledToFit()
        #else
        Image(uiImage: image).resizable().scaledToFit()
        #endif
    }
}
