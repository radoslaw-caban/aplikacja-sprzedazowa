import SwiftUI
import KitchenCore

/// Logo Karpatia — jedno źródło dla całej aplikacji.
///
/// DLACZEGO OSOBNY WIDOK: logo występuje w kilku miejscach (pasek wyszukiwania,
/// powitanie nowego klienta, dokumenty). Gdyby każdy rysował je sam, rozmiary
/// i marginesy rozjechałyby się przy pierwszej zmianie.
///
/// Plik `logo-karpatia.png` jest czarno-biały, więc:
///  - na jasnym tle rysuje się bez zmian,
///  - na ciemnym (ekran powitalny) odwracamy jasność, żeby czarne linie były
///    białe i logo było widoczne.
struct KarpatiaLogo: View {
    /// Wysokość logo; szerokość wynika z proporcji pliku (979 × 426).
    var height: CGFloat = 26
    /// Wersja na ciemne tło — odwraca jasność logo.
    var onDark: Bool = false

    private static let aspect: CGFloat = 979.0 / 426.0

    var body: some View {
        Image("logo-karpatia")
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(height: height)
            .modifier(InvertIfDark(onDark: onDark))
    }
}

/// Odwraca jasność logo na ciemnym tle (czarne linie → białe).
private struct InvertIfDark: ViewModifier {
    var onDark: Bool

    func body(content: Content) -> some View {
        if onDark {
            #if os(iOS)
            content.colorInvert()
            #else
            content.colorInvert()
            #endif
        } else {
            content
        }
    }
}
