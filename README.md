# Aplikacja sprzedażowa — konfigurator 3D na tablet

Aplikacja na tablet (iPad / Android) do **interaktywnego projektowania produktów w 3D** oraz **bezpośredniej sprzedaży** — klient lub handlowiec konfiguruje produkt w 3D, a aplikacja generuje ofertę/zamówienie.

## Koncepcja

- **Wizualizacja 3D w czasie rzeczywistym** — obracanie, przybliżanie, konfiguracja wymiarów, materiałów i kolorów na dotykowym ekranie tabletu.
- **Konfigurator produktu** — wybór wariantów z natychmiastową aktualizacją modelu 3D i ceny.
- **Moduł sprzedażowy** — kalkulacja ceny, generowanie oferty PDF, złożenie zamówienia, integracja z CRM/ERP.
- **Tryb offline** — praca w terenie / na targach bez internetu, z synchronizacją po powrocie online.

## Planowany stack (propozycja do decyzji)

| Warstwa | Opcja A | Opcja B |
|---|---|---|
| Framework | React Native + expo-gl | Flutter + native 3D |
| Silnik 3D | three.js (react-three-fiber) | Unity as a Library / filament |
| Backend | Supabase (auth, DB, storage) | Node.js + Postgres |
| Modele 3D | glTF/GLB (Draco, optymalizowane pod tablet) | glTF/GLB |
| Oferty PDF | generator po stronie backendu | — |

## Struktura repozytorium (docelowo)

```
.
├── docs/            # wymagania, makiety, decyzje architektoniczne
├── app/             # kod aplikacji tabletowej
├── server/          # backend (oferty, zamówienia, cenniki)
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
