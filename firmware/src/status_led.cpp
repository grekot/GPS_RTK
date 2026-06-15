#include "status_led.h"
#include "config.h"

// Wzorzec bezstanowy: wynik zależy tylko od czasu i typu fixa. Wydzielony, by
// dało się go testować na PC (sim/) bez sprzętu GPIO.
bool statusLedLevel(uint8_t fixQuality, uint32_t now) {
  switch (fixQuality) {
    case 4:  // RTK Fixed
      return true;  // światło ciągłe
    case 5:  // RTK Float
      return (now % 250) < 125;  // ~4 Hz
    case 1:  // GPS
    case 2:  // DGPS
      return (now % 1000) < 500;  // 1 Hz
    default:  // brak fixa
      return (now % 2000) < 60;  // krótki błysk co 2 s
  }
}

#ifdef ARDUINO  // część sprzętowa — tylko w buildzie firmware (nie w sim/)

void statusLedBegin() {
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
}

void statusLedTick(uint8_t fixQuality) {
  digitalWrite(LED_PIN, statusLedLevel(fixQuality, millis()) ? HIGH : LOW);
}

#endif  // ARDUINO
