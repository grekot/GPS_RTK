import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/measured_point.dart';
import '../models/rtk_position.dart';
import '../utils/pl2000.dart';

/// Raport PDF z tyczenia: tabela zmierzonych punktów z odchyłką od punktu
/// ewidencyjnego, współrzędnymi WGS84/PL-2000 i jakością pomiaru.
class StakeoutReportPdf {
  static Future<Uint8List> build({
    required String title,
    required List<MeasuredPoint> points,
    DateTime? date,
  }) async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final medium =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: medium);
    final d = date ?? DateTime.now();
    final fixed =
        points.where((p) => p.worstFix == FixType.rtkFixed).length;

    final doc = pw.Document(theme: theme, title: 'Raport tyczenia');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 40),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Strona ${ctx.pageNumber}/${ctx.pagesCount}',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('Raport tyczenia',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          pw.Text(
            'Data: ${_fmtDate(d)}   ·   Punktów: ${points.length}'
            '   ·   RTK Fixed: $fixed/${points.length}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          if (points.isEmpty)
            pw.Paragraph(text: 'Brak zmierzonych punktów.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              headers: const [
                'Nr',
                'Szer. [°]',
                'Dług. [°]',
                'Y2000 [m]',
                'X2000 [m]',
                'Δ [m]',
                'N [m]',
                'E [m]',
                'RMS [m]',
                'Fix',
              ],
              data: [for (final p in points) _row(p)],
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Uwaga: pomiary mają charakter informacyjny i nie zastępują '
            'czynności geodety uprawnionego (rozgraniczenie, wznowienie znaków). '
            'Końcowa niepewność zależy od dokładności punktów ewidencyjnych '
            '(BPP) oraz warunków odbioru GNSS.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static List<String> _row(MeasuredPoint p) {
    final pl = Pl2000.fromLatLon(p.latitude, p.longitude);
    return [
      p.label ?? p.id,
      p.latitude.toStringAsFixed(7),
      p.longitude.toStringAsFixed(7),
      pl.easting.toStringAsFixed(2),
      pl.northing.toStringAsFixed(2),
      p.devDistance?.toStringAsFixed(3) ?? '–',
      p.devNorth?.toStringAsFixed(3) ?? '–',
      p.devEast?.toStringAsFixed(3) ?? '–',
      p.rms.toStringAsFixed(3),
      fixLabel(p.worstFix),
    ];
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
