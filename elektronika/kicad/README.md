# KiCad — projekt schematu

Pliki projektu KiCad dla odbiornika GPS RTK. `gps_rtk_v1.kicad_sch` zawiera **schemat
blokowy** (bloki modułów + połączenia + etykiety netów), **zwalidowany i wyeksportowany**
przez `kicad-cli 9.0.9` → [gps_rtk_v1.pdf](gps_rtk_v1.pdf) i [gps_rtk_v1.svg](gps_rtk_v1.svg).
Pełny capture z symbolami bibliotecznymi + footprinty + ERC → v2 (rysunek w GUI).

> Dla v1 (prototyp na devkitach) źródłem prawdy o połączeniach są tabele w
> [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md) i pinout w
> [../docs/05-pinout-firmware.md](../docs/05-pinout-firmware.md). KiCad jest potrzebny
> dopiero, gdy będziemy projektować własne PCB.

> ✅ **Zwalidowane:** `kicad-cli 9.0.9` otwiera `gps_rtk_v1.kicad_sch` bez błędów i renderuje
> (PDF/SVG dołączone, 9848 elementów rysunku). Format KiCad 8 (`version 20231120`) — KiCad 8/9/10
> otworzą bez problemu.

## Portable KiCad już rozpakowany (ta sesja)

Instalator rozpakowano 7-Zipem **bez instalacji i bez praw admina** do
`C:\TMP\kicad_portable\` — działa stamtąd zarówno **GUI** (`C:\TMP\kicad_portable\bin\kicad.exe`),
jak i **CLI** (`C:\TMP\kicad_portable\bin\kicad-cli.exe`). Możesz otworzyć schemat od ręki:
`& "C:\TMP\kicad_portable\bin\kicad.exe" "...\elektronika\kicad\gps_rtk_v1.kicad_pro"`.
Folder można usunąć (~kilka GB) albo zachować jako przenośny KiCad.

## Instalacja KiCada na Windows (na stałe; brak winget w systemie)

Wybierz jedną drogę:

1. **Bezpośrednio (najprościej):** pobierz instalator z
   <https://www.kicad.org/download/windows/> i uruchom. KiCad 8/9, ~1,5 GB.
2. **Przez winget** (jeśli najpierw doinstalujesz „App Installer" z Microsoft Store —
   to on dostarcza `winget`): potem `winget install -e --id KiCad.KiCad`.
3. **Przez Chocolatey:** zainstaluj choco (<https://chocolatey.org/install>), potem
   `choco install kicad`.

Po instalacji w PATH pojawi się też `kicad-cli` (przydatny do eksportu schematu do PDF/SVG
z linii poleceń).

## Otwarcie projektu

Otwórz `gps_rtk_v1.kicad_pro` w KiCad → „Schematic Editor". Zobaczysz arkusz A3 z blokiem
tytułowym i notatkami opisującymi tor (z pinami i UUID-ami charakterystyk BLE).

## Plan rysowania schematu (v2) — mapowanie na symbole/footprinty

| Blok | Symbol KiCad (propozycja) | Uwaga |
|---|---|---|
| ESP32-WROOM-32 | `RF_Module:ESP32-WROOM-32` (lub devkit jako 2× listwa) | dla v1-devkitu wystarczą listwy pinów |
| Moduł GNSS LC29HEA | brak gotowego — listwa pinów / własny symbol | piny: VCC, GND, TXD, RXD, (PPS, RST), RF |
| OLED SSD1306 | listwa 4-pin (`Connector_Generic`) | VCC, GND, SDA, SCL |
| TP4056 | moduł jako blok / `Connector_Generic` | B+, B-, OUT+, OUT-, USB-C |
| Buck-boost (Pololu S7V8F3) | moduł 4-pin | VIN, GND, VOUT, (EN/SHDN) |
| Ogniwo 18650 | `Device:Battery_Cell` | + koszyk |
| Dzielnik baterii | `Device:R` ×2 (100 k) | → GPIO34 |
| Pull-up I2C | `Device:R` ×2 (4,7 k) | jeśli OLED bez własnych |
| Bulk / odsprzęganie | `Device:C` (100–470 µF, 100 nF) | szyna 3.3 V |
| LED + rezystor | `Device:LED` + `Device:R` (330 Ω) | GPIO2 |
| Przycisk | `Switch:SW_Push` | GPIO27 (opc.) |

Kolejność: rozmieść symbole → poprowadź połączenia wg [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md)
→ przypisz footprinty → (v2) PCB. Dla v1 wystarczy sam schemat jako dokumentacja.

## Eksport do PDF/SVG (po instalacji)

```powershell
kicad-cli sch export pdf gps_rtk_v1.kicad_sch -o gps_rtk_v1.pdf
kicad-cli sch export svg gps_rtk_v1.kicad_sch -o .
```
