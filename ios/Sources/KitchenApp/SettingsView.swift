import SwiftUI
import KitchenCore

/// Ustawienia aplikacji: ogniskowa kamery, czułości gestów, domyślne dane
/// do zestawienia materiałów.
struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var dirty = false
    @Environment(\.dismiss) private var dismiss

    /// Otwiera piaskownicę — osobne pole robocze do swobodnego stawiania
    /// obiektów (natura, ogród, procesy budowlane, wykończenia).
    var onOpenSandbox: (() -> Void)? = nil

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
                    Toggle("Efekty magiczne (ramka + brokat)", isOn: Binding(
                        get: { settings.magicEffects },
                        set: { settings.magicEffects = $0; dirty = true }
                    ))
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
                    Toggle("Dźwięk", isOn: Binding(
                        get: { settings.soundEnabled },
                        set: { settings.soundEnabled = $0; dirty = true }
                    ))
                    Toggle("Haptyka (wibracje)", isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0; dirty = true }
                    ))
                } header: {
                    Text("Dźwięk i wibracje")
                } footer: {
                    Text("Haptyka jest osobno od dźwięku — można mieć wibracje bez dźwięku, np. w słuchawkach.")
                        .font(.caption2)
                }

                Section {
                    level("Głośność główna", value: $settings.masterVolume, enabled: settings.soundEnabled)
                    level("Interfejs", value: $settings.uiVolume, enabled: settings.soundEnabled)
                    level("Obiekty", value: $settings.objectVolume, enabled: settings.soundEnabled)
                    level("Otoczenie", value: $settings.ambienceVolume, enabled: settings.soundEnabled)

                    Button {
                        SandboxAudio.shared.play(.tap, volume: settings.effectiveUIVolume)
                    } label: {
                        Label("Odsłuchaj", systemImage: "speaker.wave.2.fill")
                    }
                    .disabled(!settings.soundAllowed())
                } header: {
                    Text("Poziomy głośności")
                } footer: {
                    Text("Głośność efektywna = główna × poziom. Interfejs gra dyskretnie, obiekty wyraźniej, otoczenie zostaje w tle.")
                        .font(.caption2)
                }

                Section {
                    Toggle("Cisza nocna", isOn: Binding(
                        get: { settings.quietHoursEnabled },
                        set: { settings.quietHoursEnabled = $0; dirty = true }
                    ))
                    if settings.quietHoursEnabled {
                        Stepper("Od: \(settings.quietHoursFrom):00",
                                value: $settings.quietHoursFrom, in: 0...23)
                        Stepper("Do: \(settings.quietHoursTo):00",
                                value: $settings.quietHoursTo, in: 0...23)
                    }
                } header: {
                    Text("Cisza nocna")
                } footer: {
                    Text("W podanych godzinach aplikacja nie gra żadnych dźwięków. Suwaki zostają bez zmian — po zakończeniu ciszy wracają poprzednie poziomy.")
                        .font(.caption2)
                }

                if let onOpenSandbox {
                    Section {
                        Button {
                            dismiss()
                            // chwila, żeby sheet zdążył się zamknąć przed otwarciem kolejnego
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onOpenSandbox()
                            }
                        } label: {
                            HStack {
                                Label("Piaskownica", systemImage: "hand.point.up.left.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Narzędzia")
                    } footer: {
                        Text("""
                        Osobne pole robocze: wszystko można dodać z biblioteki i edytować, \u{201E}łącznie z dźwiękiem obiektu. Kursor zmienia się w rękę — \u{201E}dla natury w rękę Boga ze pstryknięciem, dla robót ludzkich w rękę fachowca z narzędziem.
                        """)
                            .font(.caption2)
                    }
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

    /// Suwak poziomu 0…100% z etykietą i wartością.
    private func level(_ title: String, value: Binding<Double>, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.05) { _ in dirty = true }
                .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.45)
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
