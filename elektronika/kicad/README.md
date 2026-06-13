# KiCad — projekt schematu (scaffold pod v2)

Pliki projektu KiCad dla odbiornika GPS RTK. **To scaffold** — `gps_rtk_v1.kicad_sch`
zawiera na razie tylko blok tytułowy i notatki tekstowe opisujące tor. Pełny schemat
z symbolami i połączeniami rysuje się w GUI KiCada (deliverable v2).

> Dla v1 (prototyp na devkitach) źródłem prawdy o połączeniach są tabele w
> [../docs/02-schemat-polaczen.md](../docs/02-schemat-polaczen.md) i pinout w
> [../docs/05-pinout-firmware.md](../docs/05-pinout-firmware.md). KiCad jest potrzebny
> dopiero, gdy będziemy projektować własne PCB.

> ⚠️ Pliki `.kicad_pro`/`.kicad_sch` napisałem ręcznie, **bez lokalnego KiCada do walidacji**
> (w środowisku brak winget/choco/scoop i samego KiCada). Format = KiCad 8 (`version 20231120`).
> Jeśli KiCad zgłosi błąd formatu przy otwieraniu — daj znać, poprawię.

## Instalacja KiCada na Windows (brak winget w systemie)

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
