import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import KitchenCore

#if os(iOS)
import UIKit
/// Podgląd dowolnego pliku (PDF, obraz, DWG przez QuickLook).
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

/// Lista dokumentów klienta z dodawaniem i usuwaniem.
struct DocumentsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                if model.documents.isEmpty {
                    ContentUnavailableView(
                        "Brak dokumentów",
                        systemImage: "folder.badge.plus",
                        description: Text("Dodaj umowę, skan, rzut lub zdjęcie klienta.")
                    )
                }
                ForEach(Array(model.documents.enumerated()), id: \.element.id) { index, doc in
                    Button {
                        model.openDocument(index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: doc.kind.icon)
                                .font(.title3)
                                .frame(width: 28)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.name).font(.callout).lineLimit(1)
                                Text("\(doc.kind.label) · \(doc.sizeLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.documentIndex == index {
                                Image(systemName: "eye").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.deleteDocument(at: index)
                        } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Dokumenty · \(model.current.name)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importing = true
                    } label: {
                        Label("Dodaj", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.pdf, .image, .plainText, .data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    model.importDocuments(from: urls)
                case .failure(let error):
                    model.status = "Import: \(error.localizedDescription)"
                }
            }
        }
    }
}
