import SwiftUI
import KitchenCore
import KitchenScene

#if os(iOS)

/// Panel skanowania LiDAR-em: podgląd siatki na żywo + jeden przycisk.
///
/// Przepływ: Skanduj → ARKit buduje siatkę → Zakończ → chmura punktów →
/// automatycznie zapisana jako dokument projektu i wczytana do sceny.
/// Użytkownik nie wybiera pliku ani nie ustawia jednostek — to robi się samo.
struct RoomScanSheet: View {
    let projectName: String
    /// wywoływane z gotową chmurą w metrach; `nil` = anulowano
    let onFinish: (PointCloud?) -> Void

    @StateObject private var scan = RoomScanSession()
    @State private var building = false
    @State private var formatNote: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if scan.isAvailable {
                    RoomScanPreview(session: scan.session)
                        .ignoresSafeArea()
                } else {
                    unavailableView
                }

                VStack(spacing: 0) {
                    statsBar
                    Spacer()
                    controls
                }
            }
            .navigationTitle("Skan pomieszczenia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        scan.stop()
                        onFinish(nil)
                    }
                }
            }
        }
        .onAppear { scan.start() }
        .onDisappear { scan.stop() }
    }

    // MARK: - pasek statystyk

    private var statsBar: some View {
        HStack(spacing: 14) {
            stat("pkt ~", scan.estimatedPoints.formatted(.number.grouping(.automatic)))
            stat("powierzchnia", scan.coverageText)
            stat("wymiary", scan.boundsText)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle()
                    .fill(scan.trackingState == "OK" ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(scan.trackingState).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1)
        }
    }

    // MARK: - sterowanie

    private var controls: some View {
        VStack(spacing: 10) {
            if let note = formatNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if scan.hasScan == false && scan.isAvailable {
                Text("Skieruj iPada na ściany i przejdź powoli całe pomieszczenie.\nSiatka pojawia się na bieżąco.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    scan.reset()
                } label: {
                    Label("Od nowa", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!scan.hasScan || building)

                Button {
                    finish()
                } label: {
                    if building {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Buduję chmurę…")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        Label("Zakończ i dodaj do projektu", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
                .background(scan.hasScan && !building ? Color.accentColor : Color.gray.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .disabled(!scan.hasScan || building)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward.slash")
                .font(.system(size: 42, weight: .light))
            Text("Brak LiDAR-u").font(.headline)
            Text("Skanowanie wymaga iPada Pro (2020+) albo iPhone'a Pro 12+. Na tym urządzeniu nie ma czujnika głębi.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).frame(maxWidth: 320)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(40)
    }

    // MARK: - zakończenie

    /// Zbiera trójkąty (MainActor — bufory ARKit) i próbkuje je w tle.
    private func finish() {
        guard scan.hasScan, !building else { return }
        building = true
        scan.stop()

        // 1) odczyt buforów Metal — tylko na MainActor (wymóg ARKit)
        let triangles = scan.collectTriangles()
        let step = scan.sampleStep
        let limit = scan.maxPoints

        Task {
            // 2) próbkowanie na czystych danych — w tle
            let cloud = await Task.detached(priority: .userInitiated) {
                MeshSampler.sample(triangles: triangles, step: step, maxPoints: limit)
            }.value

            building = false
            guard cloud.count > 0 else {
                formatNote = "Skan jest pusty — nie ma czego dodać."
                return
            }
            onFinish(cloud)
        }
    }
}

#endif

/// Krótki opis tego, co użytkownik zobaczy po zakończeniu — używane w statusie.
public enum ScanOutcome {
    public static func summary(_ cloud: PointCloud) -> String {
        let b = cloud.bounds
        let s = b.max - b.min
        let mm = { (v: Float) in Int((v * 1000).rounded()) }
        return "\(cloud.count.formatted()) pkt · \(mm(s.x))×\(mm(s.y))×\(mm(s.z)) mm"
    }
}
