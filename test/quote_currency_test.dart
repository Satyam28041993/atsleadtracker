import 'package:atsleadtracker/models/quote_currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kQuoteCurrencies', () {
    test('offers more than just the rupee', () {
      final codes = kQuoteCurrencies.map((c) => c.code).toSet();
      expect(codes, containsAll(['INR', 'USD', 'EUR', 'GBP', 'AED']));
    });

    test('INR is first and is the only one using the "/-" suffix', () {
      expect(kQuoteCurrencies.first.code, 'INR');
      expect(kQuoteCurrencies.first.usesSlashSuffix, isTrue);
      for (final c in kQuoteCurrencies.skip(1)) {
        expect(c.usesSlashSuffix, isFalse, reason: c.code);
      }
    });
  });

  group('quoteCurrencyFor', () {
    test('resolves a known code', () {
      expect(quoteCurrencyFor('USD').symbol, '\$');
    });

    test('falls back to INR for a legacy quote with no stored currency', () {
      expect(quoteCurrencyFor(null).code, 'INR');
      expect(quoteCurrencyFor('').code, 'INR');
    });

    test('falls back to INR for an unrecognised code rather than crashing', () {
      expect(quoteCurrencyFor('XYZ').code, 'INR');
    });
  });
}
