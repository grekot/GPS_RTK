import 'package:flutter/material.dart';

import '../services/app_settings.dart';

/// Ekran ustawień pomiaru/NTRIP. Zwraca true, gdy zapisano (by odświeżyć stan).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _samples = AppSettings.instance.samples;
  late bool _requireFixed = AppSettings.instance.requireFixed;
  late bool _keepAwake = AppSettings.instance.keepAwake;
  late int _gga = AppSettings.instance.ggaSeconds;
  late int _usbBaud = AppSettings.instance.usbBaud;

  Future<void> _save() async {
    await AppSettings(
      samples: _samples,
      requireFixed: _requireFixed,
      keepAwake: _keepAwake,
      ggaSeconds: _gga,
      usbBaud: _usbBaud,
    ).save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
        actions: [
          IconButton(
            tooltip: 'Zapisz',
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Liczba epok uśredniania'),
            subtitle: Text('$_samples próbek na punkt'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _samples.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              label: '$_samples',
              onChanged: (v) => setState(() => _samples = v.round()),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Wymagaj RTK Fixed'),
            subtitle: const Text(
                'Odrzucaj próbki gorsze niż Fixed (precyzyjniejszy pomiar).'),
            value: _requireFixed,
            onChanged: (v) => setState(() => _requireFixed = v),
          ),
          SwitchListTile(
            title: const Text('Nie wygaszaj ekranu'),
            subtitle: const Text('Ekran włączony podczas pomiaru w terenie.'),
            value: _keepAwake,
            onChanged: (v) => setState(() => _keepAwake = v),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Interwał GGA → NTRIP'),
            subtitle: Text('co $_gga s (sieci VRS wymagają pozycji)'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _gga.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_gga s',
              onChanged: (v) => setState(() => _gga = v.round()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Prędkość portu USB / COM'),
            subtitle: const Text(
                'Odbiornik RTK podłączony kablem (Android USB lub COM na PC). '
                'Nasza płytka LC29HEA: 460800.'),
            trailing: DropdownButton<int>(
              value: _usbBaud,
              items: [
                for (final b in AppSettings.usbBaudOptions)
                  DropdownMenuItem(value: b, child: Text('$b')),
              ],
              onChanged: (v) =>
                  v == null ? null : setState(() => _usbBaud = v),
            ),
          ),
        ],
      ),
    );
  }
}
