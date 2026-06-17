# Karty katalogowe — linki

Pobierz w razie potrzeby (środowisko nie zapisuje tu plików automatycznie). Część PDF-ów
producentów blokuje pobieranie skryptowe — otwórz w przeglądarce.

## Moduł GNSS — Quectel LC29H(EA/DA)

- **[Instrukcja ZAMÓWIONEJ płytki — LC29H „Mozi" (CN)](LC29H-mozi-board-manual-CN.pdf)** — lokalna kopia z aukcji.
  Kluczowe: rover RTK, **SMA + antena w zestawie**, **USB-C + UART** (2 przełączniki: Type-C ↔ goldpiny),
  **3.3 V/5 V** kompatybilna, **baud 115200**, bateria podtrzymująca efemerydy, RTK Fixed ~2,5 cm.
- LC29H Series GNSS Specification — https://www.quectel.com/product/gnss-lc29h/
  (mirror Mouser: https://www.mouser.com/datasheet/2/1052/Quectel_LC29H_Series_GNSS_Specification_V1_3-3009838.pdf)
- LC29H Series Hardware Design (bias anteny — Figure 17, VDD_RF) —
  https://download.mikroe.com/documents/datasheets/LC29HEA_datasheet.pdf
- LC29H (BA,CA,DA,EA) DR&RTK Application Note —
  https://5ghub.us/wp-content/uploads/2024/07/Quectel_LC29HBACADAEA_DRRTK_Application_Note_V1.1.pdf
- MikroE GNSS RTK 3 Click (LC29HEA) — schemat/pinout —
  https://www.mikroe.com/gnss-rtk-3-click-lc29hea
- rtklibexplorer (walidacja RTK, konfiguracja, antena):
  - https://rtklibexplorer.wordpress.com/2024/04/28/dual-frequency-rtk-for-less-than-60-with-the-quectel-lc29hea/
  - https://rtklibexplorer.wordpress.com/2024/05/06/configuring-the-quectel-lc29hea-receiver-for-real-time-rtk-solutions/
  - https://rtklibexplorer.wordpress.com/2024/08/01/quectel-lc29hea-with-improved-antenna/

## MCU — ESP32-WROOM-32

- Datasheet ESP32-WROOM-32 (Espressif) — https://www.espressif.com/sites/default/files/documentation/esp32-wroom-32_datasheet_en.pdf
- Boot mode / auto-reset (esptool) — https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/boot-mode-selection.html

## Zasilanie

- TP4056 (ład. Li-Ion) — nota na module; opis: https://www.best-microcontroller-projects.com/tp4056.html
- Pololu S7V8F3 (buck-boost 3.3 V) — https://www.pololu.com/product/2122
- TI TPS63020 (alt. buck-boost) — https://www.ti.com/lit/ds/symlink/tps63020.pdf
- Samsung INR18650-35E — https://www.orbtronic.com/content/samsung-35e-datasheet-inr18650-35e.pdf

## Wyświetlacz / IMU

- SSD1306 (OLED) — https://cdn-shop.adafruit.com/datasheets/SSD1306.pdf
- BNO085 (IMU, v2) — https://www.ceva-dsp.com/wp-content/uploads/2019/10/BNO080_085-Datasheet.pdf

## Antena / ground plane

- Tallysman — Ground Plane Considerations for GNSS Patch Antennas —
  https://community.emlid.com/uploads/default/original/2X/9/97c4b2e0722b4490546d21334add1a22a0f1934c.pdf
