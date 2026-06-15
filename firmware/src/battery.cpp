#include "battery.h"
#include "config.h"

static int s_mv = 0;
static int s_pct = 0;
static uint32_t s_lastSampleMs = 0;
static bool s_sampled = false;

// Przybliżona krzywa rozładowania Li-Ion (napięcie spoczynkowe -> %).
struct VPct {
  int mv;
  int pct;
};
static const VPct CURVE[] = {
    {4200, 100}, {4100, 90}, {4000, 80}, {3900, 65}, {3800, 50},
    {3700, 35},  {3600, 20}, {3500, 10}, {3300, 0},
};

static int mvToPct(int mv) {
  if (mv >= CURVE[0].mv) return 100;
  const int n = sizeof(CURVE) / sizeof(CURVE[0]);
  if (mv <= CURVE[n - 1].mv) return 0;
  for (int i = 0; i < n - 1; ++i) {
    if (mv <= CURVE[i].mv && mv > CURVE[i + 1].mv) {
      // interpolacja liniowa między punktami krzywej
      int dmv = CURVE[i].mv - CURVE[i + 1].mv;
      int dpct = CURVE[i].pct - CURVE[i + 1].pct;
      return CURVE[i + 1].pct + (mv - CURVE[i + 1].mv) * dpct / dmv;
    }
  }
  return 0;
}

void batteryBegin() {
  analogReadResolution(12);
  analogSetPinAttenuation(BAT_ADC_PIN, ADC_11db);  // pełny zakres ~0..3.1 V na pinie
}

void batteryTick() {
  uint32_t now = millis();
  if (s_sampled && (now - s_lastSampleMs < 1000)) return;
  s_lastSampleMs = now;
  s_sampled = true;

  uint32_t acc = 0;
  for (int i = 0; i < 8; ++i) acc += analogReadMilliVolts(BAT_ADC_PIN);
  int pinMv = (int)(acc / 8);
  s_mv = (int)(pinMv * BAT_DIVIDER_RATIO);
  s_pct = mvToPct(s_mv);
}

int batteryMilliVolts() { return s_mv; }
int batteryPercent() { return s_pct; }
