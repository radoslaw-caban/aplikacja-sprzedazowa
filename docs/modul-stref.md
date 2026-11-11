# Moduł: strefy zabudowy (auto-projektowanie mebli)

Status: WDRAŻANY (v1)

## Cel

W narysowanym budynku/pomieszczeniu użytkownik klika **płaszczyznę ściany w widoku 3D**.
Ściana staje się **ścianą projektową** (podświetlona, z opisem długości i przeszkód).
Następnie wybiera **rodzaj strefy z biblioteki** — program od razu wstawia gotową
propozycję zabudowy, a potem doprecyzowuje ją **pytaniami** (typ lodówki, rodzaj zlewu,
miejsce płyty, piekarnik z mikrofalą, witryny, wysokość blatu…) z jednoczesnym
zbliżeniem kamery na omawiany element.

Wszystko deterministyczne: strefa = odpowiedzi + ściana → generator szafek z biblioteki
parametrycznej. Żadnych „wymyślonych" wymiarów — stałe produkcyjne (korpus 720, blat 38,
cokół 100–150, głębokości 350/560/561/600/650).

## Model danych

```ts
interface Zone {
  id: string;
  kind: ZoneKind;              // 8 typów z biblioteki
  side: 'north'|'south'|'east'|'west';  // kliknięta ściana
  start: number;               // początek zabudowy od lewej krawędzi ściany (mm)
  answers: Record<string, string|number|boolean>;
  name: string;
}

interface ZonePlan {           // wynik reguł — czysty, testowalny
  parts: ZonePart[];           // szafki w kolejności, z rolami i urządzeniami
  start: number; width: number;
  notes: string[]; warnings: string[];
}
```

Szafki wygenerowane przez strefę mają `zoneId` i `zoneRole` (np. `sink`, `hob`,
`fridge`, `oven`, `tv`) — dzięki temu przebudowa strefy nie rusza reszty projektu,
a kamera wie, na co zjechać.

Zapis w projekcie: `ProjectData.zones: Zone[]` (zgodne wstecz — brak pola = brak stref).
Kabinet dostaje `appliances[]` (zlew, płyta, piekarnik, mikrofala, lodówka, okap,
zmywarka, TV, umywalka, lustro) rysowane przez generator.

### Decyzje wykonawcze

- **Światło drzwi jest wyłączone z zabudowy.** Planner dostaje `usableFrom/usableLength`
  (odcinek ściany poza skrzydłem); przy za krótkim odcinku skraca ciąg i pokazuje
  ostrzeżenie. Dzięki temu „gotowa propozycja" nigdy nie staje w drzwiach.
- **Wysokość blatu liczona od podłogi.** `RunSpec.bodyTop` = cokół + korpus (+ montaż),
  więc blat leży na korpusie (wcześniej leżał 130–150 mm za nisko — błąd naprawiony
  przy okazji stref). Cokół biegu bierze realną wysokość z szafek, nie z ustawień globalnych.
- **Panele AGD 4 mm przed frontem** — piekarnik, mikrofala, lodówka i zmywarka nie
  znikają pod drzwiami (brak z-fightingu).
- **Wyspa:** korpus 560, blat 860 = 560 + nawis 300 na siedzenie; blat przesunięty
  lokalnie o 150 mm, okap sufitowy z kanałem do sufitu.
- **Kamera:** `frameWall` dla pytań ogólnych, `frameAt` (2,2 m, zawsze wewnątrz
  pomieszczenia) dla pytań o konkretne urządzenie.


## Biblioteka stref (v1)

| Strefa | Bazowe reguły |
|---|---|
| Kuchnia — gotowanie | Płyta 600/800, strefy pracy min. 400 z każdej strony, szuflady pod płytą (nie skrzydła), okap 650 nad płytą, słupek piekarnika 600, lodówka 600/700/900 na końcu, witryny 400 na obu końcach, szafki górne 600 od blatu |
| Kuchnia — czystość | Zlew 600/800/900, ociekacz, zmywarka 600 obok zlewu, kosz pod zlewem, szafki górne z pominięciem okna, blat 860–910 |
| Kuchnia — wysoka zabudowa | Lodówka + słupek piekarnik/mikrofala + spiżarnia 450/600/900, wysokość 2216 lub do sufitu, cokół 150 |
| Kuchnia — wyspa | 1800–3600, blat 900 z nawisem 300 na siedzenie, okap sufitowy nad płytą, przejścia min. 900 |
| Sypialnia — szafa otwierana | Głęb. 600, skrzydła 400–600, wymagane 600 przed szafą, wys. 2216/do sufitu |
| Sypialnia — szafa przesuwna | Głęb. 650, 2/3 panele, bez strefy otwierania, prowadnice góra/dół |
| Salon — strefa RTV | Niska szafka 400–450 wys., 400 głęb., TV 55"/65"/75", opcja wisząca, nadbudowa górna |
| Łazienka | Szafka pod umywalkę 800/1000/1200, umywalka + lustro z podświetleniem, słupek 400, cokół 0–100 |

## Pytania sterujące (przykłady)

- **Rodzaj lodówki**: do zabudowy 600 / wolnostojąca 700 / side-by-side 900 / brak.
- **Zlew**: 1-komorowy 600 / 1,5-komorowy 800 / 2-komorowy 900 / brak.
- **Gdzie zlew**: suwak pozycji po ciągu + tryb przesuwania w 3D (klik/przeciągnięcie
  palcem po blacie — zlew przeskakuje między modułami).
- **Płyta grzewcza**: indukcja 600 / indukcja 800 / gaz 600 / brak — to samo przesuwanie.
- **Piekarnik z mikrofalą**: słupek 600 z niszą piekarnika i mikrofali / pod blatem / brak.
- **Witryny na końcu mebli**: tak/nie (szklane, 400, na obu końcach).
- **Wysokość blatu**: 860 / 880 / 900 / 910 mm → cokół liczony automatycznie
  (`cokół = H − 38 − 720`, 80–220 mm).
- **Fronty**: z uchwytami / bezuchwytowe.
- **Szerokość zabudowy** i **ustawienie na ścianie** (lewo/środek/prawo).

Każde pytanie ma przypisany element (`feature`), na który kamera zjeżdża
(`frameInterior`): zlew, płyta, piekarnik, lodówka, szafa, TV.

## Przebieg w aplikacji

1. Zakładka **Strefy**. Klik w ścianę w 3D → `pickWall()` (raycast matematyczny po
   4 płaszczyznach) → podświetlenie ściany + długość/przeszkody (okno, drzwi).
2. Klik w typ strefy → **natychmiastowa propozycja** (domyślne odpowiedzi) +
   przebudowa sceny + kadr na strefę.
3. Kreator po prawej: pytanie → odpowiedź → natychmiastowa przebudowa tej strefy
   (pozostałe szafki nietknięte). Krok wstecz/dalej, podsumowanie, ostrzeżenia.
4. Przeszkody: drzwi przesuwają start zabudowy, okno usuwa szafki górne w tym miejscu,
   za długa zabudowa → ostrzeżenie i pominięcie elementów opcjonalnych.
5. Zapis w projekcie; usunięcie strefy usuwa tylko jej szafki.

## Architektura plików

- `app/src/design/zonePlan.ts` — **czyste reguły** + biblioteka stref + pytania
  (bez importów runtime → testowalne w Node).
- `app/src/design/zones.ts` — geometria ścian, przeszkody, materializacja planu do `Cabinet[]`.
- `app/src/design/appliances.ts` — bryły AGD/urządzeń (zlew, płyta, piekarnik, okap, TV…).
- `app/src/ui/ZoneWizard.tsx` — kreator pytań i podsumowanie.
- `app/src/engine/ThreeEngine.ts` — `pickWall`, `highlightWall`, `frameWall`.
- `app/tools/test-zone-plan.mts` — testy reguł (`npm run test:zones`).

## Kolejność prac

1. [x] Model stref + reguły + pytania (czysty planner)
2. [x] Materializacja do szafek, urządzenia, blaty z nawisem
3. [x] Wybór ściany w 3D + podświetlenie + kadrowanie
4. [x] Kreator pytań z natychmiastową propozycją i zbliżeniem
5. [x] Przesuwanie zlewu/płyty po blacie (suwak + klik w 3D)
6. [x] Zapis w projekcie, usuwanie strefy
7. [x] Testy reguł, build, deploy
8. [ ] v2: ciągi L/U (dwie ściany), przeszkody kolumny/kaloryfery, eksport zestawienia do PDF
