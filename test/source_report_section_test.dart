import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atsleadtracker/screens/widgets/source_report_section.dart';
import 'package:atsleadtracker/services/analytics_service.dart';

SourceCell _cell(List<String> ids, [double value = 0]) =>
    SourceCell(leadIds: ids, value: value);

SourceReport _sample() {
  const ramesh = SourceReportEmployee(uid: 'u1', name: 'Ramesh');
  const priya = SourceReportEmployee(uid: 'u2', name: 'Priya');

  final indiaMart = SourceReportRow(
    source: 'India Mart',
    byTime: {'today': _cell(['a'], 1000), 'month': _cell(['a', 'b'], 3000)},
    byStatus: {'New': _cell(['a'], 1000), 'Proposal': _cell(['b'], 2000)},
    byEmployee: {'u1': _cell(['a'], 1000), 'u2': _cell(['b'], 2000)},
    employeeByTime: {
      'u1': {'today': _cell(['a'], 1000), 'month': _cell(['a'], 1000)},
      'u2': {'month': _cell(['b'], 2000)},
    },
    employeeByStatus: {
      'u1': {'New': _cell(['a'], 1000)},
      'u2': {'Proposal': _cell(['b'], 2000)},
    },
    total: _cell(['a', 'b'], 3000),
    wonCount: 1,
    wonValue: 2000,
  );

  return SourceReport(
    employees: const [ramesh, priya],
    statuses: const ['New', 'Proposal'],
    rows: [indiaMart],
    grandTotal: SourceReportRow(
      source: 'Total',
      byTime: indiaMart.byTime,
      byStatus: indiaMart.byStatus,
      byEmployee: indiaMart.byEmployee,
      employeeByTime: indiaMart.employeeByTime,
      employeeByStatus: indiaMart.employeeByStatus,
      total: indiaMart.total,
      wonCount: 1,
      wonValue: 2000,
    ),
  );
}

Widget _host(SourceReport report, {required List<String> opened, double width = 1200}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: width,
          child: SourceReportSection(
            report: report,
            colors: const [Colors.blue, Colors.green],
            onOpenLeads: (title, ids) => opened.add('$title|${ids.length}'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders wide without overflow and opens leads on tap',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host(_sample(), opened: opened));

    expect(find.text('Lead Source Report'), findsOneWidget);
    expect(find.text('India Mart'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    // "2" is India Mart's total for the month bucket / row total.
    await tester.tap(find.text('India Mart'));
    await tester.pumpAndSettle();
    // Expanding shows the employee sub-rows.
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(opened, isNotEmpty);
  });

  testWidgets('switches to status and value views', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host(_sample(), opened: opened));

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Proposal'), findsOneWidget);

    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹'), findsWidgets);
  });

  testWidgets('renders narrow without overflow', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    await tester.pumpWidget(_host(_sample(), opened: opened, width: 420));
    await tester.pumpAndSettle();

    expect(find.text('India Mart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
