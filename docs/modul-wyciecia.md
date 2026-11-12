# Wycięcia w szafkach (zlew, płyta, uchwyty, przepusty)

## Gdzie w aplikacji

Menu boczne (wysuwane z lewej) → **Projekt** → **Wycięcia w szafkach
(zlew, płyta, uchwyty)**. Otwiera się pełnoekranowy edytor: lista szafek po
lewej, karta wycięć po prawej.

## Model danych

```swift
Cabinet.cutouts: [CabinetCutout]?          // nowe, opcjonalne (stare JSON-y OK)

CabinetCutout {
  plane: top | front | side
  purpose: sink | hob | handle | cable | vent | niche | other
  x, y, width, height, cornerRadius      // mm
}
```

- `top` — blat/góra: X po szerokości, Y po głębokości.
- `front` — front: X po szerokości, Y od dolnej krawędzi korpusu.
- `side` — prawy bok: X po głębokości, Y od dolnej krawędzi.

## Presety

| Przeznaczenie | Płaszczyzna | Wymiar nominalny |
|---|---|---|
| Zlew | blat | 780 × 460, r 15 |
| Płyta grzewcza | blat | 560 × 490, r 10 |
| Uchwyt | front | 160 × 26 |
| Przepust kablowy | bok | 60 × 60 |
| Wentylacja | front | 300 × 80 |
| Wnęka / nisza | front | 500 × 300 |

Po zmianie przeznaczenia program dobiera płaszczyznę, wymiary, wysokość
i promień; wymiary są przycinane do szerokości/wysokości szafki.

## Geometria 3D

`Generator.build` dokłada bryłę roli `.cutout` (ciemna płyta 2 mm):

- blat: na górnej powierzchni blatu (`wysokość szafki + blat + 1 mm`),
- front: `z = głębokość/2 + 22 mm`,
- bok: `x = szerokość/2 + 1 mm`.

`SceneView.sceneSignature` uwzględnia wycięcia, więc scena odświeża się po
każdej zmianie. Zmiany zapisują się od razu przez `AppModel.updateCabinet`.

## Weryfikacja

- `KitchenChecks --cutouts` → **9/9 OK**:
  - zlew 560 × 460 na wysokości 901 mm (przycięty do szafki 600),
  - uchwyt 160 × 26 na froncie (y = 772 mm),
  - Codable.
- `KitchenChecks --models` → wszystkie 6 modeli GLB wczytane.
- `swift build` — OK; `xcodebuild -sdk iphonesimulator` — BUILD SUCCEEDED.
- Edytor na symulatorze iPad Pro 13": lista 12 szafek, karta „Zlew”, dodawanie
  wycięcia, zmiana płaszczyzny i wymiarów.

## Modele okuć i akcesoriów

Pobrane i dodane do `ios/Resources/Models`:

- Kenney Furniture Kit (CC0): `kenney_kitchen_cabinet.glb`, `kenney_drawer.glb`,
  `kenney_cabinet_bed_drawer.glb`.
- Innerscene (CC0) źródła STEP: zawias puszkowy 35 mm, prowadnica kulkowa
  250 mm, zawias 30 × 30 mm — w `Resources/Models/HardwareSources`.
- Proksy GLB wygenerowane na tych wymiarach: `hardware_hinge_35.glb`,
  `hardware_slide_250.glb`, `hardware_handle_160.glb`.

`SceneBuilder.hardwareEntity` wstawia zawiasy na skrzydłach, prowadnice i uchwyty
przy szufladach oraz uchwyty na frontach. Licencje i adresy źródeł:
`ios/Resources/Models/HardwareSources/CREDITS.md`.
