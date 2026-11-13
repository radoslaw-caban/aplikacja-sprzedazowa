# Moduł katalogu produktów (CatalogCore / CatalogTool / CatalogUI)

Samodzielny moduł: **rejestr produktów, konwersja modeli, kontrola prawna, marże,
opis zależności, kafelki biblioteki**. Świadomie **nie jest podpięty** do aplikacji —
aplikacja dostanie tylko gotowy `library.json`, gdy moduł będzie dopięty.

## Po co to istnieje

Producent/hurtownia dodaje produkt → my nadajemy marżę i sprawdzamy legalność →
dopiero wtedy produkt wchodzi do oficjalnej biblioteki. Katalog jest też dowodem
pochodzenia: kto dodał, z jakiej dokumentacji, kiedy i kto zatwierdził.

## Układ katalogu na dysku

```
<root>/
  manufacturers/<id>.json          # producent + logo.png obok
  products/<id>/product.json       # wpis produktu
  products/<id>/assets/model.glb   # model (po konwersji)
  products/<id>/thumb.png          # miniatura do kafelka
  library.json                     # TYLKO zatwierdzone — wejście dla aplikacji
  audit.log                        # append-only: kto, kiedy, co
```

## Przepływ

```bash
T=.build/debug/CatalogTool
$T init --root ~/KarpatiaCatalog
$T mfr add --root ~/KarpatiaCatalog --id deante --name "DEANTE" \
   --logo logo.png --trademark                 # --trademark = zgoda na znak w katalogu

$T add --root ~/KarpatiaCatalog --sku ARNIKA2 --name "Zlew Arnikа 2" \
   --mfr deante --category sink --file zlew.obj \
   --cost 32000 --basis ownGeometryFromDocs --risk low \
   --provenance "Karta DEANTE Arnika 2 (2026-03)" --ref "file:///karty/arnika2.pdf" --thumb

$T submit  --root ~/KarpatiaCatalog deante-arnika2
$T review  --root ~/KarpatiaCatalog deante-arnika2
$T approve --root ~/KarpatiaCatalog deante-arnika2 --margin 38 --by "RC"
$T tiles   --root ~/KarpatiaCatalog --out katalog.html
```

Ceny w **groszach** (`--cost 32000` = 320,00 PLN). Marża ustawiana dopiero przy
zatwierdzeniu (`--margin 38`), detal liczony jako koszt + marża, zaokrąglony do groszy.

## Konwersja

`add` przyjmuje **GLB, OBJ, STL** i sam robi z nich GLB (własny writer, bez
zależności): OBJ → triangulacja wielokątów, STL binarny i ASCII → GLB.
`gltf` (JSON) i `usdz` są jawnie odrzucane z komunikatem — wymagają eksportu.
`ply` jest odrzucany świadomie: to chmura punktów, nie model produktu.

Po wczytaniu moduł liczy **wymiary gabarytowe z geometrii** (mm) i wpisuje je do
karty produktu. Miniatura (`thumb`) renderuje model offscreen (SceneKit, 512 px,
przezroczyste tło) — to ona trafia na kafelek.

## Kontrola prawna — co blokuje zatwierdzenie

| Kod | Blokada |
|---|---|
| `legal-basis` | nieustalona podstawa geometrii (własna z dokumentacji / od producenta / licencja) |
| `provenance` | brak dokumentu pochodzenia wymiarów |
| `design-risk` | wysokie ryzyko wzoru bez notatki/decyzji prawnej |
| `trademark` | brak zgody producenta na logo/nazwę w katalogu |
| `model` / `thumbnail` | brak modelu albo miniatury (kafelek bez obrazka) |
| `cost` / `margin` | brak ceny zakupu / marża poza 0–80% |

Ostrzeżenia (nie blokują): brak logo, niepełne wymiary, brak opisu zależności dla
kategorii, która go wymaga.

## Opis zależności

Każdy produkt ma listę reguł: **trigger → selektor obiektu → efekty**.

```swift
DependencyRule(
    trigger: .onWorktop,                                   // zlew stoi na blacie
    target: DependencySelector(categories: [.cabinet], level: .base),
    effects: [.init(kind: .setRole, role: "zlewowa"),
              .init(kind: .removeTopRail),
              .init(kind: .reserveNiche, width: 500, depth: 400, height: 500)])
```

Efekty: `setRole`, `removeTopRail`, `addWorktopCutout`, `reserveNiche`,
`requireServiceAdjacent`, `forbidNeighbor`, `minDistance`, `addVent`, `noteOnly`.

Domyślne reguły (`DependencyLibrary.defaultRules(for:)`) pokrywają: zlew, płytę,
piekarnik/mikrofalę, zmywarkę, okap, lodówkę — zgodnie z regułami produkcji
(zlew → szafka bez wieńca górnego i z pionową łatą; piekarnik → nisza 600 i
gniazdo w szafce sąsiedniej; okap → 650 mm nad płytą i kanał Ø150 itd.).

`explain` pokazuje efekt na przykładowej zabudowie:

```bash
$T explain --root ~/KarpatiaCatalog deante-arnika2
  → Szafka 600 mm: rola „zlewowa”
  → Szafka 600 mm: bez wieńca górnego
  → Szafka 450 mm: rola „zlewowa”
  ...
```

## Kafelki

`CatalogUI` daje `CatalogTilesView` (SwiftUI, niewpięty): kafelek = miniatura
modelu, pod nią **logo producenta**, nazwa, ceny i skrót zależności.
`CatalogTool tiles` generuje ten sam układ jako HTML — do szybkiego podglądu
i akceptacji bez uruchamiania aplikacji.

## Czego moduł jeszcze nie robi

- nie jest podpięty do aplikacji (zgodnie z decyzją: nie przerywać pracy innego wątku),
- brak UI do dodawania produktów (jest CLI; `CatalogUI` to na razie tylko kafelki),
- brak dekodowania `gltf` (JSON) i `usdz`,
- brak wersjonowania produktu (zmiana modelu nadpisuje wpis; historia jest w `audit.log`).

## Testy

```bash
swift test --filter Catalog     # 22 testy: marże, blokady prawne, zależności, katalog, mesh
```
