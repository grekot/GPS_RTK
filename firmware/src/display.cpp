#include "display.h"
#include "config.h"

// Mapowanie typu fixa na etykietę OLED — czyste, współdzielone z sim/ (test bez sprzętu).
const char *displayFixLabel(const GnssStatus &st) {
  if (!st.valid) return "WAIT";
  switch (st.fixQuality) {
    case 1: return "3D";
    case 2: return "DGPS";
    case 4: return "FIXED";
    case 5: return "FLOAT";
    default: return "NO FIX";
  }
}

#ifdef ARDUINO  // warstwa sprzętowa (U8g2 / I2C) — pomijana w buildzie natywnym sim/

#include <Wire.h>
#include <U8g2lib.h>

// Pełny bufor ramki (1 KB RAM) — render bez migotania. Sprzętowe I2C.
static U8G2_SSD1306_128X64_NONAME_F_HW_I2C s_u8g2(U8G2_R0, U8X8_PIN_NONE);
static bool s_present = false;
static const uint8_t SSD1306_ADDR = 0x3C;

void displayBegin() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(400000);
  // Probe: czy SSD1306 odpowiada pod 0x3C?
  Wire.beginTransmission(SSD1306_ADDR);
  s_present = (Wire.endTransmission() == 0);
  if (!s_present) return;
  s_u8g2.setI2CAddress(SSD1306_ADDR << 1);
  s_u8g2.begin();
  s_u8g2.clearBuffer();
  s_u8g2.setFont(u8g2_font_6x12_tf);
  s_u8g2.drawStr(0, 12, "GPS RTK");
  s_u8g2.drawStr(0, 28, "start...");
  s_u8g2.sendBuffer();
}

bool displayPresent() { return s_present; }

void displayTick(const GnssStatus &st, int batPct, int batMv, bool bleConnected, uint16_t mtu) {
  if (!s_present) return;
  char buf[24];

  s_u8g2.clearBuffer();

  // Górny pasek: BLE/SPP + bateria
  s_u8g2.setFont(u8g2_font_6x12_tf);
  s_u8g2.drawStr(0, 10, bleConnected ? LINK_LABEL : "---");
  if (batPct >= 0) {
    snprintf(buf, sizeof(buf), "bat %d%%", batPct);
    s_u8g2.drawStr(128 - 6 * (int)strlen(buf), 10, buf);
  }

  // Typ fixa — duża czcionka
  s_u8g2.setFont(u8g2_font_logisoso16_tr);
  s_u8g2.drawStr(0, 34, displayFixLabel(st));

  // Szczegóły
  s_u8g2.setFont(u8g2_font_6x12_tf);
  snprintf(buf, sizeof(buf), "Sat %d  HDOP %.1f", st.satellites, st.hdop);
  s_u8g2.drawStr(0, 50, buf);

  // Dolna linia: wiek poprawek + (tylko BLE) wynegocjowany MTU.
  char age[14];
  if (st.ageCorr >= 0) snprintf(age, sizeof(age), "Age %.1fs", st.ageCorr);
  else snprintf(age, sizeof(age), "Age --");
  if (mtu > 0) snprintf(buf, sizeof(buf), "%s  MTU %u", age, mtu);
  else snprintf(buf, sizeof(buf), "%s", age);
  s_u8g2.drawStr(0, 62, buf);

  s_u8g2.sendBuffer();
}

#endif  // ARDUINO
