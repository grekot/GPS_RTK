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
| [docs/08-podlaczenie-stykowka.md](docs/08-podlaczenie-stykowka.md) | **schemat połączeń na płytce stykowej (v1, powerbank)** + [SVG](docs/podlaczenie-stykowka-v1.svg) | 1 |
| [docs/09-instrukcja-app-usb.md](docs/09-instrukcja-app-usb.md) | **instrukcja dla sesji aplikacji: źródło pozycji po USB** (Android) | — |
| [datasheety/README.md](datasheety/README.md) | linki do kart katalogowych | — |
| [kicad/](kicad/) | **pełny schemat** + **PCB-carrier** (gniazda pod moduły + devkit ESP32, DRC 0 naruszeń, nietrasowana): [schemat PDF](kicad/gps_rtk_v1.pdf), [PCB 3D](kicad/gps_rtk_v1_pcb.png) | 1/7 |

## Stan projektu

- **Faza:** v1 = prototyp na devkitach / płytce stykowej (PCB → v2). Dokumentacja kompletna,
  sprzęt **jeszcze niekupiony**.
- **Architektura:** Antena L1/L5 → LC29HEA → UART → ESP32 → BLE → smartfon (klient NTRIP).
  ESP32 = „głupi most" UART↔BLE. Nie zmieniać bez uzgodnienia.
- **Moduł GNSS (podstawowy):** breakout **LC29HEA + antena z AliExpress** (~197 zł, wariant EA).
  Alternatywy: MikroE GNSS RTK 3 Click (premium), Waveshare LC29H(DA) (PL od ręki, ale 1 Hz).
- **Zasilanie (v1 start):** powerbank przez **USB devkitu ESP32**; sekcja bateryjna (18650 → TP4056 → buck-boost 3.3 V) = opcja terenowa/v2 (nie montowana w v1).

## Następne kroki

1. Zakup wg [BOM](docs/03-BOM.md) (wybór wariantu modułu).
2. Montaż na stykówce wg [schematu](docs/02-schemat-polaczen.md).
3. Bring-up wg [planu programowania](docs/07-programowanie-debug.md) — test toru po SPP + SW Maps + ASG-EUPOS.
4. Firmware BLE NUS → integracja z `../app/lib/sources/ble_receiver_source.dart`.
5. (v2) KiCad + PCB + obudowa + IMU BNO085.

> **KiCad:** [kicad/](kicad/) — **pełny schemat** `gps_rtk_v1.kicad_sch` (prawdziwe symbole +
> połączenia po netach) + eksport [PDF](kicad/gps_rtk_v1.pdf)/[SVG](kicad/gps_rtk_v1.svg),
> **zweryfikowany netlistą** (`kicad-cli`). Generator: [kicad/gen/gen_schematic.py](kicad/gen/gen_schematic.py).
> **PCB-carrier** (płytka-baza z gniazdami pod wszystkie moduły + ESP32 devkit; DRC **0 naruszeń**,
> nietrasowana): [render 3D](kicad/gps_rtk_v1_pcb.png), generator [gen_pcb.py](kicad/gen/gen_pcb.py)
> — zostaje trasowanie. Portable KiCad (GUI+CLI) w `C:\TMP\kicad_portable` (zob. [kicad/README.md](kicad/README.md)).
