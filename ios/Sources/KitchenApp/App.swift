import SwiftUI
import KitchenCore

@main
struct KitchenApp: App {
    @State private var cabinets: [Cabinet] = [
        Library.make(Library.base[0], at: -1200, z: -2200),
        Library.make(Library.base[1], at: -600, z: -2200),
    ]

    var body: some Scene {
        WindowGroup {
            ContentView(cabinets: $cabinets)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

struct ContentView: View {
    @Binding var cabinets: [Cabinet]

    var body: some View {
        NavigationSplitView {
            List {
                Section("Szafki podblatowe") {
                    ForEach(Library.base) { t in
                        Button {
                            add(t)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.callout)
                                Text(t.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Wiszące") {
                    ForEach(Library.wall) { t in
                        Button { add(t) } label: { Text(t.name).font(.callout) }
                    }
                }
                Section("Stojące") {
                    ForEach(Library.tall) { t in
                        Button { add(t) } label: { Text(t.name).font(.callout) }
                    }
                }
            }
            .navigationTitle("Biblioteka")
            .frame(minWidth: 240)
        } detail: {
            VStack(spacing: 0) {
                SceneView(cabinets: cabinets)
                HStack {
                    Text("\(cabinets.count) szafek")
                    Spacer()
                    Button("Wyczyść") { cabinets.removeAll() }
                }
                .padding(12)
            }
        }
    }

    private func add(_ t: Library.Template) {
        let new = Library.make(t)
        if let placed = Generator.placeNext(to: cabinets, new: new) {
            cabinets.append(placed)
        } else {
            cabinets.append(new)
        }
    }
}
