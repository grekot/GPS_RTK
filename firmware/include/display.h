#pragma once
#include <Arduino.h>
#include "gnss_status.h"
// =============================================================================
// display — OLED SSD1306 128x64 (I2C) ze statusem urządzenia.
// Wykrywa obecność wyświetlacza (probe I2C) — jego brak nie blokuje firmware.
// =============================================================================

// Etykieta typu fixa pokazywana na OLED ("WAIT"/"NO FIX"/"3D"/"DGPS"/"FLOAT"/"FIXED").
// Czysta i bez zależności sprzętowych — współdzielona z natywnym symulatorem (sim/).
const char *displayFixLabel(const GnssStatus &st);

void displayBegin();
bool displayPresent();

// Render statusu (wołać ~kilka razy/s). batPct/batMv = -1 gdy pomiar wyłączony.
void displayTick(const GnssStatus &st, int batPct, int batMv, bool bleConnected, uint16_t mtu);
