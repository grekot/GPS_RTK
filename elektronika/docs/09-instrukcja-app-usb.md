# Instrukcja dla sesji aplikacji — źródło pozycji po USB (LC29HEA)

> Autor: sesja elektroniki. Adresat: **sesja aplikacji** (`../../app/`). Zadanie: dodać obsługę
> **bezpośredniego połączenia z modułem GPS LC29HEA przez USB** jako kolejne `PositionSource`.
> Kontekst sprzętu: [08-podlaczenie-stykowka.md](08-podlaczenie-stykowka.md) (wariant „test po USB"),
> [05-pinout-firmware.md](05-pinout-firmware.md), instrukcja płytki: [../datasheety/LC29H-mozi-board-manual-CN.pdf](../datasheety/LC29H-mozi-board-manual-CN.pdf).

## 1. Cel i uzasadnienie
Dodać **USB-serial GPS** (moduł LC29HEA przez USB-C / Android OTG) jako wymienne źródło pozycji,
obok GPS telefonu, odbiornika BLE i logów NMEA. Po co:
- **Najszybszy tor testowy/bring-up bez ESP32** — sam moduł GPS + kabel + telefon → RTK.
- Realna opcja w terenie na **Androidzie** (kabel OTG).
- Dane i tor NTRIP **identyczne jak w BLE** → mały, dobrze odgraniczony zakres.

## 2. Platforma
- **Android: TAK** (USB host / OTG; user-space sterownik dla CP2102/CH340/FTDI/PL2303).
- **iOS: NIE** (brak generycznego USB-serial dla aplikacji). Źródło **ukryj/wyłącz na iOS** —
  tam pozostaje BLE. Bramkuj `Platform.isAndroid`.
- Desktop — opcjonalnie; priorytet Android.

## 3. Kluczowa obserwacja: to klon `BleReceiverSource` z inną warstwą transportu
[`app/lib/sources/ble_receiver_source.dart`](../../app/lib/sources/ble_receiver_source.dart) jest
**gotowym wzorcem**. Parsowanie i NTRIP są **już transport-agnostyczne** — NIE pisz ich od nowa:
- `NmeaParser` ([`app/lib/rtk/nmea_parser.dart`](../../app/lib/rtk/nmea_parser.dart)) —
  `addLine(String) → RtkPosition?` (GGA/GST/RMC, suma kontrolna, `estimateAccuracy(fix,hdop)` gdy brak
  GST — **LC29HEA nie wysyła GST**, to już obsłużone). Plus `buildGgaSentence(...)`.
- `NtripClient` ([`app/lib/rtk/ntrip_client.dart`](../../app/lib/rtk/ntrip_client.dart)) —
  `NtripClient(cfg, onRtcm:, onStatus:)`, `start/stop/sendGga`. `NtripConfig` ten sam.

**BLE-specyficzne (do zamiany na USB) są tylko 3 rzeczy:**
1. skan + połączenie (FlutterBluePlus) → **wykrycie i otwarcie portu USB-serial**,
2. subskrypcja char TX (`onValueReceived`) → **strumień odczytu z portu** (te same bajty NMEA),
3. `_writeRtcm` do char RX → **zapis RTCM do portu**.

Cała reszta z BLE (buforowanie linii `_onNmeaBytes`, `_maybeStartNtrip`, timer GGA, `ntripConfig`,
`statusMessages`, zimny `StreamController` w `positions()`) — **przenosi się 1:1**.

## 4. Implementacja: `UsbReceiverSource implements PositionSource`
Nowy plik `app/lib/sources/usb_receiver_source.dart`, wzorowany na `BleReceiverSource`:

```dart
class UsbReceiverSource implements PositionSource {
  @override
  String get name => 'Odbiornik RTK (USB)';

  NtripConfig? ntripConfig;                 // jak w BLE
  final _status = StreamController<String>.broadcast();
  Stream<String> get statusMessages => _status.stream;

  final _parser = NmeaParser();             // współdzielony
  final StringBuffer _lineBuf = StringBuffer();
  // ... port, NtripClient?, Timer? ggaTimer, RtkPosition? last (jak w BLE)

  @override
  Stream<RtkPosition> positions() {
    late final StreamController<RtkPosition> ctrl;
    ctrl = StreamController<RtkPosition>(
      onListen: () => _connect(ctrl),       // otwórz port, podłącz odczyt
      onCancel: _disconnect,                // zamknij port, stop NTRIP
    );
    return ctrl.stream;
  }
  // _onNmeaBytes / _maybeStartNtrip / timer GGA / _disconnect — skopiuj z BLE.
}
```

- **`_connect`:** znajdź urządzenie USB-serial, poproś o uprawnienie, otwórz **115200, 8N1, bez
  flow control**, podłącz `inputStream` do `_onNmeaBytes(bytes, ctrl)` (skopiuj buforowanie linii
  z BLE), zawołaj `_maybeStartNtrip()`.
- **`_writeRtcm(rtcm)`:** `port.write(Uint8List.fromList(rtcm))` — **bez ograniczenia MTU** (USB
  uciągnie całość; ewentualnie dziel na kawałki, ale nie trzeba jak w BLE).
- **Telemetria:** USB nie ma charakterystyki „status" `6E400004` → nie ma `DeviceTelemetry`.
  Status fixa/satelitów i tak masz z NMEA; strumień telemetrii po prostu pomiń (albo zostaw pusty).

> (Opcjonalnie) Można wynieść wspólne fragmenty (line-buffer, timer GGA, wiring NTRIP) z BLE i USB do
> mixina/util, ale **priorytet: nie zmieniać zachowania `BleReceiverSource`** ani kontraktu `PositionSource`.

## 5. Plugin i parametry
- Dodaj do `pubspec.yaml`: **`usb_serial`** (pub.dev) — obsługuje CP2102/CH340/FTDI/PL2303, sam
  prosi o uprawnienie USB na Androidzie.
- API (orientacyjnie): `UsbSerial.listDevices()`, `device.create()`, `port.open()`,
  `port.setPortParameters(115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE)`,
  `port.inputStream.listen(...)`, `port.write(bytes)`.
- **Baud domyślny 115200** (instrukcja zamówionej płytki). Wystaw jako **ustawienie** (np. w
  `AppSettings`/`settings_screen.dart`) — inne moduły LC29HEA bywają 460800.

## 6. Android — manifest/uprawnienia
- Uprawnienie do urządzenia USB przyznawane **runtime** (dialog systemowy — `usb_serial` to obsługuje).
- Opcjonalnie w `AndroidManifest.xml`: `<uses-feature android:name="android.hardware.usb.host"/>`
  oraz intent-filter `android.hardware.usb.action.USB_DEVICE_ATTACHED` z `device_filter`
  (VID **CP2102 = 0x10C4**, **CH340 = 0x1A86**) — automatyczne wykrycie po podpięciu (nice-to-have).
- Wymaga **kabla OTG** i telefonu z USB host.

## 7. UI / UX
- Dodaj **„Odbiornik RTK (USB)"** do selektora źródeł (tam, gdzie rejestrowane są GPS telefonu /
  BLE / log). **Pokazuj tylko na Androidzie**; na iOS ukryj lub oznacz „niedostępne — użyj BLE".
- Reszta UI bez zmian: ekran statusu (fix/sats/dokładność/wiek), konfiguracja NTRIP, mock location —
  te same `RtkPosition` i `NtripConfig`.
- UX: USB = kabel od modułu do telefonu (mniej wygodne w terenie niż BLE) → to głównie **test/bench
  + opcja awaryjna**; BLE pozostaje docelowym bezprzewodowym torem.

## 8. Sprzęt (zakomunikuj użytkownikowi w UI/onboardingu)
- Przełączniki na płytce GPS: **oba w PRAWO = USB-C (Type-C)** → praca po USB; w LEWO = UART (do ESP32).
- **Baud 115200.** Antena L1/L5 + ground plane, odkryte niebo (warunek RTK Fixed).

## 9. Kryteria odbioru
1. Po OTG + podpięciu modułu (Type-C) aplikacja wykrywa urządzenie, prosi o uprawnienie, otwiera 115200.
2. `positions()` emituje `RtkPosition` z poprawnym `fixType` (gps/dgps/rtkFloat/rtkFixed), satelitami,
   dokładnością (z `estimateAccuracy`, bo brak GST).
3. Po konfiguracji NTRIP (ASG-EUPOS) i odkrytym niebie: **Single → Float → RTK Fixed** (fix=4).
4. **Parytet z BLE** — te same dane na ekranie statusu i mapie.
5. Na **iOS** źródło nie jest oferowane; BLE/GPS-telefonu/log działają bez zmian.

## 10. Czego nie psuć
- USB jest **dodatkiem**. Nie zmieniaj kontraktu `PositionSource`, zachowania `BleReceiverSource`,
  ani API `NmeaParser`/`NtripClient`/`RtkPosition`. Build na iOS musi się kompilować (bramkuj
  USB kodem platformowym, by `usb_serial` nie wymagał niczego na iOS).

## 11. Pliki referencyjne (w `app/lib/`)
`sources/ble_receiver_source.dart` (wzorzec), `sources/position_source.dart`, `sources/phone_gnss_source.dart`,
`rtk/nmea_parser.dart`, `rtk/ntrip_client.dart`, `models/rtk_position.dart`, `models/device_telemetry.dart`,
`services/app_settings.dart`, `screens/settings_screen.dart`.
