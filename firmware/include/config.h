#pragma once
#include <stdint.h>  // typy uintN_t — config.h bywa dołączany przed <Arduino.h>
// =============================================================================
// Wspólna konfiguracja firmware odbiornika GPS RTK (ESP32 — most UART<->BLE).
//
// Piny zgodne z elektronika/INSTRUKCJA-AGENTA.md (sekcja „przypisanie pinów").
// Protokół BLE zgodny z app/lib/sources/ble_receiver_source.dart (kontrakt NUS).
//
// Wartości można nadpisać z platformio.ini przez build_flags (-D NAZWA=...),
// dlatego flagi opakowane są w #ifndef.
// =============================================================================

// ---- Prędkości UART --------------------------------------------------------
static const uint32_t USB_BAUD = 115200;   // monitor / logi diagnostyczne
// Domyślny baud LC29HEA (wariant EA, goły moduł) to 460800 — potwierdzone testami
// rtklibexplorer na realnym module. Gdyby NMEA nie pojawiało się w monitorze,
// spróbuj 115200 (część płytek/firmware startuje wolniej).
static const uint32_t GNSS_BAUD = 460800;  // UART do modułu LC29HEA

// ---- Piny ESP32 (WROOM-32) -------------------------------------------------
static const int GNSS_RX_PIN = 16;  // ESP32 RX2  <- TX modułu GNSS
static const int GNSS_TX_PIN = 17;  // ESP32 TX2  -> RX modułu GNSS
static const int I2C_SDA_PIN = 21;  // OLED/IMU
static const int I2C_SCL_PIN = 22;  // OLED/IMU
static const int BAT_ADC_PIN = 34;  // pomiar baterii (ADC1, input-only) przez dzielnik
static const int LED_PIN = 2;       // LED statusu (wbudowany na większości devkitów)

// ---- Protokół BLE — Nordic UART Service (KONTRAKT z aplikacją) -------------
// NIE zmieniaj jednostronnie. Patrz app/lib/sources/ble_receiver_source.dart.
#define BLE_DEVICE_NAME "RTK-Rover"
#define NUS_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // telefon -> ESP32: RTCM (write)
#define NUS_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // ESP32 -> telefon: NMEA (notify)

// Rozszerzenie projektowe (POZA standardem NUS): charakterystyka telemetrii.
// UWAGA: to nowy element kontraktu — ZGŁOSZONY do sesji aplikacji (patrz README).
#define STATUS_UUID "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"  // ESP32 -> telefon: status JSON (read+notify)

// Docelowy ATT MTU (Android domyślnie 23 B — za mało dla RTCM, prosimy o więcej).
static const uint16_t BLE_MTU_TARGET = 247;

// Etykieta transportu pokazywana na OLED ("SPP" w buildzie testowym esp32dev-spp).
#if defined(BUILD_SPP)
#define LINK_LABEL "SPP"
#else
#define LINK_LABEL "BLE"
#endif

// ---- Pomiar baterii --------------------------------------------------------
// Współczynnik dzielnika napięcia (Vbat / Vadc). 2.0 = dwa równe rezystory.
// Finalną wartość ustala sesja elektroniki — skoryguj po pomiarze.
#ifndef BAT_DIVIDER_RATIO
#define BAT_DIVIDER_RATIO 2.0f
#endif

// ---- Flagi funkcji (można nadpisać z platformio.ini) -----------------------
#ifndef ENABLE_OLED
#define ENABLE_OLED 1        // M5: wyświetlacz SSD1306
#endif
#ifndef ENABLE_BATTERY
#define ENABLE_BATTERY 1     // M6: pomiar baterii
#endif
#ifndef ENABLE_STATUS_CHAR
#define ENABLE_STATUS_CHAR 1 // M6: charakterystyka telemetrii „status" (JSON co 1 s)
#endif
#ifndef ENABLE_GNSS_CONFIG
#define ENABLE_GNSS_CONFIG 0 // M8: konfiguracja LC29HEA przy starcie (komendy do weryfikacji z kartą modułu!)
#endif
#ifndef DEBUG_ECHO_NMEA
#define DEBUG_ECHO_NMEA 0    // diagnostyka: echo NMEA na USB Serial (zaszumia monitor)
#endif
