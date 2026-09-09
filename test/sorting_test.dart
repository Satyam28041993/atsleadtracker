import 'package:atsleadtracker/models/lead_model.dart';
import 'package:atsleadtracker/screens/follow_ups_screen.dart';
import 'package:atsleadtracker/screens/widgets/kanban_board.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 9, 9, 12, 0);

Lead _lead({
  required String id,
  DateTime? followUp,
  DateTime? leadDate,
  DateTime? lastModified,
  String company = 'Acme',
  String status = 'Follow-up',
  double amount = 0,
}) {
  final base = leadDate ?? DateTime(2026, 1, 1);
  return Lead(
    id: id,
    name: id,
    phone: '',
    email: '',
    company: company,
    status: status,
    assignedTo: 'uid',
    leadDate: base,
    createdAt: base,
    remark: '',
    location: '',
    website: '',
    lastModified: lastModified ?? base,
    nextFollowUpDate: followUp,
    totalAmount: amount,
  );
}

void main() {
  group('sortFollowUps', () {
    // Dates around _now = 9 Sep 2026.
    final staleOverdue = _lead(id: 'stale', followUp: DateTime(2026, 6, 12));
    final recentOverdue = _lead(id: 'recent', followUp: DateTime(2026, 9, 8));
    final today = _lead(id: 'today', followUp: DateTime(2026, 9, 9, 15));
    final soon = _lead(id: 'soon', followUp: DateTime(2026, 9, 10));
    final later = _lead(id: 'later', followUp: DateTime(2026, 12, 31));

    List<String> order(FollowUpSort sort) {
      final list = [staleOverdue, later, today, recentOverdue, soon];
      sortFollowUps(list, sort, _now);
      return list.map((l) => l.id).toList();
    }

    test('actionOrder puts today first, then upcoming, then overdue', () {
      // The old plain-date order opened on a June follow-up — the least
      // actionable row in the list.
      expect(
        order(FollowUpSort.actionOrder),
        ['today', 'soon', 'later', 'recent', 'stale'],
      );
    });

    test('actionOrder ranks the most recent miss above the stalest', () {
      final list = [staleOverdue, recentOverdue];
      sortFollowUps(list, FollowUpSort.actionOrder, _now);
      expect(list.first.id, 'recent');
    });

    test('mostOverdueFirst leads with the oldest miss', () {
      expect(
        order(FollowUpSort.mostOverdueFirst),
        ['stale', 'recent', 'today', 'soon', 'later'],
      );
    });

    test('dateSoonest is plain chronological order', () {
      expect(
        order(FollowUpSort.dateSoonest),
        ['stale', 'recent', 'today', 'soon', 'later'],
      );
    });

    test('dateLatest reverses it', () {
      expect(
        order(FollowUpSort.dateLatest),
        ['later', 'soon', 'today', 'recent', 'stale'],
      );
    });

    test('companyAz sorts case-insensitively and breaks ties by date', () {
      final list = [
        _lead(id: 'b', company: 'beta', followUp: DateTime(2026, 9, 20)),
        _lead(id: 'a2', company: 'Alpha', followUp: DateTime(2026, 9, 25)),
        _lead(id: 'a1', company: 'alpha', followUp: DateTime(2026, 9, 15)),
      ];
      sortFollowUps(list, FollowUpSort.companyAz, _now);
      expect(list.map((l) => l.id), ['a1', 'a2', 'b']);
    });

    test('handles an empty list', () {
      final list = <Lead>[];
      sortFollowUps(list, FollowUpSort.actionOrder, _now);
      expect(list, isEmpty);
    });
  });

  group('leadNeedsAttention', () {
    test('is true for a follow-up due today or already missed', () {
      expect(
        leadNeedsAttention(_lead(id: 'a', followUp: DateTime(2026, 9, 9, 23)), _now),
        isTrue,
      );
      expect(
        leadNeedsAttention(_lead(id: 'b', followUp: DateTime(2026, 9, 1)), _now),
        isTrue,
      );
    });

    test('is false for a future follow-up or none at all', () {
      expect(
        leadNeedsAttention(_lead(id: 'c', followUp: DateTime(2026, 9, 10)), _now),
        isFalse,
      );
      expect(leadNeedsAttention(_lead(id: 'd'), _now), isFalse);
    });

    test('a closed lead never needs attention, stale date or not', () {
      for (final status in ['Won', 'Lost', 'Loss', 'Disqualified']) {
        expect(
          leadNeedsAttention(
            _lead(id: status, status: status, followUp: DateTime(2026, 1, 1)),
            _now,
          ),
          isFalse,
          reason: status,
        );
      }
    });
  });

  group('leadSortComparator', () {
    final due = _lead(
      id: 'due',
      followUp: DateTime(2026, 9, 9, 10),
      lastModified: DateTime(2026, 1, 1),
    );
    final overdue = _lead(
      id: 'overdue',
      followUp: DateTime(2026, 8, 1),
      lastModified: DateTime(2026, 1, 1),
    );
    final freshNoFollowUp = _lead(
      id: 'fresh',
      leadDate: DateTime(2026, 9, 8),
      lastModified: DateTime(2026, 9, 8),
    );
    final oldNoFollowUp = _lead(
      id: 'old',
      leadDate: DateTime(2026, 2, 1),
      lastModified: DateTime(2026, 2, 1),
      amount: 500000,
    );

    List<String> order(LeadSort sort) {
      final list = [freshNoFollowUp, due, oldNoFollowUp, overdue]
        ..sort(leadSortComparator(sort, _now));
      return list.map((l) => l.id).toList();
    }

    test('needsAttention floats due and overdue leads to the top', () {
      final result = order(LeadSort.needsAttention);
      expect(result.take(2), containsAll(['overdue', 'due']));
      // Most overdue first inside that group.
      expect(result.first, 'overdue');
      // Everything else falls back to most recently worked.
      expect(result.sublist(2), ['fresh', 'old']);
    });

    test('recentlyUpdated ignores follow-up state', () {
      expect(order(LeadSort.recentlyUpdated).first, 'fresh');
    });

    test('newestFirst and oldestFirst use the lead date', () {
      expect(order(LeadSort.newestFirst).first, 'fresh');
      expect(order(LeadSort.oldestFirst).last, 'fresh');
    });

    test('valueHighToLow puts the biggest deal first', () {
      expect(order(LeadSort.valueHighToLow).first, 'old');
    });

    test('companyAz sorts case-insensitively', () {
      final list = [
        _lead(id: 'z', company: 'zeta'),
        _lead(id: 'a', company: 'Alpha'),
      ]..sort(leadSortComparator(LeadSort.companyAz, _now));
      expect(list.map((l) => l.id), ['a', 'z']);
    });

    test('every sort option has a label', () {
      for (final s in LeadSort.values) {
        expect(s.label, isNotEmpty);
      }
      for (final s in FollowUpSort.values) {
        expect(s.label, isNotEmpty);
      }
    });
  });
}
