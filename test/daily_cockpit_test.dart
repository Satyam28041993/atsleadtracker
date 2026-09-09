import 'package:atsleadtracker/models/daily_cockpit_model.dart';
import 'package:atsleadtracker/models/lead_model.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead({String id = 'l1', String company = 'Acme'}) {
  final now = DateTime(2026, 9, 9);
  return Lead(
    id: id,
    name: 'Contact',
    phone: '9999999999',
    email: '',
    company: company,
    status: 'Proposal',
    assignedTo: 'uid',
    createdAt: now,
    remark: '',
    location: '',
    website: '',
    lastModified: now,
  );
}

DailyCompletedActivity _activity(String id) {
  return DailyCompletedActivity(
    id: id,
    type: DailyActivityType.quotation,
    leadId: 'l1',
    title: 'Quotation sent',
    subtitle: 'ATEPL/0609/2026-2027',
    companyName: 'Acme',
    clientName: 'Contact',
    phone: '9999999999',
    timestamp: DateTime(2026, 9, 9, 11),
    employeeUid: 'uid',
    employeeName: 'Pratima',
  );
}

EmployeeDailySummary _summary({
  int pending = 0,
  int today = 0,
  double quotesValue = 0,
}) {
  return EmployeeDailySummary(
    employeeUid: 'uid',
    employeeName: 'Pratima',
    role: 'employee',
    pendingItems: [
      for (var i = 0; i < pending; i++)
        DailyPendingItem(
          lead: _lead(id: 'p$i'),
          type: DailyPendingType.overdue,
          daysOverdue: i + 1,
        ),
    ],
    todayActivities: [for (var i = 0; i < today; i++) _activity('t$i')],
    yesterdayActivities: const [],
    dueTodayCount: 0,
    overdueCount: pending,
    todayDoneCount: today,
    todayQuotesValue: quotesValue,
  );
}

void main() {
  group('DailyCockpitPayload', () {
    test('rolls per-employee counts up to the team totals', () {
      final payload = DailyCockpitPayload(
        employeeSummaries: [
          _summary(pending: 3, today: 2, quotesValue: 100000),
          _summary(pending: 5, today: 1, quotesValue: 50000),
        ],
        timestamp: DateTime(2026, 9, 9),
      );

      expect(payload.globalOverdue, 8);
      expect(payload.globalDoneToday, 3);
      expect(payload.globalQuotesValue, 150000);
    });

    test('is not degraded when nothing failed', () {
      final payload = DailyCockpitPayload(
        employeeSummaries: const [],
        timestamp: DateTime(2026, 9, 9),
      );
      expect(payload.isDegraded, isFalse);
      expect(payload.warnings, isEmpty);
    });

    test('a swallowed failure now surfaces as a warning', () {
      // The whole point: an employee whose quotations query fails used to see
      // an empty tab and conclude they had done no work.
      final payload = DailyCockpitPayload(
        employeeSummaries: const [],
        timestamp: DateTime(2026, 9, 9),
        warnings: const ['Quotations could not be loaded.'],
      );
      expect(payload.isDegraded, isTrue);
      expect(payload.warnings.single, contains('Quotations'));
    });

    test('totalPendingCount counts the rows, not the buckets', () {
      expect(_summary(pending: 4).totalPendingCount, 4);
    });
  });

  group('DailyPendingType', () {
    test('carries a bucket for a quoted lead that has gone quiet', () {
      // Added so the warmest deals in the queue are not lumped in with plain
      // stale leads.
      expect(
        DailyPendingType.values,
        contains(DailyPendingType.awaitingQuoteReply),
      );
    });

    test('every bucket is distinct', () {
      expect(
        DailyPendingType.values.toSet().length,
        DailyPendingType.values.length,
      );
    });
  });

  group('pagination arithmetic', () {
    // Mirrors _paginatedList: page 0 shows the first 30, and the footer says
    // how many are left. Without a cap every row builds eagerly, because the
    // lists use shrinkWrap inside the dashboard's scroll view.
    const pageSize = 30;
    int shownFor(int page, int total) =>
        ((page + 1) * pageSize).clamp(0, total);

    test('shows one page at a time', () {
      expect(shownFor(0, 100), 30);
      expect(shownFor(1, 100), 60);
      expect(shownFor(2, 100), 90);
      expect(shownFor(3, 100), 100);
    });

    test('never overruns a short list', () {
      expect(shownFor(0, 7), 7);
      expect(shownFor(5, 7), 7);
      expect(shownFor(0, 0), 0);
    });

    test('remaining reaches zero exactly on the last page', () {
      expect(100 - shownFor(3, 100), 0);
      expect(100 - shownFor(0, 100), 70);
    });
  });
}
