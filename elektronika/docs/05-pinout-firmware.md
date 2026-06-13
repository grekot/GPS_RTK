# Pinout i protokół BLE — interfejs sprzęt ↔ firmware ↔ aplikacja

> Deliverable §4. To **kontrakt**: firmware ESP32 i aplikacja (`../app/`) muszą być z nim spójne.
> Bazuje na: `../PROJEKT.md` (sekcje „Protokół BLE", „Firmware ESP32"),
> `../app/lib/sources/ble_receiver_source.dart`, `../app/lib/models/rtk_position.dart`.
> Decyzje sprzętowe: [01-decyzje-sprzetowe.md](01-decyzje-sprzetowe.md).

## 1. Pinout ESP32-WROOM-32 (finalny dla v1)

| Funkcja | GPIO | Kierunek | Uwagi |
|---|---|---|---|
| **GNSS UART RX** | **GPIO16** (UART2 RX) | wejście | ← **TX** modułu GNSS. WROOM OK (na WROVER zajęte przez PSRAM). |
| **GNSS UART TX** | **GPIO17** (UART2 TX) | wyjście | → **RX** modułu GNSS. |
| **I2C SDA** | **GPIO21** | dwukier. | wspólna magistrala: OLED SSD1306 + (v2) IMU BNO085. |
| **I2C SCL** | **GPIO22** | wyjście | jw. |
| **Pomiar baterii** | **GPIO34** (ADC1_CH6) | wejście | tylko-wejście, ADC1 (działa z BLE); przez dzielnik 100k/100k. |
| **LED statusu** | **GPIO2** | wyjście | pin strapping — steruj low-side; nie trzymać HIGH przy boot/flash. |
| **Przycisk użytkownika** (opcja) | **GPIO27** | wejście | „zaznacz punkt / tryb"; pull-up + do GND. Opcjonalny w v1. |
| **GNSS 1PPS** (opcja) | **GPIO35** | wejście | tylko-wejście; sygnał 1PPS do synchronizacji czasu. Opcjonalny. |
| **GNSS RESET** (opcja) | **GPIO4** | wyjście | sterowanie resetem modułu. Opcjonalny. |
| Programowanie / reset | **GPIO0 (BOOT)**, **EN** | — | obsługiwane przez devkit (przyciski + auto-reset). |
| UART0 (USB konsola) | GPIO1 (TX0) / GPIO3 (RX0) | — | **zarezerwowane** dla mostka USB-UART (flash + logi). Nie używać do GNSS. |

**Piny, których unikać** (strapping / flash): GPIO12 (MTDI — napięcie flash!), GPIO15 (MTDO),
GPIO5, GPIO6–11 (SPI flash). GPIO2 użyte na LED świadomie, z zachowaniem reguł boot.

> **Dlaczego GNSS na UART2, a nie UART0:** UART0 (GPIO1/3) jest zajęty przez mostek USB-UART
> do flashowania i logów `Serial.println`. Trzymanie GNSS na osobnym UART2 pozwala debugować
> firmware po USB bez kolizji ze strumieniem NMEA/RTCM.

## 2. UART do modułu GNSS

> Fakty EA zweryfikowane przez sesję firmware (LC29H&LC79H GNSS Protocol Spec v1.1 + rtklibexplorer).

| Parametr | Wartość | Uwaga |
|---|---|---|
| Baud | **460800** (domyślny EA) | firmware ma `GNSS_BAUD=460800`; fallback 115200 gdyby brak NMEA. Moduł do 3 Mbaud. |
| Format | 8N1 | |
| Logika | **3.3 V** | **NIE 5 V-tolerant** (VIHmax ≈ 3.08 V). ESP32 też 3.3 V → łączenie wprost OK. |
| NMEA (wyjście) | GGA, RMC, VTG, GSA, GSV, GLL | wybór przez `$PAIR062` (Type 0–5). **Brak GST na EA!** GGA=pozycja/fix, RMC/VTG=COG. |
| Dokładność | (brak GST) | szacuj z fixType+HDOP; opcjonalnie proprietarne `$PQTMEPE`, jeśli w strumieniu — patrz §6. |
| Fix rate | 1 Hz (domyślnie) / 10 Hz | `$PAIR050` na EA tylko 100 ms (10 Hz) lub 1000 ms (1 Hz); zmiana działa **po restarcie** modułu. |
| RTCM (wejście) | RTCM 3.x | **ten sam UART** co NMEA (full-duplex). |

Konfiguracja przy starcie (firmware `gnss_config`, już pod EA): `$PAIR062` (zdania NMEA),
`$PAIR050` (rate), `$PQTMCFGRCVRMODE,W,1` (rover), zapis `$PQTMSAVEPAR` (**nie** PAIR513).
Most ESP32 przepuszcza też zdania `$PQTM*`. Szczegóły: [`../firmware/README.md`](../firmware/README.md).

## 3. I2C (OLED + rezerwa IMU)

| Urządzenie | Adres I2C (typ.) | Status |
|---|---|---|
| OLED SSD1306 0,96" | 0x3C (lub 0x3D) | v1 |
| IMU BNO085 | 0x4A (lub 0x4B) | **v2** — w v1 tylko pady + linie SDA/SCL wyprowadzone |

Rezystory podciągające I2C: 4,7 kΩ do 3.3 V na SDA i SCL (jeśli moduły ich nie mają na pokładzie —
płytki OLED zwykle mają; sprawdź, żeby nie dublować zbyt niską rezystancją).

## 4. Pomiar napięcia baterii

- Dzielnik **R_góra = 100 kΩ, R_dół = 100 kΩ** (÷2): V_bat 4,2 V → 2,1 V na GPIO34 (bezpiecznie
  w zakresie ADC przy `ADC_ATTEN_DB_11`). 3,0 V → 1,5 V.
- **Kontrakt z firmware:** dzielnik ÷2 odpowiada fladze `BAT_DIVIDER_RATIO = 2.0` (domyślnej
  w `../firmware/`). Po pomiarze realnego dzielnika na sprzęcie skoryguj tę flagę.
- Kondensator **100 nF** z GPIO34 do GND (filtr / bufor S&H ADC).
- **Kalibracja:** użyj `esp_adc_cal` / eFuse Vref i uśredniaj próbki — ADC ESP32 jest nieliniowy
  (bez kalibracji błąd ±5–10%).
- Pobór dzielnika ~21 µA stale (4,2 V / 200 kΩ) — akceptowalny; przy walce o każdą µA można
  bramkować dzielnik MOSFET-em lub zwiększyć rezystory (wtedy dodaj kondensator dla ADC).
- Mapowanie % baterii: krzywa rozładowania Li-Ion (nieliniowa) — patrz [04-budzet-mocy.md](04-budzet-mocy.md).

## 5. Protokół BLE — usługa Nordic UART (NUS) + status

ESP32 = peryferium GATT. Nazewnictwo TX/RX **z perspektywy peryferium**.

### 5.1 Usługa NUS (surowy strumień)

| Element | UUID | Właściwość | Kierunek | Treść |
|---|---|---|---|---|
| Usługa NUS | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — | — | — |
| **RX** | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Write Without Response | telefon → ESP32 → UART | **surowy RTCM** (poprawki z NTRIP) |
| **TX** | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Notify | UART → ESP32 → telefon | **surowe NMEA** (GGA/RMC/GST…) |

- **MTU:** negocjuj **≥ 185 B** (cel **247 B**). Android domyślnie 23 B — bez negocjacji RTCM się dławi.
- **Fragmentacja:** strumienie NMEA/RTCM dziel na pakiety ≤ (MTU−3) B; po stronie odbiorcy sklejaj
  po znakach końca linii NMEA / po nagłówkach ramek RTCM.
- ESP32 **nie parsuje** strumienia w gorącej ścieżce — to „głupi most" (bufory ringowe UART↔BLE).

### 5.2 Charakterystyka „status" (telemetria) — ZAIMPLEMENTOWANA w firmware

> Sesja firmware **już to zaimplementowała** (`../firmware/`). Poniższe jest kontraktem zgodnym
> z [`../firmware/README.md`](../firmware/README.md) — **UUID i format są wiążące** (zaktualizowane
> 2026-06-13 po synchronizacji z sesją firmware; wcześniejsza propozycja 6E40FF0x nieaktualna).

Charakterystyka `status` to **4. charakterystyka w usłudze NUS** (rozszerzenie poza standard NUS):

| Element | UUID | Właściwość | Treść |
|---|---|---|---|
| Status | `6E400004-B5A3-F393-E0A9-E50E24DCCA9E` | **Read + Notify** | telemetria JSON, co 1 s |

Payload JSON (format firmware):

```json
{"bat_mv":3987,"bat_pct":74,"up_s":1234,"rtcm_bps":512,"ble_mtu":247,
 "fix":4,"sat":18,"hdop":0.82,"age":1.4}
```

| Pole | Znaczenie | Źródło w ESP32 |
|---|---|---|
| `bat_mv` / `bat_pct` | napięcie ogniwa [mV] / stan [%] (0 gdy pomiar wył.) | ADC + krzywa |
| `up_s` | uptime [s] | timer |
| `rtcm_bps` | przepływ RTCM telefon→moduł [B/s] | licznik mostu |
| `ble_mtu` | wynegocjowany ATT MTU | stos BLE |
| `fix` | jakość fixa wg GGA (0/1/2/4/5) | parser GGA |
| `sat` / `hdop` / `age` | satelity / HDOP / wiek poprawek [s] (`age=-1` = brak) | GGA |

- Nazwa rozgłaszana BLE: **`RTK-Rover`** (aplikacja znajduje urządzenie po UUID usługi).
- MTU: firmware prosi o **247 B**.

> ESP32 parsuje GGA **tylko** na potrzeby OLED/LED i tej telemetrii. Pozycję/dokładność/kurs
> aplikacja bierze z surowego NMEA na TX (`6E400003`) — `status` to wyłącznie telemetria urządzenia.

## 6. Zgodność z modelem danych aplikacji

Aplikacja buduje `RtkPosition` (`../app/lib/models/rtk_position.dart`) z **NMEA** odbieranego na TX:

| Pole `RtkPosition` | Zdanie NMEA | Mapowanie |
|---|---|---|
| `latitude` / `longitude` | GGA | pola pozycji |
| `altitude` | GGA | wysokość |
| `accuracy` (1σ, m) | **brak GST na EA** | szacuj z `fixType`+HDOP (Fixed≈1–3 cm, Float≈dm); opcjonalnie `$PQTMEPE` |
| `fixType` (`FixType`) | GGA quality | 0→none, 1→gps, 2→dgps, **4→rtkFixed**, **5→rtkFloat** |
| `satellites` | GGA | liczba satelitów |
| `heading` | RMC/VTG (COG) | kurs nad ziemią (tylko podczas ruchu) |
| `timestamp` | GGA/RMC | czas UTC |

`FixType` w aplikacji już zgodny z numeracją GGA (4=Fixed, 5=Float) — firmware/most nie musi nic
przeliczać; przekazuje NMEA 1:1.

> **Uwaga (EA):** moduł EA **nie wystawia GST**, więc aplikacja nie ma gotowego błędu z σ lat/lon.
> Pole `accuracy` wyznaczaj z typu fixa + HDOP (RTK Fixed ≈ 1–3 cm, Float ≈ dm, DGPS/GPS gorzej),
> a jeśli w strumieniu pojawi się proprietarne `$PQTMEPE` (oszacowania błędu N/E/D) — użyj go.
> To ustalenie sesji firmware (wsparcie `$PQTMEPE` na EA bywa zależne od wersji firmware modułu).

## 7. Rezerwacje pod v2

- **IMU BNO085** na I2C (0x4A) + opcjonalnie piny INT/RST (np. GPIO25/26) — wyprowadź pady.
- **WiFi/NTRIP na ESP32** (tryb zapasowy z `../PROJEKT.md`) — nie wymaga pinów, tylko firmware;
  uwzględnij w budżecie mocy (szczyt TX WiFi ~240 mA) jeśli wejdzie.
- **USB-C z mostkiem CP2102** zintegrowanym na PCB (v2) — wtedy UART0 idzie na CP2102.
