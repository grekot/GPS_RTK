# Decyzje sprzętowe — odbiornik GPS RTK (sesja elektroniki)

> Data: 2026-06-13. Dokument-kotwica dla warstwy sprzętowej. Wszystkie pozostałe
> dokumenty w `elektronika/docs/` odwołują się do ustaleń tutaj.
> Zakres tej sesji: **sprzęt**. Aplikacja (`../app/`) i dane (`../dane/`) — osobna sesja.

## 1. Potwierdzone decyzje

| # | Temat | Decyzja | Kto zdecydował |
|---|---|---|---|
| D1 | Zakres v1 | **Prototyp na devkitach / płytce stykowej** — pełna dokumentacja do złożenia, bez projektu PCB w tej fazie (PCB → v2) | użytkownik |
| D2 | Moduł GNSS | **Breakout LC29HEA + antena z AliExpress (~197 zł)** jako podstawowy; **MikroE GNSS RTK 3 Click (LC29HEA)** jako wariant premium; **Waveshare LC29H(DA)** jako wariant z PL od ręki (wszystkie drop-in) | użytkownik wskazał konkretny moduł AliExpress |
| D3 | Zasilanie (terenowe) | **1× 18650 → TP4056 (USB-C, z zabezpieczeniem) → buck-boost 3.3 V** — **opcja terenowa/v2** (patrz D6) | użytkownik |
| D4 | Urządzenia I2C | **OLED SSD1306** w v1 + **zarezerwowane miejsce/pady pod IMU BNO085** (montaż w v2) | użytkownik |
| D5 | USB-C | v1: programowanie przez **USB devkita** (mostek CP2102/CH340 na płytce). v2: zintegrowany CP2102 na USB-C | agent (wynika z D1) |
| D6 | Zasilanie v1 (start) | **Powerbank przez USB devkitu ESP32** (5 V → AMS1117 → 3V3 → ESP32 + GPS + OLED). Sekcja bateryjna (D3) **nie montowana w v1**. Pułapka: część powerbanków ma auto-wyłączanie przy małym poborze | użytkownik |

## 2. Kluczowe ustalenie: wariant LC29H — DA vs EA

Research (2026-06-13) ujawnił sprzeczność między nazwą w projekcie („LC29HEA", 10 Hz)
a ofertą Waveshare:

- **Waveshare sprzedaje tylko warianty AA / DA / BS — NIE EA.** Ich rover RTK to **LC29H(DA)**.
- **LC29H(DA): RTK tylko 1 Hz.** **LC29H(EA): RTK 1–10 Hz** (domyślnie 10 Hz) i jako
  jedyny daje surowe obserwacje > 1 Hz. Źródło:
  [rtklibexplorer](https://rtklibexplorer.wordpress.com/2024/05/06/configuring-the-quectel-lc29hea-receiver-for-real-time-rtk-solutions/).
- **MikroE GNSS RTK 3 Click występuje w wersji LC29H*EA*** — gotowa płytka ze złączem
  **SMA**, czyli wariant z nazwy projektu dostępny „pod klucz".
  Źródło: [mikroe.com](https://www.mikroe.com/gnss-rtk-3-click-lc29hea).

### Dlaczego breakout LC29HEA z AliExpress jako podstawowy

- **Wariant EA** — zgodny ze specyfikacją i nazwą projektu (LC29HEA, RTK do 10 Hz, surowe
  obserwacje → wspiera „kurs z ruchu RTK" z `../PROJEKT.md` i w przyszłości PPK).
- **Najlepszy stosunek możliwości do ceny:** ~197 zł **z anteną** (wybór wariantu „Lc29Hea
  and Antenna" w ofercie obejmującej Aa/Da/Ea/Ba/Bs).
- **Zwalidowany przez niezależny autorytet GNSS** — rtklibexplorer uzyskał stabilny RTK Fixed
  na tej klasie płytki: [„dual-frequency RTK za <$60 z LC29HEA"](https://rtklibexplorer.wordpress.com/2024/04/28/dual-frequency-rtk-for-less-than-60-with-the-quectel-lc29hea/).
- Interfejs UART (TTL, 3.3 V) identyczny → schemat, firmware i aplikacja bez zmian.
- **Ryzyka (świadome):** zmienna jakość partii, czas wysyłki, uboga dokumentacja; antena
  w zestawie jest „na start" — do dokładności cm dołóż ground plane Ø10–12 cm i rozważ lepszą
  antenę ([rtklibexplorer: improved antenna](https://rtklibexplorer.wordpress.com/2024/08/01/quectel-lc29hea-with-improved-antenna/)).

### Dlaczego MikroE Click (EA) jako wariant premium

- Ten sam chip EA, ale dopracowana płytka, lepsza dokumentacja/wsparcie MikroE, złącze **SMA**
  (solidne w terenie). Antena osobno. Droższy.
- Łączenie z ESP32 = 4 piny mikroBUS (3V3, GND, TX, RX) — bez dedykowanego adaptera.

### Dlaczego Waveshare DA pozostaje w BOM jako wariant z PL „od ręki"

- Tańszy, najłatwiejszy zakup w PL (Botland/Kamami), w magazynie, z kompletem antena + adapter.
- **1 Hz wystarcza dla statycznego tyczenia** (stoisz w punkcie, uśredniasz epoki).
- **Interfejs identyczny** (UART: NMEA wyjście / RTCM wejście) → wymiana modułu nie wymaga
  żadnych zmian w schemacie połączeń, firmware ani aplikacji. Zgodne z tezą `../PROJEKT.md`:
  „moduł można później wymienić na lepszy bez zmian w aplikacji".

> **Wniosek dla zespołu aplikacji:** niezależnie od wybranego wariantu interfejs jest ten sam.
> Jedyna różnica widoczna w aplikacji to częstotliwość napływu NMEA (1 Hz vs do 10 Hz).

## 3. Uzasadnienia pozostałych decyzji

- **D1 (devkit-first):** zgodne z „Etapami realizacji" w `../PROJEKT.md` — najpierw de-ryzykujemy
  tor RF/UART/BLE/NTRIP na gotowych płytkach, dopiero potem (v2) projektujemy PCB. Tańsze
  i szybsze w nauce; błędy łapiemy na stykówce, nie w miedzi.
- **D3 (TP4056 + buck-boost):** oba układy docelowe (LC29HEA, ESP32) pracują na **3.3 V**.
  Buck-boost **wprost z ogniwa (3.0–4.2 V) na 3.3 V** daje czyste zasilanie sekcji RF i dobrą
  sprawność, bez pośredniego 5 V → LDO (które dokłada szum przetwornicy blisko RF). TP4056
  **z zabezpieczeniem (DW01A)** chroni ogniwo. Szczegóły: [04-budzet-mocy.md](04-budzet-mocy.md).
- **D4 (OLED + miejsce na IMU):** OLED daje status fixa/baterii bez telefonu. BNO085 dokładamy
  w v2 (decyzja z `../PROJEKT.md`: kompas telefonu + COG z RTK jako podstawa) — w v1
  rezerwujemy tylko wspólną magistralę I2C i pady, żeby v2 nie wymagało przeprojektowania.

## 4. Otwarte pozycje do domknięcia (zweryfikować przy zakupie/montażu)

1. **Bias anteny aktywnej na złączu RF** — breakout AliExpress / Click zwykle podają bias
   z VDD_RF (3.3 V) na gniazdo, ale potwierdź dla konkretnej płytki (opis/schemat) lub zmierz
   multimetrem napięcie DC na środku gniazda. Goły moduł bez bias-tee wymaga zewnętrznego
   (L ≥ 68 nH + R 10 Ω od VDD_RF=3.3 V, C 100 pF) — patrz [02-schemat-polaczen.md](02-schemat-polaczen.md).
2. **Zakup AliExpress** — w koszyku wybierz wariant **EA** (nie DA/AA); potwierdź zakres VCC
   i że logika to 3.3 V. Cena Click w PL (Kamami) renderuje się w przeglądarce — potwierdź przy zakupie.
3. **Prąd LC29HEA w RTK dual-band** — datasheet podaje 16/23/30 mA zależnie od wariantu;
   do budżetu przyjęto roboczo ~30 mA. Patrz [04-budzet-mocy.md](04-budzet-mocy.md).
4. **Kalibracja ADC ESP32** do pomiaru baterii (eFuse Vref / esp_adc_cal) — bez niej błąd ±5–10%.

## 5. Mapa dokumentów

| Dokument | Zawartość | Deliverable (instrukcja §7) |
|---|---|---|
| [01-decyzje-sprzetowe.md](01-decyzje-sprzetowe.md) | ten dokument | — |
| [02-schemat-polaczen.md](02-schemat-polaczen.md) | schemat/diagram + tabele połączeń | 1 |
| [03-BOM.md](03-BOM.md) | lista zakupowa, numery, linki PL, ceny | 2 |
| [04-budzet-mocy.md](04-budzet-mocy.md) | budżet mocy, czas pracy | 3 |
| [05-pinout-firmware.md](05-pinout-firmware.md) | pinout + protokół BLE (kontrakt dla firmware/app) | 4 |
| [06-mechanika.md](06-mechanika.md) | obudowa, gwint 5/8", antena, ground plane, IP | 5 |
| [07-programowanie-debug.md](07-programowanie-debug.md) | toolchain, flashowanie, test toru | 6 |
| [../datasheety/README.md](../datasheety/README.md) | linki do kart katalogowych | — |
