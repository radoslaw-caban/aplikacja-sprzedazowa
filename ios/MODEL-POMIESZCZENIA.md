# Model pomieszczenia ze skanu — moduł `KitchenCore/RoomModel`

Moduł niezależny od UI i od ARKit: dostaje chmurę punktów, zwraca narożniki,
kontur i ściany z odchyłkami. Można go włączyć do aplikacji w dowolnym momencie
— nie wymaga zmian w innych plikach.

```
RoomModel.swift          typy: Sample, Corner, Wall, Opening, Result, Options
RoomModelBuilder.swift   detekcja: podłoga/sufit → kontur → ściany → otwory
RoomPlanTracker.swift    zbieranie planu w trakcie skanowania (kontur na żywo)
```

## Użycie

```swift
let samples = cloud.positions.map {
    RoomModel.Sample(position: $0, sigma: 0.004)
}
guard let model = RoomModel.build(from: samples) else { return }

print(model.corners.count)          // narożniki
print(model.area)                   // pole z konturu, m²
print(model.height)                 // wysokość pomieszczenia, m
for wall in model.walls {
    print(wall.length,              // długość, m
          wall.residualP95,         // wygięcie ściany, m (95 percentyl)
          wall.plumbMmPerM)         // pion, mm/m
}
for opening in model.openings {
    print(opening.kind,             // .window / .door
          opening.offset, opening.width, opening.sill, opening.height)
}
```

Kontur na żywo w trakcie skanowania:

```swift
let tracker = RoomPlanTracker()
tracker.add(points: depthFrame.positions(), floorY: 0)
if let snap = tracker.refreshIfNeeded(minInterval: 1.2) {
    print(snap.outline, snap.area)   // narysuj linie
}
```

## Metoda

1. **Poziom podłogi** — najgęstszy pik histogramu wysokości w dolnych 40% skanu.
   **Sufit** — najgęstszy pik powyżej 1,8 m nad podłogą.
2. **Kontur** — z pasma pod sufitem (nie przy podłodze):
   punkty → siatka zajętości 3 cm → pogrubienie 1 komórki → zalewanie z zewnątrz
   → wnętrze = to, czego zalewanie nie dosięgło → śledzenie brzegu (Moore)
   → uproszczenie (Douglas–Peucker, 5 cm).
3. **Dopracowanie konturu** — każda krawędź liczona najmniejszymi kwadratami
   z SUROWYCH punktów w jej pobliżu, narożniki jako przecięcia sąsiednich linii.
   Dwa przebiegi. Bez tego kontur byłby przesunięty o grubość pogrubienia siatki.
4. **Ściany** — każda krawędź konturu dostaje pionową płaszczyznę dopasowaną do
   punktów; raportujemy medianę i 95 percentyl odchyłki oraz pion (mm/m).
5. **Otwory** — na siatce „wysokość × długość" ściany szukamy spójnych obszarów
   bez punktów (≥ 0,4 × 0,4 m). Drzwi = obszar sięga podłogi, okno = nie.

### Dlaczego akurat tak — odrzucone metody (zmierzone)

| Metoda | Wynik |
|---|---|
| Bounding box | 10,35 × 9,02 m przy realnej podłodze 8,94 × 6,22 m |
| Profil promieniowy od środka | prostokąt 4×3 m → 8 narożników, boki 0,35 / 0,48 / 1,31 / 1,48 m |
| Hough / histogram (kąt, offset) | 4 ściany → 2 lub 3: PCA zwraca losowy zwrot normalnej, więc ta sama ściana trafia do dwóch koszy, a naprzeciwległe bywają scalane |
| **Siatka zajętości + śledzenie brzegu** | **4,00 × 3,00 m co do centymetra** |

Profil promieniowy nie działa, bo dla ściany promień nie jest kawałkami liniowy —
uproszczenie konturu łapie wtedy fałszywe załamania. Hough wymaga spójnego zwrotu
normalnej, którego PCA nie daje; każda próba łaty psuła inny przypadek.

## Zmierzone wyniki (syntetyczne, znane wymiary)

| Test | Wynik |
|---|---|
| Prostokąt 4 × 3 m | 4 narożniki, 4 ściany, 4,00 / 3,00 m ±2 cm, pole 12,00 m² |
| L-kształt (pole 12 m², 6 narożników) | 6 narożników, 6 ścian, pole 12 m² ±0,3 |
| Ściana wygięta 3 cm | wykryta: p95 = 30 mm; ściany proste p95 < 15 mm |
| Pokój 5 × 4 m z oknem i drzwiami | 4 narożniki (kontur bez rozdarć), drzwi 0,9 m / próg 0 / wys. 2,05 m, okno próg 0,9 m |
| Pusty zbiór / brak podłogi | `nil` (bez wyjątku) |

Testy: `swift run KitchenChecks` → sekcja „Model pomieszczenia" (37 sprawdzeń).

## Ograniczenia — przeczytaj przed użyciem w produkcji

- **Dokładność bezwzględna zależy od skanu, nie od tego modułu.** Na danych
  syntetycznych wychodzi ±2 cm, bo szum jest modelowy. Realny LiDAR iPada ma
  błąd systematyczny 1–2 cm na 5 m, którego żadna obróbka nie usunie.
  Do wymiarowania pod zabudowę zostaje Trimber X9.
- **Otwory przy meblach są niepewne.** Duża szafa pod ścianą daje taki sam
  „brak punktów" jak okno. Detekcja nie odróżnia mebla od otworu.
- **Pomieszczenie musi być zamknięte w skanie.** Przy otwartych drzwiach na
  korytarz zalewanie ucieka — dlatego kontur liczy się pod sufitem, ale przy
  szerokim przejściu bez nadproża (np. przejście do salonu) może się nie domknąć.
- **Sufit musi być widziany** albo pasmo nadproży wystarczająco gęste. Bez sufitu
  moduł bierze 97 percentyl wysokości — dla skanu urywającego się w połowie
  ściany da zaniżoną wysokość.
