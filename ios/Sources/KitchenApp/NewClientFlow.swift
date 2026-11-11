import SwiftUI
import KitchenCore
import MapKit
import CoreLocation

enum FieldKind { case text, phone, email }

/// Dodawanie nowego klienta — pełnoekranowy kreator.
///
/// Kolejność: intro z chmurą punktów → imię i nazwisko → „pokaż gdzie chcesz
/// działać" (mapa) → dane kontaktowe → nowa kartoteka i powrót do 3D.
struct NewClientFlow: View {
    var onFinish: (_ firstName: String, _ lastName: String, _ address: String, _ phone: String, _ email: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var email = ""

    // mapa
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 49.4776, longitude: 20.0300),
                           span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    )
    @State private var pin: CLLocationCoordinate2D?
    @State private var searching = false
    @State private var searchFailed = false

    var body: some View {
        ZStack {
            switch step {
            case 0: intro
            case 1: nameStep
            case 2: locationStep
            default: contactStep
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    // MARK: - 1. intro

    private var intro: some View {
        ZStack {
            PointCloudBackdrop()
                .ignoresSafeArea()
                .blur(radius: 0.5)

            VStack(spacing: 18) {
                Spacer()
                Text("KARPATIA")
                    .font(.system(size: 42, weight: .light, design: .serif))
                    .tracking(10)
                    .foregroundStyle(.white)
                Text("made by human, for human")
                    .font(.custom("Snell Roundhand", size: 26))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("dotknij, aby zacząć")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) { step = 1 }
        }
    }

    // MARK: - 2. imię i nazwisko

    private var nameStep: some View {
        VStack(spacing: 26) {
            Spacer()
            VStack(spacing: 6) {
                Text("Jak się nazywasz?").font(.title2.weight(.semibold)).foregroundStyle(.white)
                Text("Te dane trafią na kartotekę i umowę")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            VStack(spacing: 14) {
                bigField("Imię", text: $firstName)
                bigField("Nazwisko", text: $lastName)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 84, height: 84)
                    .background(
                        Circle().fill(Color(red: 0.98, green: 0.93, blue: 0.72))
                            .shadow(color: .white.opacity(0.35), radius: 22)
                    )
            }
            .disabled(lastName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(lastName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            .padding(.bottom, 54)
        }
    }

    // MARK: - 3. mapa

    private var locationStep: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                if let pin {
                    Marker("Adres", systemImage: "house.fill", coordinate: pin)
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("pokaż gdzie chcesz działać")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Adres, ulica, miejscowość", text: $address)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit { locate() }
                    if searching {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Szukaj") { locate() }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if searchFailed {
                    Text("Nie znalazłem adresu — wpisz dokładniej")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            VStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { step = 3 }
                } label: {
                    Label("Dalej", systemImage: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.98, green: 0.93, blue: 0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - 4. kontakt

    private var contactStep: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 6) {
                Text("Reszta danych").font(.title2.weight(.semibold)).foregroundStyle(.white)
                Text("Możesz uzupełnić później w kartotece")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            VStack(spacing: 14) {
                bigField("Telefon", text: $phone, keyboard: .phone)
                bigField("E-mail", text: $email, keyboard: .email)
            }
            .padding(.horizontal, 32)
            Spacer()

            Button {
                onFinish(firstName.trimmingCharacters(in: .whitespaces),
                         lastName.trimmingCharacters(in: .whitespaces),
                         address, phone, email)
                dismiss()
            } label: {
                Label("Utwórz kartotekę", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.98, green: 0.93, blue: 0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    private func bigField(_ title: String, text: Binding<String>, keyboard: FieldKind = .text) -> some View {
        TextField(title, text: text)
            .font(.system(size: 22, weight: .regular, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundStyle(.white)
            #if os(iOS)
            .keyboardType(keyboard == .phone ? .phonePad : (keyboard == .email ? .emailAddress : .default))
            #endif
    }

    // MARK: - geokodowanie

    private func locate() {
        let query = address.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searching = true
        searchFailed = false
        CLGeocoder().geocodeAddressString(query) { placemarks, _ in
            searching = false
            guard let placemark = placemarks?.first, let location = placemark.location else {
                searchFailed = true
                return
            }
            pin = location.coordinate
            camera = .region(MKCoordinateRegion(center: location.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            let street = [placemark.thoroughfare, placemark.subThoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let city = [placemark.postalCode, placemark.locality]
                .compactMap { $0 }
                .joined(separator: " ")
            let line = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
            if !line.isEmpty { address = line }
        }
    }
}

/// Obracająca się chmura punktów w czerni — tło intro.
struct PointCloudBackdrop: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = t * 0.25
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.34

                var dot = Path()
                // deterministyczna chmura: sfera z „szumem" — wygląda jak skan pomieszczenia
                for i in 0..<900 {
                    let seed = Double(i)
                    let phi = acos(1 - 2 * fract(seed * 0.6180339887))
                    let theta = 2 * .pi * fract(seed * 0.7548776662) + angle
                    let r = radius * (0.75 + 0.25 * fract(seed * 0.3183098862))
                    let x = r * sin(phi) * cos(theta)
                    let y = r * cos(phi) * 0.62
                    let z = r * sin(phi) * sin(theta)
                    let depth = (z + radius) / (2 * radius)      // 0…1
                    let scale = 0.5 + depth * 1.4
                    let point = CGPoint(x: center.x + x * scale, y: center.y + y * scale)
                    dot.addEllipse(in: CGRect(x: point.x, y: point.y, width: 2.6, height: 2.6))
                }
                context.fill(dot, with: .color(.white.opacity(0.8)))

                // delikatna mgławica w tle
                var glow = Path()
                glow.addEllipse(in: CGRect(x: center.x - radius * 1.5, y: center.y - radius * 1.1,
                                           width: radius * 3, height: radius * 2.2))
                context.fill(glow, with: .radialGradient(
                    Gradient(colors: [Color(red: 0.28, green: 0.36, blue: 0.55).opacity(0.35), .clear]),
                    center: center, startRadius: 10, endRadius: radius * 1.8))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func fract(_ value: Double) -> Double { value - floor(value) }
}
