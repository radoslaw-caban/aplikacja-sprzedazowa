import SwiftUI
import KitchenCore

/// Wszystkie projekty jednego klienta + dodanie kolejnego.
///
/// Jeden klient, kilka zamówień (kuchnia, potem garderoba) — dlatego kartoteka
/// nie jest tym samym co projekt. Ten arkusz pokazuje całą listę.
///
/// UKŁAD DWUKOLUMNOWY: przy jednej kolumnie wiersz był szeroki na cały ekran,
/// a informacja (nazwa, status, data, kwota) rozjeżdżała się na boki — trzeba
/// było wodzić wzrokiem. W dwóch kolumnach cały projekt mieści się w jednym
/// kafelku i widać ich kilka naraz bez przewijania.
struct ClientProjectsSheet: View {
    let model: AppModel
    var onClose: () -> Void
    /// Odblokowanie edycji projektu (zdejmuje kłódkę z widoku 3D).
    var onUnlock: () -> Void = {}

    private var clientName: String { ClientDirectory.displayName(model.current) }
    private var list: [Project] { model.projectsOfCurrentClient() }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { project in
                        card(project)
                    }
                }
                .padding(14)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.addProjectForCurrentClient()
                    onClose()
                } label: {
                    Label("Dodaj kolejny projekt", systemImage: "plus.rectangle.on.folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .navigationTitle(clientName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { onClose() }
                }
            }
        }
    }

    /// Kafelek jednego projektu.
    ///
    /// Otwarcie projektu i odblokowanie edycji to DWIE różne rzeczy: pierwsze
    /// tylko przełącza, co widzisz; drugie zdejmuje kłódkę i pozwala zmieniać
    /// projekt. Na zablokowanym widoku 3D gesty obracają kamera, a nie edytują.
    private func card(_ project: Project) -> some View {
        let isCurrent = project.id == model.current.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isCurrent {
                    Text("otwarty")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }

            Text(subtitle(project))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let order = project.order {
                Text(money(order.finalPrice))
                    .font(.callout.monospacedDigit())
            }

            HStack(spacing: 8) {
                Button {
                    if let index = model.projects.firstIndex(where: { $0.id == project.id }) {
                        model.selectProject(index)
                    }
                    onClose()
                } label: {
                    Text(isCurrent ? "Otwarty" : "Otwórz")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isCurrent)

                Button {
                    if let index = model.projects.firstIndex(where: { $0.id == project.id }) {
                        model.selectProject(index)
                    }
                    onUnlock()
                    onClose()
                } label: {
                    Label("Odblokuj", systemImage: "lock.open")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private func subtitle(_ project: Project) -> String {
        var parts: [String] = []
        if let status = project.order?.status { parts.append(status) }
        if let date = project.order?.deliveryDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("\(project.cabinets.count) szafek")
        return parts.joined(separator: " · ")
    }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return (formatter.string(from: NSNumber(value: value)) ?? "0") + " zł"
    }
}
