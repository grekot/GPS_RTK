// =============================================================================
// Natywny symulator odbiornika (PC/Windows). Karmi PRAWDZIWY parser firmware
// (gnss_status.cpp) strumieniem NMEA jak z modułu LC29HEA i sprawdza wynik —
// plus czyste funkcje firmware: statusLedLevel(), buildStatusJson(),
// displayFixLabel(). Rysuje też ASCII-owy podgląd ekranu OLED (układ 1:1 z
// display.cpp::displayTick — te same pola, etykiety i reguły).
//
// To NIE jest kopia logiki: linkujemy te same pliki .cpp co firmware ESP32.
// Radia BLE/SPP ani pikseli U8g2 nie da się tu odtworzyć — testujemy „mózg"
// i TREŚĆ ekranu. Budowanie i uruchomienie: kliknij run-sim.bat (patrz README).
// =============================================================================
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include "config.h"        // LINK_LABEL ("BLE" w tym buildzie)
#include "gnss_status.h"
#include "status_led.h"
#include "telemetry.h"
#include "display.h"        // displayFixLabel()

// --- wirtualny zegar; millis() jest deklarowane w shimie sim/Arduino.h ---
static unsigned long g_now_ms = 0;
unsigned long millis() { return g_now_ms; }

// Składa pełne zdanie NMEA "$"+body+"*"+suma+CRLF (suma liczona poprawnie).
static void nmea(char *out, size_t cap, const char *body) {
  uint8_t cs = 0;
  for (const char *p = body; *p; ++p) cs ^= (uint8_t)*p;
  snprintf(out, cap, "$%s*%02X\r\n", body, cs);
}

static const char *ledLabel(uint8_t f) {
  switch (f) {
    case 4: return "ciagle";
    case 5: return "miga ~4Hz";
    case 1:
    case 2: return "miga 1Hz";
    default: return "blysk co 2s";
  }
}
static bool approx(double a, double b) { return fabs(a - b) < 0.051; }

// --- Podgląd OLED 128x64 jako ASCII (układ 1:1 z display.cpp::displayTick) ---
static void oledLine(const char *s) { printf("    | %-24s |\n", s); }

static void drawOled(const GnssStatus &st, int batPct, bool linkUp, uint16_t mtu) {
  char top[40], bat[16], l3[40], l4[40], age[14];

  snprintf(bat, sizeof(bat), "bat %d%%", batPct);
  const char *lbl = linkUp ? LINK_LABEL : "---";
  int pad = 24 - (int)strlen(lbl) - (int)strlen(bat);
  if (pad < 1) pad = 1;
  snprintf(top, sizeof(top), "%s%*s%s", lbl, pad, "", bat);  // pasek: lewo + prawo

  snprintf(l3, sizeof(l3), "Sat %d  HDOP %.1f", st.satellites, st.hdop);

  if (st.ageCorr >= 0) snprintf(age, sizeof(age), "Age %.1fs", st.ageCorr);
  else snprintf(age, sizeof(age), "Age --");
  if (mtu > 0) snprintf(l4, sizeof(l4), "%s  MTU %u", age, mtu);
  else snprintf(l4, sizeof(l4), "%s", age);

  printf("    +%.*s+\n", 26, "--------------------------------");
  oledLine(top);
  oledLine(displayFixLabel(st));  // duża etykieta fixa (prawdziwa funkcja firmware)
  oledLine(l3);
  oledLine(l4);
  printf("    +%.*s+\n", 26, "--------------------------------");
}

struct Epoch {
  uint8_t fix;
  uint8_t sat;
  double hdop;
  double age;  // <0 = brak poprawek (puste pole w GGA)
  const char *note;
};

int main() {
  // Scenariusz: zimny start -> 3D autonomiczne -> (RTCM z NTRIP) -> Float ->
  // RTK Fixed -> starzenie poprawek -> spadek z powrotem do Float.
  static const Epoch SC[] = {
      {0, 4, 9.9, -1, "zimny start, brak fixa"},
      {1, 7, 2.1, -1, "pozycja autonomiczna (3D)"},
      {1, 10, 1.6, -1, "wiecej satelitow"},
      {1, 12, 1.4, -1, "czekam na RTCM..."},
      {5, 13, 1.2, 1.0, ">>> RTCM z NTRIP -> RTK Float"},
      {5, 15, 1.0, 2.0, "Float stabilizuje sie"},
      {4, 17, 0.8, 1.2, ">>> RTK FIXED (cm!)"},
      {4, 19, 0.7, 1.0, "Fixed, pelna liczba sat."},
      {4, 18, 0.8, 8.0, "wiek poprawek rosnie..."},
      {5, 16, 1.1, 14.0, "poprawki za stare -> spadek do Float"},
  };
  const int N = (int)(sizeof(SC) / sizeof(SC[0]));

  printf("=== Emulator LC29HEA -> ESP32: prawdziwy kod firmware na PC ===\n");
  printf("    parser gnss_status.cpp + OLED (display.cpp) + LED + telemetria JSON\n");

  int epochsOK = 0, logicOK = 0, logicTotal = 0;
  char line[160], body[140], agef[16], json[176];

  for (int i = 0; i < N; ++i) {
    const Epoch &e = SC[i];
    g_now_ms = (unsigned long)(i + 1) * 1000UL;

    if (e.age < 0) agef[0] = 0;
    else snprintf(agef, sizeof(agef), "%.1f", e.age);
    snprintf(body, sizeof(body),
             "GNGGA,123519.00,5006.0000,N,01956.0000,E,%u,%02u,%.1f,230.0,M,40.0,M,%s,0000",
             (unsigned)e.fix, (unsigned)e.sat, e.hdop, agef);
    nmea(line, sizeof(line), body);
    gnssStatusFeed((const uint8_t *)line, strlen(line));

    // Na epoce FIXED: test odporności — śmieciowe GGA (zła suma) i RMC nie mogą
    // zmienić statusu (parser ma odrzucić jedno i zignorować drugie).
    if (e.fix == 4 && i == 6) {
      const char *badBody = "GNGGA,123519.00,5006.0,N,01956.0,E,1,03,5.0,0,M,0,M,,0000";
      uint8_t bcs = 0;
      for (const char *p = badBody; *p; ++p) bcs ^= (uint8_t)*p;
      char badLine[160], rmcLine[160];
      snprintf(badLine, sizeof(badLine), "$%s*%02X\r\n", badBody, (uint8_t)(bcs ^ 0xFF));
      nmea(rmcLine, sizeof(rmcLine),
           "GNRMC,123519.00,A,5006.0000,N,01956.0000,E,0.06,77.5,051219,,,A");
      gnssStatusFeed((const uint8_t *)badLine, strlen(badLine));
      gnssStatusFeed((const uint8_t *)rmcLine, strlen(rmcLine));
      logicTotal++;
      if (gnssStatusGet().fixQuality == 4) {
        logicOK++;
        printf("\n[OK]  odrzucono GGA z bledna suma + zignorowano RMC (fix nadal 4)\n");
      } else {
        printf("\n[FAIL] smieciowe zdanie zepsulo status (fix=%u)\n",
               gnssStatusGet().fixQuality);
      }
    }

    const GnssStatus &st = gnssStatusGet();
    bool ageOK = (e.age < 0) ? (st.ageCorr < 0) : approx(st.ageCorr, e.age);
    bool ok = (st.fixQuality == e.fix) && (st.satellites == e.sat) &&
              approx(st.hdop, e.hdop) && ageOK;
    if (ok) epochsOK++;

    bool linkUp = (i >= 1);  // (symulowane) telefon laczy sie po ~2 s
    printf("\n--- t=%2lus  %s ---\n", g_now_ms / 1000, e.note);
    drawOled(st, 74, linkUp, 247);
    buildStatusJson(json, sizeof(json), 3950, 74, g_now_ms / 1000,
                    (e.fix == 4 || e.fix == 5) ? 512 : 0, 247, st);
    printf("    LED: %-11s status: %s\n", ledLabel(st.fixQuality), json);
    if (!ok)
      printf("    [FAIL] parser != oczekiwane (fix=%u sat=%u hdop=%.1f)\n",
             st.fixQuality, st.satellites, st.hdop);
  }

  // --- Testy czystej logiki LED (statusLedLevel z firmware) ---
  printf("\n");
  logicTotal++;
  if (statusLedLevel(4, 0) && statusLedLevel(4, 9999)) {
    logicOK++;
    printf("[OK]  LED: RTK Fixed = swiatlo ciagle\n");
  } else printf("[FAIL] LED Fixed nie jest ciagle\n");

  logicTotal++;
  if (statusLedLevel(5, 0) != statusLedLevel(5, 130)) {
    logicOK++;
    printf("[OK]  LED: RTK Float miga (zmienia stan)\n");
  } else printf("[FAIL] LED Float nie miga\n");

  logicTotal++;
  if (!statusLedLevel(0, 1000)) {
    logicOK++;
    printf("[OK]  LED: brak fixa = przewaznie zgaszony\n");
  } else printf("[FAIL] LED brak-fixa swieci ciagle\n");

  bool pass = (epochsOK == N) && (logicOK == logicTotal);
  printf("\n=== WYNIK: epoki %d/%d, testy logiki %d/%d -> %s ===\n", epochsOK, N,
         logicOK, logicTotal, pass ? "PASS" : "FAIL");
  return pass ? 0 : 1;
}
