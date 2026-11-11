# Strefy zabudowy — moduł w aplikacji iPad (KitchenApp)

Status: WDROŻONY (v1), zbudowany i sprawdzony na symulatorze iPad Pro 13" (M5).

## Gdzie jest moduł

```
ios/Sources/KitchenCore/
  ZoneModel.swift     model: ZoneKind, Zone, ZoneValue, pytania, plan części
  ZoneLibrary.swift   biblioteka 8 stref: opisy zależności, odpowiedzi domyślne, pytania
  ZonePlan.swift      czyste reguły (gotowanie, czystość, wysoka, wyspa, szafy, RTV, łazienka)
  Zones.swift         geometria ściany planu → szafki, przebudowa stref, podsumowanie
ios/Sources/KitchenApp/
  ZoneDesignerView.swift   biblioteka + kreator pytań + podsumowanie na żywo
```

`Generator`, `Runs`, `Types` i `Project` zostały rozszerzone:
- `Cabinet`: `zoneID`, `zoneRole`, `appliances`, `slidingPanels`, `worktopDepth/shift`
  (pola opcjonalne — stare projekty czytają się bez zmian),
- `Generator`: bryły AGD (zlew, płyta, piekarnik, mikrofala, lodówka, okap, zmywarka,
  TV, lustro, umywalka) i panele szafy przesuwnej,
- `Runs`: blat o głębokości z nawisem (wyspa) i cokół o realnej wysokości szafek,
- `Project`: `zones: [Zone]?`.

## Jak się używa

1. **Dom (plan)** → klik w ścianę → panel ściany → **Strefa…**
   (albo menu z lewej krawędzi → **Strefy zabudowy**).
2. Wybierz rodzaj zabudowy — program od razu wstawia gotową propozycję na ścianie.
3. Kreator zadaje pytania (13 dla strefy gotowania): długość ciągu, ustawienie, płyta,
   pozycja płyty na blacie, okap, piekarnik + mikrofala, lodówka, witryny, zmywarka,
   szafki górne, wysokość blatu, fronty. Każda odpowiedź przebudowuje tylko tę strefę.
4. Podsumowanie na żywo (liczba szafek, frontów, urządzeń, długość) + ostrzeżenia
   (za krótka ściana, zmywarka pominięta, strefa pracy < 400 mm).
5. Zamknięcie arkusza zostawia strefę w projekcie; usunięcie strefy usuwa tylko jej szafki.

## Reguły (takie same jak w web)

- Cokół liczony z wysokości blatu: `H − 38 − 720`, 80–220 mm.
- Płyta 600/800, strefy pracy min. 400 mm, szuflady pod płytą, okap 650 mm.
- Zlew 600/800/900 i pozycja na blacie (suwak), zmywarka 600 obok zlewu, kosz pod zlewem.
- Lodówka 600/700/900, słupek piekarnika 600, witryny 400 na końcach.
- Szafy: 600 otwierana / 650 przesuwna (2–3 panele), do sufitu lub 2216.
- Wyspa: blat 860 z nawisem 300, okap sufitowy, ostrzeżenie o przejściach < 900.
- RTV: szafka 400–500 wys., TV 55–83", nadbudowa nad ekranem.
- Łazienka: umywalka 850, lustro LED, słupek 400.

## Weryfikacja

- `swift run KitchenChecks` → **208/208** warunków (w tym 25 nowych dla stref:
  wymiary, cokół, witryny, zmywarka przy zlewie, wyspa, szafy, RTV, łazienka,
  materializacja na ścianie planu, przebudowa bez ruszania szafek ręcznych, Codable).
- `swift build` i `xcodebuild … -sdk iphonesimulator` → BUILD SUCCEEDED.
- Symulator iPad Pro 13" (M5): kreator otwiera się z gotową propozycją, pytania
  i podsumowanie działają, strefa jest widoczna w scenie 3D.
- Poprawka kamery wewnętrznej: `SceneView.baseCamera` stawia kamerę między zabudową
  a przeciwległą ścianą (wcześniej kadr wychodził przed elewację).

## Ograniczenia v1 / następne kroki

- Ściana wybierana z **planu** (klik w ścianę → Strefa…) albo z listy; bezpośredni
  raycast w scenie 3D (tap w płaszczyznę ściany) — do dodania, wymaga unprojection
  kamery RealityKit.
- Brak otworów (okna/drzwi) w modelu `FloorPlan` — strefy nie omijają jeszcze okien
  i drzwi na ścianie; w web są.
- Kamera nie zjeżdża jeszcze na pytanie (zlew/płyta/piekarnik) — jest kadr wewnętrzny
  całości; następny krok: `focus` w SceneView.
- Ciągi L/U na dwóch ścianach, zestawienie materiałów strefy do oferty PDF.
