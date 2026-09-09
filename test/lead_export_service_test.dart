import 'dart:convert';

import 'package:atsleadtracker/models/lead_event_model.dart';
import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/services/lead_export_service.dart';
import 'package:atsleadtracker/utils/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead({
  String id = 'lead-1',
  String name = 'Ravi Kumar',
  String company = 'Tesca Technologies Pvt. Ltd.',
  String status = 'Follow-up',
  String remark = '',
  double totalAmount = 0,
  DateTime? nextFollowUpDate,
  bool isTender = false,
}) {
  final now = DateTime(2026, 9, 1);
  return Lead(
    id: id,
    name: name,
    phone: '7849821302',
    email: 'purchase02@tesca.in',
    company: company,
    status: status,
    assignedTo: 'uid-emp',
    leadDate: now,
    createdAt: now,
    remark: remark,
    location: 'Jaipur',
    website: '',
    lastModified: now,
    totalAmount: totalAmount,
    nextFollowUpDate: nextFollowUpDate,
    isTender: isTender,
  );
}

LeadEvent _event(
  String action,
  String description,
  DateTime at, {
  String userName = 'Employee',
}) {
  return LeadEvent(
    id: '$action-${at.millisecondsSinceEpoch}',
    action: action,
    description: description,
    userName: userName,
    timestamp: at,
  );
}

void main() {
  group('CsvWriter', () {
    test('prefixes a BOM and uses CRLF line endings', () {
      final bytes = CsvWriter.toBytes(
        ['A', 'B'],
        [
          ['1', '2'],
        ],
      );
      // Assert on the bytes: utf8.decode strips a leading BOM, and it is the
      // raw bytes Excel inspects to decide the file is Unicode.
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes), contains('\r\n'));
    });

    test('quotes only the cells that need it', () {
      // Force-quoting every cell is what made Excel import all columns as
      // text, so amounts would not sum and dates would not sort.
      expect(CsvWriter.escapeCell('202950.00'), '202950.00');
      expect(CsvWriter.escapeCell('Tesca'), 'Tesca');
      expect(CsvWriter.escapeCell('Pune, MH'), '"Pune, MH"');
      expect(CsvWriter.escapeCell('say "hi"'), '"say ""hi"""');
    });

    test('flattens embedded newlines so a row cannot split', () {
      expect(
        CsvWriter.escapeCell('line one\nline two\r\nline three'),
        'line one line two line three',
      );
    });

    test('neutralises formula injection', () {
      expect(
        CsvWriter.escapeCell("=cmd|'/c calc'!A1"),
        contains("'=cmd"),
      );
      expect(CsvWriter.escapeCell('+1234'), "'+1234");
      expect(CsvWriter.escapeCell('@SUM(A1)'), "'@SUM(A1)");
      // A company legitimately starting with a dash is still made inert.
      expect(CsvWriter.escapeCell('-Acme'), "'-Acme");
    });

    test('the guard can be switched off', () {
      expect(CsvWriter.escapeCell('-Acme', guardFormulas: false), '-Acme');
    });

    test('leaves an empty cell empty', () {
      expect(CsvWriter.escapeCell(''), '');
    });
  });

  group('LeadExportService.csvRow', () {
    test('resolves the assignee uid to a name', () {
      final row = LeadExportService.csvRow(_lead(), {'uid-emp': 'Pratima'});
      final assigned = row[LeadExportService.csvHeaders.indexOf('Assigned To')];
      expect(assigned, 'Pratima');
    });

    test('labels an unknown or missing assignee', () {
      final i = LeadExportService.csvHeaders.indexOf('Assigned To');
      expect(LeadExportService.csvRow(_lead(), {})[i], 'Unknown Employee');
      expect(LeadExportService.assignedLabel('', {}), 'Unassigned');
    });

    test('writes the amount bare so Excel types it as a number', () {
      final i = LeadExportService.csvHeaders.indexOf('Deal Amount');
      expect(LeadExportService.csvRow(_lead(totalAmount: 202950), {})[i],
          '202950.00');
      // Zero reads as "no value", not a misleading 0.00.
      expect(LeadExportService.csvRow(_lead(), {})[i], '');
    });

    test('emits one value per header', () {
      expect(
        LeadExportService.csvRow(_lead(), {}).length,
        LeadExportService.csvHeaders.length,
      );
    });
  });

  group('LeadExportService.remarksFor', () {
    test('parses the append-only remark blob into dated entries', () {
      final lead = _lead(
        remark: '[01 Sep 2026, 10:30 AM] Called, asked for a quote.\n\n---\n'
            '[03 Sep 2026, 04:15 PM] Sent ATEPL/0609.',
      );

      final remarks = LeadExportService.remarksFor(lead, const []);

      expect(remarks.length, 2);
      expect(remarks.first.body, 'Called, asked for a quote.');
      expect(remarks.first.at, DateTime(2026, 9, 1, 10, 30));
      expect(remarks.last.body, 'Sent ATEPL/0609.');
      expect(remarks.last.at, DateTime(2026, 9, 3, 16, 15));
      expect(remarks.every((r) => !r.fromEvent), isTrue);
    });

    test('prefers the timestamped Note event over the blob copy', () {
      final lead = _lead(remark: '[01 Sep 2026, 10:30 AM] Called the client.');
      final events = [
        _event('Note', 'Called the client.', DateTime(2026, 9, 1, 10, 30)),
      ];

      final remarks = LeadExportService.remarksFor(lead, events);

      expect(remarks.length, 1);
      expect(remarks.single.fromEvent, isTrue);
      expect(remarks.single.author, 'Employee');
    });

    test('keeps blob-only history that no event covers', () {
      // Leads whose events were capped, or that predate event logging, are
      // only represented in the blob.
      final lead = _lead(
        remark: '[01 Sep 2026, 10:30 AM] Old note from before event logging.',
      );
      final events = [
        _event('Note', 'A brand new note.', DateTime(2026, 9, 5, 9, 0)),
      ];

      final remarks = LeadExportService.remarksFor(lead, events);

      expect(remarks.length, 2);
      expect(remarks.map((r) => r.fromEvent), containsAll([true, false]));
    });

    test('keeps an entry with no parseable timestamp', () {
      final remarks =
          LeadExportService.remarksFor(_lead(remark: 'plain note'), const []);
      expect(remarks.single.body, 'plain note');
      expect(remarks.single.at, isNull);
    });

    test('an empty remark yields nothing', () {
      expect(LeadExportService.remarksFor(_lead(), const []), isEmpty);
      expect(
        LeadExportService.remarksFor(_lead(remark: '   \n\n'), const []),
        isEmpty,
      );
    });
  });

  group('LeadExportService.followUpsFor', () {
    test('pairs a scheduling event with the touch that closed it', () {
      final events = [
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 05 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
        _event('Note', 'Spoke to the client.', DateTime(2026, 9, 5, 10, 0)),
      ];

      final cycles = LeadExportService.followUpsFor(_lead(), events);

      expect(cycles.length, 1);
      expect(cycles.single.dueAt, DateTime(2026, 9, 5, 11, 0));
      expect(cycles.single.done?.action, 'Note');
      expect(cycles.single.outcome(DateTime(2026, 9, 6)), 'On time');
      expect(cycles.single.delayDays, 0);
    });

    test('a touch later the same day still counts as on time', () {
      // The due time was 11:00 but the rep called at 18:00 — the day is what
      // matters, not the hour.
      final events = [
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 05 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
        _event('Status Change', 'Moved to Proposal', DateTime(2026, 9, 5, 18, 0)),
      ];

      final cycle = LeadExportService.followUpsFor(_lead(), events).single;
      expect(cycle.outcome(DateTime(2026, 9, 6)), 'On time');
    });

    test('marks a late close and counts the days', () {
      final events = [
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 05 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
        _event('Note', 'Finally reached them.', DateTime(2026, 9, 8, 12, 0)),
      ];

      final cycle = LeadExportService.followUpsFor(_lead(), events).single;
      expect(cycle.outcome(DateTime(2026, 9, 9)), 'Late');
      expect(cycle.delayDays, 3);
    });

    test('separates a still-pending follow-up from an overdue one', () {
      final events = [
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 20 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
      ];
      final cycle = LeadExportService.followUpsFor(_lead(), events).single;

      expect(cycle.outcome(DateTime(2026, 9, 10)), 'Pending');
      expect(cycle.outcome(DateTime(2026, 9, 25)), 'Overdue');
      expect(cycle.delayDays, isNull);
    });

    test('a scheduling event does not close itself', () {
      // The analytics heuristic counts any event containing "follow-up" as
      // work done, so rescheduling inflates the "done" figure. isLeadTouch
      // excludes scheduling, so a reschedule leaves the first cycle open.
      final events = [
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 05 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
        _event(
          'Follow-up Scheduled',
          'Follow-up set for 12 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 4, 9, 0),
        ),
      ];

      final cycles = LeadExportService.followUpsFor(_lead(), events);

      expect(cycles.length, 2);
      expect(cycles.every((c) => c.done == null), isTrue);
    });

    test('ignores a cancellation event', () {
      final events = [
        _event('Follow-up Cancelled', 'Client declined', DateTime(2026, 9, 2)),
      ];
      expect(LeadExportService.followUpsFor(_lead(), events), isEmpty);
    });

    test('flags a smart follow-up', () {
      final events = [
        _event(
          'Smart Follow-up Scheduled',
          'Follow-up set for 05 Sep 2026, 11:00 AM',
          DateTime(2026, 9, 1, 9, 0),
        ),
      ];
      expect(LeadExportService.followUpsFor(_lead(), events).single.isSmart,
          isTrue);
    });

    test('survives a description it cannot parse a date from', () {
      final events = [
        _event('Follow-up Scheduled', 'rescheduled', DateTime(2026, 9, 1)),
      ];
      final cycle = LeadExportService.followUpsFor(_lead(), events).single;
      expect(cycle.dueAt, isNull);
      expect(cycle.outcome(DateTime(2026, 9, 9)), 'Unknown');
    });
  });

  group('LeadExportService lead classification', () {
    test('maps statuses to Won / Lost / Open', () {
      expect(LeadExportService.outcomeOfLead(_lead(status: 'Won')), 'Won');
      expect(LeadExportService.outcomeOfLead(_lead(status: 'Lost')), 'Lost');
      expect(LeadExportService.outcomeOfLead(_lead(status: 'Loss')), 'Lost');
      expect(LeadExportService.outcomeOfLead(_lead(status: 'New')), 'Open');
    });

    test('buckets follow-up state against today', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      String bucket(DateTime? due, {String status = 'Follow-up'}) =>
          LeadExportService.followUpBucket(
            _lead(status: status, nextFollowUpDate: due),
            now,
          );

      expect(bucket(DateTime(2026, 9, 8)), 'Overdue');
      expect(bucket(DateTime(2026, 9, 10, 16, 0)), 'Due today');
      expect(bucket(DateTime(2026, 9, 20)), 'Scheduled');
      expect(bucket(null), 'None');
      // A closed lead is never chased, whatever date it still carries.
      expect(bucket(DateTime(2026, 9, 8), status: 'Won'), 'Closed');
    });
  });
}
