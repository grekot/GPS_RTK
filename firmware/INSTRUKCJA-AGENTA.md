# Instrukcja dla agenta — firmware ESP32 odbiornika GPS RTK

Ten plik jest punktem startowym dla osobnej sesji agenta, która ma napisać
**firmware ESP32** (most UART↔BLE). Aplikacja mobilna i elektronika są prowadzone
w INNYCH sesjach — nie modyfikuj `../app/`, `../dane/`, `../elektronika/`.

## 0. Zanim zaczniesz — przeczytaj

1. `../PROJEKT.md` — główny dokument (cel, architektura, sekcje „Protokół BLE",
   „Kierunek/orientacja", „Ryzyka"). **Przeczytaj w całości.**
2. `../app/lib/sources/ble_receiver_source.dart` — protokół BLE, pod który firmware
   MUSI pasować (to kontrakt sprzęt↔aplikacja).
3. `../app/lib/models/rtk_position.dart` — jakie dane konsumuje aplikacja
   (pozycja, typ fixa z GGA, dokładność, satelity, kurs).
4. `../elektronika/INSTRUKCJA-AGENTA.md` — przypisanie pinów ESP32 (UART/I2C/ADC).
   Trzymaj firmware spójny z tym pinoutem.

## 1. Kontekst produktu (skrót)

Przenośny odbiornik GNSS RTK do odszukiwania punktów granicznych działki. Smartfon
jest interfejsem i bramką do internetu (poprawki NTRIP z ASG-EUPOS). ESP32 to most
między modułem GNSS a telefonem.

## 2. Architektura

```
LC29HEA  ──UART (NMEA ↑)──►  ESP32  ──BLE notify──►  Smartfon
   ▲                            │                        │
   └──────UART (RTCM ↓)─────────┘  ◄──BLE write──────────┘ (RTCM z castera NTRIP)
```

ESP32 jest „głupim", niezawodnym mostem: przepompowuje bajty UART↔BLE i parsuje
GGA tylko na potrzeby statusu (OLED/LED). Bez ciężkiego przetwarzania w gorącej ścieżce.

## 3. Toolchain (VS Code + PlatformIO)

PlatformIO Core **jest zainstalowane** (6.1.x), VS Code również. W VS Code użyj
rozszerzenia „PlatformIO IDE" (otwórz katalog `firmware/`). Z linii poleceń:

- Budowanie: `pio run`
- Wgranie:   `pio run -t upload`
- Monitor:   `pio device monitor` (115200)

Konfiguracja w `platformio.ini`: `board = esp32dev` (ESP32-WROOM-32),
`framework = arduino`. Biblioteki dokładaj przez `lib_deps` (propozycje w pliku).

## 4. Stan projektu (szkielet już jest)

- `platformio.ini` — gotowy (esp32dev / arduino).
- `src/main.cpp` — **kamień milowy 1**: przezroczysty most USB↔GNSS (Serial2 na
  GPIO16/17 ↔ Serial USB). Pozwala zobaczyć NMEA z modułu w monitorze. To Twój
  punkt wyjścia — zweryfikuj `pio run`, a po podłączeniu modułu odczytaj NMEA.

## 5. Plan (kamienie milowe)

- **M1 (zrobione w szkielecie):** most USB↔GNSS — podgląd NMEA.
- **M2:** BLE NUS — wysyłanie NMEA z UART jako notify (TX) do telefonu.
- **M3:** odbiór RTCM z telefonu (write na RX) → zapis do UART modułu (→ RTK Fixed).
- **M4:** parser GGA → status (typ fixa 0/1/2/4/5, liczba satelitów, HDOP, wiek
  poprawek) → LED statusu.
- **M5:** OLED SSD1306 (I2C) — typ fixa, satelity, bateria.
- **M6:** pomiar napięcia baterii (ADC, GPIO34 przez dzielnik) + charakterystyka
  „status" (JSON/CBOR co 1 s): bateria, uptime, przepływ RTCM B/s.
- **M7 (opcja):** równoległy profil **Bluetooth Classic SPP** — pozwala testować cały
  tor z gotowymi aplikacjami (SW Maps, Lefebure NTRIP) zanim dopniemy własną.
- **M8 (opcja):** konfiguracja LC29HEA przez UART przy starcie (częstotliwość 1–5 Hz,
  włączone zdania GGA/RMC/GST, prędkość UART) — komendy PQTM/PAIR wg karty modułu.

## 6. Protokół BLE — KONTRAKT z aplikacją (nie zmieniaj jednostronnie)

Usługa **Nordic UART Service (NUS)**:

- Usługa:            `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- **TX (Notify)**, urządzenie → telefon: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
  — strumień **NMEA** z odbiornika.
- **RX (Write/WriteNoResponse)**, telefon → urządzenie: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
  — strumień **RTCM** do modułu.

Wymagania:
- Negocjuj **MTU** (proś o ~247 B). Android domyślnie 23 B — za mało dla RTCM.
- RTCM bywa fragmentowany — sklejaj zapisy i przekazuj do UART bez modyfikacji.
- Rozważ drugą charakterystykę „status" (telemetria niezależna od strumienia NMEA).
- Rekomendowana biblioteka: **NimBLE-Arduino** (lekka). Jeśli zmienisz UUID/profil,
  ZGŁOŚ to — sesja aplikacji musi użyć tych samych wartości w `BleReceiverSource`.

## 7. Pinout (z elektroniki — do potwierdzenia)

| Funkcja | Pin ESP32 |
|---|---|
| GNSS UART2 RX (← TX modułu) | GPIO16 |
| GNSS UART2 TX (→ RX modułu) | GPIO17 |
| I2C SDA (OLED/IMU) | GPIO21 |
| I2C SCL (OLED/IMU) | GPIO22 |
| Napięcie baterii (ADC1) | GPIO34 (input-only) |
| LED statusu | GPIO2 |

## 8. Konwencje i weryfikacja

- Komentarze i dokumentacja po polsku (spójnie z repo); kod idiomatyczny Arduino/ESP32.
- Każdy etap kończ czystym `pio run`. Jeśli masz sprzęt — `pio run -t upload`
  + `pio device monitor` i potwierdź zachowanie (np. NMEA w monitorze, fix w aplikacji).
- Trzymaj kod w tym katalogu (`src/`, `include/`, `lib/`).

## 9. Czego NIE robić

- Nie modyfikuj `../app/`, `../dane/`, `../elektronika/`.
- Nie zmieniaj protokołu BLE jednostronnie (to kontrakt z aplikacją).
- Nie commituj/nie pushuj bez prośby użytkownika.
