# Plan działania — kartoteka klienta i dalszy rozwój aplikacji

Dokument roboczy. Stan: 2026-11-11. Aplikacja: natywna iPadOS/macOS (`ios/`, SwiftUI + RealityKit).
Wersja web (`app/`) **zostaje zamrożona** — traktujemy ją wyłącznie jako źródło gotowych rozwiązań.

---

## 1. Zasady, które przyjmujemy

1. **Jedno źródło prawdy: aplikacja natywna.** Web nie dostaje nowych funkcji. Portujemy z niego tylko to, co już działa dobrze (renderer szafek, tekstury, logika wyceny).
2. **Domena w milimetrach, precyzja 0,0001 mm**, wyświetlanie w całych mm. Każda nowa funkcja trzyma się tej reguły.
3. **Dane produkcyjne, nie demo.** Data montażu, adres, maile i załączniki to dane realne — muszą przetrwać restart, aktualizację i brak sieci.
4. **Każdy etap kończy się działającą funkcją na iPadzie**, testami jednostkowymi i commitem. Bez „prawie gotowe".
5. **Zero zgadywania w geometrii.** Automaty (import planu, wykrywanie ścian) proponują, człowiek poprawia.

---

## 2. Cel najbliższego etapu: kartoteka klienta

Ekran projektu (dziś `OrderFlowView`) ma pokazać trzy rzeczy, których dziś brakuje:

| Element | Stan dziś | Cel |
|---|---|---|
| **Data montażu** | brak pola | data + godzina, kalendarz, przypomnienie, widoczna w liście zleceń |
| **Mapa pod adresem** | tylko tekst adresu | podgląd mapy pod polem adresu, pinezka, „nawiguj", cache offline |
| **Maile klienta** | brak | wątki w formie iMessage: tytuł, treść, załączniki jako miniaturki w dymkach |

### 2.1. Model danych (KitchenCore)

```swift
// ProjectOrder — rozszerzenie (pola opcjonalne = zgodność ze starymi zapisami)
public struct ProjectOrder {
    // … istniejące pola …
    public var assemblyDate: Date?          // data i godzina montażu
    public var assemblyNote: String         // ekipa, uwagi („wjazd od podwórza")
    public var latitude: Double?            // geokodowany adres
    public var longitude: Double?
    public var emailThreads: [EmailThread]  // zaczytane wątki
}

public struct EmailThread: Identifiable, Codable {
    public var id: UUID
    public var subject: String
    public var messages: [EmailMessage]
    public var updatedAt: Date
}

public struct EmailMessage: Identifiable, Codable {
    public var id: UUID
    public var from: String
    public var to: [String]
    public var sentAt: Date
    public var body: String                  // czysty tekst, bez HTML
    public var isFromClient: Bool            // decyduje o stronie dymka
    public var attachments: [EmailAttachment]
}

public struct EmailAttachment: Identifiable, Codable {
    public var id: UUID
    public var fileName: String
    public var mimeType: String
    public var sizeBytes: Int
    public var localFile: String             // plik w Documents/mail/<projekt>/
    public var thumbnailFile: String?        // miniaturka 240 px (obrazy, PDF str. 1)
}
```

Wszystko `Codable` + pola opcjonalne → stare `projects.json` czytają się bez migracji.

### 2.2. Data montażu

- Pole `DatePicker` (data + godzina) w karcie klienta, przycisk „Dziś", „Za tydzień".
- Po zapisie: **lokalne powiadomienie** (`UNUserNotificationCenter`) 3 dni i 1 dzień przed, o 8:00.
- W liście zleceń sortowanie po `assemblyDate` (najbliższe na górze), z kolorem: ≤3 dni czerwony, ≤7 dni pomarańczowy.
- Uwaga: powiadomienia wymagają zgody — pytamy przy pierwszym ustawieniu daty, nie przy starcie aplikacji.

### 2.3. Mapa pod adresem

- `CLGeocoder.geocodeAddressString` → współrzędne; zapisujemy w `ProjectOrder` (żeby działało offline).
- Podgląd: `Map` (MapKit) w karcie klienta, wysokość ~180 pt, pinezka, tryb nieinteraktywny + przycisk „Otwórz w Mapach".
- Gdy brak internetu albo geokodowanie nie wyszło: szara plansza z „Nie udało się zlokalizować adresu" i przyciskiem ponowienia.
- **Cache:** raz zapisane współrzędne nie są pytane ponownie; zmiana adresu czyści je i geokoduje od nowa (test: zmiana adresu → współrzędne wyzerowane).

### 2.4. Maile — jak je zaczytujemy

To jedyna część, której nie da się zrobić „przy okazji", bo wymaga dostępu do skrzynki. Trzy warianty:

| Wariant | Jak | Plusy | Minusy |
|---|---|---|---|
| **A. Gmail API + OAuth** | `ASWebAuthenticationSession` + tokeny, `users.messages.list` | pełny dostęp do wątków i załączników, działa na iPadzie | tylko konta Google; wymaga `client_id` (Google Cloud, darmowe) |
| **B. Microsoft Graph** | OAuth + `mail/messages` | Outlook/Office 365 | jak wyżej, osobna rejestracja aplikacji |
| **C. IMAP (dowolny dostawca)** | `NIOIMAP` / `libetpan`, hasło aplikacji | działa z każdą skrzynką (WP, Onet, home.pl) | trudniejsze: MIME, załączniki, throttling; hasła aplikacji |
| **D. Import pliku .eml/.mbox** | użytkownik wrzuca eksport | zero integracji, działa od razu | ręczne, dobre na start i do testów |

**Decyzja proponowana:** start od **D** (import .eml — pozwala zbudować cały ekran i przetestować na prawdziwej poczcie klienta), równolegle **A** (Gmail) jako pierwszy automat. B i C dopiero, gdy pojawi się klient na Outlooku/WP.

Przetwarzanie wiadomości:

1. Pobranie wątku → wyciągnięcie `subject`, `from`, `date`, treści tekstowej (HTML → tekst, bez obrazków w treści).
2. Załączniki: zapis do `Documents/mail/<projectID>/`, miniaturka 240 px dla obrazów i pierwszej strony PDF.
3. Grupowanie po konwersacji (nagłówki `References`/`Message-ID`; w Gmailu gotowe wątki).
4. Filtr: pokazujemy tylko wątki powiązane z adresem e-mail klienta **albo** z adresem nieruchomości; reszta skrzynki nie jest kopiowana.
5. Odświeżanie: ręczne „Odśwież" + automatyczne przy wejściu w kartę (maks. raz na 5 min).

### 2.5. Ekran „Maile" — dymki jak w iMessage

```
┌──────────────────────────────────────────────┐
│  Re: kuchnia Nagnajewicz       3 wiadomości  │
│                                              │
│              ┌────────────────────────────┐  │
│              │ Dzień dobry, przesyłam     │  │
│              │ wymiary kuchni.            │  │
│              │ ┌────┐ ┌────┐ ┌────┐       │  │  ← załączniki: miniaturki
│              │ │IMG │ │PDF │ │IMG │       │  │     w dymku, 64×64, zaokrąglone
│              │ └────┘ └────┘ └────┘       │  │
│              └────────────────────────────┘  │
│  ┌──────────────────────────┐                │
│  │ Dziękuję, w poniedziałek │                │  ← własna odpowiedź (prawa)
│  │ potwierdzę montaż.       │                │
│  └──────────────────────────┘                │
│           wtorek 14:32                       │
└──────────────────────────────────────────────┘
```

- Dymki: klient po lewej (szary), my po prawej (niebieski jak iMessage), zaokrąglenie 18 pt, maks. szerokość 78 % ekranu.
- Załączniki: miniaturki 64 × 64 w dymku, maks. 3 + „+2"; dotknięcie otwiera podgląd (QuickLook).
- Treść: maks. 4 linie, „więcej" rozwija; daty jako separator między dniami.
- Zero HTML, zero ramek tabel — to ma być czytelne, nie wierne.

---

## 3. Kolejność prac (etapy)

| Etap | Zakres | Efekt | Szacunek |
|---|---|---|---|
| **0** | Zamrożenie web: README + `docs/web-dawca.md` (co bierzemy, czego nie) | jasna granica | 0,5 dnia |
| **1** | `ProjectOrder`: data montażu, geokodowanie, powiadomienia | działa data + przypomnienia | 1 dzień |
| **2** | Mapa pod adresem (MapKit + cache współrzędnych) | podgląd mapy w karcie | 0,5 dnia |
| **3** | Model maili + import `.eml` + ekran dymków + miniaturki | pełny ekran na prawdziwej poczcie | 2 dni |
| **4** | Gmail OAuth (auto pobieranie wątków klienta) | maile same się zaczytują | 2–3 dni |
| **5** | Lista zleceń: sortowanie po dacie montażu, przenoszenie góra/dół | panel akcji jak w zamówieniu | 1 dzień |
| **6** | Plan piętra: zestawienie w kolumnie po prawej (nie w arkuszu) | widok dwukolumnowy | 1 dzień |
| **7** | Powrót do ostatniego widoku kamery po zablokowaniu projektu | dopracowanie UX | 0,5 dnia |
| **8** | Testy na iPadzie, poprawki, przygotowanie do TestFlight | kandydat do wysyłki | 2 dni |

Razem ≈ 11 dni roboczych do wersji „kartoteka + maile + porządek w zleceniach".

---

## 4. Kryteria akceptacji (co musi być prawdą)

**Data montażu**
- [ ] Data i godzina zapisują się i są widoczne po restarcie aplikacji.
- [ ] Powiadomienie przychodzi 3 dni i 1 dzień przed, o 8:00.
- [ ] Lista zleceń sortuje się po dacie; brak daty = na końcu.

**Mapa**
- [ ] Po wpisaniu adresu pojawia się podgląd z pinezką.
- [ ] Po restarcie bez internetu mapa nadal ma pinezkę (cache współrzędnych).
- [ ] Zmiana adresu unieważnia stare współrzędne.

**Maile**
- [ ] Import `.eml` pokazuje tytuł, treść i miniaturki załączników.
- [ ] Załącznik otwiera się w podglądzie systemowym.
- [ ] Wątki są grupowane; wiadomości klienta po lewej, nasze po prawej.
- [ ] Pobrane są **tylko** wątki powiązane z klientem/adresem.
- [ ] Brak sieci: ekran pokazuje ostatnio pobrane wątki i nie wisi.

**Ogólne**
- [ ] 0 ostrzeżeń w Xcode, testy jednostkowe zielone.
- [ ] 60 kl./s w widoku 3D; plan przewija się płynnie.
- [ ] Wszystkie wymiary w mm, wyświetlane bez ułamków.

---

## 5. Ryzyka i jak je ograniczamy

| Ryzyko | Wpływ | Ograniczenie |
|---|---|---|
| OAuth do Gmaila odrzucony przez Google (weryfikacja aplikacji) | brak auto-pobierania | wariant D (import .eml) działa zawsze; wniosek o weryfikację składa się raz |
| Załączniki 20 MB+ (zdjęcia z telefonu klienta) | pamięć, czas importu | limit 25 MB na plik, miniaturki zamiast oryginałów w podglądzie |
| Adresy wiejskie bez numeru w geokoderze | brak mapy | pinezka po nazwie miejscowości + ręczne przeciągnięcie, współrzędne zapisane |
| Duplikaty wątków przy ponownym pobraniu | bałagan | klucz `Message-ID`, deduplikacja przy zapisie |
| Rozjazd planu i 3D po edycji | błędna wycena | plan → `room` → sygnatura sceny (już działa, pilnujemy testem) |

---

## 6. Czego świadomie NIE robimy teraz

- Web: brak nowych funkcji, brak deployów poza krytycznymi poprawkami.
- Pełna wektoryzacja ścian z obrazu (zostaje obrys + korekta palcem).
- Synchronizacja chmury między urządzeniami (dane lokalne; iCloud dopiero po TestFlight).
- Automatyczne odpowiedzi mailem z aplikacji (wysyłka później, po ustaleniu szablonów).
- Skanowanie LiDAR w tym etapie (kod jest, ale nie blokuje kartoteki).

---

## 7. Pytania do decyzji

1. **Poczta:** Gmail, Outlook, czy „dowolna przez IMAP"? (od tego zależy etap 4)
2. **Montaż:** czy oprócz daty potrzebna jest ekipa i godzina „od–do"?
3. **Załączniki:** trzymamy oryginały w aplikacji, czy tylko miniaturki + ścieżka do pliku?
4. **Zlecenia:** sortowanie tylko po dacie montażu, czy też po wartości oferty / zaległej zaliczce?
