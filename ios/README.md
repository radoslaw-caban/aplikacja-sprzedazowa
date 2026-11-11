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
│   │   ├── Library.swift      # szablony produkcyjne
│   │   └── PointCloud.swift   # parser PLY (ASCII + binarny), decymacja
│   ├── KitchenScene/          # budowa sceny RealityKit (mm → metry)
│   │   └── SceneBuilder.swift
│   ├── KitchenApp/            # SwiftUI + RealityKit
│   │   ├── App.swift          # widok: biblioteka + scena
│   │   └── SceneView.swift    # RealityKit: mm → metry
│   └── KitchenChecks/         # samokontrola bez Xcode
└── KitchenConfigurator.xcodeproj
```

## Uruchomienie

**Mac:**
```bash
cd ios
swift run KitchenChecks   # 42 warunki, kod wyjścia 1 przy błędzie
swift test                # 9 testów XCTest
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
- [x] Scena RealityKit (`KitchenScene`): bryły w metrach, światło, podłoga, kadr
- [x] Parser PLY (ASCII + binary_little_endian) — realny skan 491 953 pkt w 0,30 s
- [x] Decymacja chmury i obrys z percentyli (odporny na punkty odstające
- [x] Projekt Xcode (iOS + macOS) generowany przez XcodeGen
- [x] Build na iOS Simulator SDK przechodzi (`xcodebuild ... BUILD SUCCEEDED`)

## Co zostaje do przeniesienia

- [ ] Dekoder E57 (własny parser `CompressedVector` albo bridge do C++ libE57)
- [x] Render chmury w RealityKit (LowLevelMesh, kubełki RGB, 0,49 mln pkt na iPadzie)
- [x] Wyrównanie skanu: auto-dopasowanie (skala/środek/podłoga) + ręczne odsunięcia i obrót
- [x] Model pomieszczenia (podłoga, ściany, listwy) jako punkt odniesienia
- [x] Powierzchnia skanu: wokselizacja 2,5 cm z kolorami (64 kubełki), liczenie w tle
- [x] Wskazywanie punktów skanu (tap → promień → woksel, DDA)
- [x] Rejestracja ściany: 2 punkty + realna długość → obrót i skala, punkt zaczepienia stały
- [ ] Wygładzanie powierzchni (normalne, decymacja) i dziury po niezeskanowanych ścianach
- [ ] Wokselizacja w release: 1,75 s dla 200 tys. pkt; w debug ~4–9 s (pakiet kompiluje się bez -O)
- [ ] Panele: edycja wnętrza, wycena, oferta PDF, warianty
- [ ] Oświetlenie: HDRI w bundle + `EnvironmentResource` dla IBL
- [ ] Zapis projektów i plików: SwiftData
- [ ] Podpisywanie, ikona, TestFlight, App Store Connect
