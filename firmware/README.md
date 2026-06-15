# Firmware ESP32 — odbiornik GPS RTK

Most UART↔BLE między modułem GNSS LC29HEA a aplikacją mobilną. ESP32 jest „głupim",
niezawodnym mostem: surowe **NMEA** w górę (do telefonu), surowe **RTCM** w dół (do
modułu). GGA parsujemy tylko na potrzeby statusu (LED/OLED/telemetria).

- **Toolchain:** PlatformIO (VS Code + rozszerzenie „PlatformIO IDE").
- **Budowanie:** `pio run` · **Wgranie:** `pio run -t upload` · **Monitor:** `pio device monitor`
- **Pełny opis zadania:** [INSTRUKCJA-AGENTA.md](INSTRUKCJA-AGENTA.md)
- **Kontekst projektu:** [../PROJEKT.md](../PROJEKT.md)

## Stan: M2–M7 zaimplementowane (M8 opcjonalnie)

| Etap | Zakres | Status |
|---|---|---|
| M1 | Most USB↔GNSS (podgląd NMEA) | ✅ (zastąpiony przez most BLE) |
| M2 | BLE NUS — NMEA notify (TX) → telefon | ✅ |
| M3 | RTCM write (RX) → UART modułu | ✅ |
| M4 | Parser GGA → status + LED (GPIO2) | ✅ |
| M5 | OLED SSD1306 (I2C) | ✅ (auto-wykrywany) |
| M6 | Bateria (ADC) + charakterystyka „status" (JSON co 1 s) | ✅ |
| M7 | Bluetooth Classic SPP (osobny build testowy) | ✅ (env `esp32dev-spp`) |
| M8 | Konfiguracja LC29HEA przy starcie | ⚙️ opcja, domyślnie **off** (komendy zweryfikowane ze spec. — patrz niżej) |

Build zweryfikowany (`pio run`, oba środowiska zielone), Arduino-ESP32 3.3.5:
- `esp32dev` (BLE/NimBLE): **Flash ~51%**, **RAM ~11.5%**
- `esp32dev-spp` (SPP/Bluedroid): **Flash ~86%**, **RAM ~13%** (Bluedroid jest ciężki, mieści się)

**Nie testowane na sprzęcie** — weryfikacja to kompilacja + natywny test logiki na PC
([`sim/`](sim/), patrz niżej). Pełny tor potwierdzisz po podłączeniu sprzętu:
`pio run -e esp32dev -t upload` + `pio device monitor`.

## Protokół BLE (zaimplementowany)

Usługa **Nordic UART Service (NUS)** — zgodna z kontraktem aplikacji
([../app/lib/sources/ble_receiver_source.dart](../app/lib/sources/ble_receiver_source.dart)):

| Charakterystyka | UUID | Właściwości | Kierunek / treść |
|---|---|---|---|
| Usługa NUS | `6E400001-…` | — | — |
| **RX** | `6E400002-…` | Write / WriteNR | telefon → ESP32: **RTCM** (do UART modułu, bez modyfikacji) |
| **TX** | `6E400003-…` | Notify | ESP32 → telefon: **NMEA** (chunkowane wg MTU) |
| **status** ⚠️ | `6E400004-…` | Read + Notify | ESP32 → telefon: **telemetria JSON** (co 1 s) |

- MTU: prosimy o **247 B** (`NimBLEDevice::setMTU`); NMEA dzielone na paczki ≤ MTU−3.
- Nazwa rozgłaszana: `RTK-Rover`; aplikacja i tak znajduje urządzenie po UUID usługi.

### ⚠️ DO ZGŁOSZENIA sesji aplikacji — nowa charakterystyka „status"

Charakterystyka `6E400004-B5A3-F393-E0A9-E50E24DCCA9E` to **rozszerzenie poza standard
NUS** (telemetria niezależna od strumienia NMEA, zgodnie z sekcją „Protokół BLE" w
PROJEKT.md). Jest opcjonalna — most działa bez niej. Jeśli aplikacja ma ją czytać,
sesja aplikacji musi użyć tego UUID i formatu. Format (JSON, co 1 s):

```json
{"bat_mv":3987,"bat_pct":74,"up_s":1234,"rtcm_bps":512,"ble_mtu":247,
 "fix":4,"sat":18,"hdop":0.82,"age":1.4}
```

| Pole | Znaczenie |
|---|---|
| `bat_mv` / `bat_pct` | napięcie ogniwa [mV] / szacowany stan [%] (0 gdy pomiar wyłączony) |
| `up_s` | uptime [s] |
| `rtcm_bps` | przepływ RTCM telefon→moduł [B/s] (potwierdza dosył poprawek) |
| `ble_mtu` | wynegocjowany ATT MTU |
| `fix` | typ fixa z GGA (0/1/2/4/5) |
| `sat` / `hdop` / `age` | satelity / HDOP / wiek poprawek [s] (`age=-1` = brak) |

> Pozostałe parametry (pozycja, dokładność z GST, kurs) aplikacja bierze z surowego
> NMEA na charakterystyce TX — `status` to tylko telemetria urządzenia.

## Warianty buildu: BLE (docelowy) vs SPP (testowy)

SPP (Bluetooth Classic) wymaga stosu **Bluedroid**, a BLE NUS używa **NimBLE** —
w jednym firmware się wykluczają. Dlatego są dwa środowiska PlatformIO; flashujesz jedno:

| Środowisko | Radio | Po co | Wgranie |
|---|---|---|---|
| `esp32dev` (domyślne) | BLE NUS (NimBLE) | wariant **docelowy**, kontrakt z aplikacją; iOS + Android | `pio run -e esp32dev -t upload` |
| `esp32dev-spp` | Bluetooth Classic SPP (Bluedroid) | **test** całego toru z SW Maps / Lefebure NTRIP, zanim powstanie własna aplikacja (tylko Android) | `pio run -e esp32dev-spp -t upload` |

Most SPP jest funkcjonalnie identyczny (NMEA ↑, RTCM ↓), brak w nim tylko charakterystyki
telemetrii (to pojęcie BLE). Współdzieli wszystkie pozostałe moduły. Na OLED górny pasek
pokazuje wtedy `SPP` zamiast `BLE`. Gdyby kiedyś był potrzebny **jednoczesny** BLE+SPP,
trzeba by przepisać warstwę BLE z NimBLE na Bluedroid (cięższe) — dziś niepotrzebne.

## Symulator na PC — test bez sprzętu ([`sim/`](sim/))

Konsolowy harness, który uruchamia **prawdziwy kod parsera firmware** na Windows
(g++ z MSYS2) — bez modułu GNSS i ESP32. Karmi `gnss_status.cpp` strumieniem NMEA
jak z LC29HEA (zimny start → 3D → RTK Float → RTK Fixed → starzenie poprawek →
spadek), sprawdza wynik i **rysuje podgląd ekranu OLED** (ASCII, układ 1:1 z
`display.cpp`) ewoluujący z każdą epoką. Dorzuca testy `statusLedLevel()`,
`buildStatusJson()` i `displayFixLabel()`.

- **Uruchomienie:** dwuklik [`sim/run-sim.bat`](sim/run-sim.bat) (sam znajdzie g++,
  skompiluje i odpali). Kończy się `PASS`/`FAIL` (kod wyjścia 0/1 — nadaje się do CI).
- **Po co:** wyłapuje błędy realnego parsera (suma kontrolna, indeksy pól, wiek
  poprawek, odrzucanie śmieci) zanim pojawi się sprzęt. Te same pliki `.cpp` linkuje
  firmware ESP32 — to nie kopia logiki.
- **Czego nie obejmuje:** radia BLE/SPP ani peryferiów I2C/ADC (warstwa fizyczna).
- Szczegóły i ręczne polecenie g++: [`sim/README.md`](sim/README.md).

## Struktura kodu

```
include/            src/
  config.h            ← piny, UUID-y, flagi funkcji (nadpisywalne z build_flags)
  uart_link.h         uart_link.cpp     ← Serial2: NMEA ↑, RTCM ↓
  ble_bridge.h        ble_bridge.cpp    ← NimBLE NUS (TX/RX/status) — build domyślny
  spp_bridge.h        spp_bridge.cpp    ← Bluetooth Classic SPP — build esp32dev-spp
  gnss_status.h       gnss_status.cpp   ← parser GGA (suma kontrolna) → status
  status_led.h        status_led.cpp    ← LED GPIO2 wg typu fixa
  display.h           display.cpp       ← OLED SSD1306 (U8g2), auto-wykrywanie
  battery.h           battery.cpp       ← ADC GPIO34 + krzywa Li-Ion → %
  gnss_config.h       gnss_config.cpp   ← M8: komendy PAIR/PQTM przy starcie (gated)
  telemetry.h         telemetry.cpp     ← format JSON statusu (wspoldzielony z sim/)
                      main.cpp          ← orkiestracja setup()/loop()

sim/  device_sim.cpp + Arduino.h (shim) + run-sim.bat  ← natywny test parsera na PC
```

LED statusu (GPIO2): brak fixa = krótki błysk co 2 s · GPS/DGPS = 1 Hz ·
RTK Float = ~4 Hz · **RTK Fixed = światło ciągłe**.

## Flagi funkcji (`platformio.ini` → `build_flags`)

Domyślne wartości w [include/config.h](include/config.h):

| Flaga | Domyślnie | Opis |
|---|---|---|
| `ENABLE_OLED` | 1 | wyświetlacz SSD1306 (brak OLED nie szkodzi — auto-wykrywanie) |
| `ENABLE_BATTERY` | 1 | pomiar baterii (GPIO34) |
| `ENABLE_STATUS_CHAR` | 1 | charakterystyka telemetrii „status" |
| `ENABLE_GNSS_CONFIG` | 0 | konfiguracja LC29HEA przy starcie (komendy pod EA — patrz „Uwagi") |
| `DEBUG_ECHO_NMEA` | 0 | echo NMEA na monitor USB |

`BAT_DIVIDER_RATIO` (domyślnie 2.0) — współczynnik dzielnika napięcia baterii; ustala
sesja elektroniki, skoryguj po pomiarze.

## Uwagi / do zrobienia

- **M7 (SPP)** zrobiony jako osobny build `esp32dev-spp` (patrz „Warianty buildu").
  Jednoczesny BLE+SPP świadomie pominięty — wymagałby porzucenia NimBLE na rzecz
  cięższego Bluedroid, bez korzyści dla celu (test z gotowymi aplikacjami).
- **M8 (LC29HEA)** komendy zweryfikowane: PAIR050/PAIR062 wg oficjalnej „LC29H&LC79H
  Series GNSS Protocol Specification" v1.1, PQTM* (tryb rover, zapis) wg rtklibexplorer
  (testy na realnym EA). Ustalenia istotne dla EA:
  - **GST nie istnieje na EA** (PAIR062 `<Type>` tylko 0..5) — pole `accuracy` w aplikacji
    NIE przyjdzie z GST; bierz ją z typu fixa + HDOP (lub z `$PQTMEPE`, jeśli dane firmware
    EA je wystawia — to niepewne między wersjami).
  - PAIR050 na EA: tylko 100 (10 Hz) lub 1000 (1 Hz), zmiana działa **po restarcie** modułu.
  - Zapis ustawień to `$PQTMSAVEPAR` (nie `PAIR513`) — w kodzie zakomentowany.
  Domyślnie wyłączone (most działa bez tego); włącz `-D ENABLE_GNSS_CONFIG=1` po teście na sprzęcie.
- **Baud LC29HEA = 460800** (domyślny dla gołego EA wg rtklibexplorer) — ustawiony w
  `config.h`. Jeśli NMEA nie pojawia się w monitorze, spróbuj 115200.
- Pinout zgodny z [../elektronika/INSTRUKCJA-AGENTA.md](../elektronika/INSTRUKCJA-AGENTA.md);
  oba układy 3.3 V → UART bez konwersji poziomów.
