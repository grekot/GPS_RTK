#pragma once
#include <Arduino.h>
// =============================================================================
// gnss_status — lekki parser zdań GGA WYŁĄCZNIE na potrzeby statusu (OLED/LED/
// telemetria). To NIE jest gorąca ścieżka danych — surowe NMEA i tak leci w
// całości do telefonu przez BLE, a aplikacja parsuje je u siebie.
// =============================================================================

struct GnssStatus {
  uint8_t fixQuality;    // pole „fix quality" z GGA: 0 brak, 1 GPS, 2 DGPS, 4 RTK Fixed, 5 RTK Float
  uint8_t satellites;    // liczba satelitów użytych w rozwiązaniu
  float hdop;            // poziomy DOP
  float ageCorr;         // wiek poprawek różnicowych [s], <0 gdy nieznany/brak
  bool valid;            // czy odebrano choć jedno poprawne GGA
  uint32_t lastUpdateMs; // millis() ostatniej aktualizacji
};

// Podaj kolejną porcję bajtów NMEA (składanie linii + parsowanie GGA wewnątrz).
void gnssStatusFeed(const uint8_t *data, size_t len);

// Bieżący status (kopia trzymana wewnętrznie).
const GnssStatus &gnssStatusGet();
