import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atsleadtracker/screens/widgets/follow_up_date_picker.dart';

void main() {
  Future<DateTime?> open(
    WidgetTester tester,
    Future<DateTime?> Function(BuildContext) show,
  ) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('month and year dropdowns move the day grid', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DateTime? picked;
    await open(tester, (context) async {
      picked = await showFollowUpDatePicker(
        context,
        initialDate: DateTime(2026, 10, 7),
        firstDate: DateTime(2026, 10, 1),
        lastDate: DateTime(2031, 10, 1),
      );
      return picked;
    });

    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('October'), findsOneWidget);

    await tester.tap(find.text('October'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('December').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2027').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2027, 12, 15));
  });

  testWidgets('cancel returns null', (tester) async {
    DateTime? picked = DateTime(2000);
    await open(tester, (context) async {
      picked = await showFollowUpDatePicker(
        context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 400)),
      );
      return picked;
    });
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
