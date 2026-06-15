#pragma once
#include <Arduino.h>
// =============================================================================
// status_led — LED statusu na GPIO2, sterowany typem fixa (nieblokująco).
//   brak fixa   : krótki „heartbeat" (żyje, ale brak pozycji)
//   GPS/DGPS    : wolne miganie (1 Hz)
//   RTK Float   : szybkie miganie (~4 Hz)
//   RTK Fixed   : światło ciągłe (cel osiągnięty)
// =============================================================================

// Czysta funkcja: czy LED ma świecić w chwili nowMs dla danego typu fixa.
// Bezstanowa i bez zależności sprzętowych — testowalna natywnie (sim/).
bool statusLedLevel(uint8_t fixQuality, uint32_t nowMs);

void statusLedBegin();

// Wołane często w loop(); fixQuality jak w GGA (0/1/2/4/5).
void statusLedTick(uint8_t fixQuality);
