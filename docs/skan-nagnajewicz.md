# Skan Nagnajewicz 1462.glb — analiza i odczyt kuchni

Plik: `/Users/radoslawcaban/Dom /Chmura dom/Nagnajewicz 1462.glb` (17,7 MB).

## Co to jest

| Cecha | Wartość |
|---|---|
| Format | glTF 2.0 binary (GLB), generator **SimLab GLTF** (eksport ze SketchUp) |
| Rozszerzenia | `KHR_materials_pbrSpecularGlossiness` |
| Węzły / siatki / materiały | 3966 / 1003 / 55 |
| Trójkąty | 364 219 |
| Skala jednostki | 0,01 (model w centymetrach → po transformacji metry) |
| Nazwy obiektów | brak znaczących — wszystko `Geom3D_#…` (SketchUp nie przeniósł nazw komponentów) |

Obrys całej sceny: 29,9 × 2,8 × 15,2 m — to nie jest samo pomieszczenie, ale cały
fragment budynku (kilka pomieszczeń, meble, sprzęt).

## Kuchnia w środku

Kuchnia leży w rejonie `x ≈ 9,6–12,5`, `z ≈ -15,6…-11,7`:

* **blat na wysokości 0,84–0,86 m** (pas poziomych powierzchni skierowanych w górę),
* **kuchnia jest obrócona o ~11°** względem osi sceny (potwierdzone dwiema metodami:
  PCA blatów 10,9°, detektor 11,0°),
* kształt **L**: dłuższe ramię ~3,9 m i krótsze ~2,9 m, głębokość blatu 0,6 m,
* łączna długość zabudowy ~6,2 m (ramiona spotykają się w narożniku).

W pasie 0,72–1,05 m detektor naliczył 14,35 m² powierzchni „blatowej" — oprócz
kuchni łapie też stół i inne poziome płaszczyzny w pomieszczeniu.

## Moduł `ScanKitchen` (KitchenCore)

Niezależny od UI, bez RealityKit — wejście to trójkąty w metrach.

1. **Blaty** — trójkąty poziome (`|n.y| > 0,85`) w pasie 0,72–1,05 m.
2. **Orientacja** — kąt, przy którym punkty tworzą najostrzejsze histogramy rzutów
   (krok 1°, doprecyzowanie 0,5°). Obwiednia zawodziła na L-kach (kwadratowa → 60°),
   krawędzie trójkątów mają przekątne, więc też nie.
3. **Rasteryzacja** 5 cm i spójne wyspy.
4. **Pasy** — prostokąty o głębokości 0,48–0,70 m i wypełnieniu ≥ 85%; pas grubszy
   niż blat (750 mm) przegrywa z właściwym 600 mm.
5. **Przy ścianie** — bieg musi mieć pionową powierzchnię (wys. > 1,2 m) za jedną
   z długich krawędzi; to odsiewa stoły i wyspy.
6. **Moduły** — równe szerokości najbliższe 600 mm (300–1000), suma = długość
   biegu co do 1 mm.

### Wynik na tym pliku

```
obrót kuchni: 11,0°   blat: 858 mm   powierzchnia blatów: 14,35 m²
biegi: 2, moduły: 8, suma: 4750 mm
  bieg 1: 3500 × 550 mm  kąt 101,0°  moduły 6 × [583, 583, 583, 583, 583, 585]
  bieg 2: 1250 × 600 mm  kąt 101,0°  moduły 2 × [625, 625]
```

Po dodaniu scalania współliniowych odcinków (przerwa ≤ 400 mm) trzy fragmenty
ramienia zlały się w jeden bieg 3,5 m. Nadal brakuje **drugiego ramienia L**
(powinno mieć ~2,9 m pod kątem ~11°, a wszystko wychodzi 101°) i 1,25 m
„ogona" na równoległej linii 0,45 m od pierwszego biegu — to prawdopodobnie
druga płaszczyzna tego samego blatu (np. część przy okapie), a nie osobny bieg.

Ścieżka „biegi wzdłuż ścian" (`useWallRuns`) jest napisana, ale **domyślnie
wyłączona**: w tym pliku są ściany z całego mieszkania, więc kierunki wychodziły
95–179° zamiast 11/101°. Potrzebne jest grupowanie ścian w pokoje, zanim ta
metoda będzie użyteczna.

### Czego moduł nie robi (świadomie)

* nie rozpoznaje **frontów, zlewu, płyty, okapu** — z samych trójkątów nie da się
  tego pewnie odróżnić od korpusu; wymaga albo nazw komponentów, albo uczenia,
* nie składa projektu w `Cabinet` — zwraca tylko geometrię biegu i moduły;
  podpięcie do generatora szafek to osobny krok,
* nie jest podpięty do UI.

## Jak uruchomić

```bash
cd ios
swift run KitchenChecks --kitchen-scan "/Users/radoslawcaban/Dom /Chmura dom/Nagnajewicz 1462.glb"
swift test --filter ScanKitchenTests
```

Testy (9) sprawdzają L-kę syntetyczną: dwa biegi 3,9 m i 2,9 m × 0,6 m, obrót 30°,
sumę modułów, ignorowanie ścian pionowych, scalanie blatu przerwanego na 0,3 m,
nierozłączanie biegnów prostopadłych i powtarzalność wyniku.

## Następne kroki (do decyzji)

1. ✅ scalanie współliniowych odcinków (zrobione, przerwa ≤ 400 mm).
2. **Drugie ramię L** — najbardziej brakujący element; wymaga albo grupowania
   ścian w pokoje (żeby `useWallRuns` miało sens), albo wykrywania załamań
   obrysu blatu po jego krawędziach zewnętrznych.
3. Odrzucanie „bliźniaczych" pasaży na tej samej ścianie (dwa pasy 0,45 m od
   siebie to jeden blat, nie dwa biegi).
4. Rozpoznanie zlewu/płyty po otworach we blacie.
5. Mapowanie biegu na `Cabinet` + blat + cokół i podpięcie w UI.
