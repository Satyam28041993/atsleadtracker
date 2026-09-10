import 'package:atsleadtracker/screens/widgets/daily_action_cockpit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cockpitColumnsFor', () {
    test('a phone width gets a single column', () {
      expect(cockpitColumnsFor(360), 1);
      expect(cockpitColumnsFor(600), 1);
    });

    test('a tablet-ish width gets two columns', () {
      expect(cockpitColumnsFor(700), 2);
      expect(cockpitColumnsFor(900), 2);
    });

    test('a desktop dashboard gets three columns', () {
      expect(cockpitColumnsFor(1000), 3);
      expect(cockpitColumnsFor(1200), 3);
    });

    test('caps out at four columns on an ultra-wide monitor', () {
      expect(cockpitColumnsFor(1900), 4);
      expect(cockpitColumnsFor(3000), 4);
    });

    test('never drops below one column, even for a tiny width', () {
      expect(cockpitColumnsFor(0), 1);
      expect(cockpitColumnsFor(50), 1);
    });
  });

  group('cockpitCardWidthFor', () {
    test('a single column takes the full width', () {
      expect(cockpitCardWidthFor(400, 1), 400);
    });

    test('splits the width evenly minus the gaps between cards', () {
      // 3 columns need 2 gaps between them.
      final width = cockpitCardWidthFor(1000, 3);
      expect(width, (1000 - kCockpitCardGap * 2) / 3);
    });

    test('every column at a given width is at least the minimum card width', () {
      for (final width in <double>[320, 500, 700, 1000, 1400, 1920, 2600]) {
        final columns = cockpitColumnsFor(width);
        final cardWidth = cockpitCardWidthFor(width, columns);
        expect(
          cardWidth,
          greaterThanOrEqualTo(kCockpitMinCardWidth - 0.01),
          reason: 'width=$width columns=$columns cardWidth=$cardWidth',
        );
      }
    });

    test('columns times card width plus gaps never exceeds the available width', () {
      for (final width in <double>[320, 500, 700, 1000, 1400, 1920, 2600]) {
        final columns = cockpitColumnsFor(width);
        final cardWidth = cockpitCardWidthFor(width, columns);
        final used = cardWidth * columns + kCockpitCardGap * (columns - 1);
        expect(used, lessThanOrEqualTo(width + 0.01));
      }
    });
  });
}
