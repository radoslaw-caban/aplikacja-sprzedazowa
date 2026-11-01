# Aplikacja sprzedażowa — konfigurator 3D (web, wszystkie urządzenia)

**Aplikacja webowa PWA** do interaktywnego projektowania produktów w 3D i bezpośredniej sprzedaży. Działa na **każdym urządzeniu z przeglądarką**: laptop, tablet, macOS, Windows, Android, iOS — bez instalacji z App Store / Google Play.

## Koncepcja

- **Wizualizacja 3D w czasie rzeczywistym** — obracanie, przybliżanie, konfiguracja wymiarów, materiałów i kolorów na dotykowym ekranie tabletu.
- **Konfigurator produktu** — wybór wariantów z natychmiastową aktualizacją modelu 3D i ceny.
- **Moduł sprzedażowy** — kalkulacja ceny, generowanie oferty PDF, złożenie zamówienia, integracja z CRM/ERP.
- **Tryb offline** — praca w terenie / na targach bez internetu, z synchronizacją po powrocie online.

## Kluczowa decyzja architektoniczna: wymienialny silnik graficzny

Renderowanie 3D jest oddzielone od logiki aplikacji przez **wewnętrzne API (port)** —
aplikacja nigdy nie importuje bezpośrednio three.js ani innego silnika. Silnik to
**wtyczka (adapter)** implementująca wspólny interfejs, wybierana w konfiguracji.

```ts
// Port — stały kontrakt, niezależny od silnika
interface RenderEngine {
  id: string;
  init(canvas: HTMLCanvasElement, opts?: EngineOptions): Promise<void>;
  loadModel(url: string): Promise<SceneHandle>;
  applyConfig(config: ProductConfig): void;   // materiały, kolory, wymiary
  setEnvironment(hdri: string): void;
  screenshot(): Promise<Blob>;                // do ofert PDF
  dispose(): void;
  capabilities: { maxTextureSize: number; supportsDraco: boolean; ... };
}
```

| Silnik (adapter) | Status | Uwagi |
|---|---|---|
| `@app/engine-three` (three.js / react-three-fiber) | **domyślny, MVP** | dojrzały ekosystem, glTF, Draco, WebGPU w drodze |
| `@app/engine-babylon` (Babylon.js) | opcjonalny | mocny w PBR i narzędziach |
| `@app/engine-playcanvas` | opcjonalny | dobry współpraca z designera­mi |
| natywny / WebGPU | przyszłość | gdy przeglądarki dojrzeją |

**Zasady:**
- Kod produktu/konfiguratora komunicuje się **wyłącznie przez `RenderEngine`** — zero importów z konkretnego silnika poza pakietem adaptera.
- Selekcja silnika: `VITE_RENDER_ENGINE=three` (env) lub automatycznie na podstawie `capabilities` urządzenia (np. fallback przy słabym GPU).
- Modele 3D zawsze w formacie **glTF/GLB** — neutralnym wobec silników, więc wymiana silnika nie wymusza konwersji assetów.
- Wspólne narzędzia (optymalizacja modeli, testy snapshotowe renderu) współdzielone między adapterami.

## Planowany stack

| Warstwa | Technologia | Dlaczego |
|---|---|---|
| Frontend | **React + TypeScript + Vite** | jedna baza kodu na wszystkie platformy |
| Silnik 3D | **three.js (react-three-fiber)** | WebGL działa w każdej przeglądarce (desktop i mobile) |
| PWA | Vite PWA (service worker, manifest) | instalacja na ekranie głównym, tryb offline |
| UI | responsywny design (mobile-first + touch + mouse) | tablet, laptop, telefon jednym kodem |
| Backend | **Supabase** (auth, Postgres, storage) | szybki start, hosting API w cenie free |
| Modele 3D | glTF/GLB + Draco/KTX2 | małe pliki, szybkie ładowanie na mobile |
| Oferty PDF | generowanie po stronie backendu | spójny wygląd na każdym urządzeniu |
| Hosting | Vercel / Netlify / Cloudflare Pages | CDN globalnie, HTTPS out-of-the-box |

> Dzięki PWA aplikacja można "zainstalować" na tablecie/telefonie jak natywną apkę
> (ikona na ekranie głównym, pełny ekran, praca offline), a jednocześnie uruchomić
> ją na laptopie zwykle przez URL.

## Struktura repozytorium (docelowo)

```
.
├── docs/                  # wymagania, makiety, decyzje architektoniczne
├── app/                   # frontend (React, PWA) — logika, UI, konfigurator
│   └── src/engine/        # PORT: interfejs RenderEngine + rejestr/wybór silnika
├── packages/
│   ├── engine-core/       # kontrakt RenderEngine (typy, shared utils)
│   ├── engine-three/      # adapter: three.js (domyślny)
│   └── engine-babylon/    # adapter: Babylon.js (opcjonalny)
├── server/                # backend / funkcje (oferty, zamówienia, cenniki)
└── assets/models/         # modele 3D produktów (glTF/GLB — neutralne dla silników)
```

> Repo w monorepo (np. pnpm workspaces) — każdy silnik to osobny pakiet, dołączany
> do builda zależnie od konfiguracji (`VITE_RENDER_ENGINE` / capabilities urządzenia).

## Pierwsze kroki

1. Sklonuj repozytorium:
   ```bash
   git clone https://github.com/radoslaw-caban/aplikacja-sprzedazowa.git
   ```
2. Wymagania produktowe będą dokumentowane w `docs/wymagania.md`.
3. Wymagania architektoniczne:
   - Renderowanie 3D **wyłącznie przez port `RenderEngine`** (pakiet `engine-core`) —
     silnik graficzny musi być wymienny bez zmian w logice konfiguratora i sprzedaży.
   - Nowy silnik = nowy adapter implementujący `RenderEngine` + rejestracja w rejestrze; zero zmian w `app/`.

## Licencja

Wewnętrzny projekt — wszelkie prawa zastrzeżone.
