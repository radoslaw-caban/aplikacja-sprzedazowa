import SwiftUI
import KitchenCore

/// EDYTOR OBIEKTU PIASKOWNICY — wszystkie parametry, łącznie z dźwiękiem.
///
/// Każde pole zmienia obiekt od razu (live), bo piaskownica ma być zabawą,
/// a nie formularzem do wypełnienia. Zapis do projektu robi AppModel.
struct SandboxObjectEditor: View {
    @Binding var object: SandboxObject
    var onChange: (SandboxObject) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// Odsłuch dźwięku — żeby usłyszeć, co się ustawiło.
    private let audio = SandboxAudio.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identity
                    geometry
                    appearance
                    sound
                    danger
                }
                .padding(12)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: nagłówek

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: object.kind.trade?.tool ?? "hand.point.up.left.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(object.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var subtitle: String {
        if let t = object.kind.trade {
            return "\(object.kind.label) · \(t.label)"
        }
        return "\(object.kind.label) · natura"
    }

    private var tint: Color {
        if let t = object.kind.trade { return Color(hex: t.tintHex) }
        return Color(hex: object.color)
    }

    // MARK: tożsamość

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Obiekt")
            TextField("Nazwa", text: $object.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: object.name) { _, _ in commit() }

            HStack {
                Text("Rodzaj").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(object.kind.label).font(.caption.weight(.medium))
            }

            if let trade = object.kind.trade {
                HStack(spacing: 6) {
                    Image(systemName: trade.tool)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color(hex: trade.tintHex)))
                    Text("Wykonuje: \(trade.label)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Element naturalny — nikt tego nie wykonuje")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: geometria

    private var geometry: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Wymiary bazowe (mm)")
            numRow("Szerokość X", value: $object.size.x, range: 10...20000)
            numRow("Wysokość Y", value: $object.size.y, range: 5...12000)
            numRow("Głębokość Z", value: $object.size.z, range: 10...20000)

            section("Skala")
            numRow("Skala X", value: $object.scale.x, range: 0.05...20, step: 0.05)
            numRow("Skala Y", value: $object.scale.y, range: 0.05...20, step: 0.05)
            numRow("Skala Z", value: $object.scale.z, range: 0.05...20, step: 0.05)

            HStack {
                Text("Wymiar po skali").font(.caption).foregroundStyle(.secondary)
                Spacer()
                let e = object.effectiveSize
                Text("\(Int(e.x)) × \(Int(e.y)) × \(Int(e.z)) mm")
                    .font(.caption.weight(.medium).monospacedDigit())
            }

            section("Pozycja i obrót")
            numRow("X", value: $object.position.x, range: -50000...50000, step: 10)
            numRow("Y (wysokość)", value: $object.position.y, range: 0...20000, step: 10)
            numRow("Z", value: $object.position.z, range: -50000...50000, step: 10)
            numRow("Obrót", value: $object.rotationY, range: 0...360, step: 5, unit: "°")

            Toggle("Przywiązany do terenu", isOn: $object.grounded)
                .font(.caption)
                .onChange(of: object.grounded) { _, _ in commit() }
        }
    }

    // MARK: wygląd

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Kolor")
            HStack(spacing: 8) {
                ForEach(Self.palette, id: \.self) { hex in
                    Button {
                        object.color = hex
                        commit()
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        object.color == hex ? Color.primary : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private static let palette = [
        "#7a6a52", "#6b5741", "#9a958c", "#8a8681", "#d9c8a3",
        "#4a6b3f", "#557a48", "#6b8f52", "#b06a8a", "#43643a",
        "#b0a89c", "#8b7355", "#8c8c8c", "#d8d3c9", "#e4ded2",
    ]

    // MARK: dźwięk

    private var sound: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Dźwięk wstawienia")

            Picker("Dźwięk", selection: $object.sound) {
                ForEach(SandboxSound.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: object.sound) { _, new in
                commit()
                audio.play(new, volume: object.soundVolume)   // odsłuch od razu
            }

            HStack {
                Text("Głośność").font(.caption).foregroundStyle(.secondary)
                Slider(value: $object.soundVolume, in: 0...1)
                    .onChange(of: object.soundVolume) { _, _ in commit() }
                Text("\(Int(object.soundVolume * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Button {
                    audio.play(object.sound, volume: object.soundVolume)
                } label: {
                    Label("Odsłuchaj", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                Button {
                    object.sound = object.kind.defaultSound
                    object.soundVolume = 0.7
                    commit()
                    audio.play(object.sound, volume: object.soundVolume)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }

            Text("Dźwięki są syntezowane w aplikacji — żadnych plików audio, działa offline.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: usuwanie

    private var danger: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Usuń z piaskownicy", systemImage: "trash")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(.red.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    // MARK: pomocniki

    private func section(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func numRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        unit: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.caption.weight(.medium).monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in commit() }
        }
    }

    private func commit() {
        onChange(object)
    }
}
