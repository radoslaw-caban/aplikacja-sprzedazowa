import SwiftUI
import KitchenCore
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Biblioteka tekstur: import plików, nazwa = nazwa pliku, wyszukiwarka.
///
/// Po co osobny moduł: tekstury to dane produkcyjne (fornir, laminat, lakier).
/// Klient ma je w folderze i chce je znaleźć po nazwie, a nie przeklikiwać
/// listę. Dlatego import kopiuje plik, a nazwa jest brana z pliku.
struct TextureLibraryView: View {
    /// wybór tekstury → aplikacja nakłada ją na fronty
    var onApply: (StoredTexture) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var textures: [StoredTexture] = []
    @State private var importing = false
    @State private var message: String?
    @State private var selection: StoredTexture?

    private let store = TextureStore.shared
    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if textures.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(textures) { texture in
                                card(texture)
                            }
                        }
                        .padding(14)
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Tekstury")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importing = true
                    } label: {
                        Label("Wczytaj", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.image, .jpeg, .png, .heic, .tiff],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        }
        .onAppear { reload() }
    }

    // MARK: - pasek wyszukiwania

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Szukaj tekstury (np. dąb, bielony)", text: $query)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .textFieldStyle(.plain)
                .onChange(of: query) { _, _ in reload() }
            if !query.isEmpty {
                Button {
                    query = ""
                    reload()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("\(textures.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "Brak tekstur" : "Nic nie znaleziono")
                .font(.headline)
            Text(query.isEmpty
                 ? "Wczytaj pliki JPG/PNG — nazwa tekstury będzie taka jak nazwa pliku."
                 : "Spróbuj krótszego fragmentu nazwy.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - kafelek

    private func card(_ texture: StoredTexture) -> some View {
        let selected = selection?.id == texture.id
        return VStack(alignment: .leading, spacing: 6) {
            thumbnail(texture)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(texture.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(selected ? Color.orange : Color.primary)

            HStack(spacing: 6) {
                Button("Użyj") {
                    selection = texture
                    onApply(texture)
                    message = "Nałożono: \(texture.name)"
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .fixedSize()

                Button {
                    store.delete(texture)
                    reload()
                    if selection?.id == texture.id { selection = nil }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.orange.opacity(0.12) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.orange : Color.clear, lineWidth: 1.5)
        )
    }

    private func thumbnail(_ texture: StoredTexture) -> some View {
        let url = store.folder.appendingPathComponent(texture.fileName)
        #if os(iOS)
        if let image = UIImage(contentsOfFile: url.path) {
            return AnyView(Image(uiImage: image).resizable().scaledToFill())
        }
        #else
        if let image = NSImage(contentsOf: url) {
            return AnyView(Image(nsImage: image).resizable().scaledToFill())
        }
        #endif
        return AnyView(
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        )
    }

    // MARK: - import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var imported = 0
            var failures: [String] = []
            for url in urls {
                // plik z „Otwórz w…" bywa poza sandboxem — trzeba go objąć dostępem
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try store.importFile(at: url)
                    imported += 1
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            reload()
            if imported > 0 {
                message = "Wczytano \(imported) \(imported == 1 ? "teksturę" : "tekstur")"
            }
            if !failures.isEmpty {
                message = "Nie udało się: \(failures.joined(separator: ", "))"
            }
        case .failure(let error):
            message = "Błąd importu: \(error.localizedDescription)"
        }
    }

    private func reload() {
        textures = store.search(query)
    }
}
