# Symulator firmware na PC (`sim/`)

Konsolowy test, który uruchamia **prawdziwy kod parsera firmware** na komputerze
(Windows) — bez modułu GNSS i bez ESP32. Karmi parser strumieniem NMEA jak z
LC29HEA (zimny start → 3D → RTK Float → RTK Fixed → starzenie poprawek → spadek)
i sprawdza, czy wynik jest poprawny. Rysuje też **podgląd ekranu OLED** (ASCII,
układ 1:1 z `display.cpp`) ewoluujący z każdą epoką:

```
    +--------------------------+
    | BLE              bat 74% |
    | FIXED                    |
    | Sat 17  HDOP 0.8         |
    | Age 1.2s  MTU 247        |
    +--------------------------+
```

## Jak uruchomić

**Dwuklik w `run-sim.bat`** (skompiluje i uruchomi; okno zostanie otwarte).

Albo ręcznie z linii poleceń (z katalogu `sim/`):

```
g++ -std=c++17 -static -I. -I..\include device_sim.cpp ..\src\gnss_status.cpp ..\src\status_led.cpp ..\src\telemetry.cpp -o device_sim.exe
device_sim.exe
```

Wymaga `g++` (jest w MSYS2/MinGW-w64, np. `C:\msys64\mingw64\bin`). Skrypt sam go
znajdzie na PATH lub w domyślnej lokalizacji MSYS2.

## Co to naprawdę testuje

Linkuje **te same pliki .cpp**, co firmware ESP32 — nie kopię:

- `src/gnss_status.cpp` — parser GGA (walidacja sumy kontrolnej, indeksy pól,
  wiek poprawek, odrzucanie zdań spoza GGA i z błędną sumą),
- `statusLedLevel()` z `src/status_led.cpp` — mapowanie typu fixa na wzorzec LED,
- `buildStatusJson()` z `src/telemetry.cpp` — format telemetrii wysyłanej po BLE,
- `displayFixLabel()` z `src/display.cpp` — etykieta fixa na OLED (reszta układu
  ekranu to wierny mock ASCII; piksele/fonty U8g2 wymagają sprzętu).

Aby to było możliwe na PC, `sim/Arduino.h` to mini-shim (dostarcza `millis()`),
a sprzętowe fragmenty firmware są pod `#ifdef ARDUINO` — tu się nie kompilują.

Każda epoka jest porównywana z wartością oczekiwaną; na końcu `PASS`/`FAIL`
(kod wyjścia 0/1, więc nadaje się też do CI).

## Czego NIE testuje (i dlaczego)

- **Radia BLE/SPP** — nie da się sensownie emulować na PC (to warstwa fizyczna
  Bluetooth). Tu sprawdzamy „mózg": parsowanie i logikę statusu.
- **I2C/OLED, ADC baterii** — to peryferia sprzętowe (kod pod `#ifdef ARDUINO`).

Pełny tor (NMEA→BLE→telefon, RTCM→moduł→Fixed) potwierdzisz dopiero na sprzęcie:
`pio run -e esp32dev -t upload` + `pio device monitor`.

> `device_sim.exe` to artefakt buildu — nie wrzucaj do gita (patrz `.gitignore`).
