# Lista zadań — moduły do zrobienia

Stan na 13.11.2026. Kolejność = kolejność realizacji (od najłatwiejszych).
Pozycje oznaczone ✅ są zrobione; reszta czeka.

## Zrobione

- ✅ **Usunięcie modelu Tesla** — był CC-BY-4.0 (Ameer Studio, fanowski),
  wymagał widocznej atrybucji przy publikacji. Zastąpiony bryłą proceduralną
  (`EnvironmentBuilder.teslaProcedural`), która czyta się z 20 m tak samo.
  Zysk: −6,7 MB i zero obowiązków licencyjnych.
- ✅ **Testy w schemacie** — `xcodebuild test` nie działał (schemat bez targetu
  testowego). Dodany `KitchenCoreTests` w `project.yml`, 120 testów przechodzi.

## Do zrobienia — od najłatwiejszych

### 1. Ustawienia dźwięku (parametry globalne)
Panel w Ustawieniach: głośność ogólna, głośność UI (kliknięcia), głośność
dźwięków obiektów, wyciszenie wszystkiego, wybór „cisza nocna" (limit godzin).
Bez tego każdy dźwięk w apce gra z inną głośnością i nie da się tego zmienić.

### 2. Kolizje obiektów + interakcje między nimi
Obiekty się nie przenikają. Przy dotknięciu jednego obiektu drugim (albo
dotknięciu obiektu przez użytkownika) wynik zależy od pary: np. drzewo + wiatr
= szum liści, kamień + kamień = stuk, szkło + kamień = brzęk. Każda para ma
ustalony dźwięk. Wymaga: bryły otaczające (AABB/box) na obiektach piaskownicy,
test kolizji, tablica par → dźwięk.

### 3. Panel precyzji „Pomiar na oko"
Prawy dolny róg: aktualna precyzja (od 1 mm do 1 m), pomiar narzędziem
„Pomiar na oko" (taśma miernicza, ale teoretyczna — bo realne pomiary robią
skanery). Parametry wpisywane w dowolnym narzędziu też pokazują się w panelu.
Siatka o zmiennej gęstości, która zmienia precyzję wstawiania i dokładność
pomiarową. Ten sam parametr ma być dostępny w trybie projektu wnętrza.

### 4. `.gravityAndHeading` — prawdziwa północ
Jedna linia w `RoomScanSession`: `worldAlignment = .gravity` →
`.gravityAndHeading`. ARKit ustawia wtedy `(0,0,-1)` na północ geograficzną.
Wymaga `NSLocationWhenInUseUsageDescription` w Info.plist. Odblokowuje
pory dnia i słońce z adresu. Dokładność 5–10° — do nasłonecznienia wystarczy,
ale do geodezji nie.

### 5. Otoczenie z adresu (miasto / wieś / las)
Po wybraniu adresu program rozpoznaje typ otoczenia i sam dodaje dedykowane
otoczenie + dźwięk tła:
- **miasto** — zabudowa, ulica, szum komunikacyjny,
- **wieś** — pola, zabudowa luźna, ptaki, owady,
- **las** — drzewa do horyzontu, szum liści, dzięcioł,
- **woda** — jeśli w pobliżu rzeka/jezioro, plus szum wody.
Wymaga: reverse geocoding (CLGeocoder) + klasyfikacja + presety otoczenia.

### 6. Pory dnia + słońce z adresu
6 pór (świt, rano, południe, popołudnie, wieczór, noc), pozycja słońca liczona
z szerokości geograficznej, daty i godziny. Wymaga `.gravityAndHeading`
(punkt 4) i HDRI dla pór.

### 7. Piaskownica w 3D
`SandboxObject` ma 0 odwołań w `SceneView`/`KitchenScene` — obiekty istnieją
tylko na planszy 2D. Dodać renderowanie w scenie 3D, żeby piaskownica była
prawdziwym polem roboczym, a nie rysunkiem.

### 8. Podpięcie martwego kodu skanu (2438 linii)
Kod istnieje i jest dokończony, ale UI go nie woła:
- `ScanFit` (359) — dopasowanie skanu do pomieszczenia. **Bez tego skan jest
  bezużyteczny w praktyce.** Najwyższy priorytet w tej grupie.
- `RoomModelBuilder` (748) — kontur pomieszczenia z bryły, 0 odwołań.
- `ScanWalls` (381), `ScanKitchen` (736) — tylko w narzędziach CLI.
- `ScanRegistration` (81), `PlanMethodChooser` (133) — 0 odwołań.

### 9. Geoportal — import ukształtowania terenu
Import NMT (Numeryczny Model Terenu) z Geoportalu dla adresu, żeby teren
w piaskownicy był realny, nie płaski. To NIE jest „w locie" — raster wysokości
trzeba pobrać i przetworzyć raz na adres. Realne, ale nie natychmiastowe.

### 10. Widok okolicy ze Street View
**UWAGA — sprawdzić przed implementacją.** Google Street View zabrania
wykorzystywania swoich danych do rekonstrukcji 3D otoczenia w warunkach
licencji. Nie da się z tego zrobić „otoczenia podobnego do oryginału".
Realna ścieżka: własne zdjęcia klienta jako referencja + proceduralne
wypełnienie. Do potwierdzenia w warunkach Google, zanim cokolwiek zbudujemy.

### 11. Rangi / licencje / profil użytkownika
Moduł w rogu ekranu: ranga użytkownika (uczeń → użytkownik → pomocnik
projektanta po 10 projektach; rangi profesjonalne w złocie: architekt,
hydraulik, elektryk, posadzkarz, monter, mistrz montażu, operator maszyn,
kierownik, szef, prezes, wspólnik, członek zarządu; rangi specjalne
w perłowo-macicznych: bluźnierca, bóg softu, przystojniak). Obok ksywa.
Klik → edycja profilu: dane, avatar, procent używanych modułów.

### 12. Edytor działki (fundament już jest w web)
W iOS brak. W wersji web jest `app/src/design/plot.ts` z geometrią działki,
gęstościami siatki 1 mm–1 m i precyzją — można przenieść. Rysowanie obrysu,
zaznaczenie dojazdu, siatka o zmiennej gęstości.

### 13. Ogród + wzrost roślin
Projektowanie ogrodu i symulacja wzrostu roślin na przestrzeni lat.
Największy moduł, wymaga modelu wzrostu per gatunek i stanu „rok projektu".

## Zasady, które obowiązują przy każdej pozycji

- Wszystko w milimetrach, wymiary z realnych standardów (nie wymyślone).
- Zero plików audio w bundlu — dźwięki syntezowane proceduralnie
  (`SandboxAudio`).
- Zero modeli na licencjach wymagających atrybucji (CC0 tylko).
- Każda zmiana: build + testy + weryfikacja na żywo, potem commit.
- Apka dla iPada = natywna SwiftUI w `ios/`. Katalog `app/` to wersja webowa.
