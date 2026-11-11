# Dokładność skanowania LiDAR

Jak działa skan w tej aplikacji i dlaczego jest dokładniejszy niż „próbkowanie siatki".

## Dwa źródła geometrii w ARKit

| Źródło | Rozdzielczość | Charakter | Użycie |
|---|---|---|---|
| `ARMeshAnchor` (scene reconstruction) | **~5–10 cm** | wygładzona siatka, gotowe trójkąty | podgląd na żywo, fallback, klasyfikacja powierzchni |
| `ARDepthData.depthMap` (LiDAR) | **256×192 px / klatkę**, ~30 klatek/s | surowe pomiary odległości | **źródło dokładnej chmury** |

Kluczowa konsekwencja: **zmniejszanie kroku próbkowania siatki nic nie daje.**
Siatka ma trójkąty o boku centymetrów — gęstsze próbkowanie to interpolacja
płaskiego trójkąta, nie nowy detal. Dlatego pierwsza wersja (krok 2 cm) dawała
chmurę gęstą, ale nie dokładniejszą.

Dokładność bierze się z **fuzji wielu pomiarów głębi**.

## Fuzja: uśrednianie niezależnych pomiarów

Każdy piksel mapy głębi rzutujemy na punkt w przestrzeni świata i wrzucamy do
siatki wokseli. Woksel pamięta **średnią ważoną** pozycji, gdzie waga = 1/σ²:

```
σ_wynik = 1 / √(Σ 1/σᵢ²)
```

To nie jest wygładzanie — to uśrednianie niezależnych pomiarów tego samego
fragmentu powierzchni. Szum maleje jak 1/√N: po 100 klatkach z σ = 10 mm
schodzimy do ~2,4 mm.

### Niepewność pojedynczego pomiaru

```swift
σ_depth = (ufność wysoka ? 4 mm : 12 mm) × (1 + 0,5·max(0, d−1m))
σ_lateral = d / fx          // rozstaw pikseli w przestrzeni
σ_total  = √(σ_depth² + σ_lateral²)
```

Niepewność rośnie z odległością — fizyka, nie zgadywanie: dalej jest mniej
fotonów na piksel i większa łata pomiarowa.

### Rozmiar woksela — zmierzony, nie zgadnięty

Woksel to **ziarno grupowania**, nie ziarno dokładności. Musi być **większy niż
rozstaw pikseli mapy głębi w przestrzeni**, inaczej każdy piksel trafia do
własnego woksela i uśrednianie w ogóle nie zachodzi.

Pomiar (`swift run KitchenChecks --sweep`, ściana 2 m, szum 10 mm):

| Woksel | pkt/woksel | σ po 100 klatkach | błąd systematyczny | pokrycie |
|---|---|---|---|---|
| 4 mm | 1,00 | 4,14 mm | 0,03 mm | 100% |
| 8 mm | 1,00 | 3,24 mm | 0,01 mm | 100% |
| **12 mm** | **8–30** | **2,40 mm** | **0,61 mm** | **100%** |
| 15 mm | 8–53 | 1,98 mm | 1,30 mm | 73% |
| 20 mm | 13–120 | 1,43 mm | 0,75 mm | 51% |
| 25 mm | 20–194 | 1,36 mm | 0,25 mm | 33% |

**Wybrano 12 mm**: pierwszy rozmiar, przy którym fuzja realnie uśrednia, przy
pełnym pokryciu i błędzie systematycznym poniżej pół milimetra. Większe woksele
dają niższe σ, ale gubią pokrycie i tworzą „kostkę" na powierzchniach pochyłych.

## Błąd, który to złapało

Pierwsza wersja miała woksel 8 mm. Test regresyjny („σ po 100 klatkach musi być
mniejsze niż po 10") nie przechodził: σ stało na 4,8 mm mimo 40 klatek.

Przyczyna: przy 2 m piksel mapy głębi zajmuje ~1 cm w przestrzeni, więc przy
wokslu 8 mm **każdy piksel trafiał do osobnego woksela** (dokładnie 1,00
pkt/woksel). Fuzja dodawała woksele, ale nie uśredniała.

Dodatkowo sam test symulował złą fizykę: mnożył głębokość przez długość promienia,
co tworzyło sztuczną kulistość i dawało stały błąd 13 mm niezależny od liczby
klatek. ARKit podaje „distance from the plane of the camera" — odległość wzdłuż
osi Z, więc płaska ściana prostopadła do osi ma **identyczną** głębokość na
każdym pikselu.

## Co jeszcze podnosi dokładność (kolejność zysku)

1. **Wolniejsze przejście pomieszczenia** — więcej klatek na ten sam fragment.
   Największy pojedynczy zysk, darmowy.
2. **Kilka ujęć z różnych kątów** — uśrednia błędy systematyczne LiDAR-u
   (skan pod kątem widzi krawędzie, których nie widzi na wprost).
3. **Wysoka ufność** (`minConfidence = 2`) — odrzuca krawędzie i powierzchnie
   poślizgowe, gdzie LiDAR myli się najbardziej.
4. **Odsiew wokseli widzianych raz** (`minSamples = 2`) — pojedynczy pomiar to
   szum, nie geometria.
5. **Kalibracja do znanego wymiaru** — dwa punkty na ścianie + realna długość
   (`ScanRegistration.aligningWall`). To poprawia **skalę**, nie szum.

## Ograniczenia, których nie da się obejść

- **LiDAR iPad ma błąd 1–2 cm na 5 m** — fuzja zbija szum losowy, ale nie
  usuwa błędu systematycznego czujnika. Do wymiarowania pod zabudowę zostaje
  Trimble X9.
- **Cienkie krawędzie i szkło** — LiDAR ich nie widzi lub widzi źle.
  Szyby, lustra i błyszczące fronty wypadają jako dziury lub szum.
- **Powierzchnie poślizgowe** (patrzenie wzdłuż ściany) — mała ufność,
  odsiewane przy `minConfidence = 2`.

## Gdzie to jest w kodzie

| Plik | Rola |
|---|---|
| `KitchenCore/DepthFusion.swift` | cała matematyka: rzutowanie, wagi, woksele, σ |
| `KitchenScene/DepthCapture.swift` | konwersja `ARDepthData` → `DepthFrame`, lock, statystyki |
| `KitchenScene/RoomScanSession.swift` | sesja ARKit, `frameSemantics = .sceneDepth` |
| `KitchenApp/RoomScanSheet.swift` | UI: podgląd, przycisk, wybór fuzji vs siatka |
| `KitchenChecks/Sweep.swift` | eksperyment: rozmiar woksela vs dokładność |

Uruchomienie eksperymentu:

```bash
cd ios && swift run KitchenChecks --sweep
```
