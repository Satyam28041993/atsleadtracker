import 'package:atsleadtracker/utils/name_salutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kNameSalutations', () {
    test('offers more than just Mr.', () {
      expect(kNameSalutations, containsAll(['Mr.', 'Mrs.', 'Ms.', 'Dr.', 'M/s.']));
    });
  });

  group('applySalutation', () {
    test('prepends the salutation onto a bare name', () {
      expect(applySalutation('Priya Sharma', 'Mrs.'), 'Mrs. Priya Sharma');
    });

    test('replaces an existing salutation instead of stacking a second one', () {
      expect(applySalutation('Mr. Ravi Kumar', 'Dr.'), 'Dr. Ravi Kumar');
    });

    test('is case-insensitive when detecting an existing salutation', () {
      expect(applySalutation('mr. ravi kumar', 'Ms.'), 'Ms. ravi kumar');
    });

    test('a blank salutation just strips whatever was there', () {
      expect(applySalutation('Mr. Ravi Kumar', ''), 'Ravi Kumar');
      expect(applySalutation('Mr. Ravi Kumar', null), 'Ravi Kumar');
    });

    test('picking a title before any name is typed leaves just the title', () {
      expect(applySalutation('', 'Mr.'), 'Mr.');
    });

    test('an M/s. company-style salutation round-trips too', () {
      expect(applySalutation('ABC Traders', 'M/s.'), 'M/s. ABC Traders');
      expect(applySalutation('M/s. ABC Traders', 'Mr.'), 'Mr. ABC Traders');
    });
  });

  group('hasSalutation', () {
    test('true for every recognised prefix', () {
      for (final name in ['Mr. Ravi', 'Mrs Priya', 'Ms. Anita', 'Dr Verma', 'M/s. ABC Co']) {
        expect(hasSalutation(name), isTrue, reason: name);
      }
    });

    test('false for a plain name', () {
      expect(hasSalutation('Ravi Kumar'), isFalse);
    });
  });
}
