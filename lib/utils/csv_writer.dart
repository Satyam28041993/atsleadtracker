import 'dart:convert';
import 'dart:typed_data';

/// RFC-4180 CSV writer that Excel on Windows opens correctly.
///
/// Lives here rather than on a service so the Kanban export doesn't have to
/// reach into the backup service just to write a CSV.
class CsvWriter {
  const CsvWriter._();

  /// UTF-8 with a BOM, CRLF line endings, built through a [StringBuffer].
  ///
  /// The BOM is what makes Excel read the file as Unicode rather than the
  /// system codepage — without it `₹` and non-ASCII names arrive mangled.
  static Uint8List toBytes(
    List<String> headers,
    List<List<String>> rows, {
    bool guardFormulas = true,
  }) {
    final buffer = StringBuffer()
      ..write(line(headers, guardFormulas: guardFormulas));
    for (final row in rows) {
      buffer.write(line(row, guardFormulas: guardFormulas));
    }
    return Uint8List.fromList(utf8.encode('﻿$buffer'));
  }

  static String line(List<String> cells, {bool guardFormulas = true}) {
    return '${cells.map((c) => escapeCell(c, guardFormulas: guardFormulas)).join(',')}\r\n';
  }

  /// Quotes only when the cell needs it.
  ///
  /// Quoting *every* cell — which the Kanban export used to do — is why Excel
  /// imported all columns as text, so amounts would not sum and dates would
  /// not sort.
  static String escapeCell(String value, {bool guardFormulas = true}) {
    var v = value
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    if (guardFormulas) v = _guardFormula(v);
    if (v.contains('"') || v.contains(',')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// Excel and Sheets execute a cell that opens with `= + - @` or a tab, so a
  /// company named `=cmd|'/c calc'!A1` would run on open. A leading apostrophe
  /// neutralises it and stays invisible on import.
  static String _guardFormula(String v) {
    if (v.isEmpty) return v;
    const triggers = {'=', '+', '-', '@', '\t'};
    return triggers.contains(v[0]) ? "'$v" : v;
  }
}
