# Instrukcja dla agenta — projekt elektroniki odbiornika GPS RTK

Ten plik jest punktem startowym dla osobnej sesji agenta, która ma zaprojektować
**warstwę sprzętową** odbiornika. Aplikacja mobilna jest rozwijana w INNEJ sesji —
nie modyfikuj katalogów `../app/` ani `../dane/`.

## 0. Zanim zaczniesz — przeczytaj

1. `../PROJEKT.md` — główny dokument projektu (cel, architektura, BOM, decyzje,
   sekcje „Kierunek/orientacja", „Protokół BLE", „Ryzyka"). **Przeczytaj w całości.**
2. `../app/lib/sources/ble_receiver_source.dart` — planowany protokół BLE, pod który
   musi pasować firmware (usługa NUS, NMEA w górę, RTCM w dół).
3. `../app/lib/models/rtk_position.dart` — jakie dane konsumuje aplikacja
   (pozycja, typ fixa GGA, dokładność, satelity, kurs).
4. Pamięć projektu (jeśli dostępna): `projekt-rtk-granice-dzialki.md`.

## 1. Kontekst produktu (skrót)

Przenośny odbiornik GNSS RTK o dokładności centymetrowej, którego głównym zadaniem
jest **odszukiwanie w terenie punktów granicznych działki** (tyczenie). Smartfon jest
głównym interfejsem i bramką do internetu (poprawki NTRIP z ASG-EUPOS); urządzenie
w terenie nie potrzebuje SIM ani WiFi.

## 2. Architektura (już zdecydowana — nie podważaj bez powodu)

```
satelity ))) Antena L1/L5 → LC29HEA → UART → ESP32 → BLE → Smartfon → mapa/tyczenie
                              ^                  |              ^
                              └── RTCM (UART) ───┘              │ internet
                                                          Caster NTRIP (ASG-EUPOS)
```

- **LC29HEA** liczy pozycję RTK, wysyła **NMEA** po UART, przyjmuje **RTCM** po UART.
- **ESP32** to most UART↔BLE + zarządzanie zasilaniem + status (OLED/LED). „Głupi" most —
  bez parsowania w gorącej ścieżce; parsuje GGA tylko na potrzeby statusu.
- **Smartfon** = klient NTRIP, mapa, logika tyczenia.

## 3. Rola elektroniki (zakres tej sesji)

- Most UART↔BLE: dwukierunkowy przepływ (NMEA ↑, RTCM ↓).
- Zasilanie: Li-Ion + ładowanie USB-C + pomiar napięcia baterii.
- OLED 0,96" SSD1306 (I2C) — status fixa/baterii bez telefonu (opcjonalny, ale przewidź).
- **IMU BNO085 (I2C)** — OPCJA na v2: kierunek „od urządzenia" + kompensacja pochylenia
  tyczki (patrz sekcja „Kierunek/orientacja" w PROJEKT.md). Przewidź miejsce, nie wymagaj.

## 4. BOM — punkt wyjścia (doprecyzuj numery katalogowe)

Z PROJEKT.md: LC29HEA (goły moduł / Waveshare LC29H(DA) HAT / MikroE GNSS RTK 3 Click),
ESP32-WROOM-32, antena L1/L5 z ground plane, OLED SSD1306, ogniwo 18650 + ładowarka
(TP4056 lub IP5306), obudowa z gwintem 5/8"×11 do tyczki geodezyjnej.

## 5. Kluczowe ograniczenia techniczne

- **Klasyczny ESP32-WROOM** (BT Classic SPP **i** BLE) — SPP pozwala testować cały tor
  z gotowymi aplikacjami (SW Maps, Lefebure) zanim powstanie nasza; docelowo BLE NUS,
  bo iOS nie wspiera SPP. Nie wybieraj S3/C3 (tylko BLE) bez świadomej decyzji.
- **Oba układy 3.3V** (LC29HEA i ESP32) → UART bez konwersji poziomów.
- **Antena aktywna L1/L5** — sprawdź w datasheet LC29HEA, czy moduł podaje bias na RF_IN
  (i jakie napięcie). Jeśli nie — zaprojektuj bias-tee (dławik + kondensator), 3.3V.
- **BLE**: usługa typu Nordic UART (NUS). NMEA → notify (TX). RTCM → write-without-response
  (RX). Negocjuj MTU ~185+ (Android domyślnie 23 B — to za mało dla RTCM). Druga
  charakterystyka „status" (bateria/uptime/przepływ) — patrz PROJEKT.md.
- **UART do GNSS**: 115200 na start, rozważ 460800 (RTCM + NMEA przy 5 Hz).

## 6. Sugerowane przypisanie pinów ESP32 (DO WERYFIKACJI)

To propozycja — zweryfikuj z kartą wybranego modułu i udokumentuj finalną wersję,
bo firmware i protokół aplikacji muszą być z nią spójne.

| Funkcja | Pin ESP32 (WROOM) | Uwaga |
|---|---|---|
| GNSS UART2 RX | GPIO16 | ← TX modułu GNSS (na WROVER zajęte przez PSRAM; WROOM OK) |
| GNSS UART2 TX | GPIO17 | → RX modułu GNSS |
| GNSS PPS | GPIO (dowolny wejściowy) | opcjonalnie, sygnał 1PPS |
| GNSS RESET | GPIO (wyjściowy) | opcjonalnie |
| OLED + IMU I2C SDA | GPIO21 | wspólna magistrala I2C |
| OLED + IMU I2C SCL | GPIO22 | |
| Pomiar napięcia baterii | GPIO34 | input-only, ADC1, przez dzielnik |
| LED statusu | GPIO2 | |
| Przyciski | GPIO0 (BOOT) / EN | programowanie/reset |

## 7. Oczekiwane produkty (deliverables)

1. **Schemat** (najlepiej KiCad): ESP32, moduł GNSS (UART/zasilanie/RF/antena+bias),
   OLED (I2C), miejsce na IMU (I2C), tor zasilania (bateria→ładowarka→3.3V LDO/DC-DC),
   USB-C, przyciski, LED.
2. **Dobór komponentów** z numerami katalogowymi i linkami (PL: Botland, Kamami, TME).
3. **Budżet mocy** i szacowany czas pracy dla wybranego ogniwa.
4. **Pinout / mapa do firmware** — osobny dokument, żeby zespół aplikacji mógł dopiąć
   protokół BLE i parser NMEA. To jest interfejs między sprzętem a oprogramowaniem.
5. **Uwagi mechaniczne**: obudowa, gwint 5/8"×11 do tyczki, montaż anteny + ground plane
   (min. ~10 cm dla anteny patch), odporność na warunki.
6. **Plan programowania/debugowania ESP32** (mostek USB-UART CP2102/CH340 lub devkit z USB).
7. (Opcjonalnie) projekt PCB dla v2 — v1 może powstać na płytkach stykowych/devkitach.

## 8. Otwarte pytania do rozstrzygnięcia z użytkownikiem

- LC29HEA: goły moduł vs Waveshare LC29H(DA) HAT vs MikroE GNSS RTK 3 Click?
- Antena: patch L1/L5 z ground plane vs helikalna survey; złącze SMA czy u.FL?
- Bateria: pojemność 18650 (np. 3500 mAh) vs pakiet; ładowarka TP4056 vs IP5306?
- USB-C: tylko ładowanie, czy również programowanie (wbudowany mostek USB-UART)?
- v1 na płytkach stykowych/devkitach, czy od razu własne PCB?
- Czy IMU BNO085 wchodzi już do v1, czy dopiero v2?

## 9. Środowisko i konwencje

- System: Windows. Narzędzie do schematów/PCB: KiCad (sprawdź dostępność / zaproponuj
  instalację).
- Pliki trzymaj w TYM katalogu, np. `kicad/`, `docs/`, `datasheety/`.
- Język dokumentacji: **polski** (spójnie z resztą repo).
- Jeśli podejmiesz nowe decyzje sprzętowe, dopisz je tutaj lub w `../PROJEKT.md`
  (sekcja sprzętowa) i zostaw krótką notkę, żeby sesja aplikacji była zgodna.

## 10. Czego NIE robić

- Nie modyfikuj `../app/` ani `../dane/` (to domena sesji aplikacji).
- Nie zmieniaj architektury (rola ESP32/telefonu) bez uzgodnienia — to świadoma decyzja.
- Nie commituj/nie pushuj bez prośby użytkownika.

## 11. Log decyzji sprzętowych

> Dopisywane przez sesję elektroniki (zgodnie z §9). Pełne uzasadnienia: `docs/01-decyzje-sprzetowe.md`.

### 2026-06-13 — pierwsza sesja projektowa

- **Zakres v1:** prototyp na devkitach/płytce stykowej; projekt PCB odłożony do v2.
- **Moduł GNSS:** podstawowo **MikroE GNSS RTK 3 Click (LC29HEA)** — to jedyny „gotowiec"
  z wariantem **EA** (RTK 1–10 Hz, SMA). **Waveshare ma tylko DA (RTK 1 Hz), nie EA.**
  Wariant budżetowy w BOM: **Waveshare LC29H(DA)**. Interfejs UART identyczny → moduł wymienny
  bez zmian w firmware/aplikacji.
- **Zasilanie:** 1× 18650 → TP4056 (USB-C, z zabezpieczeniem DW01A) → buck-boost 3.3 V.
- **I2C:** OLED SSD1306 w v1 + zarezerwowane pady pod IMU BNO085 (montaż w v2).
- **Programowanie v1:** przez USB devkita (CP2102/CH340); USB-C TP4056 tylko ładowanie.
- Pełna dokumentacja (schemat połączeń, BOM, budżet mocy, pinout, mechanika, programowanie)
  w `docs/`. KiCad niezainstalowany — schemat w v1 jako diagram + tabele połączeń; formalny
  schemat KiCad zaproponowany dla v2.
