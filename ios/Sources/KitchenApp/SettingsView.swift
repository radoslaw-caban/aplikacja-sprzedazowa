import SwiftUI
import KitchenCore

/// Ustawienia aplikacji: ogniskowa kamery, czułości gestów, domyślne dane
/// do zestawienia materiałów.
struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var dirty = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Ogniskowa kamery")
                            Spacer()
                            Text("\(Int(settings.fieldOfView))°")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.fieldOfView, in: 28...75, step: 1) { _ in
                            dirty = true
                        }
                        Text("Domyślnie 47°. Wartość dotyczy wszystkich widoków 3D — nie zmienia się przy zbliżaniu.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Kamera")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Odległość orbity od osi")
                            Spacer()
                            Text(String(format: "%.2f×", settings.orbitRadiusScale))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.orbitRadiusScale, in: 0.25...1.6, step: 0.05) { _ in
                            dirty = true
                        }
                        Text("""
                        Mniejsza wartość = obrót ciaśniejszy, projekt \u{201E}w ręku\u{201D}. \
                        Większa = kamera krąży dalej od środka. Zmiana działa od razu \
                        po zapisaniu ustawień.
                        """)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    slider("Czułość zbliżania", value: $settings.zoomSensitivity, range: 0.2...1.6)
                    slider("Czułość przesuwania", value: $settings.panSensitivity, range: 0.3...2.0)
                    slider("Wygładzanie ruchu", value: $settings.smoothing, range: 0.1...0.95)
                    Toggle("Ołówek przy oddalonym planie", isOn: $settings.showPencil)
                } header: {
                    Text("Sterowanie")
                } footer: {
                    Text("Większa czułość = szybszy ruch. Wygładzanie tłumi drgania palca.")
                        .font(.caption2)
                }

                Section {
                    Stepper("Okna: \(settings.windowCount)", value: $settings.windowCount, in: 0...12)
                    Stepper("Drzwi: \(settings.doorCount)", value: $settings.doorCount, in: 0...6)
                    Stepper("Warstwy farby: \(settings.paintCoats)", value: $settings.paintCoats, in: 1...3)
                } header: {
                    Text("Zestawienie materiałów")
                } footer: {
                    Text("Te wartości wchodzą do kalkulacji farby, listew i stolarki.")
                        .font(.caption2)
                }

                Section {
                    Button {
                        settings = AppSettings()
                        dirty = true
                    } label: {
                        Label("Przywróć domyślne", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Ustawienia")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        settings.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: settings) { _, _ in dirty = true }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
