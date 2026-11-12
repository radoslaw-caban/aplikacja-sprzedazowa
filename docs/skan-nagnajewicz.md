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
biegi: 3, moduły: 10, suma: 6150 mm
  bieg 1: 2550 × 500 mm  kąt 101,0°  moduły 4 × [638, 638, 638, 636]
  bieg 2: 2350 × 550 mm  kąt 101,0°  moduły 4 × [588, 588, 588, 586]
  bieg 3: 1250 × 600 mm  kąt 101,0°  moduły 2 × [625, 625]
```

Suma 6,15 m zgadza się z realną długością zabudowy (~6,2 m), ale detektor
**pociął jedno ramię na trzy odcinki** i nie rozpoznał drugiego ramienia L
(jego kąt powinien wyjść ~11°, a wyszedł 101° dla wszystkich). Przyczyny:
przerwy w siatce (zlew, płyta, sprzęt) i zbyt sztywne kryterium przylegania
do ściany — próg dobrany tak, by przechodził blat przy ścianie z szumem skanu.

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

Testy (7) sprawdzają L-kę syntetyczną: dwa biegi 3,9 m i 2,9 m × 0,6 m, obrót 30°,
sumę modułów, ignorowanie ścian pionowych i powtarzalność wyniku.

## Następne kroki (do decyzji)

1. Łączenie współliniowych odcinków w jeden bieg (przerwy < 400 mm) — to naprawi
   podział 2550 + 2350 + 1250.
2. Wykrywanie drugiego ramienia: pasy liczone też po **ścianach**, a nie tylko
   po blacie (blat w L bywa przerwany okapem).
3. Rozpoznanie zlewu/płyty po otworach i „wklęsłościach” w blacie.
4. Dopiero potem: mapowanie biegu na `Cabinet` + blat + cokół i podpięcie w UI.
