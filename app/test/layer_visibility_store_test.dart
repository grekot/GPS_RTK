import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gps_rtk_app/services/layer_visibility_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('brak zapisu → pusty zbiór (wszystko widoczne)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LayerVisibilityStore().load(), isEmpty);
  });

  test('round-trip: ukryte warstwy przeżywają restart aplikacji', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LayerVisibilityStore();
    await store.save({'parcel:120205_2.0001.222/1', 'utilities'});
    // Nowa instancja = symulacja ponownego uruchomienia.
    expect(await LayerVisibilityStore().load(),
        {'parcel:120205_2.0001.222/1', 'utilities'});
  });

  test('zapis pustego zbioru czyści ukrycia', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LayerVisibilityStore();
    await store.save({'building:b1'});
    await store.save({});
    expect(await store.load(), isEmpty);
  });
}
