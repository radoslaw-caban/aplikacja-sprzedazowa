import SwiftUI
import KitchenCore

/// Pierwszy krok nowego projektu: **czym klient chce określić budynek**.
///
/// Wcześniej aplikacja od razu wrzucała edytor planu — klient nie wiedział,
/// od czego zacząć i nie było wyjścia do 3D. Teraz najpierw wybór metody,
/// a każda metoda prowadzi do tego samego edytora, tylko w innym trybie.
enum PlanMethod: String, CaseIterable, Identifiable {
    case presets
    case dimensions
    case rectangle
    case lines
    case image
    case scan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: "Gotowy plan"
        case .dimensions: "Wpiszę wymiary"
        case .rectangle: "Narysuję prostokąt"
        case .lines: "Obrysuję kreskami"
        case .image: "Mam plan w pliku"
        case .scan: "Mam skan pomieszczenia"
        }
    }

    var subtitle: String {
        switch self {
        case .presets: "Kuchnia, salon, dom 120 m², willa, dom w L"
        case .dimensions: "Szerokość, głębokość, wysokość — z klawiatury"
        case .rectangle: "Przeciągnij po kartce od narożnika do narożnika"
        case .lines: "Klikasz kolejne punkty ścian"
        case .image: "Zdjęcie albo PDF planu — wykryję obrys"
        case .scan: "LiDAR z iPada albo wczytany plik"
        }
    }

    var icon: String {
        switch self {
        case .presets: "square.grid.2x2"
        case .dimensions: "ruler"
        case .rectangle: "rectangle.dashed"
        case .lines: "pencil.tip"
        case .image: "photo.on.rectangle.angled"
        case .scan: "cube.transparent"
        }
    }
}

struct PlanMethodChooser: View {
    var onPick: (PlanMethod) -> Void
    var onCancel: () -> Void
    /// nazwa klienta/projektu, żeby było wiadomo, czego dotyczy wybór
    var projectName: String = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.12),
                                    Color(red: 0.10, green: 0.13, blue: 0.19)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onCancel()
                    } label: {
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
                .padding(.horizontal, 24)
                .padding(.top, 18)

                VStack(spacing: 8) {
                    Text("Jak określimy budynek?")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Wybierz metodę — potem możesz ją zmienić w edytorze planu.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 26)
                .padding(.bottom, 26)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(PlanMethod.allCases) { method in
                            Button {
                                onPick(method)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: method.icon)
                                        .font(.system(size: 26, weight: .regular))
                                        .foregroundStyle(Color(red: 0.98, green: 0.93, blue: 0.72))
                                    Text(method.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(method.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                                .padding(18)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
