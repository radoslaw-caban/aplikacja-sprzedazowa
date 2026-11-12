# Biblioteka 3D i zaznaczanie elementów

## Jak wrzucać modele 3D

1. W aplikacji otwórz **MODELE** na pasku biblioteki.
2. Kliknij **„Wgraj modele z Plików”**.
3. Wskaż pliki `.glb` (zalecane) albo `.gltf` z iCloud Drive, AirDrop,
   „Na iPhonie/iPadzie” lub pendrive'a.
4. Model kopiuje się do `Documents/Modele` i pojawia się na liście.
   Nazwa = nazwa pliku; można go usunąć z listy.

Wymagania:

- **GLB** — jeden plik, najlepszy wybór (siatki + materiały w środku).
- **GLTF** — tylko wariant z osadzonymi danymi; `.gltf` + osobne `.bin`
  i tekstury nie są kopiowane razem, więc używaj GLB.
- Nie ma limitu rozmiaru poza pamięcią i czasem kopiowania.
- Model jest dostępny w bibliotece; wstawianie do sceny i przypisywanie
  do kategorii (zawias, kosz, front) będzie kolejnym krokiem.

Aby wrzucić wiele plików: zaznacz je wszystkie w Plikach (albo przeciągnij
folder na iPada w aplikacji Pliki do `Konfigurator/Modele`). Import z Plików
obsługuje wielokrotny wybór.

## Pasek biblioteki

- Pasek zakładek jest przyklejony do lewej krawędzi (odstęp 4 px na efekt
  magiczny). Zakładki jedna pod drugą: **SZAFKI, FRONTY, ZAWIA, AKCES, MODELE**.
- Gdy nic nie jest zaznaczone, rozwija się biblioteka.
- Kliknięcie elementu w 3D zaznacza go i **zamienia bibliotekę w edytor**.
- Wyjście z edycji:
  - **Mac:** ESC,
  - **iPad:** gest przesunięcia w lewo na panelu albo X w nagłówku,
  - kliknięcie innego elementu przełącza edycję.

## Zaznaczanie i kontury

- Klik w szafkę: promień z kamery trafia w jej bryłę, panel otwiera edycję,
  a w scenie rysowane są **cyjanowe kontury wszystkich brył składowych**
  (boki, dno, góra, półki, fronty, szuflady).
- Klik poza szafką zdejmuje zaznaczenie.
- Ten sam mechanizm jest przygotowany pod ściany, okna i drzwi — kolejny
  krok to dodanie ich brył do raycastu i paneli parametrów.

## Efekt magiczny

- Ramka panelu ma kolorowy gradient (cyan → fiolet → róż → złoto).
- Przy ważnej akcji (np. dodanie szafki z biblioteki) ramka rozjaśnia się
  i pojawiają się drobinki brokatu.
- Wyłączenie: **Ustawienia → Sterowanie → Efekty magiczne (ramka + brokat)**.
