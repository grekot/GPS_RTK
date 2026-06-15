#include <Arduino.h>
#include "config.h"
#include "uart_link.h"
#if defined(BUILD_SPP)
#include "spp_bridge.h"  // wariant testowy (Bluetooth Classic SPP)
#else
#include "ble_bridge.h"  // wariant docelowy (BLE NUS)
#endif
#include "gnss_status.h"
#include "status_led.h"
#include "telemetry.h"
#include "gnss_config.h"
#if ENABLE_OLED
#include "display.h"
#endif
#if ENABLE_BATTERY
#include "battery.h"
#endif

// =============================================================================
// Odbiornik GPS RTK — ESP32 jako most UART<->BLE (NimBLE NUS).
//
//   LC29HEA ──UART(NMEA)──► ESP32 ──BLE notify──► telefon
//      ▲                       │                     │
//      └────UART(RTCM)─────────┘  ◄──BLE write───────┘ (RTCM z castera NTRIP)
//
// Most jest „głupi": surowe NMEA w górę, surowe RTCM w dół. GGA parsujemy tylko
// na potrzeby statusu (LED/OLED/telemetria). Szczegóły: INSTRUKCJA-AGENTA.md.
// =============================================================================

static uint8_t s_nmeaBuf[256];
#if ENABLE_STATUS_CHAR && !defined(BUILD_SPP)
static uint32_t s_lastStatusMs = 0;
#endif
#if ENABLE_OLED
static uint32_t s_lastDisplayMs = 0;
#endif

void setup() {
  Serial.begin(USB_BAUD);
  delay(50);
  Serial.println(F("[GPS_RTK] Start — most UART<->BLE"));

  statusLedBegin();
  uartLinkBegin(GNSS_BAUD);
  gnssConfigApply();  // no-op, dopóki ENABLE_GNSS_CONFIG=0

#if ENABLE_BATTERY
  batteryBegin();
#endif
#if ENABLE_OLED
  displayBegin();
  Serial.printf("[GPS_RTK] OLED: %s\n", displayPresent() ? "wykryty" : "brak");
#endif

#if defined(BUILD_SPP)
  sppBridgeBegin();
  Serial.println(F("[GPS_RTK] Bluetooth SPP gotowy (wariant testowy)"));
#else
  bleBridgeBegin();
  Serial.println(F("[GPS_RTK] BLE NUS rozglasza sie; most gotowy"));
#endif
}

void loop() {
  // 1) NMEA z modułu -> telefon (notify) + parser statusu.
  size_t n = uartLinkReadNmea(s_nmeaBuf, sizeof(s_nmeaBuf));
  if (n > 0) {
#if defined(BUILD_SPP)
    sppBridgeSendNmea(s_nmeaBuf, n);
#else
    bleBridgeSendNmea(s_nmeaBuf, n);
#endif
    gnssStatusFeed(s_nmeaBuf, n);
#if DEBUG_ECHO_NMEA
    Serial.write(s_nmeaBuf, n);
#endif
  }
#if defined(BUILD_SPP)
  sppBridgePoll();  // RTCM z SPP -> UART (w trybie BLE robi to callback RX)
#else
  // RTCM (telefon -> moduł) trafia do UART w callbacku BLE (ble_bridge.cpp).
#endif

  const GnssStatus &st = gnssStatusGet();
  statusLedTick(st.valid ? st.fixQuality : 0);

#if ENABLE_BATTERY
  batteryTick();
#endif

  uint32_t now = millis();

  // 2) OLED ~5 Hz.
#if ENABLE_OLED
  if (now - s_lastDisplayMs >= 200) {
    s_lastDisplayMs = now;
  #if defined(BUILD_SPP)
    bool linkUp = sppBridgeConnected();
    uint16_t linkMtu = 0;  // SPP nie ma negocjowanego MTU jak BLE — OLED pominie
  #else
    bool linkUp = bleBridgeConnected();
    uint16_t linkMtu = bleBridgeMtu();
  #endif
  #if ENABLE_BATTERY
    displayTick(st, batteryPercent(), batteryMilliVolts(), linkUp, linkMtu);
  #else
    displayTick(st, -1, -1, linkUp, linkMtu);
  #endif
  }
#endif

  // 3) Telemetria „status" (JSON) co 1 s.
#if ENABLE_STATUS_CHAR && !defined(BUILD_SPP)  // telemetria JSON tylko po BLE
  if (now - s_lastStatusMs >= 1000) {
    uint32_t dt = now - s_lastStatusMs;
    s_lastStatusMs = now;
    uint32_t rtcmBytes = bleBridgeTakeRtcmBytes();
    uint32_t bps = (dt > 0) ? (rtcmBytes * 1000UL / dt) : 0;
  #if ENABLE_BATTERY
    int mv = batteryMilliVolts(), pct = batteryPercent();
  #else
    int mv = 0, pct = 0;
  #endif
    char json[176];
    buildStatusJson(json, sizeof(json), mv, pct, now / 1000, bps,
                    bleBridgeMtu(), st);
    bleBridgeSendStatus(json);
  }
#endif

  // Oddaj CPU, gdy brak danych — zapobiega watchdogowi taska idle, nie dodaje
  // latencji do RTCM (obsługiwane w osobnym tasku BLE).
  if (n == 0) delay(1);
}
