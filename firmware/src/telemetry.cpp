#include "telemetry.h"
#include <stdio.h>

int buildStatusJson(char *out, size_t cap, int batMv, int batPct,
                    uint32_t upSeconds, uint32_t rtcmBps, uint16_t mtu,
                    const GnssStatus &st) {
  return snprintf(out, cap,
                  "{\"bat_mv\":%d,\"bat_pct\":%d,\"up_s\":%lu,\"rtcm_bps\":%lu,"
                  "\"ble_mtu\":%u,\"fix\":%u,\"sat\":%u,\"hdop\":%.2f,\"age\":%.1f}",
                  batMv, batPct, (unsigned long)upSeconds, (unsigned long)rtcmBps,
                  (unsigned)mtu, (unsigned)(st.valid ? st.fixQuality : 0),
                  (unsigned)st.satellites, st.hdop, st.ageCorr);
}
