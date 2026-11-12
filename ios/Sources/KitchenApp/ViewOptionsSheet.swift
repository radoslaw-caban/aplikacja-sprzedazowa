import SwiftUI
import KitchenCore

/// Panel opcji widoku — kafelki do wyboru zamiast dolnego paska przycisków.
///
/// PO CO: dolny pasek zajmował całą szerokość ekranu i był mieszanką rzeczy
/// ważnych (skan) i rzadkich (willa/dom ze skanu, moduł pierwszoosobowy).
/// Na iPadzie odbierał miejsce scenie 3D i wymuszał trafianie w małe przyciski.
/// Tutaj każda opcja jest dużym kafelkiem z opisem, a panel otwiera się
/// tylko wtedy, gdy jest potrzebny.
struct ViewOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var interiorView: Bool
    @Binding var useScanHouse: Bool
    @Binding var showScanCloud: Bool
    /// Warstwa skanu — włączana niezależnie od bryły budynku.
    @Binding var showScan: Bool
    /// Warstwa budynku (ściany, podłoga, sufit) — niezależnie od skanu.
    @Binding var showBuilding: Bool

    /// Skan dostępny w projekcie? Decyduje, czy kafelki chmury są aktywne.
    var hasScan: Bool
    /// Czy urządzenie ma LiDAR (decyduje o kafelku skanowania).
    var canScan: Bool
    var onScan: () -> Void
    var onClearScan: () -> Void
    var onPlan: () -> Void
    var onTextures: () -> Void
    var onFirstPerson: (() -> Void)?
    /// Opcje widoku, zapisywane razem z resztą ustawień.
    var onPersist: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                // MARK: widok 3D
                section("Widok 3D") {
                    tile("Wnętrze", "house", active: interiorView) {
                        interiorView = true; onPersist()
                    }
                    tile("Otoczenie", "tree", active: !interiorView) {
                        interiorView = false; onPersist()
                    }
                }

                // MARK: warstwy (skan i budynek niezależnie)
                section("Warstwy") {
                    tile("Chmura skanu", "circle.grid.3x3", active: showScan,
                         subtitle: hasScan ? nil : "Brak skanu") {
                        // Włączamy warstwę nawet bez skanu — po to, żeby dało się
                        // ją przygotować przed wczytaniem pliku.
                        showScan.toggle(); onPersist()
                    }
                    tile("Budynek", "cube.transparent", active: showBuilding) {
                        showBuilding.toggle(); onPersist()
                    }
                }

                // MARK: bryła domu
                section("Bryła budynku") {
                    tile("Dom ze skanu", "cube.transparent", active: useScanHouse) {
                        useScanHouse = true; onPersist()
                    }
                    tile("Willa", "building.2", active: !useScanHouse) {
                        useScanHouse = false; onPersist()
                    }
                }

                // MARK: skan
                section("Skan") {
                    tile("Skanuj", "sensor.tag.radiowaves.forward", active: false,
                         enabled: canScan,
                         subtitle: canScan ? nil : "Brak LiDAR-u") {
                        dismiss(); onScan()
                    }
                    tile("Chmura", "circle.grid.3x3", active: showScanCloud,
                         enabled: hasScan) {
                        showScanCloud.toggle(); onPersist()
                    }
                    tile("Usuń skan", "xmark.circle", active: false,
                         enabled: hasScan, subtitle: hasScan ? nil : "Brak skanu") {
                        onClearScan()
                    }
                }

                // MARK: narzędzia
                section("Narzędzia") {
                    tile("Plan", "map", active: false) { dismiss(); onPlan() }
                    tile("Tekstury", "photo.on.rectangle.angled", active: false) {
                        dismiss(); onTextures()
                    }
                    if let onFirstPerson {
                        tile("Wejdź do domu", "figure.walk", active: false,
                             subtitle: "moduł pokazowy") {
                            dismiss(); onFirstPerson()
                        }
                    }
                }
            }
            .navigationTitle("Opcje widoku")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - budulec

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func tile(_ title: String, _ icon: String, active: Bool,
                      enabled: Bool = true, subtitle: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(active ? Color.accentColor : .primary)
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
