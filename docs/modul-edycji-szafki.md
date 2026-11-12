# Moduł edycji szafki (FPS — iPad)

## Cel

Jedno dotknięcie szafki w trybie pierwszoosobowym zaznacza ją i otwiera edycję
bryły. Dwa dotknięcia otwierają front i przechodzą do edycji wnętrza.

## Sterowanie

| Gest | Efekt |
|---|---|
| 1 dotknięcie szafki | zaznaczenie (cyjanowa ramka 3D) + panel „Bryła” |
| 2 dotknięcia szafki | zaznaczenie + otwarcie frontu + panel „Wnętrze” |
| 1 dotknięcie ściany | paleta koloru ściany (bez zmian) |
| 1 dotknięcie poza szafką | zamknięcie edytora; drzwi/pies jak dotąd |
| „Przeciągnij szafkę palcem w 3D” | uzbraja przesuwanie: przeciągnięcie sceny zmienia X/Z szafki |

Panel jest po prawej stronie, żeby cały czas widzieć szafkę w 3D.

## Bryła (1 dotknięcie)

- **Wymiary**: szerokość 150–2400 (co 50), wysokość 300–2400 (co 18),
  głębokość 300–650 (co 10), cokół 0–220 (co 5), montaż szafki wiszącej.
- **Położenie w budynku**: X/Z co 10 mm, obrót 0/90/180/270°, przycisk
  „Przyciągnij plecami do najbliższej ściany”.
- **Przeciąganie palcem w 3D**: przycisk uzbraja tryb; ruch palca przesuwa
  szafkę po podłodze w osiach kamery (skala zależna od odległości), z
  ograniczeniem do pomieszczenia. Po puszczeniu pozycja zapisuje się w projekcie.
  Gdy tryb jest wyłączony, przeciągnięcie nadal obraca widok.
- **Rodzaj**: dolna / wisząca / stojąca / zaślepka.
- **Szablon z biblioteki**: `Library.all` (Dolna 600 / 3 szuflady, Pod umywalkę,
  Wisząca, Stojąca itd.) — ustawia wymiary i wyposażenie.
- **Przeznaczenie**: gotowanie, czystość/zlew, wysoka zabudowa, wyspa,
  garderoba, RTV/salon, łazienka, przechowywanie.
- Nazwa szafki edytowalna.

Każda zmiana jest natychmiast odtwarzana w scenie 3D (`FirstPersonWorld.updateCabinets`).
„Zapisz szafkę” zapisuje do `projects.json`.

## Wnętrze (2 dotknięcia)

- Front odjeżdża w bok i obraca się o 90° (szuflady wysuwają się do przodu),
  dzięki czemu widać środek.
- Lista elementów: półki i szuflady N/M/K (Blum LEGRABOX 66,5 / 90,5 / 128,5 mm).
- Dla każdego elementu lista **co będzie przechowywane**: talerze, kubki,
  garnki, sztućce, butelki, produkty, pieczywo, ręczniki, kosmetyki, ubrania,
  buty, książki, sprzęt RTV, środki czystości, inne.
- Wybór asortymentu:
  - ustawia zalecaną wysokość (np. talerze 300, kubki 200, garnki 350,
    sztućce 90 mm),
  - dla szuflad dobiera system Blum (N/M/K),
  - przelicza położenie elementów od dołu (`autoLayout`),
  - dokłada modele towarów w 3D (talerze, kubki, butelki, książki itd.).
- „Ułóż” — ponowne rozłożenie według asortymentu.
- „Dodaj” — półka albo szuflada N/M/K.
- Menu elementu — przesunięcie o ±10 mm, usunięcie.

## Model danych

```swift
Cabinet.purpose: CabinetPurpose?        // nowe, opcjonalne (zgodność JSON)
CabinetElement.storage: StorageKind?    // nowe, opcjonalne
```

`StorageKind` (KitchenCore/Storage.swift) zawiera etykiety, ikony, zalecane
wysokości i domyślny system szuflad. Stare projekty czytają się bez zmian.

## Weryfikacja

- `swift build` — OK.
- `xcodebuild -sdk iphonesimulator` — BUILD SUCCEEDED.
- Przeciągnięcie: X -300 → -128 mm, panel pokazuje nową wartość, zapis w JSON.
- Symulator iPad Pro 13" (M5):
  - jedno dotknięcie → panel bryły, cyjanowa ramka, wymiary 600×862×560,
  - dwa dotknięcia → front otwarty, lista 3 szuflad, przycisk „Ułóż”,
  - wybór „Talerze” → `storage: plates` w JSON, `y: 282`,
  - w 3D widać stos talerzy na półce słupka.
- Na iPadzie fizycznym **nie instalowano** (zgodnie z prośbą).
- Uwaga: moduł FPS jest obecnie schowany za ustawieniem
  `showFirstPersonModule` (domyślnie wyłączony) — włącz go w Ustawieniach,
  żeby wejść do sceny pierwszoosobowej.

## Następne kroki

- Przeciąganie szafki palcem po scenie (teraz X/Z przyciskami).
- Zaznaczanie wielu szafek i wyrównywanie ciągu.
- Kosz i drążek jako osobne akcesoria wnętrza (teraz półka/szuflada).
- Podgląd „co się nie zmieści” przy zbyt niskim wnętrzu.
