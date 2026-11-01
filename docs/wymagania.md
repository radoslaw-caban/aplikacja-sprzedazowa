# Wymagania produktowe — Konfigurator 3D na tablet (wersja robocza)

> Status: DRAFT — do uzupełnienia z interesariuszami.

## 1. Cel produktu

Aplikacja tabletowa umożliwiająca handlowcom i klientom interaktywne projektowanie
produktu w 3D oraz natychmiastowe sfinalizowanie sprzedaży (wycena → oferta → zamówienie).

## 2. Grupy docelowe / użytkownicy

- Handlowiec (prezentacja u klienta, targi, showroom)
- Klient końcowy (samodzielna konfiguracja, np. kiosk)

## 3. Funkcje MVP

1. **Katalog produktów** — lista konfigurowalnych produktów z modelami 3D.
2. **Widok 3D** — render modelu glTF/GLB, gesty: obrót, zoom, pinch.
3. **Konfigurator** — wymiary, materiały/kolory, dodatki; aktualizacja modelu i ceny w czasie rzeczywistym.
4. **Wycena** — reguły cenowe per wariant; podsumowanie konfiguracji.
5. **Oferta** — generowanie PDF z rzutem 3D i specyfikacją; wysyłka e-mail.
6. **Zamówienie** — zapis konfiguracji i przesłanie do backendu.
7. **Tryb offline** — lokalna baza + synchronizacja.

## 4. Wymagania niefunkcjonalne

- Płynność renderu: ≥ 30 FPS na tablecie ze średniej półki (2020+).
- Czas startu aplikacji: < 3 s.
- Modele 3D: < 20 MB na produkt (Draco/mipmapping).
- Bezpieczeństwo: logowanie, role (handlowiec / admin), HTTPS.

## 5. Otwarte pytania

- [ ] Która platforma priorytetowa: iPad, Android, obie?
- [ ] Jaki asortyment / kategorie produktów w pierwszej wersji?
- [ ] Integracja z istniejącym CRM/ERP (którym)?
- [ ] Kto przygotowuje modele 3D (proces, format, budżet)?
- [ ] Waluta, ceny, rabaty — skąd pochodzą dane cenowe?
