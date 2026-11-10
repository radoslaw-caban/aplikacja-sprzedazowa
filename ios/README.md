# Konfigurator (SwiftUI + RealityKit)

Wersja natywna dla Apple: iPad, iPhone, Mac. Cel: App Store.

## Dlaczego Swift, a nie web

| | Swift + RealityKit | Web (obecne) |
|---|---|---|
| Jakość renderu | PBR + IBL + miękkie cienie + AA, Metal | WebGL, ograniczone |
| App Store | natywnie, bez wrappera | wrapper (ryzyko odrzucenia) |
| Testowanie | Xcode + symulator + TestFlight | przeglądarka |
| Formularze, tabele, wycena | SwiftUI | HTML/React |

## Struktura

```
ios/
├── Package.swift              # pakiet SwiftPM (KitchenCore + KitchenApp + KitchenChecks)
├── project.yml                # specyfikacja XcodeGen → KitchenConfigurator.xcodeproj
├── Sources/
│   ├── KitchenCore/           # logika domenowa, bez UI, w 100% testowalna
│   │   ├── Types.swift        # mm, standardy, Cabinet, Box
│   │   ├── Generator.swift    # korpus, fronty, wyposażenie
│   │   ├── Runs.swift         # biegi, blat, cokół, cień kontaktowy
│   │   ├── Collision.swift    # kolizje, wolne miejsce, punkty chwytu
│   │   └── Library.swift      # szablony produkcyjne
│   ├── KitchenApp/            # SwiftUI + RealityKit
│   │   ├── App.swift          # widok: biblioteka + scena
│   │   └── SceneView.swift    # RealityKit: mm → metry
│   └── KitchenChecks/         # samokontrola bez Xcode
└── KitchenConfigurator.xcodeproj
```

## Uruchomienie

**Mac (bez Xcode):**
```bash
cd ios
swift run KitchenChecks   # 25 warunków, kod wyjścia 1 przy błędzie
swift run KitchenApp      # okno z biblioteką i sceną 3D
```

**iPad / iPhone (wymaga Xcode.app + zalogowanego Apple Developer):**
```bash
cd ios
xcodegen generate                     # po każdej zmianie project.yml
open KitchenConfigurator.xcodeproj
# wybierz schemat KitchenConfigurator, symulator iPad Pro, ⌘R
```

Do App Store: Xcode → Product → Archive → Distribute → App Store Connect.
TestFlight: po wgraniu build pojawia się w App Store Connect → TestFlight.

## Co jest przeniesione

- [x] Model w mm, standardy produkcji (720/560/18/38, LEGRABOX 66.5/90.5/128.5)
- [x] Generator korpusu: boki, dno, wieniec, plecy, front z fazą
- [x] Biegi: blat na korpusie (739 mm), cokół cofnięty 40 mm, cień kontaktowy
- [x] Kolizje, dokładanie w rzędzie, wolne miejsce na szufladę
- [x] Biblioteka szablonów (dolne, wiszące, stojące)
- [x] Scena RealityKit z bryłami, światłem kierunkowym i podłogą
- [x] Projekt Xcode (iOS + macOS) generowany przez XcodeGen

## Co zostaje do przeniesienia

- [ ] Chmura punktów: dekoder PLY (łatwe) i E57 (własny parser lub bridge C++ libE57)
- [ ] Render chmury w RealityKit (Metal point cloud, do 8 mln punktów)
- [ ] Panele: edycja wnętrza, wycena, oferta PDF, warianty
- [ ] Oświetlenie: HDRI w bundle + `EnvironmentResource` dla IBL
- [ ] Zapis projektów i plików: SwiftData
- [ ] Podpisywanie, ikona, TestFlight, App Store Connect
