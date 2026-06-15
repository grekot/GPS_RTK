#pragma once
#include <stdint.h>
#include <stddef.h>
#include "gnss_status.h"
// =============================================================================
// telemetry — budowa ładunku JSON charakterystyki „status" (M6).
// Wydzielone z main.cpp jako czysta funkcja: ten sam format używa firmware
// (BLE) i natywny symulator (sim/), więc test sprawdza realny kod.
// =============================================================================

// Składa JSON statusu do bufora out (cap bajtów). Zwraca długość jak snprintf.
int buildStatusJson(char *out, size_t cap, int batMv, int batPct,
                    uint32_t upSeconds, uint32_t rtcmBps, uint16_t mtu,
                    const GnssStatus &st);
