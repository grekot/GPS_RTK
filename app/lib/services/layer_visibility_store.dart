import 'package:shared_preferences/shared_preferences.dart';

/// Trwała widoczność warstw mapy GŁÓWNEJ (klucze `parcel:id` / `building:id` /
/// `design:id` / `utilities`). Przechowuje zbiór warstw UKRYTYCH — brak wpisu
/// = wszystko widoczne (stan domyślny). Wcześniej wybór żył tylko w pamięci
/// ekranu i ginął przy każdym restarcie aplikacji.
class LayerVisibilityStore {
  static const _key = 'hiddenLayers.v1';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<void> save(Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [...hidden]..sort());
  }
}
