import SwiftUI
import KitchenCore

/// Wybór sposobu pracy nad projektem: pomiar, rozmowa albo rysowanie planu.
///
/// JEDYNE WEJŚCIE DO SKANU. Wcześniej „Skanuj" było w trzech miejscach
/// (dolny pasek, biblioteka, akcje) i użytkownik nie wiedział, czy to to samo.
/// Teraz skan jest jedną z opcji pomiaru — z opisem dokładności, więc wybiera
/// się go świadomie, a nie przez przypadek.
///
/// FORMA: pytanie → opis → piktogram → parametry. Każda opcja odpowiada na
/// pytanie „czy to dla mnie?", bo klient nie zna nazw technologii.
struct MeasurementChooser: View {
    /// Akcje ofertowe (zakup, subskrypcja, spotkanie) — pierwsze w liście,
    /// bo przyjmują domyślną wartość i wystarczy je podać, gdy są potrzebne.
    var onOffer: (MeasurementGuide.Offer, MeasurementGuide.Option) -> Void = { _, _ in }
    /// Czy urządzenie ma LiDAR (decyduje o dostępności szybkiego skanu).
    var canScan: Bool = true
    var projectName: String = ""
    var onCancel: () -> Void
    var onPick: (MeasurementGuide.Option) -> Void

    @State private var category: MeasurementGuide.Category = .automatic
    @State private var expanded: MeasurementGuide.Option?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.12),
                                    Color(red: 0.10, green: 0.13, blue: 0.19)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                categoryPicker
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(options) { option in
                            card(option)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var options: [MeasurementGuide.Option] {
        MeasurementGuide.Option.allCases.filter { $0.category == category }
    }

    // MARK: - nagłówek

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onCancel() } label: {
                    Label("Wróć", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if !projectName.isEmpty {
                    Text(projectName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Jak zdobędziemy wymiary?")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Każda metoda ma inną dokładność. Wybierz tę, która wystarczy do Twojego celu.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 30)
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - kategorie jako pytania

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MeasurementGuide.Category.allCases) { c in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            category = c
                            expanded = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: c.pictogram).font(.footnote)
                            Text(c.question).font(.footnote.weight(.medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(category == c ? Color(red: 0.98, green: 0.93, blue: 0.72) : Color.white.opacity(0.08),
                                    in: Capsule())
                        .foregroundStyle(category == c ? .black : .white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 4)
    }

    // MARK: - karta opcji

    private func card(_ option: MeasurementGuide.Option) -> some View {
        let params = option.parameters
        let isOpen = expanded == option
        // szybki skan bez LiDAR-u — nie ukrywamy, tylko mówimy dlaczego nie działa
        let disabled = (option == .quickScan && !canScan)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded = isOpen ? nil : option
                }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: option.pictogram)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Color(red: 0.98, green: 0.93, blue: 0.72))
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(option.question)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        // dokładność i czas od razu — to decyduje o wyborze
                        HStack(spacing: 12) {
                            badge(params.accuracyText, icon: "scope")
                            badge(params.timeOnSite, icon: "clock")
                            if !params.suitableForProduction {
                                badge("nie do produkcji", icon: "exclamationmark.triangle")
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            if isOpen {
                VStack(alignment: .leading, spacing: 14) {
                    Text(option.description)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    parametersTable(params)
                        .overlay(alignment: .topLeading) {
                            if params.accuracyMM != nil, let mm = params.accuracyMM, mm > 10 {
                                Text("skan orientacyjny — do produkcji potrzeba dokładniejszej metody")
                                    .font(.caption2)
                                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.45))
                                    .padding(.top, 2)
                                    .offset(y: -14)
                            }
                        }
                        .padding(.top, params.accuracyMM != nil ? 12 : 0)

                    offersRow(option)

                    Button {
                        onPick(option)
                    } label: {
                        Label(disabled ? "Brak LiDAR-u na tym urządzeniu" : "Wybieram: \(option.title)",
                              systemImage: disabled ? "xmark.circle" : "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(disabled ? Color.white.opacity(0.10) : Color(red: 0.98, green: 0.93, blue: 0.72),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(disabled ? .white.opacity(0.5) : .black)
                    .disabled(disabled)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isOpen ? Color(red: 0.98, green: 0.93, blue: 0.72).opacity(0.5) : Color.white.opacity(0.10),
                        lineWidth: 1)
        )
        .opacity(disabled ? 0.6 : 1)
    }

    /// Tabela parametrów — dokładność, wymiary zwracane i zapisywane, sprzęt.
    private func parametersTable(_ p: MeasurementGuide.Params) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            row("Dokładność", p.accuracyText, detail: p.accuracyNote)
            row("Zwraca", "\(p.dimensionsReturned) wymiarów na pomiar")
            row("Zapisuje", p.savedText)
            row("Na miejscu", p.timeOnSite)
            row("Wymagany sprzęt", p.requiresHardware)
        }
        .padding(12)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 108, alignment: .leading)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 116)
            }
        }
    }

    /// Oferty towarzyszące: zakup, subskrypcja, spotkanie.
    private func offersRow(_ option: MeasurementGuide.Option) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRZY TYM MOŻESZ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(MeasurementGuide.offers(for: option)) { offer in
                Button {
                    onOffer(offer, option)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: offer.pictogram)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.98, green: 0.93, blue: 0.72))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(offer.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                            Text(offer.description)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(0.10), in: Capsule())
        .foregroundStyle(.white.opacity(0.8))
    }
}
