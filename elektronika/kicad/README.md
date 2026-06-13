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

## Weryfikacja (bez ERC — patrz niżej)

- ✅ **Netlista** (`kicad-cli sch export netlist`) — przeszła; każdy net ma dokładnie właściwe węzły
  (sprawdzone programowo: brak zlanych/rozjechanych netów).
- ✅ **Render** PDF/SVG (`kicad-cli sch export`) — bez błędów (10935 elementów rysunku).
- ⚠️ `kicad-cli sch erc` **crashuje** na tym pliku (quirk zgodności wyjścia generatora `kiutils`
  z silnikiem ERC w kicad-cli 9.0.9). Dlatego poprawność połączeń potwierdziłem **netlistą**, nie ERC.
  Po otwarciu i zapisaniu pliku w **GUI KiCada** (które normalizuje format) ERC powinien działać.

## Do zrobienia w v2 (PCB)

- Przypisać **footprinty** do symboli, uruchomić **ERC** w GUI, wygenerować **PCB**.
- Sekcja RF/bias anteny dla gołego modułu (jeśli nie gotowa płytka) — patrz [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md).

## Regeneracja / eksport

```powershell
$cli = "C:\TMP\kicad_portable\bin\kicad-cli.exe"   # lub kicad-cli z instalacji
py -3 gen\gen_schematic.py                          # wymaga: pip install kiutils
& $cli sch export pdf     --output gps_rtk_v1.pdf gps_rtk_v1.kicad_sch
& $cli sch export svg     --output .               gps_rtk_v1.kicad_sch
& $cli sch export netlist --output gps_rtk_v1.net  gps_rtk_v1.kicad_sch
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
