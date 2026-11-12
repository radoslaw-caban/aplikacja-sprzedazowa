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

- `KitchenChecks --cutouts` → **20/20 OK** (w tym półki, zawiasy, akcesoria,
  10 tekstur wykończeń):
  - zlew 560 × 460 na wysokości 901 mm (przycięty do szafki 600),
  - uchwyt 160 × 26 na froncie (y = 772 mm),
  - Codable.
- `KitchenChecks --models` → wszystkie 6 modeli GLB wczytane.
- `swift build` — OK; `xcodebuild -sdk iphonesimulator` — BUILD SUCCEEDED.
- Edytor na symulatorze iPad Pro 13": lista 12 szafek, karta „Zlew”, dodawanie
  wycięcia, zmiana płaszczyzny i wymiarów.
- Zakładka „Projekt 3D kuchnia”: kadr wewnętrzny liczony z zabudowy (nie ze
  skanu); widać czarne wycięcie zlewu na blacie oraz uchwyty na frontach.

## Edytor szafek (bez FPS)

Menu boczne → **Projekt** → **Szafki — edytor**.

- lista wszystkich szafek z wymiarami, typem i przeznaczeniem,
- wymiary, położenie w budynku, obrót, przyciąganie do ściany,
- rodzaj (dolna/wisząca/stojąca/zaślepka), szablon z biblioteki, przeznaczenie,
- **wykończenie**: wyłącznie tekstury — 10 wbudowanych (dąb naturalny,
  dąb bielony, orzech, wiśnia, biel matowa, grafit, beż piaskowy, oliwka,
  beton jasny, aluminium szczotkowane) + tekstury użytkownika.
  Nowe szafki bez wyboru dostają domyślnie dąb naturalny; tekstura trafia na
  front, boki oraz górę i dół korpusu, nie tylko na skrzydło.
- **liczba drzwi**: 1 lub 2 skrzydła (Generator dzieli front z 3 mm szczeliną),
- wnętrze: **liczba półek (0–12)** i **rozstaw (120–600 mm)** — półki rozkładają
  się nad szufladami, zachowując przypisany asortyment,
- **zawiasy**: standard clip / soft-close Blumotion / push-to-open Tip-On / brak,
  po 2 na skrzydło (przy 2 drzwiach po obu stronach),
- **akcesoria wnętrza**: kosz wyciągany, drążek, organizer sztućców, kosz na
  odpady, przegrody, półka szklana, LED; wysokość regulowana co 50 mm,
- półki/szuflady i asortyment,
- duplikowanie, usuwanie, odłączanie szafki od strefy,
- dodawanie nowej szafki z biblioteki (stawiana przy ścianie).

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
