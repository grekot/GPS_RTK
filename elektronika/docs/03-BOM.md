# BOM — lista zakupowa prototypu v1

> Deliverable §2. Ceny orientacyjne (research 2026-06-13) — **zweryfikuj w koszyku**; sklepy
> renderują ceny w przeglądarce / zależnie od regionu (część podana w EUR ≈ ×4,3 zł).
> Decyzje: [01-decyzje-sprzetowe.md](01-decyzje-sprzetowe.md). Połączenia: [02-schemat-polaczen.md](02-schemat-polaczen.md).

## 1. Moduł GNSS — wybierz JEDEN wariant

| Wariant | Produkt | RTK | Cena | Gdzie |
|---|---|---|---|---|
| **Podstawowy** ⭐ | **Breakout Quectel LC29HEA + antena** (wybór „Lc29Hea and Antenna") | 1–10 Hz | **~197 zł** (z anteną) | AliExpress — oferta wskazana przez użytkownika; podobne: [item 1](https://www.aliexpress.com/item/3256809276964723.html), [item 2](https://www.aliexpress.com/item/3256808809491636.html) |
| Premium | MikroE **GNSS RTK 3 Click (LC29HEA)** | 1–10 Hz | ~$50–70 (potwierdź) | [mikroe.com](https://www.mikroe.com/gnss-rtk-3-click-lc29hea), Kamami (dystrybutor PL) |
| Budżet / PL od ręki | Waveshare **LC29H(DA)** HAT, nr 25279 | **1 Hz** | ~€73 | [Botland](https://botland.store/raspberry-pi-hat-connection/23875-dual-band-gpsrtk-l1l5-module-with-lc29hda-gnss-chip-overlay-for-raspberry-pi-waveshare-25279.html), [Kamami](https://kamami.pl/en/gps-modules/1187927-lc29h-series-dual-band-gps-module-for-raspberry-pi-dual-band-l1-l5-positioning-technology-optional-5906623465965.html) |

> ⚠️ Na AliExpress jedna oferta sprzedaje warianty Aa/Da/Ea/Ba/Bs — **wybierz EA**. Potwierdź
> zakres VCC i logikę **3.3 V**. Bias anteny na gnieździe RF — zweryfikuj (warunek anteny aktywnej).

## 2. Antena L1/L5 (jeśli nie w zestawie z modułem)

| Pozycja | Produkt | Złącze | Cena | Gdzie |
|---|---|---|---|---|
| Antena aktywna L1/L5 | Waveshare 25346 (LNA 28 dB, bias 3–18 V, RG174 3 m) | SMA | ~€23 | [Botland](https://botland.store/gps-antennas/23872-active-dual-frequency-gpsgnss-l1l5-antenna-with-sma-connector-waveshare-25346.html) |
| (wariant Waveshare DA) adapter | IPEX → SMA | — | w zestawie z HAT | — |
| **Ground plane** | dysk Al/Cu Ø100–120 mm **lub** folia miedziana na tackę 3D | — | grosze / DIY | warsztat / [06-mechanika.md](06-mechanika.md) |

> Dla wariantu podstawowego antena jest w zestawie (na start OK). Do dokładności cm **dołóż
> ground plane**; lepszą antenę rozważ później ([rtklibexplorer: improved antenna](https://rtklibexplorer.wordpress.com/2024/08/01/quectel-lc29hea-with-improved-antenna/)).

## 3. MCU

| Pozycja | Produkt | Cena | Gdzie | Uwaga |
|---|---|---|---|---|
| MCU | **ESP32-WROOM-32 DevKitC** (USB, CP2102/CH340 na pokładzie) | ~30–45 zł | Botland / Kamami | BT Classic (SPP) + BLE; devkit = programowanie po USB od ręki |

> Wybierz devkit z **WROOM-32** (nie S3/C3 — te mają tylko BLE, bez SPP do testów z SW Maps).
> Sprawdź mostek (CP2102 vs CH340) → sterownik na Windows ([07-programowanie-debug.md](07-programowanie-debug.md)).

## 4. Wyświetlacz

| Pozycja | Produkt | Cena | Gdzie |
|---|---|---|---|
| OLED | **SSD1306 0,96" I2C** (adres 0x3C) | ~10–15 zł | Botland / Kamami |

## 5. Zasilanie

| Pozycja | Produkt | Cena | Gdzie |
|---|---|---|---|
| Ładowarka | **TP4056 USB-C z zabezpieczeniem (DW01A)**, 1 A | **2,69 zł** | [mikrobot.pl](https://mikrobot.pl/ladowarka-ogniw-li-ion-usb-c-1a-tp4056-usb-c) |
| Przetwornica (wariant 3.3 V — Click/AliExpress) | **Pololu S7V8F3** buck-boost 3.3 V / 1 A | ~€8,50 | [Botland](https://botland.store/converters-step-up-step-down/1427-step-up-step-down-voltage-regulator-s7v8f3-33v-1a-pololu-2122-5904422373092.html) |
| Przetwornica (alt. wyższy prąd / WiFi v2) | Pololu S13V25F3 3,3 V / 2,5 A | ~€13,90 | [Botland](https://botland.store/electronics/23466-step-upstep-down-voltage-regulator-s13v25f3-33v-25a-pololu-4980.html) |
| Przetwornica (wariant 5 V — Waveshare DA) | Pololu S7V8F5 5 V / 1 A (odpowiednik 5 V) | ~€8,50 | Botland (seria S7V8Fx) |
| Ogniwo | **Samsung INR18650-35E** 3500 mAh, 8 A | ~€6,90 | [Botland](https://botland.store/li-ion-batteries/15216-18650-li-ion-samsung-inr18650-35e-3400mah-5904422343071.html) |
| Koszyk | Koszyk 1× 18650 z przewodami | ~€0,90 | [Botland](https://botland.store/battery-holders/5242-cell-holder-for-1x-18650-5904422333393.html) |

> **Dobór przetwornicy zależy od modułu:** Click/AliExpress (3.3 V) → buck-boost **3.3 V**.
> Waveshare HAT (5 V) → buck-boost **5 V** (ESP32 z Vin/5V). Patrz [02-schemat-polaczen.md](02-schemat-polaczen.md) §3.
> S7V8F3 (1 A) wystarcza dla BLE; jeśli v2 z WiFi/NTRIP (szczyt ~240 mA) → S13V25F3.

## 6. Drobnica (stykówka v1)

| Pozycja | Wartość / typ | Ilość | Po co |
|---|---|---|---|
| Rezystory | 100 kΩ | 2 | dzielnik pomiaru baterii |
| Rezystory | 4,7 kΩ | 2 | pull-up I2C (jeśli OLED nie ma) |
| Rezystor | ~330 Ω | 1 | szeregowy LED |
| Kondensator | 100–470 µF elektrolit | 1 | bulk na szynie 3.3V (anty-brownout BLE) |
| Kondensatory | 100 nF ceramiczne | 3–4 | odsprzęganie + filtr ADC |
| LED | dowolny 3 mm | 1 | status |
| Przycisk tact | — | 1 | użytkownika (opcja v1) |
| Przełącznik SPDT lub dioda Schottky | — | 1 | wybór źródła USB↔bateria (devkit) |
| Płytka stykowa + zwory | — | 1 kpl | montaż v1 |

**Tylko dla gołego modułu bez bias-tee** (nie dotyczy breakout/Click/Waveshare): dławik 68 nH,
rezystor 10 Ω, kondensator 100 pF — bias-tee anteny.

## 7. Pozycje v2 (NIE kupować teraz)

| Pozycja | Produkt | Uwaga |
|---|---|---|
| IMU | **BNO085** (np. Adafruit/SparkFun, ~80–120 zł) | heading „od urządzenia" + kompensacja pochylenia; na I2C 0x4A |
| PCB | własna płytka (KiCad) | po przetestowaniu toru na devkitach |
| Mostek USB-UART | CP2102 na USB-C | gdy USB-C ma też programować (bez devkita) |

## 8. Szacunkowy koszt prototypu v1 (wariant podstawowy)

| Grupa | Kwota |
|---|---|
| Moduł GNSS LC29HEA + antena (AliExpress) | ~197 zł |
| ESP32-WROOM DevKitC | ~40 zł |
| OLED SSD1306 | ~12 zł |
| TP4056 USB-C + buck-boost 3.3V (Pololu) | ~3 zł + ~37 zł |
| 18650 35E + koszyk | ~30 zł + ~4 zł |
| Drobnica (R/C/LED/przewody/stykówka) | ~30–40 zł |
| **Razem** | **~350–360 zł** |

> Ground plane i obudowa 3D — materiał własny/druk (poza kwotą). Wariant Waveshare DA zamiast
> AliExpress: moduł ~€73 + antena ~€23 ≈ +100 zł względem powyższego, ale RTK 1 Hz.
