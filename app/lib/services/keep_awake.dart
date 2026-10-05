import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_settings.dart';

/// Wspólna blokada wygaszania ekranu z licznikiem właścicieli.
///
/// Ekran główny (sesja Start) i ekrany terenowe (tyczenie, powierzchnia,
/// wytyczenie budynku) trzymają ją niezależnie. Ekran gaśnie dopiero, gdy
/// zwolni ją ostatni właściciel — wyjście z tyczenia nie wyłącza blokady
/// trwającej sesji, a wejście w tyczenie bez „Start" i tak ją włącza.
/// Respektuje ustawienie [AppSettings.keepAwake].
class KeepAwake {
  KeepAwake._();

  static final KeepAwake instance = KeepAwake._();

  /// Faktyczne przełączenie blokady — podmieniane w testach.
  static Future<void> Function(bool enable) apply =
      (enable) => WakelockPlus.toggle(enable: enable);

  final Set<Object> _owners = {};
  bool? _applied;

  bool get active => _owners.isNotEmpty && AppSettings.instance.keepAwake;

  void hold(Object owner) {
    _owners.add(owner);
    refresh();
  }

  void release(Object owner) {
    _owners.remove(owner);
    refresh();
  }

  /// Ponowna ocena po zmianie ustawienia „Nie wygaszaj ekranu".
  void refresh() {
    final want = active;
    if (want == _applied) return;
    _applied = want;
    unawaited(apply(want).catchError((Object _) {/* brak wtyczki (testy) */}));
  }
}
