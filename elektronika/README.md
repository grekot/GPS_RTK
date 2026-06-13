# Elektronika — odbiornik GPS RTK (warstwa sprzętowa)

Projekt **warstwy sprzętowej** odbiornika GNSS RTK do tyczenia granic działki.
Aplikacja mobilna — osobna sesja (`../app/`). Kontekst produktu: [`../PROJEKT.md`](../PROJEKT.md).

## Start tutaj

1. [INSTRUKCJA-AGENTA.md](INSTRUKCJA-AGENTA.md) — brief dla sesji elektroniki (+ §11 log decyzji).
2. [docs/01-decyzje-sprzetowe.md](docs/01-decyzje-sprzetowe.md) — **co i dlaczego zdecydowano** (czytaj najpierw).

## Dokumentacja (deliverables wg INSTRUKCJA §7)

| Dokument | Zawartość | § |
|---|---|---|
| [docs/01-decyzje-sprzetowe.md](docs/01-decyzje-sprzetowe.md) | decyzje, uzasadnienia, otwarte pozycje | — |
| [docs/02-schemat-polaczen.md](docs/02-schemat-polaczen.md) | diagram + tabele połączeń, tor zasilania, bias anteny | 1 |
| [docs/03-BOM.md](docs/03-BOM.md) | lista zakupowa, numery, linki PL, ceny, ~koszt | 2 |
| [docs/04-budzet-mocy.md](docs/04-budzet-mocy.md) | budżet mocy, czas pracy (~19–20 h), ładowanie | 3 |
| [docs/05-pinout-firmware.md](docs/05-pinout-firmware.md) | pinout ESP32 + protokół BLE — **kontrakt dla firmware/app** | 4 |
| [docs/06-mechanika.md](docs/06-mechanika.md) | obudowa, gwint 5/8"-11, antena + ground plane, IP65 | 5 |
| [docs/07-programowanie-debug.md](docs/07-programowanie-debug.md) | toolchain, flashowanie, test toru SPP→BLE | 6 |
| [datasheety/README.md](datasheety/README.md) | linki do kart katalogowych | — |
| [kicad/](kicad/) | schemat blokowy KiCad + eksport [PDF](kicad/gps_rtk_v1.pdf)/[SVG](kicad/gps_rtk_v1.svg) (zwalidowany kicad-cli 9.0.9) | 1/7 |

## Stan projektu

- **Faza:** v1 = prototyp na devkitach / płytce stykowej (PCB → v2). Dokumentacja kompletna,
  sprzęt **jeszcze niekupiony**.
- **Architektura:** Antena L1/L5 → LC29HEA → UART → ESP32 → BLE → smartfon (klient NTRIP).
  ESP32 = „głupi most" UART↔BLE. Nie zmieniać bez uzgodnienia.
- **Moduł GNSS (podstawowy):** breakout **LC29HEA + antena z AliExpress** (~197 zł, wariant EA).
  Alternatywy: MikroE GNSS RTK 3 Click (premium), Waveshare LC29H(DA) (PL od ręki, ale 1 Hz).
- **Zasilanie:** 18650 → TP4056 (USB-C) → buck-boost 3.3 V.

## Następne kroki

1. Zakup wg [BOM](docs/03-BOM.md) (wybór wariantu modułu).
2. Montaż na stykówce wg [schematu](docs/02-schemat-polaczen.md).
3. Bring-up wg [planu programowania](docs/07-programowanie-debug.md) — test toru po SPP + SW Maps + ASG-EUPOS.
4. Firmware BLE NUS → integracja z `../app/lib/sources/ble_receiver_source.dart`.
5. (v2) KiCad + PCB + obudowa + IMU BNO085.

> **KiCad:** [kicad/](kicad/) — schemat blokowy `gps_rtk_v1.kicad_sch` + eksport
> [PDF](kicad/gps_rtk_v1.pdf)/[SVG](kicad/gps_rtk_v1.svg), zwalidowany `kicad-cli 9.0.9`.
> Pełny capture z symbolami → v2. Portable KiCad (GUI+CLI) rozpakowany w `C:\TMP\kicad_portable`
> (szczegóły w [kicad/README.md](kicad/README.md)).
