#pragma once
#include <Arduino.h>
// =============================================================================
// battery — pomiar napięcia ogniwa Li-Ion przez dzielnik na GPIO34 (ADC1).
// Używa kalibrowanego analogReadMilliVolts() + uśredniania.
// =============================================================================

void batteryBegin();

// Wołać często; sam próbkuje co ~1 s (reszta wywołań to no-op).
void batteryTick();

int batteryMilliVolts();  // napięcie ogniwa [mV] (po korekcie dzielnika)
int batteryPercent();     // szacowany stan naładowania [0..100]
