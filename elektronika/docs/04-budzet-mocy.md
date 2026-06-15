# Budżet mocy i czas pracy

> Deliverable §3. Część prądów to **szacunki** — karty katalogowe Quectel/TI nie sparsowały się
> w researchu, więc liczby pochodzą ze streszczeń/forów. Oznaczone `[~]`. Zweryfikuj na sprzęcie
> miernikiem przed projektem PCB v2. Komponenty: [03-BOM.md](03-BOM.md).

> **Zasilanie v1 (start, decyzja D6): powerbank przez USB devkitu ESP32** — 5 V → AMS1117 (na devkicie)
> → 3V3 → ESP32 + GPS + OLED. Poniższy budżet **baterii** dotyczy **opcji terenowej/v2** (18650 + buck-boost).
> Na powerbanku uwaga na **auto-wyłączanie** przy małym poborze (~<50–75 mA) — nasz pobór ~150–250 mA
> zwykle utrzymuje go włączonym; jeśli gaśnie, użyj powerbanku bez auto-off.

## 1. Pobór prądu @ 3.3 V

| Element | Tryb | Prąd | Pewność |
|---|---|---|---|
| Moduł LC29HEA | śledzenie/akwizycja RTK (dual-band) | **~30 mA** `[~]` | datasheet: 16/23/30 mA zależnie od wariantu; przyjęto górną |
| Antena aktywna (LNA) | bias przez RF | **~10–15 mA** `[~]` | brak twardej liczby; typowo dla patch L1/L5 |
| ESP32-WROOM-32 | BLE aktywne, bez light-sleep | **~100 mA** `[~]` | CPU pełna prędkość między eventami |
| ESP32-WROOM-32 | szczyt TX BLE @0 dBm | ~130 mA (1–5 ms) | szczyt sprzętowy — wymiarowanie buforu/zasilania |
| OLED SSD1306 | typowo | **~15–20 mA** | zależne od liczby zapalonych pikseli; można wygasić |

Źródła prądów: [Hubble — ESP32 BLE](https://hubble.com/community/guides/esp32-power-consumption-in-ble-mode-what-to-expect-from-advertising-scanning-and-connected-states/),
[Adafruit — SSD1306](https://learn.adafruit.com/monochrome-oled-breakouts/power-requirements),
[Quectel LC29H Spec](https://www.quectel.com/product/gnss-lc29h/).

## 2. Scenariusze i czas pracy

Założenia: ogniwo **Samsung 35E**, pojemność min. **3350 mAh**, śr. napięcie **~3,6 V**;
realnie użyteczne do cut-off ~3,0 V: **~3000–3200 mAh** (~11 Wh). Sprawność buck-boost **~92%** `[~]`.

Przeliczenie prądu z szyny 3.3V na ogniwo: `I_ogniwo = (I_3.3 × 3.3) / (3.6 × 0,92)`.

| Scenariusz | Pobór @3.3V | Prąd z ogniwa | **Czas pracy** |
|---|---|---|---|
| **Tyczenie ciągłe** (BLE aktywne, OLED wł.) | GNSS 30 + ant 12 + ESP32 100 + OLED 18 ≈ **160 mA** | ~159 mA | **~19–20 h** |
| **Zoptymalizowany** (OLED wygaszony, BLE conn-interval strojony, ESP32 modem/light-sleep między eventami) | ≈ **90–110 mA** | ~90–110 mA | **~28–35 h** |
| **Idle/akwizycja** (przed Fixem, bez BLE) | ≈ **45 mA** | ~45 mA | **~65 h** |

> **Wniosek:** jedno ogniwo 18650 3500 mAh daje **co najmniej pełny dzień roboczy** tyczenia
> (8–10 h) z dużym zapasem, nawet w wariancie bez optymalizacji. To z naddatkiem wystarcza
> dla scenariusza „wyjście w teren na działkę".

## 3. Dźwignie wydłużenia czasu pracy (firmware)

W kolejności opłacalności:
1. **Light-sleep / modem-sleep ESP32** między eventami BLE — największy zysk (ESP32 to dominujący
   odbiornik prądu). Strojenie connection interval (np. 100–500 ms) + slave latency.
2. **Wygaszanie OLED** po czasie bezczynności (przycisk budzi) — oszczędza ~15–20 mA.
3. **Niższy rate GNSS gdy stoisz** (np. 1 Hz w trybie pomiaru punktu, 5–10 Hz w nawigacji).
4. Wyłączanie nieużywanych konstelacji/zdań NMEA.

## 4. Ładowanie

- TP4056 domyślnie **1 A** (rezystor RPROG; `I = 1200 / R[Ω]`). Dla 35E (3350 mAh) ładowanie
  ~1 A → pełne **~3,5–4 h** (CC/CV).
- Łagodniej dla ogniwa / przy słabym USB: zmień RPROG na ~0,5 A (~2,4 kΩ) → ~7 h.
- USB-C **tylko ładowanie**; programowanie po USB devkita. Przy ładowaniu i pracy jednocześnie
  pamiętaj o uwadze „wybór źródła" z [02-schemat-polaczen.md](02-schemat-polaczen.md) §2.

## 5. Wymiarowanie i zapasy

- **Buck-boost ≥ 1 A** (Pololu S7V8F3) — zapas na szczyty BLE (~130 mA) + GNSS + OLED z dużym
  marginesem. Jeśli v2 doda **WiFi/NTRIP** (szczyt ~240 mA), przejdź na **S13V25F3 (2,5 A)**.
- **Bulk 100–470 µF** na szynie 3.3V — pokrywa szczyty radia, chroni przed brownout/resetem.
- **Max prąd rozładowania ogniwa** (35E: 8 A) — wielokrotnie powyżej naszego ~0,2 A; bez znaczenia.
- Samorozładowanie i starzenie ogniwa — licz realnie ~90% pojemności nominalnej w praktyce.

## 6. Do zweryfikowania miernikiem (przed PCB v2)

- Rzeczywisty prąd modułu LC29HEA w RTK dual-band 5–10 Hz (kluczowy `[~]`).
- Prąd anteny aktywnej (`[~]`) i napięcie biasu.
- Realny średni prąd ESP32 przy docelowym firmware BLE (zależny od conn-interval i sleepu).
- Sprawność buck-boost przy rzeczywistym obciążeniu i napięciu ogniwa.
