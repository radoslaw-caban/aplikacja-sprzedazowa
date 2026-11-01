# Aplikacja sprzedażowa — konfigurator 3D (web, wszystkie urządzenia)

**Aplikacja webowa PWA** do interaktywnego projektowania produktów w 3D i bezpośredniej sprzedaży. Działa na **każdym urządzeniu z przeglądarką**: laptop, tablet, macOS, Windows, Android, iOS — bez instalacji z App Store / Google Play.

## Koncepcja

- **Wizualizacja 3D w czasie rzeczywistym** — obracanie, przybliżanie, konfiguracja wymiarów, materiałów i kolorów na dotykowym ekranie tabletu.
- **Konfigurator produktu** — wybór wariantów z natychmiastową aktualizacją modelu 3D i ceny.
- **Moduł sprzedażowy** — kalkulacja ceny, generowanie oferty PDF, złożenie zamówienia, integracja z CRM/ERP.
- **Tryb offline** — praca w terenie / na targach bez internetu, z synchronizacją po powrocie online.

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
├── docs/            # wymagania, makiety, decyzje architektoniczne
├── app/             # frontend (React + three.js, PWA)
├── server/          # backend / funkcje (oferty, zamówienia, cenniki)
└── assets/models/   # modele 3D produktów (glTF/GLB)
```

## Pierwsze kroki

1. Sklonuj repozytorium:
   ```bash
   git clone https://github.com/radoslaw-caban/aplikacja-sprzedazowa.git
   ```
2. Wymagania produktowe będą dokumentowane w `docs/wymagania.md`.
3. Repo jest w fazie startowej — stack i architektura do ustalenia.

## Licencja

Wewnętrzny projekt — wszelkie prawa zastrzeżone.
