# Uwagi mechaniczne — obudowa, gwint, antena, odporność

> Deliverable §5. Obudowa drukowana 3D na tyczkę geodezyjną. Źródła w treści.

## 1. Gwint mocujący do tyczki: 5/8"-11 UNC

- **Standard geodezyjny:** średnica **5/8" (15,875 mm)**, **11 zwojów/cal (TPI)**, zarys **UNC** (60°).
  To dominujące mocowanie tyczek, statywów, luster, tachimetrów.
- **NIE myli się** z gwintami fotograficznymi: **1/4"-20** (aparaty) i **3/8"-16** (głowice) to inne,
  niewymienne gwinty. Obudowa **musi mieć 5/8"-11**, żeby wejść na tyczkę geodezyjną.
- Niuans: starsze źródła podają 5/8"×11 jako BSW (55°); współcześnie standardem jest UNC — bierz UNC.

Źródła: [tabela gwintów statywów geodezyjnych](http://www.antiquesurveying.com/tripod_thread_sizes.htm),
[1/4"-20 vs 3/8"-16](https://www.ulanzi.com/blogs/knowledges/1-4-20-vs-3-8-16-thread-pitch-legacy-gear-guide).

## 2. Jak zrobić gwint 5/8"-11 w wydruku 3D (od najtrwalszego)

Połączenie z tyczką jest obciążane momentem i zginaniem, wielokrotnie skręcane w terenie →
**plastik sam nie wystarczy**.

1. **Zatopiona metalowa nakrętka 5/8"-11 lub gotowy metalowy adapter — ZALECANE.** Gniazdo
   sześciokątne w wydruku na nakrętkę stalową 5/8"-11 (pauza druku + wrzucenie, albo wklejenie po),
   ewentualnie gotowy adapter geodezyjny z gwintem 5/8". Metal przenosi cały moment, plastik tylko
   trzyma nakrętkę. „Embedded nut + machine screw is the strongest" ([Hackaday](https://hackaday.com/2025/09/02/no-need-for-inserts-if-youre-prepared-to-use-self-tappers/)).
2. **Heat-set insert mosiężny** — świetny do wielokrotnego montażu (radełko = duża siła wyrwania),
   ale w rozmiarze **5/8"-11 rzadko dostępny** (typowo M2–M8). ([Protolabs](https://www.protolabs.com/resources/blog/threading-and-inserts-for-3d-printing/)).
3. **Gwintowanie wydruku gwintownikiem (PETG/ABS)** — tylko awaryjnie; powtarzane skręcanie ściera
   zwoje.

**Gdzie kupić adapter/nakrętkę 5/8"-11 (PL):**
[sklepleicageosystems.com](https://sklepleicageosystems.com/produkt/gad32-tyczka-teleskopowa-gwint-5-8-cala/),
[tpi.com.pl](https://tpi.com.pl/produkt/dodatki-geodezyjne/),
[zmierz.to](https://zmierz.to/k397,akcesoria-geodezyjne-tyczki-geodezyjne.html),
albo zwykła **nakrętka stalowa 5/8"-11 UNC** ze sklepu z elementami złącznymi calowymi + zatopienie.
Inspiracje druku: [Emlid survey pole](https://community.emlid.com/t/3d-design-files-for-survey-pole/10903),
[Printables](https://www.printables.com/model/36039-bunnings-paint-pole-to-gps-thread-for-surveyors).

## 3. Antena i ground plane

Na podstawie noty Tallysman „Ground Plane Considerations for GNSS Ceramic Patch Antennas":

- **Rozmiar:** ground plane **Ø100–120 mm** (zgodne z założeniem „min ~10 cm" z `../PROJEKT.md`).
  Reguła ~0,5 λ; L1 λ≈19 cm. **Większy nie znaczy lepszy** — powyżej zysk spada przez dyfrakcję na krawędziach.
- **Kształt:** **koło** (sygnał GNSS jest RHCP — symetria poprawia axial ratio i tłumi multipath),
  ciągłe, bez szczelin.
- **Materiał:** dysk **aluminiowy/miedziany** (trwały) **lub folia metaliczna** na płaskiej tacce
  wydruku — RF działa tak samo. **Nie musi być masą elektryczną** odbiornika (to reflektor RF).
- **Kabel anteny prowadź pod** ground plane (płaszczyzna ekranuje kabel).
- Antena **helikalna QFH** ground plane **nie wymaga** — alternatywa, jeśli zależy na zwartości.

Źródła: [Tallysman App Note](https://community.emlid.com/uploads/default/original/2X/9/97c4b2e0722b4490546d21334add1a22a0f1934c.pdf),
[reguła 0,5 λ](https://files.igs.org/pub/resource/pubs/04_rtberne/cdrom/Session8/8_3_Tatarnikov.pdf).

## 4. Odporność na warunki (urządzenie ręczne w terenie)

- **Cel realistyczny: IP65** (pyłoszczelność + ochrona przed strugą wody/deszczem). IP67 (zanurzenie)
  to znaczny wzrost złożoności — dla tyczki zwykle zbędny. ([IP65 vs IP67](https://www.polycase.com/techtalk/ip-rated-enclosures/ip65-vs-ip67.html)).
- **Uszczelka:** ciągła silikon/EPDM/neopren w rowku, **ścisk 20–50%**, bez przerw na narożnikach.
- **USB-C:** najsłabszy punkt szczelności → **gumowa klapka/zatyczka na uwięzi**; port tylko do
  ładowania/flashowania, na co dzień zamknięty.
- **Ciepło vs szczelność (konflikt):** szczelna obudowa = „efekt piekarnika" (ESP32 + GNSS +
  ładowanie + słońce). Rozwiązania bez naruszania IP: montaż grzejących układów **do ścianki**
  (płytka Al jako heat-spreader), jasny kolor obudowy, zapas objętości na konwekcję, ewentualnie
  membrana **Gore-Tex** wyrównująca ciśnienie/wilgoć. ([uszczelnienia](https://ohmframe.com/blog/how-to-design-enclosure-ip65-ip67)).

## 5. Kompozycja urządzenia (propozycja)

```
        ┌─ antena patch L1/L5 na ground plane Ø100–120 mm  ── najlepsza widoczność nieba
        │  (kabel pod spód)
   ╔════╪════════════╗
   ║  [korpus 3D]    ║   ← ESP32 + moduł GNSS + buck-boost + TP4056
   ║  OLED ◻  LED •  ║   ← OLED + LED widoczne z zewnątrz
   ║  18650          ║   ← ogniwo (wymienne lub stałe)
   ║  USB-C (klapka) ║   ← ładowanie
   ╚════╤════════════╝
        │ nakrętka/adapter 5/8"-11 UNC (metal)
        ▼
     tyczka geodezyjna
```

- **Antena na samej górze**, centrycznie nad osią tyczki (offset pionowy do uwzględnienia w aplikacji
  przy pomiarze — „antenna height").
- **Środek ciężkości** możliwie nisko (ogniwo niżej) — stabilność na tyczce.
- **OLED + LED + przycisk** dostępne i czytelne w słońcu (rozważ daszek/kontrast).
- Gwint 5/8" na osi, współosiowo z anteną.
