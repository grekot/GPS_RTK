# Podłączenie na płytce stykowej — v1 (zasilanie z powerbanku)

Szybki bring-up na stykówce: **ESP32 DevKit V1 (30-pin)** + moduł **GPS LC29HEA** + **OLED SSD1306**,
zasilanie z **powerbanku przez USB devkitu** (decyzja D6 w [01-decyzje-sprzetowe.md](01-decyzje-sprzetowe.md)).

**Rysunek:** [podlaczenie-stykowka-v1.svg](podlaczenie-stykowka-v1.svg) (kolorowy schemat połączeń).
Pinout/protokół: [05-pinout-firmware.md](05-pinout-firmware.md). Bring-up krok po kroku: [07-programowanie-debug.md](07-programowanie-debug.md).

## Tabela połączeń

Szyny zasilania jak na stykówce: **+3V3** (z pinu 3V3 devkitu) i **GND**.

| Od | Do | Przewód / sygnał |
|---|---|---|
| Powerbank (USB-A) | **USB devkitu ESP32** | 5 V — zasilanie (pomarańczowy) |
| ESP32 **3V3** | szyna **+3V3** | 3.3 V (z AMS1117 devkitu) — czerwony |
| ESP32 **GND** | szyna **GND** | masa — czarny |
| GPS **VCC** | szyna **+3V3** | 3.3 V — czerwony |
| GPS **GND** | szyna **GND** | masa — czarny |
| GPS **TX** | ESP32 **IO16 (RX2)** | NMEA ↑ — niebieski |
| GPS **RX** | ESP32 **IO17 (TX2)** | RTCM ↓ — niebieski |
| OLED **VCC** | szyna **+3V3** | 3.3 V — czerwony |
| OLED **GND** | szyna **GND** | masa — czarny |
| OLED **SDA** | ESP32 **IO21** | I2C — zielony |
| OLED **SCL** | ESP32 **IO22** | I2C — zielony |
| GPS **PPS** *(opc.)* | ESP32 **IO35** | 1PPS — przerywany |
| GPS **RST** *(opc.)* | ESP32 **IO4** | reset modułu — przerywany |
| ESP32 **IO2** *(opc.)* | 330 Ω → LED → **GND** | LED statusu |
| ESP32 **IO27** *(opc.)* | przycisk → **GND** | przycisk (pull-up wewn.) |

> **Minimum do RTK:** ESP32 + GPS (VCC, GND, TX→IO16, RX←IO17) + powerbank. OLED/LED/przycisk dołóż później.

## Schemat (ASCII)

```
   powerbank ──USB 5V──> [ESP32 DevKit V1 30-pin]
                              │ 3V3        │ GND
            ┌─────────────────┴──── +3V3 rail ───────────────┐
            │                                                 │
        GPS VCC                                           OLED VCC
   [GPS LC29HEA]                                       [OLED SSD1306]
     TX ──────────────> IO16 (RX2)   IO21 <───────────── SDA
     RX <────────────── IO17 (TX2)   IO22 <───────────── SCL
     GND ──┐                                              GND ──┐
           └──────────────── GND rail ──────────────────────────┘
     ANT → antena L1/L5 + ground plane
```

## Uwagi (ważne)

- **Napięcie** — GPS i OLED zasilaj z pinu **3V3** devkitu. Zamówiona płytka GPS jest wg instrukcji
  **3.3 V/5 V kompatybilna**, ale z ESP32 (3.3 V) łączymy na **3.3 V**; OLED zawsze 3.3 V.
- **Przełączniki na płytce GPS** — 2 suwaki: **oba w LEWO = UART (goldpiny)** → praca z ESP32;
  **oba w PRAWO = USB-C (Type-C)** → bezpośrednio do PC/telefonu. Do stykówki z ESP32 ustaw **UART**.
- **Wspólna masa** — wszystkie GND razem (devkit, GPS, OLED). Bez tego UART/I2C nie działają.
- **Powerbank: auto-wyłączanie** — wiele powerbanków gaśnie przy małym poborze; nasz ~150–250 mA zwykle
  go utrzyma, ale jak gaśnie, użyj powerbanku bez auto-off.
- **LED** — na większości devkitów jest **wbudowana LED na IO2 (D2)**, więc zewnętrzna jest opcjonalna.
- **Pull-upy I2C** — gotowe moduły OLED zwykle mają je na pokładzie; dodaj 4,7 kΩ (SDA/SCL→3V3) tylko gdy brak.
- **UART baud** — **115200** (domyślny dla zamówionej płytki, wg instrukcji); ustaw 115200 w monitorze/aplikacji i `GNSS_BAUD` firmware (goły moduł EA bywa 460800 — tu 115200).
- **Antena** — **w zestawie z płytką** (aktywna, SMA); do RTK użyj L1/L5; dołóż **ground plane Ø10–12 cm**; odkryte niebo.
- **Pinout 30-pin** — sprawdź oznaczenia ze srebrnym nadrukiem swojej płytki (tabela w [../kicad/README.md](../kicad/README.md));
  klony DevKit V1 bywają różne.

## Wariant: szybki test po USB (bez ESP32)

Płytka GPS ma USB-C — ustaw oba przełączniki w **PRAWO (Type-C)** i podłącz:
- **PC:** **QGNSS** (lub u-center), port COM, baud **115200** → NMEA; klient NTRIP w QGNSS → RTK Fixed.
- **Android:** OTG + **SW Maps / Lefebure**, USB-serial, 115200 → NMEA; NTRIP (ASG-EUPOS) → RTK.
- **iOS:** brak (USB-serial niewspierane) — tam tylko BLE przez ESP32.

Pozwala zwalidować moduł, antenę i konto NTRIP **zanim** podłączysz ESP32. Do pracy z ESP32
przełącz suwaki w **LEWO (UART)**.

## Kolejność uruchamiania

Zgodnie z [07-programowanie-debug.md](07-programowanie-debug.md):
1. „Blink" LED (IO2) — toolchain + flashowanie OK.
2. Skan I2C → OLED widoczny (0x3C), „hello" na ekranie.
3. UART2 ↔ GPS: surowe NMEA na monitorze (potwierdza moduł + antenę).
4. Build **SPP** (`esp32dev-spp` z `../../firmware/`) + **SW Maps** → NMEA na telefonie.
5. **NTRIP** (ASG-EUPOS) → korekty RTCM → **Single → Float → RTK Fix**.
6. Dopiero potem firmware **BLE** (NimBLE) → integracja z aplikacją.
