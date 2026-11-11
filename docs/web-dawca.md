# Wersja web — tylko dawca

Katalog `app/` (React + Vite + three.js) **nie jest już rozwijany**. Zostaje w repo jako
źródło sprawdzonych rozwiązań; produkcja pod adresem GitHub Pages nie dostaje nowych funkcji.

## Co bierzemy z webu (port do `ios/`)

| Moduł web | Plik | Co przenosimy | Stan portu |
|---|---|---|---|
| Generator szafek | `app/src/design/generator.ts` | proporcje korpusu, fronty, szuflady Blum | ✅ `KitchenCore/Generator.swift` |
| Zabudowa (runs) | `app/src/design/runs.ts` | blat na korpusie, cokół 40 mm, łączenie ciągów | ✅ `KitchenCore/Runs.swift` |
| Kolizje | `app/src/design/*` | nakładanie szafek, wycięcia | ✅ `KitchenCore/Collision.swift` |
| Tekstury PBR | `app/src/engine/textures.ts` | proceduralne drewno/kamień, skala 1024 px | ✅ zastąpione teksturami Poly Haven (lepsza jakość) |
| PostFX / kadr | `app/src/engine/PostFX.ts` | ACES, ekspozycja | ✅ IBL + kamera w RealityKit |
| Biblioteka elementów | `app/src/design/types.ts` | katalog szafek i parametrów | ✅ `KitchenCore/Library.swift` |
| Organizer szuflad | `app/src/design/organizer.ts` | podział szuflady na przegrody | ⏳ do portu po kartotece |

## Czego NIE przenosimy

- Import E57 w przeglądarce (`e57-js` + WASM) — na iPadzie jest LiDAR i `ARKit`, a pliki 5 GB nie mają sensu w WebView.
- Parser GLB w JS — mamy własny loader w Swift.
- UI (React) — wygląd i zachowanie piszemy od nowa pod iPadOS.
- Deploy przez gh-pages — proces zostaje tylko dla archiwalnej wersji.

## Zasada

Zmiana w `app/` jest dopuszczalna **tylko** wtedy, gdy poprawia błąd uniemożliwiający
korzystanie z wersji webowej. Nowe funkcje: wyłącznie `ios/`.
