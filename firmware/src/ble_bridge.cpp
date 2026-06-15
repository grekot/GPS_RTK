// W buildzie testowym SPP (BUILD_SPP) most BLE jest wyłączony — patrz spp_bridge.cpp.
// #include NimBLE jest WEWNĄTRZ guardu, żeby build SPP nie ciągnął stosu NimBLE.
#if !defined(BUILD_SPP)

#include "ble_bridge.h"
#include "config.h"
#include "uart_link.h"
#include <NimBLEDevice.h>

// Stan współdzielony z taskiem hosta BLE (callbacki) -> volatile.
static volatile bool s_connected = false;
static volatile uint16_t s_mtu = 23;  // ATT MTU domyślny zanim klient podbije
static volatile uint32_t s_rtcmBytes = 0;

static NimBLECharacteristic *s_txChar = nullptr;      // NMEA notify
static NimBLECharacteristic *s_statusChar = nullptr;  // telemetria

// --- Callbacki serwera: połączenie / rozłączenie / zmiana MTU ---------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo) override {
    s_connected = true;
  }
  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo, int reason) override {
    s_connected = false;
    s_mtu = 23;
    NimBLEDevice::startAdvertising();  // wznów rozgłaszanie po rozłączeniu
  }
  void onMTUChange(uint16_t MTU, NimBLEConnInfo &connInfo) override {
    s_mtu = MTU;
  }
};

// --- Callback RX: surowe RTCM od telefonu -> UART modułu --------------------
class RxCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo &connInfo) override {
    NimBLEAttValue v = pCharacteristic->getValue();
    if (v.length() > 0) {
      uartLinkWriteRtcm(v.data(), v.length());
      s_rtcmBytes += v.length();
    }
  }
};

void bleBridgeBegin() {
  NimBLEDevice::init(BLE_DEVICE_NAME);
  NimBLEDevice::setMTU(BLE_MTU_TARGET);  // poproś o większy MTU (klient i tak decyduje)

  NimBLEServer *server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService *svc = server->createService(NUS_SERVICE_UUID);

  s_txChar = svc->createCharacteristic(NUS_TX_UUID, NIMBLE_PROPERTY::NOTIFY);

  NimBLECharacteristic *rxChar = svc->createCharacteristic(
      NUS_RX_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rxChar->setCallbacks(new RxCallbacks());

  s_statusChar = svc->createCharacteristic(
      STATUS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  // W NimBLE 2.x usługi startują automatycznie wraz z serwerem (svc->start()
  // jest przestarzałe i nie ma efektu) — uruchamiamy rozgłaszanie.
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(NUS_SERVICE_UUID);
  adv->setName(BLE_DEVICE_NAME);
  adv->enableScanResponse(true);
  NimBLEDevice::startAdvertising();
}

void bleBridgeSendNmea(const uint8_t *data, size_t len) {
  if (!s_connected || s_txChar == nullptr) return;
  // Notify mieści się w pojedynczym pakiecie ATT: MTU - 3 bajty narzutu.
  uint16_t mtu = s_mtu;
  size_t maxChunk = (mtu > 3) ? (size_t)(mtu - 3) : 20;
  size_t off = 0;
  while (off < len) {
    size_t n = (len - off < maxChunk) ? (len - off) : maxChunk;
    s_txChar->setValue(data + off, n);
    s_txChar->notify();
    off += n;
  }
}

void bleBridgeSendStatus(const char *json) {
  if (s_statusChar == nullptr) return;
  s_statusChar->setValue((const uint8_t *)json, strlen(json));  // dostępne też przez READ
  if (s_connected) s_statusChar->notify();
}

bool bleBridgeConnected() { return s_connected; }

uint16_t bleBridgeMtu() { return s_mtu; }

uint32_t bleBridgeTakeRtcmBytes() {
  uint32_t v = s_rtcmBytes;
  s_rtcmBytes = 0;  // drobny wyścig z callbackiem akceptowalny dla telemetrii
  return v;
}

#endif  // !BUILD_SPP
