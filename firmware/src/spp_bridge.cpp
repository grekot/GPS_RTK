// W buildzie domyślnym (BLE/NimBLE) ten moduł jest pusty — patrz ble_bridge.cpp.
// #include BluetoothSerial jest WEWNĄTRZ guardu, żeby build BLE nie ciągnął Bluedroid.
#if defined(BUILD_SPP)

#include "spp_bridge.h"
#include "config.h"
#include "uart_link.h"
#include "BluetoothSerial.h"

static BluetoothSerial s_bt;

void sppBridgeBegin() {
  // Urządzenie widoczne na liście Bluetooth pod nazwą jak w BLE.
  s_bt.begin(BLE_DEVICE_NAME);
}

void sppBridgeSendNmea(const uint8_t *data, size_t len) {
  if (s_bt.hasClient()) s_bt.write(data, len);
}

void sppBridgePoll() {
  // RTCM z aplikacji (SW Maps/Lefebure) -> UART modułu, partiami, bez modyfikacji.
  uint8_t buf[256];
  while (s_bt.available()) {
    size_t n = 0;
    while (s_bt.available() && n < sizeof(buf)) buf[n++] = (uint8_t)s_bt.read();
    if (n > 0) uartLinkWriteRtcm(buf, n);
  }
}

bool sppBridgeConnected() { return s_bt.hasClient(); }

#endif  // BUILD_SPP
