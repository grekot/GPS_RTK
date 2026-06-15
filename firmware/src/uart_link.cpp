#include "uart_link.h"
#include "config.h"

void uartLinkBegin(uint32_t baud) {
  Serial2.begin(baud, SERIAL_8N1, GNSS_RX_PIN, GNSS_TX_PIN);
}

size_t uartLinkReadNmea(uint8_t *buf, size_t maxLen) {
  size_t n = 0;
  while (n < maxLen && Serial2.available()) {
    buf[n++] = (uint8_t)Serial2.read();
  }
  return n;
}

void uartLinkWriteRtcm(const uint8_t *data, size_t len) {
  // Przekazujemy bajt w bajt, bez modyfikacji (RTCM jest binarne).
  Serial2.write(data, len);
}
