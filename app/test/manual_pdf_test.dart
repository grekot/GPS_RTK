import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/services/manual_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF instrukcji generuje się (nagłówek %PDF, niepusty)', () async {
    final bytes = await ManualPdf.build();
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF'));
  });
}
