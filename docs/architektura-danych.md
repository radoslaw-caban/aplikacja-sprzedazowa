# Architektura danych — skan X9, DXF, SketchUp (CabinetSense)

Status: ZATWIERDZONO (na podstawie realnych danych: pliki E57 ~5 GB, 20–50 mln punktów)

## 1. Chmura punktów — Trimble X9 (.e57)

**Decyzja: import natywny .e57 w przeglądarce przez dekoder WASM `e57-js` (libE57).**

- Działa w Web Workerze — UI nie zamarza, widoczny pasek postępu.
- Odczyt porcjami po 200 tys. pkt + automatyczna decymacja do **8 mln pkt**
  (powyżej tego limitu pamięć tabletu/iOS przestaje wystarczać).
- Punkty z NaN/Inf są odfiltrowywane (CloudCompare zapisuje punkty "invalid").

### Wymagania techniczne (krytyczne — nie oczywiste)

1. **COOP/COEP → SharedArrayBuffer.** `libe57-js.wasm` jest zbudowany z pthreads
   i wymaga `SharedArrayBuffer`, a ten istnieje tylko przy `crossOriginIsolated`.
   GitHub Pages nie pozwala ustawić nagłówków HTTP, więc używamy
   `coi-serviceworker.min.js` (skopiowany z npm `coi-serviceworker` do `public/`,
   ładowany w `index.html`). Efekt: `window.crossOriginIsolated === true`.
2. **`window` w Workerze.** `e57-js` wybiera ścieżkę Node (NODEFS) gdy `typeof window === 'undefined'`,
   co w Workerze kończy się `Aborted(Assertion failed)`. Rozwiązanie: na początku
   workera ustawić `self.window = self`.
3. **Pliki dekodera kopiujemy z npm do `public/e57js/`** (`index.browser.mjs`,
   `libe57-js.js`, `libe57-js.wasm`) i importujemy dynamicznie przez
   `${import.meta.env.BASE_URL}e57js/index.browser.mjs` z `/* @vite-ignore */`.
   Worker musi być ES module: `worker: { format: 'es' }` w `vite.config.ts`.

### API dekodera (potwierdzone na pliku X9 491 953 pkt)
```js
await E57.Init();
const reader = E57Reader.FromBuffer(uint8array);
reader.GetData3DCount();                       // liczba skanów
const scan = reader.GetScan(0);
Number(scan.GetHeader().pointCount);           // 491953
const pts = scan.ReadPointsSync(chunk, true);  // VectorPoint
pts.size(); pts.get(i).cartesianX/.../colorRed;
```

### Fallback: konwersja offline
`tools/e57_to_ply.py` (pye57) → binarny PLY → parser `plyParser.ts` w aplikacji.
Przetestowany: 491 953 pkt, wynik identyczny bit-w-bit z ground truth.

### Rozszerzenie kontraktu RenderEngine
```ts
loadPointCloud(data: PointCloudData): Promise<() => void>;
interface PointCloudData {
  positions: Float32Array;   // xyz
  colors?: Uint8Array;       // rgb, opcjonalnie
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}
```

## 2. DXF — odroczony (priorytet niski)

Triangulacja/measuring w app ≈ etap późniejszy. Wymagane narzędzia:
- Poisson meshing → server-side (Python/Open3D) lub WASM dla fragmentów
- DXF writer → prosty, własny (LWPOLYLINE/LINE wystarczą)

## 3. SketchUp / CabinetSense (.skp)

**Dwie równoległe ścieżki:**

### A) Automatyczny pipeline (GitHub Actions) — preferowana
Użytkownik wrzuca `projekt.skp` do `assets/skp/` → GitHub Actions:
1. Blender CLI + importer SketchUp (dostępny oficjalnie dla Windows/macOS)
2. eksport GLB z Draco + KTX2
3. commit do `assets/models/` → aplikacja widzi model automatycznie
- Zero ręcznej pracy; konwersja ~1–2 min w CI.
- Wymagania: runner macOS/Windows (Blender + SketchUp importer),
  lub self-hosted runner z Blenderem.

### B) Ręczny eksport z SketchUp (fallback, dziś)
SketchUp 2025/2026 → File → Export → glTF/GLB → wrzucić GLB do
`assets/models/` → push → widoczne w aplikacji. Potwierdzone przez użytkownika
jako akceptowalna ścieżka równoległa.

## 5. Parametryczne szafki (kolejny etap)

**Model docelowy:** szafki z pliku .skp (komponenty CabinetSense) są **tylko dawcami układu** —
dostarczają topologię (podział na sekcje, liczba frontów/szuflad, proporcje, kolejność elementów).
Nie skalujemy geometrii z GLB. Zamiast tego budujemy **własną bazę parametryczną** w nowym
środowisku: szafka = zestaw parametrów → generowana geometria (panele korpusu, fronty, blat, cokół).

### Parametry szafki (v1)
```ts
interface CabinetParams {
  id: string;
  type: 'base' | 'wall' | 'tall' | 'corner';   // dolna / górna / słupek / narożna
  width: number;    // mm
  height: number;   // mm
  depth: number;    // mm
  sections: CabinetSection[];                  // podział na sekcje (kolumny)
  plinth: number;        // cokół, mm
  worktop: number;       // blat, mm (0 = brak)
  panelThickness: number; // grubość płyty, mm (domyślnie 18)
  material: string;      // np. 'dab-natur', 'bialy-mat'
}

interface CabinetSection {
  kind: 'door' | 'drawers' | 'open' | 'sink' | 'oven';
  doors?: number;      // liczba frontów przy 'door'
  drawers?: number;    // liczba szuflad przy 'drawers'
  widthRatio: number;  // udział w szerokości szafki (suma = 1)
}
```

### Generowanie geometrii
- Korpus: 2 boki, spód, wieniec, plecy — prostopadłościany z `panelThickness`.
- Fronty: panele o wymiarach wynikających z podziału sekcji, z 3 mm szczeliną.
- Blat i cokół: panele pełnej szerokości/głębokości wg parametrów.
- Wszystko jako `THREE.Group` z nazwanymi częściami — gotowe do edycji i wyceny.
- Katalog z `CabinetParams` = baza szafek (JSON), niezależna od SketchUp/CabinetSense.

### Kolejność prac
1. [x] Import GLB + gizmo na chmurę punktów
2. [ ] Parser .skp → ekstrakcja nazw komponentów i wymiarów (dawcy układu)
3. [ ] Generator parametryczny jednej szafki (typ + wymiary + sekcje)
4. [ ] Baza szafek (JSON) + UI wyboru i wstawiania do sceny
5. [ ] Zapis/odczyt projektu i zrzut do oferty PDF

## 6. Docelowy scenariusz sprzedażowy

1. Skan X9 realnej kuchni klienta (.e57) → import do aplikacji
2. Projekt CabinetSense (.skp → GLB) → nałożenie na chmurę
3. Dopasowanie pozycji szafek do rzeczywistości (przesuwanie/obracanie, snap)
4. Zdjęcie ekranu → oferta PDF z realną wizualizacją

## Priorytety wdrożenia

| # | Zadanie | Status |
|---|---|---|
| 1 | Parser E57 (Worker) + loadPointCloud + LOD | DO ZROBIENIA — najwyższy |
| 2 | Pipeline SKP → GLB (GitHub Actions + Blender) | DO ZROBIENIA |
| 3 | Nałożenie modelu GLB na chmurę (transform gizmo) | planowane |
| 4 | Pomiar w chmurze + eksport DXF 2D | odroczone |
| 5 | Oferta PDF ze zrzutu sceny | planowane |
