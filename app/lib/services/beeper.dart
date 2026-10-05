import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Sygnały dźwiękowe tyczenia.
///
/// `SystemSound.play(SystemSoundType.alert)` działa tylko na desktopie — na
/// Androidzie i iOS jest ignorowany, więc „na punkcie" było ciche. Na
/// Androidzie grają systemowe tony (`ToneGenerator`, kanał `gps_rtk/beep` w
/// `MainActivity.kt`); gdzie indziej zostaje dźwięk systemowy.
class Beeper {
  Beeper._();

  static const MethodChannel _channel = MethodChannel('gps_rtk/beep');

  /// Długi sygnał: użytkownik jest na punkcie.
  static void arrived() => _play('arrived');

  /// Krótki sygnał: zbliżenie (< 1 m).
  static void near() => _play('near');

  static void _play(String kind) {
    if (Platform.isAndroid) {
      unawaited(_channel
          .invokeMethod<void>('beep', {'kind': kind})
          .catchError((Object _) {/* brak kanału — trudno, jest wibracja */}));
    } else {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
  }
}
