import SwiftUI
import KitchenCore

/// KURSOR PIASKOWNICY — ręka wskazująca palcem, jak kursor.
///
/// Dwa wcielenia, zależne od tego, CO wstawiamy:
///  - **natura** → ręka Boga: dłoń wskazuje palcem, a przy wstawieniu robi
///    pstryknięcie palcami (kciuk uderza w palec) i rozbłyskują iskry.
///  - **robota ludzka** → ręka fachowca: dłoń trzyma narzędzie swojego fachu,
///    więc od razu widać, kto za ten element odpowiada.
///
/// Punkt dotknięcia trafia w KONIUSZEK PALCA, nie w środek dłoni.
/// To cała różnica między kursorem a ozdobą: jeśli palec nie wskazuje miejsca
/// wstawienia, użytkownik nie wie, gdzie trafi obiekt.
struct SandboxCursor: View {
    /// pozycja palca w przestrzeni widoku
    let point: CGPoint
    /// natura (nil) = ręka Boga, inaczej ręka fachowca
    let trade: SandboxTrade?
    /// faza pstryknięcia 0…1
    let snapPhase: Double
    /// kolor wstawianego obiektu
    let tint: Color
    /// czy miejsce jest wolne — kontur zielony (można) albo czerwony (kolizja)
    var valid: Bool = true

    /// Koniuszek palca względem środka rysunku. Ręka jest rysowana tak,
    /// żeby palec wskazujący sięgał w lewo-górę; te przesunięcia kładą
    /// koniuszek dokładnie na punkcie dotknięcia.
    private let tip = CGSize(width: -16, height: -22)

    private var isGod: Bool { trade == nil }

    var body: some View {
        ZStack {
            // poświata: zielona gdy można wstawić, czerwona przy kolizji.
            // To ten sam sygnał co kontur w edytorze mebli — bez niego
            // użytkownik dowiaduje się o kolizji dopiero po fakcie.
            Circle()
                .fill(RadialGradient(
                    colors: [(valid ? Color.green : Color.red).opacity(0.45),
                             (valid ? Color.green : Color.red).opacity(0)],
                    center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 92, height: 92)
                .offset(tip)
                .blendMode(.plusLighter)

            // pierścień walidacji wokół koniuszka palca
            Circle()
                .strokeBorder(valid ? Color.green : Color.red,
                              lineWidth: 2)
                .frame(width: 34, height: 34)
                .offset(tip)
                .opacity(0.9)

            hand
                .offset(tip)
                .scaleEffect(handScale, anchor: .bottomTrailing)
                .rotationEffect(.degrees(handRotation), anchor: .bottomTrailing)

            if let trade {
                toolBadge(trade)
                    .offset(x: tip.width + 10, y: tip.height + 34)
            }

            if isGod, snapPhase > 0.01 {
                SnapBurst(phase: snapPhase, tint: tint)
                    .offset(x: tip.width + 2, y: tip.height + 26)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: dłoń

    /// Dłoń rysowana wektorowo: nadgarstek, grzbiet, cztery zgięte palce
    /// i wyprostowany palec wskazujący. Bez plików graficznych — skaluje się
    /// do każdego iPada i nie traci ostrości.
    private var hand: some View {
        ZStack {
            HandShape(isGod: isGod, snap: snapPhase)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.99), Color(white: 0.88)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    HandShape(isGod: isGod, snap: snapPhase)
                        .stroke(Color.black.opacity(0.28), lineWidth: 1.1)
                )
                .frame(width: 62, height: 72)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
        }
    }

    private var handScale: Double {
        guard isGod else { return 1 }
        let p = sin(min(1, max(0, snapPhase)) * .pi)
        return 1 - p * 0.10
    }

    private var handRotation: Double {
        guard isGod else { return 0 }
        let p = sin(min(1, max(0, snapPhase)) * .pi)
        return -p * 8
    }

    // MARK: narzędzie fachu

    private func toolBadge(_ trade: SandboxTrade) -> some View {
        HStack(spacing: 4) {
            Image(systemName: trade.tool)
                .font(.system(size: 10, weight: .bold))
            Text(trade.label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(
            Capsule().fill(Color(hex: trade.tintHex).opacity(0.95))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

// MARK: - kształt dłoni

/// Dłoń wskazująca. Rysowana w układzie 62×72, koniuszek palca w lewym górnym.
///
/// `snap` (0…1) przybliża kciuk do palca środkowego — to jest pstryknięcie.
private struct HandShape: Shape {
    var isGod: Bool
    var snap: Double

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()

        // --- palec wskazujący: wyprostowany, sięga lewego górnego rogu ---
        let tipX = w * 0.06, tipY = h * 0.04
        let fingerW = w * 0.17
        p.move(to: CGPoint(x: tipX, y: tipY))
        p.addLine(to: CGPoint(x: tipX + fingerW, y: tipY + h * 0.02))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.42))
        p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.20))
        p.closeSubpath()

        // --- grzbiet dłoni ---
        p.move(to: CGPoint(x: w * 0.26, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.42))
        p.addCurve(to: CGPoint(x: w * 0.80, y: h * 0.58),
                   control1: CGPoint(x: w * 0.58, y: h * 0.40),
                   control2: CGPoint(x: w * 0.76, y: h * 0.44))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
        p.addCurve(to: CGPoint(x: w * 0.34, y: h * 0.92),
                   control1: CGPoint(x: w * 0.70, y: h * 1.02),
                   control2: CGPoint(x: w * 0.44, y: h * 1.02))
        p.closeSubpath()

        // --- zgięte palce (trzy garstki po prawej) ---
        for i in 0..<3 {
            let y = h * (0.60 + Double(i) * 0.11)
            let inset = Double(i) * w * 0.03
            p.move(to: CGPoint(x: w * 0.72 - inset, y: y))
            p.addCurve(to: CGPoint(x: w * 0.95 - inset, y: y + h * 0.06),
                       control1: CGPoint(x: w * 0.84 - inset, y: y - h * 0.03),
                       control2: CGPoint(x: w * 0.95 - inset, y: y - h * 0.01))
            p.addCurve(to: CGPoint(x: w * 0.72 - inset, y: y + h * 0.09),
                       control1: CGPoint(x: w * 0.95 - inset, y: y + h * 0.12),
                       control2: CGPoint(x: w * 0.84 - inset, y: y + h * 0.12))
            p.closeSubpath()
        }

        // --- kciuk: przy pstryknięciu unosi się do palca środkowego ---
        // snap 0 = kciuk luźno z boku, snap 1 = kciuk dotyka palca
        let lift = snap * h * 0.16
        p.move(to: CGPoint(x: w * 0.30, y: h * 0.62))
        p.addCurve(
            to: CGPoint(x: w * 0.30 + w * 0.04, y: h * 0.40 - lift),
            control1: CGPoint(x: w * 0.12, y: h * 0.60 - lift * 0.5),
            control2: CGPoint(x: w * 0.14, y: h * 0.44 - lift)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.60),
            control1: CGPoint(x: w * 0.40, y: h * 0.46 - lift),
            control2: CGPoint(x: w * 0.44, y: h * 0.54)
        )
        p.closeSubpath()

        return p
    }
}

// MARK: - iskry pstryknięcia

/// Rozbłysk iskier z koniuszka palca — magia pstryknięcia.
private struct SnapBurst: View {
    let phase: Double
    let tint: Color
    private let count = 16

    var body: some View {
        ZStack {
            // błysk w punkcie
            Circle()
                .fill(.white)
                .frame(width: 6 + (1 - phase) * 14,
                       height: 6 + (1 - phase) * 14)
                .opacity(max(0, 1 - phase * 1.5))
                .blendMode(.plusLighter)

            // iskry rozchodzące się promieniście
            ForEach(0..<count, id: \.self) { i in
                let a = Double(i) / Double(count) * 2 * .pi
                let jitter = 0.6 + 0.4 * abs(sin(Double(i) * 12.9898))
                let rad = 8 + phase * 40 * jitter
                let fade = max(0, 1 - phase)
                Capsule()
                    .fill(i % 3 == 0 ? Color.white : tint)
                    .frame(width: 2.2, height: 5 + (1 - phase) * 5)
                    .offset(x: cos(a) * rad, y: sin(a) * rad)
                    .rotationEffect(.radians(a + .pi / 2))
                    .opacity(fade * fade)
                    .blendMode(.plusLighter)
            }
        }
    }
}
