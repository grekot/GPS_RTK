import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generator PDF z instrukcją użytkowania aplikacji (polskie znaki — Roboto).
class ManualPdf {
  static Future<Uint8List> build() async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final medium =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: medium);

    final doc = pw.Document(theme: theme, title: 'Instrukcja GPS RTK');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Strona ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('GPS RTK — instrukcja użytkowania',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Paragraph(
            text: 'Aplikacja współpracuje z odbiornikiem GNSS RTK (lub działa '
                'orientacyjnie na GPS telefonu). Służy do odszukiwania punktów '
                'granicznych działki, pomiaru własnych punktów oraz '
                'inwentaryzacji uzbrojenia terenu.',
          ),
          ..._section('1. Źródło pozycji', [
            'Ikona anteny (pasek górny) przełącza źródło: „GPS telefonu" '
                '(dokładność metry — do testów) lub „Odbiornik RTK (BLE)" '
                '(centymetry — po połączeniu ze sprzętem).',
            'Przycisk Start/Stop uruchamia i zatrzymuje odczyt pozycji. Karta '
                'na dole pokazuje współrzędne, dokładność i typ fixa '
                '(GPS / DGPS / RTK Float / RTK Fixed).',
          ]),
          ..._section('2. Wczytanie działki', [
            'Lupa — wyszukanie po numerze, np. „Gnojnik 222/1".',
            'Ikona globusa — „działka, na której stoję" (z aktualnej pozycji).',
            'Długie przytrzymanie palca na mapie — pobranie działki w tym '
                'miejscu (np. sąsiada).',
            'Dane pochodzą z usługi ULDK (GUGiK) i są zapisywane lokalnie '
                '(dostępne offline po pobraniu).',
          ]),
          ..._section('3. Tyczenie punktów granicznych', [
            'Tapnij działkę na mapie i potwierdź „Tycz", albo wybierz ją z '
                'listy w menu głównym i użyj ikony chorągiewki.',
            'Na dystansie wskazuje duża strzałka (kierunek względem tego, jak '
                'trzymasz telefon — używa kompasu) z podpowiedzią „prosto / '
                'w lewo / w prawo".',
            'Poniżej 3 m pojawia się tarcza celownicza: sprowadź kropkę do '
                'środka. Telefon wibruje coraz mocniej; poniżej 30 cm sygnał '
                'i napis „na punkcie".',
          ]),
          ..._section('4. Pomiar punktu i odchyłka', [
            'Na ekranie tyczenia przycisk „Zmierz" uśrednia 20 epok i zapisuje '
                'punkt z odchyłką od punktu z ewidencji (odległość oraz N/E).',
            'Pomiar wykonuj w trybie RTK Fixed — przy słabszym fixie wynik jest '
                'oznaczony jako orientacyjny.',
          ]),
          ..._section('5. Punkty uzbrojenia terenu', [
            'Po Start użyj małego przycisku „+lokalizacja" i wybierz kategorię '
                '(wodociąg, kanalizacja, gaz, energetyka, telekom, ciepło, inne).',
            'Punkt zapisuje się z kolorem kategorii. W menu głównym wybierz '
                '„Punkty uzbrojenia", aby dodać notatkę/kod i zdjęcie (aparat '
                'lub galeria) oraz usunąć punkt.',
            'Warstwę istniejących sieci włączysz w menu warstw, zaznaczając '
                '„Uzbrojenie (KIUT)". Tapnięcie poza działką (przy włączonej '
                'warstwie) odczytuje atrybuty sieci w danym miejscu.',
          ]),
          ..._section('6. Warstwy mapy i tryb offline', [
            'Przycisk warstw (prawy górny róg mapy): podkład OSM, ortofoto '
                'GUGiK lub zdjęcia Esri oraz przełącznik nakładki uzbrojenia.',
            'W menu głównym wybierz „Mapa offline": pobranie okolicy wczytanych '
                'działek do pamięci (działa potem bez zasięgu) oraz czyszczenie '
                'cache.',
          ]),
          ..._section('7. Eksport danych', [
            'Listy punktów (uzbrojenie oraz pomiary tyczenia) mają przycisk '
                '„Udostępnij" — tworzy pliki CSV i GeoJSON i otwiera systemowy '
                'arkusz udostępniania; dołączane są też zdjęcia.',
            'Współrzędne zapisywane są w WGS84 oraz w układzie PL-2000 '
                '(easting Y / northing X i numer strefy).',
          ]),
          ..._section('Uwagi i ograniczenia', [
            'Samodzielne pomiary mają charakter informacyjny — nie zastępują '
                'czynności geodety uprawnionego (rozgraniczenie, wznowienie '
                'znaków granicznych).',
            'Dokładność końcowa zależy od jakości punktów w ewidencji (atrybut '
                'BPP) oraz od warunków odbioru GNSS (odkryte niebo).',
            'Warstwa KIUT to podgląd — jej kompletność zależy od powiatu; '
                'geometrii sieci nie można stąd pobrać.',
          ]),
        ],
      ),
    );
    return doc.save();
  }

  static List<pw.Widget> _section(String title, List<String> bullets) => [
        pw.SizedBox(height: 6),
        pw.Header(
          level: 1,
          child: pw.Text(title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final b in bullets)
              pw.Bullet(text: b, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      ];
}
