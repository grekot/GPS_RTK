# Schemat połączeń — prototyp v1 (devkit / płytka stykowa)

> Deliverable §1. v1 składamy z gotowych modułów — to **schemat połączeń + tabele pin-do-pinu**,
> nie layout PCB (PCB → v2). Pinout ESP32: [05-pinout-firmware.md](05-pinout-firmware.md).
> Wybór komponentów i linki: [03-BOM.md](03-BOM.md). Decyzje: [01-decyzje-sprzetowe.md](01-decyzje-sprzetowe.md).
>
> **KiCad** niezainstalowany w środowisku. Dla v1 (devkity) tabele połączeń są wystarczające i
> wygodniejsze przy montażu na stykówce. Formalny schemat KiCad proponuję wykonać dopiero dla v2
> (PCB) — instalacja: `winget install KiCad.KiCad`.

## 1. Diagram blokowy

```
                          ANTENA L1/L5 (aktywna)
                                  │ RF + bias DC 3.3V
                                  │ (SMA / u.FL)
                          ┌───────┴────────┐
   satelity )))           │  MODUŁ GNSS    │
                          │   LC29HEA      │
                          │  (EA, rover)   │
                          └───┬────────┬───┘
                       TX ────┘        └──── RX        UART 3.3V, 115200→460800
                        │                │            NMEA ↑ (GGA/RMC/GST)
                        │                │            RTCM ↓ (poprawki)
                   GPIO16(RX2)      GPIO17(TX2)
                          ┌───────────────────┐
                          │   ESP32-WROOM-32   │
                          │   (BT Classic+BLE) │
   OLED SSD1306 ──I2C─────┤ GPIO21 SDA          │
   (+ pady IMU v2)        │ GPIO22 SCL          │── BLE NUS ))) SMARTFON
                          │ GPIO34 ADC (bateria)│       NMEA↑ / RTCM↓ / status
   LED ──────────────────┤ GPIO2               │            │ internet
   przycisk (opc.) ───────┤ GPIO27              │       Caster NTRIP (ASG-EUPOS)
                          └─────────┬───────────┘
                                    │ 3.3V / GND
   ┌────────────────────────────────┴───────────────────────────────┐
   │  TOR ZASILANIA                                                   │
   │  18650 ──► TP4056 (ład. USB-C + ochrona DW01A) ──► buck-boost ──►│ 3.3V rail
   │   3.0–4.2V        ▲                                  3.3V         │
   │                   └─ USB-C (tylko ładowanie)                      │
   └──────────────────────────────────────────────────────────────────┘
```

> ESP32 = „głupi most" UART↔BLE (bufory ringowe, bez parsowania w gorącej ścieżce). GGA parsuje
> tylko na potrzeby OLED i charakterystyki status. Cała logika NTRIP/mapa/tyczenie — w telefonie.

## 2. Tor zasilania

```
 18650 (+) ──► TP4056 B+        TP4056 OUT+ ──► Vin buck-boost ──► Vout 3.3V ──┬─► ESP32 3V3
 18650 (−) ──► TP4056 B−        TP4056 OUT− ──► GND buck-boost ──► GND ────────┼─► GNSS 3V3
                                                                               ├─► OLED VCC
   USB-C ──► TP4056 (IN)                                                       └─► dzielnik baterii
```

| Węzeł | Połączenie | Uwaga |
|---|---|---|
| Ogniwo → ładowarka | 18650 +/− → TP4056 **B+ / B−** | TP4056 **z DW01A** (ochrona pod/prze-ładowania, zwarcie). |
| Ładowanie | USB-C → TP4056 wejście | USB-C **tylko ładowanie** (programowanie przez USB devkita). |
| Ładowarka → przetwornica | TP4056 **OUT+ / OUT−** → Vin/GND buck-boost | OUT idzie za zabezpieczeniem DW01A. |
| Przetwornica → szyna | buck-boost **Vout = 3.3 V** → szyna 3.3V | Vin 3.0–4.2 V z ogniwa, Vout stałe 3.3 V (buck-boost!). |
| Szyna 3.3V | → ESP32 **3V3**, GNSS **3V3/VCC**, OLED **VCC** | wspólna masa wszystkich modułów. |

**Bulk kondensator na szynie 3.3V:** dodaj **100–470 µF** (elektrolit/tantal) + 100 nF blisko ESP32.
Szczyty prądu radia BLE (~130 mA przez 1–5 ms) potrafią wywołać brownout/reset na stykówce bez bufora.

> ⚠️ **Wybór źródła przy programowaniu (devkit):** zasilanie ESP32 jednocześnie z szyny 3.3V (pin 3V3)
> **i** z USB grozi back-feedem. Rozwiązania: (a) **przełącznik SPDT** „USB ↔ bateria" na zasilaniu
> ESP32, albo (b) dioda Schottky z buck-boost do węzła 3V3, albo (c) po prostu odłącz szynę baterii
> na czas flashowania po USB. Na stykówce v1 wystarczy zwora/przełącznik.

## 3. Połączenia: ESP32 ↔ moduł GNSS (UART, 3.3V)

Logika obu układów to **3.3 V** → łączymy wprost (krzyżowo TX↔RX). **Nie podawać 5 V na piny UART.**

| ESP32 | ↔ | Moduł GNSS | Sygnał |
|---|---|---|---|
| GPIO17 (TX2) | → | **RX / RXD** | ESP32 → GNSS: **RTCM** (poprawki) |
| GPIO16 (RX2) | ← | **TX / TXD** | GNSS → ESP32: **NMEA** |
| 3V3 | — | **VCC / 3V3** | zasilanie modułu (patrz uwaga o wariantach) |
| GND | — | **GND** | wspólna masa (konieczna!) |
| GPIO35 (opc.) | ← | **PPS** | 1PPS — synchronizacja czasu (opcjonalnie) |
| GPIO4 (opc.) | → | **RESET** | reset modułu (opcjonalnie) |

### Warianty modułu — różnice w okablowaniu

- **Breakout LC29HEA (AliExpress, podstawowy):** zasilanie z szyny **3.3 V** (potwierdź zakres VCC
  płytki). UART na pinach TXD/RXD. Antena na gnieździe SMA/u.FL z biasem (zweryfikuj — pkt 6).
- **MikroE GNSS RTK 3 Click (premium):** to płytka **mikroBUS**. Wystarczą 4 piny: **3V3, GND, TX, RX**
  (UART na prawym rzędzie mikroBUS). Bez gniazda mikroBUS — połącz zworami do ESP32. SMA z biasem.
- **Waveshare LC29H(DA) HAT (budżet/PL):** płytka **wymaga zasilania 5 V** (ma własny LDO→3.3V).
  → ustaw buck-boost na **5 V**, zasil HAT z 5 V, a ESP32 z **Vin/5V** (jego LDO robi 3.3V),
  OLED z **3V3 ESP32**. UART HAT-u (TXD/RXD, logika 3.3V) → GPIO16/17. Antena: IPEX → adapter SMA
  (w zestawie). **To jedyne miejsce, gdzie wybór modułu zmienia tor zasilania.**

## 4. Połączenia: ESP32 ↔ OLED SSD1306 (I2C) + rezerwa IMU

| ESP32 | ↔ | OLED | Uwaga |
|---|---|---|---|
| GPIO21 | ↔ | **SDA** | wspólna magistrala I2C |
| GPIO22 | → | **SCL** | |
| 3V3 | — | **VCC** | OLED 3.3V |
| GND | — | **GND** | |

- Pull-up I2C **4,7 kΩ** do 3.3V na SDA i SCL (jeśli moduł OLED nie ma własnych — zwykle ma).
- **Rezerwa IMU (v2):** wyprowadź SDA/SCL/3V3/GND na dodatkowe pady/listwę pod **BNO085** (adres 0x4A).
  Opcjonalnie zostaw 2 wolne GPIO (np. GPIO25/26) pod INT/RST IMU.

## 5. Pomiar napięcia baterii

```
  szyna baterii (OUT+ TP4056, 3.0–4.2V) ──[ R1 100k ]──┬──[ R2 100k ]── GND
                                                       │
                                                  GPIO34 (ADC1)  + 100nF do GND
```

| Element | Wartość | Uwaga |
|---|---|---|
| R1 (góra) | 100 kΩ | dzielnik ÷2: 4,2 V → 2,1 V |
| R2 (dół) | 100 kΩ | |
| C | 100 nF GPIO34→GND | bufor S&H ADC |

- Mierz **napięcie ogniwa** (przed buck-boost), nie szynę 3.3V. Wejście na **GPIO34** (ADC1, tylko-wejście).
- W firmware: `ADC_ATTEN_DB_11`, kalibracja `esp_adc_cal`/eFuse Vref, uśrednianie. Patrz [05-pinout-firmware.md](05-pinout-firmware.md).

## 6. Antena + bias (sekcja RF)

- **Antena aktywna L1/L5** wymaga **biasu DC** na linii RF (zasila wbudowany LNA).
- **Płytki gotowe (breakout AliExpress / Click / Waveshare):** bias-tee jest zwykle **na płytce**
  (z VDD_RF = 3.3 V). **Zweryfikuj** (opis/schemat/multimetr na środku gniazda) — to warunek
  działania anteny aktywnej.
- **Goły moduł bez bias-tee** — zbuduj wg noty Quectel (Figure 17):

```
  VDD_RF (3.3V) ──[ L ≥ 68nH ]──┬───────────[ C 100pF ]─── do gniazda anteny (RF)
                                │
                          [ R 10Ω ]   (ochrona przy zwarciu anteny do masy)
                                │
                            RF_IN modułu
```

- **Ground plane:** dla anteny patch metalowy **dysk/folia Ø100–120 mm** pod anteną (reguła ~0,5 λ;
  L1 λ≈19 cm). Antena helikalna QFH ground plane nie wymaga. Szczegóły: [06-mechanika.md](06-mechanika.md).

## 7. Zasady montażu (stykówka v1)

- **Wspólna masa** wszystkich modułów — bez tego UART/I2C nie działają.
- Krótkie połączenia UART; przy 460800 trzymaj przewody krótkie.
- **Bulk kondensator** na 3.3V (pkt 2) — przeciw resetom od BLE.
- Antena: pełne pole widzenia nieba; na stykówce do pierwszych testów wystarczy parapet/dach.
- Najpierw uruchom tor po **Bluetooth SPP + SW Maps** (bez własnego firmware BLE) — patrz
  [07-programowanie-debug.md](07-programowanie-debug.md).
