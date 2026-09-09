import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// What to switch on for one worksheet.
class SheetFeature {
  const SheetFeature({
    this.freezeRows = 1,
    this.freezeCols = 0,
    this.autoFilterRef,
  });

  final int freezeRows;
  final int freezeCols;

  /// Full data range including the header row, e.g. `A1:AN241`. Null disables
  /// the filter (wanted on sheets that use merged cells).
  final String? autoFilterRef;
}

/// Adds freeze panes and auto-filters to a workbook produced by `excel`.
///
/// The package can style cells but has no API for either feature, so we patch
/// the generated .xlsx package directly — the same unzip / string-patch / rezip
/// trick `BulkUploadService` already uses to inject data validations.
class XlsxFeatures {
  const XlsxFeatures._();

  /// Returns the patched bytes, or [xlsxBytes] unchanged if anything about the
  /// package looks unexpected. Never throws: a workbook without frozen headers
  /// is far better than a failed export.
  static Uint8List apply(
    Uint8List xlsxBytes,
    Map<String, SheetFeature> featuresBySheetName,
  ) {
    if (featuresBySheetName.isEmpty) return xlsxBytes;
    try {
      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      final wb = archive.findFile('xl/workbook.xml');
      final rels = archive.findFile('xl/_rels/workbook.xml.rels');
      if (wb == null || rels == null) return xlsxBytes;

      // sheet name -> r:id
      final wbXml = utf8.decode(wb.content as List<int>);
      final ridByName = <String, String>{};
      for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wbXml)) {
        final tag = m.group(0)!;
        final name = RegExp(r'name="([^"]*)"').firstMatch(tag)?.group(1);
        final rid = RegExp(r'r:id="([^"]*)"').firstMatch(tag)?.group(1);
        if (name != null && rid != null) ridByName[_unescape(name)] = rid;
      }

      // r:id -> worksheet path
      final relXml = utf8.decode(rels.content as List<int>);
      final pathByRid = <String, String>{};
      for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(relXml)) {
        final tag = m.group(0)!;
        final id = RegExp(r'Id="([^"]*)"').firstMatch(tag)?.group(1);
        var target = RegExp(r'Target="([^"]*)"').firstMatch(tag)?.group(1);
        if (id == null || target == null) continue;
        if (target.startsWith('/')) target = target.substring(1);
        if (target.startsWith('./')) target = target.substring(2);
        pathByRid[id] = target.startsWith('xl/') ? target : 'xl/$target';
      }

      final patched = <String, String>{};
      featuresBySheetName.forEach((name, f) {
        final rid = ridByName[name];
        if (rid == null) return;
        final path = pathByRid[rid];
        if (path == null) return;
        final file = archive.findFile(path);
        if (file == null) return;
        patched[path] = _patchSheet(
          utf8.decode(file.content as List<int>),
          f,
        );
      });
      if (patched.isEmpty) return xlsxBytes;

      final out = Archive();
      for (final file in archive.files) {
        final xml = patched[file.name];
        out.addFile(xml == null ? file : ArchiveFile.string(file.name, xml));
      }
      // archive 3.x returns a nullable encode().
      final encoded = ZipEncoder().encode(out);
      return encoded == null ? xlsxBytes : Uint8List.fromList(encoded);
    } catch (_) {
      return xlsxBytes;
    }
  }

  static String _patchSheet(String xml, SheetFeature f) {
    var out = xml;

    // Freeze panes live inside <sheetView>, which sits in <sheetViews> BEFORE
    // <sheetData>.
    if ((f.freezeRows > 0 || f.freezeCols > 0) && !out.contains('<pane ')) {
      final panes = _panesXml(f.freezeRows, f.freezeCols);
      final selfClosing = RegExp(r'<sheetView\b([^>/]*)/>');
      if (selfClosing.hasMatch(out)) {
        out = out.replaceFirstMapped(
          selfClosing,
          (m) => '<sheetView${m.group(1)}>$panes</sheetView>',
        );
      } else {
        out = out.replaceFirstMapped(
          RegExp(r'<sheetView\b([^>]*)>'),
          (m) => '<sheetView${m.group(1)}>$panes',
        );
      }
    }

    // The auto-filter goes immediately AFTER </sheetData>. CT_Worksheet fixes
    // child order as sheetData -> ... -> autoFilter -> ... -> mergeCells ->
    // ... -> pageMargins, so inserting here keeps the document schema-valid
    // against everything the excel package may emit after sheetData.
    const anchor = '</sheetData>';
    final ref = f.autoFilterRef;
    if (ref != null && !out.contains('<autoFilter') && out.contains(anchor)) {
      out = out.replaceFirst(anchor, '$anchor<autoFilter ref="$ref"/>');
    }
    return out;
  }

  static String _panesXml(int rows, int cols) {
    final topLeft = '${colName(cols)}${rows + 1}'; // rows:1 cols:0 -> A2
    final split = <String>[
      if (cols > 0) 'xSplit="$cols"',
      if (rows > 0) 'ySplit="$rows"',
    ].join(' ');
    final active = (cols > 0 && rows > 0)
        ? 'bottomRight'
        : (cols > 0 ? 'topRight' : 'bottomLeft');
    return '<pane $split topLeftCell="$topLeft" activePane="$active" '
        'state="frozen"/>'
        '<selection pane="$active" activeCell="$topLeft" sqref="$topLeft"/>';
  }

  /// 0 -> `A`, 25 -> `Z`, 26 -> `AA`, 39 -> `AN`.
  static String colName(int zeroBased) {
    var n = zeroBased;
    var s = '';
    do {
      s = String.fromCharCode(65 + n % 26) + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return s;
  }

  /// Convenience: `A1:{lastCol}{rows}` for a sheet with [columns] columns and
  /// [dataRows] rows under the header.
  static String rangeRef(int columns, int dataRows) =>
      'A1:${colName(columns - 1)}${dataRows + 1}';

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
