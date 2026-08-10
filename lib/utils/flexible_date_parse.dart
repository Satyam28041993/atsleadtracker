import 'package:intl/intl.dart';

/// Calendar date at local midnight (no time component).
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Parses user/Excel date strings in many common formats.
/// Returns null when empty or unrecognised.
DateTime? parseFlexibleDate(String? input) {
  if (input == null) return null;
  final str = input.trim();
  if (str.isEmpty) return null;

  final serial = double.tryParse(str.replaceAll(',', ''));
  if (serial != null && serial >= 1 && serial < 1000000) {
    final days = serial.floor();
    if (days >= 1 && days <= 500000) {
      final excelEpoch = DateTime(1899, 12, 30);
      return dateOnly(excelEpoch.add(Duration(days: days)));
    }
  }

  try {
    return dateOnly(DateTime.parse(str));
  } catch (_) {}

  final dmy = RegExp(
    r'^(\d{1,2})[\.\-\/\s]+(\d{1,2})[\.\-\/\s]+(\d{4})$',
  ).firstMatch(str);
  if (dmy != null) {
    final day = int.parse(dmy.group(1)!);
    final month = int.parse(dmy.group(2)!);
    final year = int.parse(dmy.group(3)!);
    final parsed = _safeDate(year, month, day);
    if (parsed != null) return parsed;
  }

  final ymd = RegExp(r'^(\d{4})[\.\-\/](\d{1,2})[\.\-\/](\d{1,2})$').firstMatch(str);
  if (ymd != null) {
    final year = int.parse(ymd.group(1)!);
    final month = int.parse(ymd.group(2)!);
    final day = int.parse(ymd.group(3)!);
    final parsed = _safeDate(year, month, day);
    if (parsed != null) return parsed;
  }

  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(str);
  if (slash != null) {
    final a = int.parse(slash.group(1)!);
    final b = int.parse(slash.group(2)!);
    final year = int.parse(slash.group(3)!);
    if (a > 12) {
      return _safeDate(year, b, a);
    }
    if (b > 12) {
      return _safeDate(year, a, b);
    }
    return _safeDate(year, a, b);
  }

  const patterns = <String>[
    'dd/MM/yyyy',
    'd/M/yyyy',
    'dd-MM-yyyy',
    'd-M-yyyy',
    'dd.MM.yyyy',
    'd.M.yyyy',
    'dd MMM yyyy',
    'd MMM yyyy',
    'MMM dd, yyyy',
    'MMMM dd, yyyy',
    'yyyy-MM-dd',
  ];
  for (final pattern in patterns) {
    try {
      final parsed = DateFormat(pattern).parseStrict(str);
      return dateOnly(parsed);
    } catch (_) {}
  }

  return null;
}

DateTime? _safeDate(int year, int month, int day) {
  if (year < 1900 || year > 2100) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  try {
    return dateOnly(DateTime(year, month, day));
  } catch (_) {
    return null;
  }
}

/// Today at local midnight.
DateTime todayDateOnly() => dateOnly(DateTime.now());
