import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/screens/widgets/status_remark_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _tender() => Lead(
  id: 't1',
  name: 'Tender Contact',
  phone: 'N/A',
  email: '',
  company: 'NTPC',
  status: 'Reverse Auction(RA)',
  assignedTo: 'u1',
  createdAt: DateTime(2026, 10, 1),
  remark: '',
  location: '',
  website: '',
  isTender: true,
);

Future<Lead?> _run(WidgetTester tester, String target, String? typed) async {
  Lead? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await leadWithStatusRemark(context, _tender(), target);
              done = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (typed == null) {
    await tester.tap(find.text('Cancel'));
  } else {
    await tester.enterText(find.byType(TextField), typed);
    await tester.tap(find.text('Confirm'));
  }
  await tester.pumpAndSettle();
  expect(done, isTrue);
  return result;
}

void main() {
  test('Commercial Status sits right after RA in the tender pipeline', () {
    final i = Lead.tenderStatuses.indexOf('Reverse Auction(RA)');
    expect(Lead.tenderStatuses[i + 1], Lead.commercialStatusStage);
    expect(Lead.commercialStatusStage, 'Commercial Status');
    expect(Lead.statuses, isNot(contains(Lead.commercialStatusStage)));
  });

  test('a tender stored at Commercial Status keeps its column', () {
    expect(
      Lead.kanbanColumnFor(Lead.commercialStatusStage, isTender: true),
      Lead.commercialStatusStage,
    );
  });

  testWidgets('moving to Commercial Status stores the remark', (t) async {
    final lead = await _run(t, Lead.commercialStatusStage, '  L1 at 4.2 L ');
    expect(lead?.commercialStatus, 'L1 at 4.2 L');
  });

  testWidgets('a blank remark or cancel blocks the move', (t) async {
    expect(await _run(t, Lead.commercialStatusStage, '   '), isNull);
    expect(find.textContaining('A remark is required'), findsOneWidget);
    expect(await _run(t, Lead.commercialStatusStage, null), isNull);
  });

  testWidgets('Loss asks for a reason too', (t) async {
    final lead = await _run(t, 'Loss', 'Price too high');
    expect(lead?.lossReason, 'Price too high');
  });
}
