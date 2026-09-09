import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atsleadtracker/utils/xlsx_features.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a real two-sheet workbook so the patcher is exercised against what
/// the `excel` package actually emits, not a hand-written fixture.
Uint8List _workbook() {
  final book = Excel.createExcel();
  for (final name in ['Leads', 'Notes']) {
    final sheet = book[name];
    sheet.appendRow(<CellValue>[
      TextCellValue('Company'),
      TextCellValue('Owner'),
      TextCellValue('Amount'),
    ]);
    sheet.appendRow(<CellValue>[
      TextCellValue('Tesca Technologies'),
      TextCellValue('Employee'),
      DoubleCellValue(202950),
    ]);
  }
  book.delete('Sheet1');
  return Uint8List.fromList(book.encode()!);
}

String _sheetXmlFor(Uint8List bytes, String sheetName) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final wbXml = utf8.decode(
    archive.findFile('xl/workbook.xml')!.content as List<int>,
  );
  final tag = RegExp('<sheet\\b[^>]*name="$sheetName"[^>]*>').firstMatch(wbXml)!;
  final rid = RegExp(r'r:id="([^"]*)"').firstMatch(tag.group(0)!)!.group(1);

  final relXml = utf8.decode(
    archive.findFile('xl/_rels/workbook.xml.rels')!.content as List<int>,
  );
  final rel = RegExp('<Relationship\\b[^>]*Id="$rid"[^>]*>')
      .firstMatch(relXml)!
      .group(0)!;
  var target = RegExp(r'Target="([^"]*)"').firstMatch(rel)!.group(1)!;
  if (target.startsWith('/')) target = target.substring(1);
  if (target.startsWith('./')) target = target.substring(2);
  final path = target.startsWith('xl/') ? target : 'xl/$target';

  return utf8.decode(archive.findFile(path)!.content as List<int>);
}

void main() {
  group('XlsxFeatures.colName', () {
    test('maps zero-based indexes to spreadsheet column letters', () {
      expect(XlsxFeatures.colName(0), 'A');
      expect(XlsxFeatures.colName(25), 'Z');
      expect(XlsxFeatures.colName(26), 'AA');
      expect(XlsxFeatures.colName(39), 'AN');
      expect(XlsxFeatures.colName(51), 'AZ');
      expect(XlsxFeatures.colName(52), 'BA');
    });

    test('rangeRef spans the header plus the data rows', () {
      expect(XlsxFeatures.rangeRef(40, 240), 'A1:AN241');
      expect(XlsxFeatures.rangeRef(3, 0), 'A1:C1');
    });
  });

  group('XlsxFeatures.apply', () {
    test('injects an auto-filter after sheetData', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Leads': const SheetFeature(autoFilterRef: 'A1:C2'),
      });
      final xml = _sheetXmlFor(patched, 'Leads');

      expect(xml, contains('<autoFilter ref="A1:C2"/>'));
      // Element order inside <worksheet> is schema-fixed; landing before
      // </sheetData> is what makes Excel offer to repair the file.
      expect(
        xml.indexOf('<autoFilter'),
        greaterThan(xml.indexOf('</sheetData>')),
      );
    });

    test('injects a frozen header pane inside sheetView', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Leads': const SheetFeature(freezeRows: 1),
      });
      final xml = _sheetXmlFor(patched, 'Leads');

      expect(xml, contains('ySplit="1"'));
      expect(xml, contains('topLeftCell="A2"'));
      expect(xml, contains('state="frozen"'));
      expect(xml.indexOf('<pane '), lessThan(xml.indexOf('<sheetData')));
    });

    test('freezes rows and columns together', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Leads': const SheetFeature(freezeRows: 1, freezeCols: 2),
      });
      final xml = _sheetXmlFor(patched, 'Leads');

      expect(xml, contains('xSplit="2"'));
      expect(xml, contains('ySplit="1"'));
      expect(xml, contains('topLeftCell="C2"'));
      expect(xml, contains('activePane="bottomRight"'));
    });

    test('patches only the named sheets', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Leads': const SheetFeature(autoFilterRef: 'A1:C2'),
      });

      expect(_sheetXmlFor(patched, 'Leads'), contains('<autoFilter'));
      expect(_sheetXmlFor(patched, 'Notes'), isNot(contains('<autoFilter')));
    });

    test('resolves a second sheet to its own worksheet part', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Notes': const SheetFeature(autoFilterRef: 'A1:C2', freezeRows: 1),
      });

      expect(_sheetXmlFor(patched, 'Notes'), contains('<autoFilter'));
      expect(_sheetXmlFor(patched, 'Notes'), contains('state="frozen"'));
      expect(_sheetXmlFor(patched, 'Leads'), isNot(contains('<pane ')));
    });

    test('keeps the workbook readable and its data intact', () {
      final patched = XlsxFeatures.apply(_workbook(), {
        'Leads': const SheetFeature(freezeRows: 1, autoFilterRef: 'A1:C2'),
      });

      final reopened = Excel.decodeBytes(patched);
      final rows = reopened.tables['Leads']!.rows;
      expect(rows.first.first?.value, isA<TextCellValue>());
      // A whole-number double reads back as IntCellValue, so compare the
      // number rather than the cell type.
      final amount = rows[1][2]?.value;
      final asNumber = amount is DoubleCellValue
          ? amount.value
          : (amount as IntCellValue).value;
      expect(asNumber, 202950);
    });

    test('an unknown sheet name is a no-op, not a crash', () {
      final original = _workbook();
      final patched = XlsxFeatures.apply(original, {
        'Nope': const SheetFeature(autoFilterRef: 'A1:C2'),
      });
      expect(patched, original);
    });

    test('bytes that are not a zip come back untouched', () {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(
        XlsxFeatures.apply(junk, {'Leads': const SheetFeature()}),
        junk,
      );
    });

    test('an empty feature map short-circuits', () {
      final original = _workbook();
      expect(XlsxFeatures.apply(original, const {}), original);
    });
  });
}
