#pragma once
#include <Arduino.h>
// =============================================================================
// spp_bridge — most po Bluetooth Classic SPP (M7, wariant TESTOWY).
//
// Kompilowany TYLKO w środowisku esp32dev-spp (flaga BUILD_SPP). Pozwala
// przetestować cały tor (NMEA w górę, RTCM w dół) z gotowymi aplikacjami
// (SW Maps, Lefebure NTRIP) zanim powstanie własna aplikacja BLE.
//
// UWAGA: SPP (Bluedroid) i BLE (NimBLE) wykluczają się w jednym firmware —
// to osobny build. iOS nie obsługuje SPP; profil docelowy to BLE NUS.
// =============================================================================

void sppBridgeBegin();

// Wyślij porcję NMEA do aplikacji (strumień SPP).
void sppBridgeSendNmea(const uint8_t *data, size_t len);

// Odbierz RTCM z aplikacji i przekaż do UART modułu. Wołać w loop().
void sppBridgePoll();

bool sppBridgeConnected();
