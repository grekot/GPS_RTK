#include "gnss_config.h"
#include "config.h"
#include <Arduino.h>

#if ENABLE_GNSS_CONFIG

// Wysyła proprietarne zdanie NMEA: "$" + body + "*" + suma_kontrolna + CRLF.
// body np. "PAIR050,1000" (bez znaków '$' i '*'). Sumę liczymy sami.
static void sendNmeaCmd(const char *body) {
  uint8_t cs = 0;
  for (const char *p = body; *p; ++p) cs ^= (uint8_t)*p;
  char out[96];
  snprintf(out, sizeof(out), "$%s*%02X\r\n", body, cs);
  Serial2.print(out);
  delay(100);  // odstęp na odpowiedź modułu ($PAIR001 / $PQTM...) między komendami
}

// Konfiguracja modułu LC29HEA (wariant EA) przy starcie. Komendy zweryfikowane:
//  - PAIR050 / PAIR062 — oficjalna "LC29H&LC79H Series GNSS Protocol Specification" v1.1,
//  - PQTM*             — artykuł rtklibexplorer (konfiguracja testowana na realnym LC29HEA).
//
// Uwaga o dokładności: EA NIE wysyła zdania GST (spec: na EA <Type> w PAIR062 to tylko 0..5).
// Dokładność pozycji bierz z typu fixa + HDOP (lub z $PQTMEPE, jeśli dane firmware EA je daje —
// to niepewne między wersjami). Patrz README, sekcja M8.
void gnssConfigApply() {
  // (1) Tryb rover RTK. EA jest roverem sprzętowo, więc to potwierdzenie ustawienia
  //     domyślnego. Zmiana trybu (np. na bazę) wymaga zapisu + restartu — patrz (4).
  sendNmeaCmd("PQTMCFGRCVRMODE,W,1");

  // (2) Wybór zdań NMEA. EA: <Type> tylko 0..5, <OutputRate> tylko 0 (off) lub 1 (on).
  //     Działa od razu (bez restartu). Zostawiamy minimalny zestaw dla aplikacji.
  sendNmeaCmd("PAIR062,0,1");  // GGA on  — pozycja, typ fixa, satelity, HDOP, wiek poprawek
  sendNmeaCmd("PAIR062,4,1");  // RMC on  — UTC + kurs nad ziemią (COG)
  sendNmeaCmd("PAIR062,1,0");  // GLL off
  sendNmeaCmd("PAIR062,2,0");  // GSA off
  sendNmeaCmd("PAIR062,3,0");  // GSV off — oszczędzamy pasmo BLE (sat. count i tak jest w GGA)
  sendNmeaCmd("PAIR062,5,0");  // VTG off — COG jest już w RMC

  // (3) Częstotliwość pozycji. EA: <Time> tylko 100 (10 Hz) lub 1000 (1 Hz), domyślnie 1000.
  //     Na EA zmiana działa dopiero po restarcie modułu (więc bez (4) to potwierdzenie 1 Hz).
  sendNmeaCmd("PAIR050,1000");  // 1 Hz — wystarcza do tyczenia, mniej ruchu po BLE

  // (4) Zapis do pamięci nieulotnej modułu. Odkomentuj, gdy zmieniasz tryb (1) lub
  //     częstotliwość (3) na wartość inną niż domyślna — na EA zadziała po restarcie.
  //     Domyślnie pomijamy, by nie zużywać flasha modułu przy każdym starcie ESP32.
  // sendNmeaCmd("PQTMSAVEPAR");
}

#else  // ENABLE_GNSS_CONFIG == 0

void gnssConfigApply() {
  // Konfiguracja wyłączona — most przezroczysty, ustawienia modułu bez zmian.
}

#endif
