#pragma once
// =============================================================================
// Shim "Arduino.h" WYŁĄCZNIE dla natywnego buildu na PC (katalog sim/).
// Pozwala skompilować prawdziwe pliki firmware (gnss_status.cpp, status_led.cpp,
// telemetry.cpp) zwykłym g++, bez rdzenia Arduino/ESP32.
//
// Świadomie NIE definiuje makra ARDUINO — dzięki temu fragmenty sprzętowe
// firmware (#ifdef ARDUINO, np. pinMode/digitalWrite/Serial2) są pomijane,
// a kompiluje się tylko logika niezależna od sprzętu.
// =============================================================================
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>

#define F(x) (x)

// Wirtualny zegar sterowany przez harness (definicja w device_sim.cpp).
unsigned long millis();
