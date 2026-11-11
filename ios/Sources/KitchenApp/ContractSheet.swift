import SwiftUI
import KitchenCore
#if canImport(UIKit)
import UIKit
#endif

/// Umowa do podpisu: dane są już uzupełnione z kartoteki, zostaje podpis.
///
/// Podpis rysowany palcem lub rysikiem (Canvas), zapisywany jako PNG w
/// `Documents/umowy/` i podpinany do zamówienia razem z datą podpisania.
struct ContractSheet: View {
    let project: Project
    var onSigned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var message: String?

    private var order: ProjectOrder { project.order ?? ProjectOrder() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    parties
                    scope
                    signatureArea

                    if let message {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .navigationTitle(order.isContractSigned ? "Umowa (podpisana)" : "Umowa")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Podpisz i zapisz") { save() }
                        .disabled(strokes.isEmpty)
                }
            }
        }
    }

    // MARK: - treść umowy

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UMOWA NA WYKONANIE ZABUDOWY MEBLOWEJ")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(order.clientName.isEmpty ? project.name : order.clientName)
                .font(.title2.weight(.semibold))
            if order.isContractSigned, let date = order.contractSignedAt {
                Label("podpisana \(date.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("do podpisu", systemImage: "signature")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var parties: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Zamawiający", order.clientName.isEmpty ? "—" : order.clientName)
            row("Adres", order.address.isEmpty ? "—" : order.address)
            row("Telefon", order.phone.isEmpty ? "—" : order.phone)
            row("E-mail", order.email.isEmpty ? "—" : order.email)
            Divider()
            row("Wartość zamówienia", money(order.price))
            if order.effectiveDiscount > 0 {
                row("Rabat", "\(Units.mm(order.effectiveDiscount)) %  (\(money(order.discountAmount)))")
            }
            row("Do zapłaty", money(order.finalPrice))
            row("Zaliczka wpłacona", money(order.deposit))
            row("Pozostało", money(max(0, order.finalPrice - order.deposit)))
            if let delivery = order.deliveryDate {
                row("Termin dostawy", delivery.formatted(date: .long, time: .omitted))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zakres i uwagi").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(order.notes.isEmpty
                 ? "Zakres zgodny z zatwierdzoną ofertą i projektem technicznym. Montaż po przygotowaniu pomieszczenia."
                 : order.notes)
                .font(.callout)
        }
    }

    // MARK: - podpis

    private var signatureArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Podpis klienta").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Wyczyść") { strokes.removeAll(); current.removeAll() }
                    .font(.caption)
                    .disabled(strokes.isEmpty)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                if strokes.isEmpty && current.isEmpty {
                    Text("Podpisz tutaj palcem lub rysikiem")
                        .font(.footnote)
                        .foregroundStyle(.black.opacity(0.35))
                        .padding(14)
                }
                SignaturePad(strokes: strokes, current: current)
            }
            .frame(height: 190)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1).padding(.horizontal, 10)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    current.append(value.location)
                }
                .onEnded { _ in
                    if current.count > 1 { strokes.append(current) }
                    current = []
                }
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.callout.monospacedDigit()).multilineTextAlignment(.trailing)
        }
    }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "PLN"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value)) zł"
    }

    // MARK: - zapis

    private func save() {
        #if canImport(UIKit)
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("umowy", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let size = CGSize(width: 900, height: 380)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                context.cgContext.move(to: first)
                for point in stroke.dropFirst() {
                    context.cgContext.addLine(to: point)
                }
                context.cgContext.strokePath()
            }
        }

        guard let data = image.pngData() else {
            message = "Nie udało się zapisać podpisu"
            return
        }
        let fileName = "\(project.id.uuidString)-podpis.png"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            onSigned(fileName)
            dismiss()
        } catch {
            message = "Błąd zapisu: \(error.localizedDescription)"
        }
        #else
        message = "Podpis dostępny tylko na iPadzie"
        #endif
    }
}

/// Rysowanie linii podpisu.
struct SignaturePad: View {
    let strokes: [[CGPoint]]
    let current: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for stroke in strokes + [current] {
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }
    }
}
