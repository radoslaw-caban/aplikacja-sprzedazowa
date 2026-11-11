import SwiftUI
import KitchenCore
import UniformTypeIdentifiers
import ImageIO

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Import planu z pliku graficznego: wybierz obraz, podaj rzeczywistą szerokość,
/// a program wstawi obrys ścian do korekty.
struct PlanImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onImport: (FloorPlan) -> Void

    @State private var picking = false
    @State private var image: CGImage?
    @State private var analysis: PlanImageImport.Analysis?
    @State private var widthText = "10000"
    @State private var heightText = "2600"
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview

                if let analysis {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wykryty obrys: \(analysis.box.w) × \(analysis.box.h) px, "
                             + "kresek: \(analysis.verticalLines.count) pionowych, \(analysis.horizontalLines.count) poziomych")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            field("Szerokość rzeczywista", text: $widthText)
                            field("Wysokość ścian", text: $heightText)
                        }

                        if let plan = computedPlan(analysis) {
                            Text("Plan: \(Units.mm(plan.size.x)) × \(Units.mm(plan.size.y)) mm · \(Units.m2Area(plan.areaM2 * 1_000_000))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    picking = true
                } label: {
                    Label("Wybierz obraz planu", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button {
                    if let analysis, let plan = computedPlan(analysis) {
                        onImport(plan)
                        dismiss()
                    }
                } label: {
                    Label("Wstaw ściany z planu", systemImage: "square.dashed.inset.filled")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(analysis == nil)
            }
            .padding(16)
            .navigationTitle("Import planu")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.image, .pdf]) { result in
                handle(result)
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let image {
                #if os(iOS)
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                #else
                Image(nsImage: NSImage(cgImage: image, size: .zero))
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                #endif
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.image").font(.system(size: 38))
                    Text("Zdjęcie, skan albo PDF z planem").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 300)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("mm", text: text)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
        }
    }

    private func computedPlan(_ analysis: PlanImageImport.Analysis) -> FloorPlan? {
        guard let width = Units.parseMM(widthText), width > 500 else { return nil }
        let height = Units.parseMM(heightText).flatMap { $0 > 1000 ? $0 : nil } ?? 2600
        return PlanImageImport.plan(from: analysis, realWidthMM: width, height: height)
    }

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let cg = loadImage(url) else {
                message = "Nie udało się odczytać obrazu"
                return
            }
            image = cg
            guard let gray = PlanImageImport.grayscale(cg) else {
                message = "Nie udało się przetworzyć obrazu"
                return
            }
            guard let found = PlanImageImport.analyze(gray: gray.pixels, width: gray.width, height: gray.height) else {
                message = "Nie znalazłem kresek — plan jest zbyt jasny albo to nie plan"
                return
            }
            analysis = found
            message = nil
        case .failure(let error):
            message = "Błąd: \(error.localizedDescription)"
        }
    }

    private func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // PDF-y: pierwsza strona jako obraz
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
