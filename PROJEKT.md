# Odbiornik GPS RTK na ESP32 ze smartfonem jako terminalem

## Cel

Przenośny odbiornik GNSS o dokładności centymetrowej (RTK), w którym:
- **smartfon** jest głównym interfejsem użytkownika (mapa, status, logowanie punktów) i bramką do internetu (poprawki NTRIP),
- **ESP32** pełni rolę mostka między modułem GNSS a telefonem (BLE) oraz zarządza zasilaniem,
- opcjonalny **mały OLED** na urządzeniu pokazuje podstawowy status bez telefonu.

**Główny scenariusz użycia:** odszukanie w terenie punktów granicznych działki (tyczenie) na podstawie współrzędnych z ewidencji gruntów oraz pomiar własnych punktów. To wymusza w aplikacji: obsługę układu **PL-2000**, tryb **tyczenia** (nawigacja do punktu o zadanych współrzędnych) i warstwę **działek ewidencyjnych** na mapie.

## Architektura

```
satelity ))) Antena L1/L2 ──> ZED-F9P ──UART1 (NMEA)──> ESP32 ──BLE──> Smartfon ──> mapa, log
                                  ^                        |             ^
                                  └──UART (RTCM in)────────┘             │ internet
                                                                   Caster NTRIP
                                                                  (np. ASG-EUPOS)
```

Przepływ danych:
1. ZED-F9P liczy pozycję i wysyła zdania **NMEA** (GGA, RMC, GST) po UART do ESP32.
2. ESP32 przekazuje NMEA przez **BLE** (usługa typu Nordic UART Service) do telefonu.
3. Aplikacja na telefonie działa jako **klient NTRIP**: łączy się z casterem przez internet komórkowy, pobiera strumień **RTCM 3.x** i odsyła go przez BLE do ESP32.
4. ESP32 wpuszcza RTCM z powrotem do UART modułu F9P → moduł przechodzi w tryb **RTK Fixed** (~1–2 cm).

Zalety tego podziału: urządzenie nie potrzebuje karty SIM ani WiFi w terenie, a cała logika "ciężka" (mapa, konto NTRIP, eksport danych) żyje w telefonie.

Tryb zapasowy (do rozważenia w v2): ESP32 sam łączy się z hotspotem telefonu po WiFi i odpala własnego klienta NTRIP — telefon wtedy tylko wyświetla.

## Sprzęt (BOM)

| Element | Propozycja | Orientacyjna cena |
|---|---|---|
| Moduł GNSS RTK (budżetowo) | **Quectel LC29HEA** (L1+L5, rover RTK, 10 Hz) — płytka z AliExpress lub MikroE GNSS RTK 3 Click; w PL: Waveshare LC29H(DA) HAT (Botland/Kamami) | ~230–330 zł |
| Moduł GNSS RTK (średnia półka) | **Unicore UM980** (triple-band L1/L2/L5) — płytka z AliExpress/GNSS Store | ~400–600 zł |
| Moduł GNSS RTK (premium) | **u-blox ZED-F9P** (ArduSimple simpleRTK2B / SparkFun GPS-RTK2) | ~800–1200 zł |
| MCU | **ESP32-WROOM-32** (devkit lub własna płytka) | ~25–40 zł |
| Antena | do LC29HEA: tania antena **L1/L5** (np. Waveshare, ~70–120 zł); do UM980/F9P: u-blox **ANN-MB-00** | ~70–300 zł |
| Wyświetlacz (opcja) | OLED 0,96" SSD1306, I2C | ~10 zł |
| Zasilanie | Li-Ion 18650 + ładowarka USB-C (IP5306 / TP4056+boost) | ~20–30 zł |
| Obudowa | druk 3D, gwint 5/8" do tyczki geodezyjnej | — |

> **Uwaga na wybór modułu GNSS:** LC29HEA jest tylko roverem (do własnej stacji bazowej potrzebny wariant LC29HBS), ma słabszą odporność na zakłócenia i multipath niż F9P/UM980 oraz ograniczone surowe obserwacje (PPK utrudniony). Dla projektu rover + poprawki z sieci NTRIP (nasz przypadek) w terenie z dobrą widocznością nieba sprawdza się bardzo dobrze — testy rtklibexplorer potwierdzają stabilny RTK Fixed. Interfejs jest identyczny jak w F9P (UART: NMEA wyjście, RTCM wejście), więc architektura i firmware nie zmieniają się wcale — moduł można później wymienić na lepszy bez zmian w aplikacji.

> **Uwaga na wybór ESP32:** klasyczny ESP32 ma Bluetooth Classic (SPP) **i** BLE — SPP daje od ręki zgodność z istniejącymi aplikacjami (SW Maps, Lefebure NTRIP Client), co jest świetne do testów zanim powstanie nasza aplikacja. ESP32-S3/C3 mają **tylko BLE**. iOS nie obsługuje SPP, więc docelowa własna aplikacja i tak powinna używać **BLE**.

> **Status sprzętu (sesja elektroniki, 2026-06-13):** projekt warstwy sprzętowej żyje w
> `elektronika/docs/` (schemat połączeń, BOM, budżet mocy, pinout dla firmware, mechanika,
> plan programowania). Kluczowe ustalenia: v1 na devkitach (PCB → v2); zasilanie
> 18650 + TP4056 + buck-boost 3.3 V; OLED w v1, IMU BNO085 w v2. **Uwaga dot. modułu GNSS:**
> Waveshare oferuje tylko wariant **DA (RTK 1 Hz)**, nie EA. Wariant **EA (do 10 Hz)** z nazwy
> projektu kupimy jako **MikroE GNSS RTK 3 Click (LC29HEA)** — to obecnie moduł podstawowy.
> Dla aplikacji jedyna różnica to częstotliwość napływu NMEA (1 Hz przy DA vs do 10 Hz przy EA);
> interfejs (NUS: NMEA↑ notify / RTCM↓ write) bez zmian.

> **Dla sesji aplikacji (2026-06-13):** dodać źródło pozycji po **USB** (Android, moduł LC29HEA
> przez USB-C / OTG, baud 115200) — pełna instrukcja: `elektronika/docs/09-instrukcja-app-usb.md`
> (to klon `BleReceiverSource` z transportem `usb_serial`; `NmeaParser`/`NtripClient` współdzielone).

## Firmware ESP32 (PlatformIO, Arduino lub ESP-IDF)

Moduły:
- **uart_bridge** — dwukierunkowe przepompowywanie UART ↔ BLE (NMEA w górę, RTCM w dół), bufory ringowe, bez parsowania w gorącej ścieżce.
- **ble_service** — Nordic UART Service (TX notify / RX write), MTU ~185–247 B, fragmentacja strumienia RTCM.
- **gnss_config** — konfiguracja F9P przez UBX przy starcie (częstotliwość 1–5 Hz, włączone GGA/RMC/GST, prędkość UART 115200/460800).
- **status** — parsowanie GGA tylko na potrzeby OLED/LED: typ fixa (0/1/2/4/5), liczba satelitów, HDOP, wiek poprawek.
- **power** — pomiar napięcia baterii (ADC + dzielnik), raportowanie % do aplikacji.
- **(opcja) bt_spp** — równoległy profil SPP dla zgodności z SW Maps/Lefebure.

## Aplikacja mobilna

Rekomendacja: **Flutter** (jedna baza kodu Android + iOS; biblioteki: `flutter_blue_plus`, `flutter_map` z OpenStreetMap). Alternatywa: natywnie Kotlin, jeśli celujemy tylko w Androida.

Funkcje (MVP → dalej):
1. Skanowanie i parowanie BLE z odbiornikiem.
2. Klient NTRIP (login do castera, wybór mountpointu, wysyłanie GGA do castera — wymagane przez sieci VRS jak ASG-EUPOS).
3. Ekran statusu: typ fixa (No fix / 3D / Float / **Fixed**), dokładność (z GST), satelity, wiek poprawek, bateria odbiornika.
4. Mapa (OSM) z aktualną pozycją i śladem.
5. Pomiar i zapis punktów (uśrednianie n epok), eksport **CSV / GPX / GeoJSON**.
6. **Tryb tyczenia (stakeout)** — kluczowy dla granic działki: import listy punktów (CSV/GeoJSON, współrzędne PL-2000 lub WGS84), wybór punktu docelowego, ekran nawigacji „do punktu": strzałka kierunku, odległość (z dokładnością do cm przy Fixed), sygnał dźwiękowy przy < 5 cm.
   - **„Na jakiej działce stoję?"** — jeden przycisk: aktualna pozycja RTK → ULDK `GetParcelByXY` (zwraca identyfikator i geometrię działki pod podanymi współrzędnymi, przetestowane 2026-06-12) → obrys działki na mapie + wierzchołki jako lista punktów do tyczenia. Wymaga internetu w telefonie (i tak jest, bo NTRIP); wynik cache'owany offline. Uwaga UX: przy pozycji Float blisko granicy aplikacja może wskazać sąsiednią działkę — pokazywać identyfikator i pozwolić wybrać sąsiada jednym gestem.
7. **Układy współrzędnych** — transformacja WGS84/PL-ETRF2000 ↔ **PL-2000** (strefy 5–8, EPSG:2176–2179); współrzędne punktów granicznych z dokumentów geodezyjnych są zawsze w PL-2000. Implementacja: biblioteka proj4dart lub własna transformacja Gaussa-Krügera.
8. **Warstwa działek ewidencyjnych** na mapie — WMS GUGiK „Krajowa Integracja Ewidencji Gruntów" (KIEG) podkłada granice i numery działek pod aktualną pozycję; usługa **ULDK** pozwala pobrać geometrię działki po jej identyfikatorze.
9. (Android) **Mock location** — pozycja RTK podstawiana systemowo, korzystają z niej wszystkie aplikacje na telefonie.
10. Konfiguracja odbiornika (częstotliwość pomiaru, ustawienia BLE).

## Wyznaczanie granic działki — uwagi praktyczne i prawne

- **Skąd wziąć współrzędne punktów granicznych:** wniosek do powiatowego ośrodka dokumentacji geodezyjnej (PODGiK) o wykaz współrzędnych punktów granicznych działki (w PL-2000), albo podgląd w serwisie geoportal.gov.pl (warstwa „punkty graniczne" z atrybutami).
- **Atrybut dokładności punktu (BPP/ZRD):** punkty graniczne w ewidencji mają różne pochodzenie — te z pomiarów nowoczesnych mają błąd ≤ 0,10 m, ale starsze (digitalizacja map) mogą mieć błąd 0,3–3 m. Zanim zaczniesz tyczyć, sprawdź atrybuty punktów — RTK o dokładności 2 cm nie naprawi punktu, który w ewidencji ma dokładność 1 m.
- **Granica prawna vs informacyjna:** samodzielne odszukanie punktów ma charakter **wyłącznie informacyjny** (np. gdzie postawić płot z bezpiecznym marginesem). Prawnie skuteczne wznowienie znaków granicznych lub rozgraniczenie może wykonać tylko **geodeta uprawniony**. Nasze urządzenie świetnie nadaje się do weryfikacji „czy płot sąsiada stoi na moim" — ale dowodem w sporze nie będzie.
- **Dokładność wystarczająca:** RTK Fixed (1–3 cm) + punkt graniczny o BPP ≤ 0,10 m daje realną niepewność ~10 cm — w zupełności wystarczy do celów informacyjnych i planowania ogrodzenia.

## Kierunek / orientacja (heading)

LC29HEA jest **jednoantenowy** — daje precyzyjną pozycję, ale nie orientację.
Z NMEA dostępny jest tylko kurs nad ziemią (COG, zdania RMC/VTG) — działa wyłącznie
podczas ruchu. Brak magnetometru na module. Źródła kierunku w projekcie:

1. **Kompas telefonu** (zaimplementowane, `flutter_compass`) — działa na stojąco;
   ±kilka stopni, czuły na metal/kalibrację. Podstawa.
2. **COG z ruchu RTK** — do dołożenia: dzięki pozycjom cm-owym jeden krok wyznacza
   kierunek bardzo dokładnie (w telefonie nieosiągalne przez szum). Za darmo.
3. **IMU na ESP32 (np. BNO085)** — opcja hardware v2: kierunek „od urządzenia"
   bez machania telefonem + kompensacja pochylenia tyczki. ~40–80 zł.
4. **Odbiornik dwuantenowy (UM982)** — prawdziwy heading GNSS <1°, odporny na metal,
   na stojąco; ale drożej i wymaga drugiej anteny.

Decyzja: kompas telefonu + COG z RTK jako podstawa; BNO085 rozważyć w v2.
Aplikacja ma już `_effectiveHeading` (kompas → kurs zapasowo) — wpięcie COG z NMEA
to dodanie kolejnego źródła bez zmian w UI. Do samego odnalezienia punktu kierunek
nie jest krytyczny (tarcza celownicza + „zrób krok, by się zorientować").

## Protokół BLE (szkic)

- Usługa NUS `6E400001-…`:
  - **TX (notify)**: surowe NMEA z odbiornika.
  - **RX (write without response)**: surowe RTCM z telefonu.
- Druga, własna charakterystyka "status" (JSON/CBOR co 1 s): bateria, uptime, przepływ RTCM B/s — żeby nie parsować NMEA po stronie ESP32 i mieć telemetrię niezależną od strumienia.

## Etapy realizacji

Kolejność odwrócona względem pierwotnego planu — aplikacja powstaje **przed** sprzętem,
zasilana pozycją z GPS telefonu przez abstrakcję `PositionSource` (źródła wymienne:
telefon / odbiornik BLE / odtwarzanie logów NMEA).

1. **Aplikacja MVP na GPS telefonu** *(w toku — szkielet w `app/` działa)* — mapa OSM,
   obrys działki, marker pozycji z kołem niepewności, przełącznik źródeł pozycji.
2. **Aplikacja v2** — tyczenie punktów, PL-2000, „na jakiej działce stoję" (ULDK),
   klient NTRIP (gotowy zanim przyjdzie sprzęt), eksport pomiarów.
3. **Zakup i prototyp sprzętu** — LC29HEA + ESP32 devkit na płytkach stykowych;
   test z SW Maps (SPP) i ASG-EUPOS → potwierdzenie RTK Fixed.
4. **Firmware v1** — most BLE NUS + konfiguracja LC29HEA + status na OLED;
   w aplikacji implementacja `BleReceiverSource` (parser NMEA GGA/GST).
5. **Hardware v2** — własne PCB, bateria, obudowa z gwintem na tyczkę.

## Struktura repo

- `PROJEKT.md` — ten dokument
- `dane/` — dane referencyjne (punkty graniczne działki 222/1 w CSV i GeoJSON)
- `app/` — aplikacja Flutter (Android + iOS); źródła pozycji w `app/lib/sources/`,
  obrys działki testowej jako asset

## Ryzyka i uwagi

- **Przepustowość BLE**: strumień RTCM (MSM4, sieć VRS) to zwykle 0,5–2 kB/s — BLE z MTU 185+ i write-without-response spokojnie wystarcza, ale trzeba poprawnie negocjować MTU (Android domyślnie 23 B!).
- **ASG-EUPOS** wymaga darmowej rejestracji konta; do testów bez konta można postawić własną bazę (drugi F9P) lub użyć publicznych casterów (rtk2go).
- **Wiek poprawek > 10–30 s** → spadek z Fixed do Float; aplikacja powinna to wyraźnie sygnalizować.
- Antena ma **kluczowy** wpływ na jakość — ground plane min. ~10 cm dla anten patch.
