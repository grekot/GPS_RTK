#pragma once
#include <Arduino.h>
// =============================================================================
// uart_link — dostęp do UART modułu GNSS (Serial2).
// Most jest „głupi": w górę przepompowujemy surowe NMEA, w dół surowe RTCM.
// =============================================================================

// Inicjalizacja UART2 na pinach GNSS_RX_PIN / GNSS_TX_PIN.
void uartLinkBegin(uint32_t baud);

// Odczyt dostępnych bajtów NMEA z modułu do bufora (nieblokujący).
// Zwraca liczbę odczytanych bajtów (0..maxLen).
size_t uartLinkReadNmea(uint8_t *buf, size_t maxLen);

// Zapis surowego RTCM do modułu (wołane z callbacku BLE — patrz ble_bridge).
void uartLinkWriteRtcm(const uint8_t *data, size_t len);
