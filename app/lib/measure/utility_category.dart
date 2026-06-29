import 'package:flutter/painting.dart';

/// Kategoria medium uzbrojenia terenu dla zbieranych punktów.
enum UtilityCategory {
  woda('woda', 'Wodociąg', Color(0xFF1565C0)),
  kanalizacja('kanalizacja', 'Kanalizacja', Color(0xFF6D4C41)),
  gaz('gaz', 'Gaz', Color(0xFFF9A825)),
  energetyka('energetyka', 'Energetyka', Color(0xFFD32F2F)),
  telekom('telekom', 'Telekomunikacja', Color(0xFF00838F)),
  cieplo('cieplo', 'Ciepłownictwo', Color(0xFFEF6C00)),
  inne('inne', 'Inne', Color(0xFF455A64));

  const UtilityCategory(this.code, this.label, this.color);

  final String code;
  final String label;
  final Color color;

  static UtilityCategory? fromCode(String? code) {
    if (code == null) return null;
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
