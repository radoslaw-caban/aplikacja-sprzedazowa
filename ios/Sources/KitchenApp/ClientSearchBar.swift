import SwiftUI
import KitchenCore

/// Pasek wyszukiwania klientów — lewy górny róg aplikacji.
///
/// Zachowanie:
/// * pokazuje **imię, nazwisko i adres** aktualnie wczytanego projektu,
/// * kliknięcie czyści pole i pozwala pisać od zera (np. samo nazwisko),
/// * pod polem rozwija się lista trafień; każda pozycja ma „+", który dokłada
///   klienta do **Pulpit projektowego** (przewijanie góra/dół),
/// * kliknięcie w pozycję (poza plusem) otwiera kartotekę klienta.
struct ClientSearchBar: View {
    let projects: [Project]
    let currentName: String
    let currentAddress: String
    let workingSet: [UUID]
    var onOpen: (UUID) -> Void
    var onToggleWorking: (UUID) -> Void
    var onNewClient: () -> Void

    @State private var expanded = false
    @State private var query = ""
    @FocusState private var focused: Bool

    private var hits: [ClientHit] {
        ClientDirectory.search(projects, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onNewClient) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Nowy klient")

                if expanded {
                    TextField("Szukaj: nazwisko, adres…", text: $query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .onSubmit { if let first = hits.first { open(first) } }
                    Button {
                        collapse()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        expand()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(currentName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(currentAddress.isEmpty ? "—" : currentAddress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 320, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: expanded ? 420 : 380)
            .onTapGesture { if !expanded { expand() } }

            if expanded {
                results
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: expanded) { _, isOpen in
            if isOpen { focused = true } else { focused = false }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text(query.isEmpty ? "Brak klientów w bazie" : "Nic nie znaleziono")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hits) { hit in
                            HStack(spacing: 10) {
                                Button {
                                    onOpen(hit.projectID)
                                    collapse()
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(hit.name).font(.callout.weight(.medium))
                                            if hit.projectCount > 1 {
                                                Text("\(hit.projectCount) proj.")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                                            }
                                        }
                                        Text(hit.address.isEmpty ? hit.status : hit.address)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onToggleWorking(hit.projectID)
                                } label: {
                                    Image(systemName: workingSet.contains(hit.projectID) ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(workingSet.contains(hit.projectID) ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Dodaj do pulpitu projektowego")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider().opacity(0.35)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            HStack {
                Text("Pulpit projektowy: \(workingSet.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("przesuń palcem ↑↓, by zmienić projekt")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 6)
    }

    private func open(_ hit: ClientHit) {
        onOpen(hit.projectID)
        collapse()
    }

    private func expand() {
        query = ""
        expanded = true
    }

    private func collapse() {
        expanded = false
        query = ""
    }
}
