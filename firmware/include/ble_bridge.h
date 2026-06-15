#pragma once
#include <Arduino.h>
// =============================================================================
// ble_bridge — Nordic UART Service (NUS) na NimBLE-Arduino 2.x.
//   TX (notify)  : strumień NMEA  ESP32 -> telefon  (chunkowane wg MTU)
//   RX (write)   : strumień RTCM  telefon -> ESP32  (zapis prosto do UART modułu)
//   status (R+N) : telemetria JSON (rozszerzenie poza NUS)
// Kontrakt UUID/profilu w config.h — zgodny z aplikacją (ble_receiver_source.dart).
// =============================================================================

// Inicjalizacja stosu BLE, usługi NUS i rozgłaszania.
void bleBridgeBegin();

// Wyślij porcję NMEA do telefonu (notify na TX). Dzieli na paczki <= MTU-3.
void bleBridgeSendNmea(const uint8_t *data, size_t len);

// Wyślij telemetrię JSON (ustawia wartość do READ i notify, jeśli połączono).
void bleBridgeSendStatus(const char *json);

bool bleBridgeConnected();

// Wynegocjowany ATT MTU (23 dopóki klient nie podbije).
uint16_t bleBridgeMtu();

// Liczba bajtów RTCM odebranych od ostatniego wywołania (zeruje licznik) —
// do wyliczenia przepływu B/s w telemetrii.
uint32_t bleBridgeTakeRtcmBytes();
