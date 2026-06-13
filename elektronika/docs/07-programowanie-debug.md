# Plan programowania i debugowania ESP32

> Deliverable §6. System: **Windows**. Pinout: [05-pinout-firmware.md](05-pinout-firmware.md).
> **Firmware już istnieje** w [`../firmware/`](../firmware/) (etapy M2–M7, build zielony, niesprawdzony
> na sprzęcie) — ten dokument to companion do **bring-upu sprzętu**, nie pisania firmware od zera.

## 1. Mostek USB-UART i wgrywanie

ESP32-WROOM-32 **nie ma natywnego USB** → potrzebny mostek **USB-UART (CP2102 lub CH340)**.
**Devkit (DevKitC) ma go na pokładzie** wraz z układem auto-reset → w v1 programujemy **po USB devkita**.

### Układ auto-reset (dlaczego „po prostu działa" na devkicie)

- `esptool` steruje liniami **DTR/RTS** mostka (aktywne LOW), które przez **dwa tranzystory NPN**
  przełączają **EN (CHIP_PU)** i **GPIO0**. Sekwencja: GPIO0=LOW → impuls reset EN → wejście w
  **Firmware Download Mode**.
- Krzyżowy układ 2 tranzystorów gwarantuje, że gdy DTR i RTS są oba aktywne (np. otwarty monitor),
  układ **nie** jest resetowany.
- **Kondensator 1 µF na EN→GND** jest niezbędny dla niezawodności (tanie klony go pomijają →
  problemy na Windows).

Źródła: [Espressif boot-mode](https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/boot-mode-selection.html),
[schemat 2 tranzystorów](https://hydraraptor.blogspot.com/2021/08/esp32-auto-program-fix.html).

### Goły WROOM (bez devkita) — gdyby trzeba ręcznie

Stany do trybu download: **GPIO0 = LOW** podczas resetu, **EN** pull-up 10 kΩ + przycisk do GND,
kond. 1 µF na EN. Sekwencja: trzymaj **BOOT (GPIO0→GND)** → puknij **EN/RESET** → puść BOOT →
flash → reset bez BOOT = normalny start. Połączenia: TX↔RX krzyżowo, wspólna masa, mocne 3.3 V.
([strapping pins](https://www.espboards.dev/blog/esp32-strapping-pins/)).

## 2. Toolchain (rekomendacja: PlatformIO + VS Code)

| Opcja | Werdykt |
|---|---|
| **PlatformIO + VS Code** ⭐ | najlepszy dla mostka UART↔BLE: jeden `platformio.ini`, dobre zarządzanie bibliotekami, framework Arduino **lub** ESP-IDF. Dla BLE użyj **NimBLE-Arduino** (dużo mniej RAM/flash niż Bluedroid — istotne na WROOM). |
| Arduino IDE | najniższy próg, masa przykładów (`BluetoothSerial` SPP, `BLE`); słabsze zarządzanie projektem. Dobre na pierwsze próby. |
| ESP-IDF | pełna kontrola, najbardziej stromo; wybierz przy customowym stosie BLE. |

**Sterowniki Windows 11** (różne dla różnych mostków — sprawdź, co masz na płytce):
- **CP2102 (Silicon Labs):** CP210x Universal Windows Driver (VCP) → instalacja z `.inf`.
- **CH340 (WCH):** CH341SER z **oficjalnej** strony WCH (uwaga na podróbki) → Uninstall starych, Install.
- Po instalacji port = **COMx** w Menedżerze urządzeń.

[PlatformIO+ESP32](https://randomnerdtutorials.com/vs-code-platformio-ide-esp32-esp8266-arduino/),
[NimBLE](https://registry.platformio.org/libraries/h2zero/NimBLE-Arduino).

### Przykładowy `platformio.ini`

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
upload_speed = 921600
; lib_deps = h2zero/NimBLE-Arduino   ; gdy ruszymy firmware BLE
```

## 3. Flashowanie i monitor (Windows)

1. Zainstaluj sterownik mostka (§2), podłącz USB, sprawdź **COMx** w Menedżerze urządzeń.
2. VS Code + rozszerzenie **PlatformIO IDE**, ustaw `platformio.ini`.
3. **Build** (✓) → **Upload** (→). PlatformIO woła esptool; auto-reset wprowadza w bootloader.
4. **Monitor:** `pio device monitor -b 115200 -p COMx` (lub ikona). Tu lecą logi `Serial.println`.
5. Typowe problemy: „Failed to connect / wrong boot mode" → zawodny auto-reset (kond. 1 µF na EN)
   albo zajęty port (zamknij monitor przed uploadem). Jeśli 921600 zrywa → zejdź na 115200.

> **Uwaga konflikt UART:** logi debugowe idą po **UART0 (USB)**, a GNSS jest na **UART2 (GPIO16/17)** —
> dzięki temu można debugować bez kolizji ze strumieniem NMEA/RTCM. Patrz [05-pinout-firmware.md](05-pinout-firmware.md).

## 4. Najpierw test toru po Bluetooth SPP (PRZED firmware BLE)

Najlepszy sposób walidacji **sprzętu, anteny, UART i toru NTRIP** zanim powstanie firmware BLE.
ESP32 classic ma profil **SPP** → biblioteka Arduino **`BluetoothSerial`** robi trywialny most
UART↔SPP (kilkanaście linii).

**Sekwencja:**
1. Wgraj **gotowy build SPP** z `../firmware/`: `pio run -e esp32dev-spp -t upload`
   (most UART↔SPP już napisany — nie trzeba pisać szkicu).
2. Sparuj telefon (Android) z urządzeniem (nazwa `RTK-Rover`).
3. **SW Maps** (Android, darmowa): dodaj instrument Bluetooth → urządzenie → zobacz NMEA/satelity.
4. Skonfiguruj **NTRIP** (Twój caster, np. **ASG-EUPOS**) → korekty RTCM lecą do GNSS →
   obserwuj **Single → Float → RTK Fix**.
5. Po potwierdzeniu toru przełącz na build **BLE**: `pio run -e esp32dev -t upload` (NimBLE NUS)
   → integracja z aplikacją (`BleReceiverSource`).

Alternatywa do testu: **Lefebure NTRIP Client** (Android) + Mock Location (podmiana GPS systemowego).

> **iOS nie obsługuje SPP** — tam konieczne BLE. SPP to ścieżka testowa na Androidzie; docelowa
> aplikacja (`../app/`) i tak używa **BLE NUS** (patrz [05-pinout-firmware.md](05-pinout-firmware.md)).

Źródła: [SW Maps + NTRIP](https://docs.rtkdata.com/integration-hub/ntrip-clients-and-field-software/sw-maps),
[SparkFun RTK: SPP/NTRIP](https://learn.sparkfun.com/tutorials/sparkfun-rtk-surveyor-hookup-guide/bluetooth-and-ntrip),
[przykład ESP32 GPS+SPP+NTRIP](https://github.com/mrichar1/esp32-gps/).

## 5. Firmware — JUŻ ZAIMPLEMENTOWANE (sesja firmware)

> Most BLE jest napisany w [`../firmware/`](../firmware/) — **M2–M7 gotowe** (build zielony,
> niesprawdzony na sprzęcie). Pełny opis i protokół: [`../firmware/README.md`](../firmware/README.md).

| Moduł (`firmware/src/`) | Zadanie | Status |
|---|---|---|
| `uart_link` | Serial2: NMEA↑ / RTCM↓ | ✅ |
| `ble_bridge` | NUS NimBLE (TX/RX + status `6E400004`), MTU 247 | ✅ |
| `spp_bridge` | Bluetooth Classic SPP — **osobny build** `esp32dev-spp` | ✅ |
| `gnss_status` | parser GGA (suma kontrolna) → status/LED | ✅ |
| `display` | OLED SSD1306 (U8g2, auto-wykrywanie) | ✅ |
| `battery` | ADC GPIO34 + krzywa Li-Ion → % (`BAT_DIVIDER_RATIO`=2.0) | ✅ |
| `gnss_config` | `$PAIR062`/`$PAIR050` + PQTM (rover, zapis `$PQTMSAVEPAR`) — pod EA | ⚙️ off domyślnie |

> **SPP i BLE to dwa osobne buildy** (SPP=Bluedroid, BLE=NimBLE — wykluczają się): do testu toru
> `esp32dev-spp`, docelowo `esp32dev`. Flashujesz jeden naraz.

## 6. Kolejność bring-up (proponowana)

1. „Blink" na LED (GPIO2) — potwierdzenie toolchainu i flashowania.
2. Skan I2C → wykrycie OLED (0x3C), „hello" na ekranie.
3. UART2 ↔ GNSS: surowe NMEA na monitor (potwierdzenie modułu i biasu anteny — czy łapie satelity).
4. Build SPP (`esp32dev-spp`) + SW Maps → NMEA na telefonie.
5. NTRIP (ASG-EUPOS) przez SW Maps → **RTK Fix**.
6. Pomiar baterii (ADC + dzielnik), kalibracja.
7. Firmware BLE NUS (NimBLE) + charakterystyka status → integracja z aplikacją (`BleReceiverSource`).
