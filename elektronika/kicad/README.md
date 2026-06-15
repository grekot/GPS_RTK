# KiCad — schemat odbiornika GPS RTK (v1)

`gps_rtk_v1.kicad_sch` to **pełny schemat** z prawdziwymi symbolami KiCad i połączeniami
(po nazwach netów). Wygenerowany skryptem [gen/gen_schematic.py](gen/gen_schematic.py) z bibliotek
symboli KiCad 9, **zweryfikowany netlistą** i wyrenderowany do
[gps_rtk_v1.pdf](gps_rtk_v1.pdf) / [gps_rtk_v1.svg](gps_rtk_v1.svg).

## Zawartość schematu

Symbole: **U1** ESP32-WROOM-32; złącza modułów: **J1** GNSS LC29HEA, **J2** OLED SSD1306,
**J3** IMU BNO085 (v2, DNP), **J4** buck-boost 3V3, **J5** TP4056 USB-C; **BT1** ogniwo 18650;
dzielnik baterii **R1/R2** (100k); pull-upy I2C **R3/R4** (4k7); **R5**+**D1** LED statusu;
**SW1** przycisk; **C1/C2** bulk/odsprzęganie.

Nety (zweryfikowane netlistą): `+3V3, GND, VBAT, VBAT_SENSE, BATT_CELL, VBUS, GNSS_TX, GNSS_RX,
GNSS_PPS, GNSS_RST, SDA, SCL, LED_STAT, LED_A, BTN`. Zgodne z [../docs/05-pinout-firmware.md](../docs/05-pinout-firmware.md)
i [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md).

> **Styl:** połączenia przez **etykiety netów po nazwie** (a nie rysowane przewody między częściami) —
> typowe i czytelne przy gęstych wyprowadzeniach MCU. Moduły jako złącza — w v1 to i tak gotowe
> płytki łączone przewodami. 24 nieużywane GPIO ESP32 zostają wolne (zapas).

## PCB — carrier `gps_rtk_v1.kicad_pcb`

**Płytka-baza (carrier) 100 × 78 mm**: wszystkie elementy aktywne to **gotowe moduły wpinane
w gniazda żeńskie** (łącznie z ESP32 jako devkit). Wygenerowana [gen/gen_pcb.py](gen/gen_pcb.py)
(pcbnew — Python KiCada). Podgląd: **[render 3D PNG](gps_rtk_v1_pcb.png)**, [2D SVG](gps_rtk_v1_pcb.svg).

Gniazda **PinSocket 2.54 mm**: **U1L+U1R** = ESP32 **DOIT DevKit V1 (30-pin)**, 2× **1×15**;
**J1** GNSS LC29HEA (1×06), **J2** OLED (1×04), **J3** IMU v2 (1×04), **J4** buck-boost (1×04),
**J5** TP4056 (1×06), **BT1** ogniwo (1×02). Na carrierze (SMD/THT): dzielnik **R1/R2**,
pull-upy I2C **R3/R4**, **R5+D1** LED, **C1/C2** bulk/odsprzęg., **SW1** przycisk.

**ESP32 jako devkit:** 3.3 V wchodzi na pin **3V3**; **EN i VIN(5V) wolne** — devkit ma własny
auto-reset i LDO (podpięcie EN do 3V3 zablokowałoby programowanie!). (Schemat pokazuje ESP32 jako
symbol WROOM — logicznie równoważny; na płytce to gniazdo devkitu.)

> **Zasilanie v1 = powerbank przez USB devkitu** (decyzja użytkownika). W tym trybie **nie montuj**
> modułów zasilania: buck-boost (J4), TP4056 (J5), ogniwo (BT1) ani dzielnika baterii (R1/R2) — szynę
> **+3V3** napędza wtedy AMS1117 devkitu. Sekcja bateryjna zostaje na płytce jako **opcja terenowa/v2**.

### Pinout ESP32 użyty na płytce — ZWERYFIKUJ z nadrukiem swojej płytki!

Kolejność fizyczna góra→dół (DOIT DevKit V1 30-pin). **Pogrubione = podłączone (mają net):**

| U1L (lewa) | net | · | U1R (prawa) | net |
|---|---|---|---|---|
| 1 EN | — | · | 1 3V3 | **+3V3** |
| 2 IO36 | — | · | 2 GND | **GND** |
| 3 IO39 | — | · | 3 IO15 | — |
| **4 IO34** | **VBAT_SENSE** | · | **4 IO2** | **LED_STAT** |
| **5 IO35** | **GNSS_PPS** | · | **5 IO4** | **GNSS_RST** |
| 6 IO32 | — | · | **6 IO16** | **GNSS_TX** |
| 7 IO33 | — | · | **7 IO17** | **GNSS_RX** |
| 8 IO25 | — | · | 8 IO5 | — |
| 9 IO26 | — | · | 9 IO18 | — |
| **10 IO27** | **BTN** | · | 10 IO19 | — |
| 11 IO14 | — | · | **11 IO21** | **SDA** |
| 12 IO12 | — | · | 12 IO3 | — |
| 13 IO13 | — | · | 13 IO1 | — |
| **14 GND** | **GND** | · | **14 IO22** | **SCL** |
| 15 VIN | — | · | 15 IO23 | — |

**Stan: rozmieszczona + onetowana, NIETRASOWANA** (ratsnest). DRC: **0 naruszeń**, 0 błędów
footprintów; **43 pady do połączenia = trasowanie**.

> ⚠️ **Zweryfikuj pod swój egzemplarz:** (1) **rozstaw rzędów** gniazd ESP32 — przyjąłem **22,86 mm**
> (stała `ESP_ROW_MM` w [gen/gen_pcb.py](gen/gen_pcb.py)); zmierz środek-do-środka rzędów i popraw.
> (2) **Pinout** wg tabeli wyżej — klony 30-pin bywają różne; jeśli się różni, popraw listy
> `ESP_L`/`ESP_R`. Rozmieszczenie zgrubne — dociągnij w GUI pod krótkie trasy.

## Weryfikacja (bez ERC — patrz niżej)

- ✅ **Netlista** (`kicad-cli sch export netlist`) — przeszła; każdy net ma dokładnie właściwe węzły
  (sprawdzone programowo: brak zlanych/rozjechanych netów).
- ✅ **Render** PDF/SVG (`kicad-cli sch export`) — bez błędów (10935 elementów rysunku).
- ⚠️ `kicad-cli sch erc` **crashuje** na tym pliku (quirk zgodności wyjścia generatora `kiutils`
  z silnikiem ERC w kicad-cli 9.0.9). Dlatego poprawność połączeń potwierdziłem **netlistą**, nie ERC.
  Po otwarciu i zapisaniu pliku w **GUI KiCada** (które normalizuje format) ERC powinien działać.

## Dalej (trasowanie + produkcja)

- **Trasowanie ścieżek** — jedyny brakujący krok: w GUI pcbnew, albo autorouterem **freerouting**
  (eksport `.dsn` → route → import `.ses`). Warto **wylać masę (GND pour)** — skróci ratsnest.
- Po trasowaniu: DRC w GUI, **gerbery** (`kicad-cli pcb export gerbers`), plik wierceń, BOM/CPL.
- Sekcja RF/bias anteny dla gołego modułu — patrz [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md).

## Regeneracja / eksport

```powershell
$cli = "C:\TMP\kicad_portable\bin\kicad-cli.exe"   # lub kicad-cli z instalacji
py -3 gen\gen_schematic.py                          # wymaga: pip install kiutils
& $cli sch export pdf     --output gps_rtk_v1.pdf gps_rtk_v1.kicad_sch
& $cli sch export svg     --output .               gps_rtk_v1.kicad_sch
& $cli sch export netlist --output gps_rtk_v1.net  gps_rtk_v1.kicad_sch
# PCB (pcbnew — Python KiCada):
& "C:\TMP\kicad_portable\bin\python.exe" gen\gen_pcb.py
& $cli pcb drc    --output pcb.drc.rpt        gps_rtk_v1.kicad_pcb
& $cli pcb render --output gps_rtk_v1_pcb.png gps_rtk_v1.kicad_pcb
```

## Portable KiCad (rozpakowany w tej sesji)

Instalator rozpakowano 7-Zipem **bez instalacji i bez praw admina** do `C:\TMP\kicad_portable\`.
Działa GUI (`bin\kicad.exe`) i CLI (`bin\kicad-cli.exe`). Otwórz schemat:
`& "C:\TMP\kicad_portable\bin\kicad.exe" "...\elektronika\kicad\gps_rtk_v1.kicad_pro"`.
Folder można usunąć (~kilka GB) albo zachować jako przenośny KiCad.

## Instalacja KiCada na stałe (brak winget w systemie)

1. **Bezpośrednio:** <https://www.kicad.org/download/windows/> (KiCad 9/10).
2. **winget** (po doinstalowaniu „App Installer" z MS Store): `winget install -e --id KiCad.KiCad`.
3. **Chocolatey:** `choco install kicad`.
