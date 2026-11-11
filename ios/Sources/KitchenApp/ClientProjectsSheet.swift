import SwiftUI
import KitchenCore

/// Wszystkie projekty jednego klienta + dodanie kolejnego.
///
/// Jeden klient, kilka zamówień (kuchnia, potem garderoba) — dlatego kartoteka
/// nie jest tym samym co projekt. Ten arkusz pokazuje całą listę.
struct ClientProjectsSheet: View {
    let model: AppModel
    var onClose: () -> Void

    private var clientName: String { ClientDirectory.displayName(model.current) }
    private var list: [Project] { model.projectsOfCurrentClient() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(list) { project in
                        Button {
                            if let index = model.projects.firstIndex(where: { $0.id == project.id }) {
                                model.selectProject(index)
                            }
                            onClose()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(project.name).font(.callout.weight(.semibold))
                                    if project.id == model.current.id {
                                        Text("otwarty")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                                    }
                                    Spacer()
                                    if let order = project.order {
                                        Text(money(order.finalPrice))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(subtitle(project))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(clientName)
                }

                Section {
                    Button {
                        model.addProjectForCurrentClient()
                        onClose()
                    } label: {
                        Label("Dodaj kolejny projekt", systemImage: "plus.rectangle.on.folder")
                    }
                }
            }
            .navigationTitle("Projekty klienta")
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
