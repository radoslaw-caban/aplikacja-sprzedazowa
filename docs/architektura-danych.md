# Architektura danych — skan X9, DXF, SketchUp (CabinetSense)

Status: ZATWIERDZONO (na podstawie realnych danych: pliki E57 ~5 GB, 20–50 mln punktów)

## 1. Chmura punktów — Trimble X9 (.e57)

**Decyzja: import natywny .e57 w aplikacji, parsowanie w Web Workerze.**

- Rozmiar 5 GB / 20–50 mln pkt → mieszci się w przeglądarce po deymacji/LOD
  (limit RAM iOS ~1–2 GB → chmura w Float32 = 20–50 mln × 12 B = 240–600 MB, OK).
- Parser E57 (XML + binarne bloby) działa w Web Workerze — UI nie zamarza,
  pasek postępu.
- X9 zapisuje też pliki .fls/.e57 z podglądami — kamera/pozycje skanów ignorowane w MVP.
- **Perspective pozostaje narzędziem przycinania** (usuwanie noise/sufit/obce obiekty),
  ale konwersja do GLB/PLY nie jest wymagana — aplikacja czyta E57 bezpośrednio.

### Pipeline w aplikacji
```
plik.e57 (z Perspective lub prosto z X9)
  → Web Worker: parse E57 (XML index + binary buffer)
  → decymacja opcjonalna (co N-ty punkt, jeśli > 30 mln)
  → Float32Array xyz (+ rgb jeśli obecne)
  → RenderEngine.loadPointCloud() → THREE.Points
  → LOD: 3 poziomy (co 1 / co 4 / co 16 punktu) przełączane wg zoomu
```

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

## 4. Docelowy scenariusz sprzedażowy (etap 5)

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
