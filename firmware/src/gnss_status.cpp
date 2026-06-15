#include "gnss_status.h"
#include <stdlib.h>
#include <string.h>

static GnssStatus s_status = {0, 0, 99.9f, -1.0f, false, 0};

// Bufor składania jednej linii NMEA (najdłuższe zdania ~82 znaki + zapas).
static char s_line[120];
static size_t s_lineLen = 0;

// Walidacja sumy kontrolnej NMEA: XOR bajtów między '$' a '*', porównany z hex po '*'.
static bool validChecksum(const char *s) {
  if (s[0] != '$') return false;
  const char *star = strchr(s, '*');
  if (!star || !isxdigit((int)star[1]) || !isxdigit((int)star[2])) return false;
  uint8_t cs = 0;
  for (const char *p = s + 1; p < star; ++p) cs ^= (uint8_t)*p;
  uint8_t given = (uint8_t)strtol(star + 1, nullptr, 16);
  return cs == given;
}

// Wyłuskuje pole o indeksie idx (0 = nagłówek „$..GGA") do out. Zwraca false,
// gdy pola nie ma. Pola pomiędzy przecinkami; '*' kończy część danych.
static bool field(const char *s, int idx, char *out, size_t outsz) {
  int f = 0;
  size_t o = 0;
  for (const char *p = s; *p; ++p) {
    if (*p == ',' || *p == '*') {
      if (f == idx) { out[o] = 0; return true; }
      if (*p == '*') return false;
      f++;
      o = 0;
      continue;
    }
    if (f == idx && o < outsz - 1) out[o++] = *p;
  }
  if (f == idx) { out[o] = 0; return true; }
  return false;
}

static void processLine(const char *s) {
  if (!validChecksum(s)) return;
  // Akceptujemy dowolny talker (GP/GN/GL/GA...), interesuje nas „GGA".
  if (strncmp(s + 3, "GGA", 3) != 0) return;

  char buf[12];
  if (field(s, 6, buf, sizeof(buf))) s_status.fixQuality = (uint8_t)atoi(buf);
  if (field(s, 7, buf, sizeof(buf))) s_status.satellites = (uint8_t)atoi(buf);
  if (field(s, 8, buf, sizeof(buf))) s_status.hdop = (float)atof(buf);
  if (field(s, 13, buf, sizeof(buf))) {
    s_status.ageCorr = (buf[0] != 0) ? (float)atof(buf) : -1.0f;
  } else {
    s_status.ageCorr = -1.0f;
  }
  s_status.valid = true;
  s_status.lastUpdateMs = millis();
}

void gnssStatusFeed(const uint8_t *data, size_t len) {
  for (size_t i = 0; i < len; ++i) {
    char c = (char)data[i];
    if (c == '\r' || c == '\n') {
      if (s_lineLen > 0) {
        s_line[s_lineLen] = 0;
        processLine(s_line);
        s_lineLen = 0;
      }
    } else if (s_lineLen < sizeof(s_line) - 1) {
      s_line[s_lineLen++] = c;
    } else {
      s_lineLen = 0;  // przepełnienie = śmieci, odrzuć linię
    }
  }
}

const GnssStatus &gnssStatusGet() { return s_status; }
