import 'package:atsleadtracker/models/lead_model.dart';
import 'package:flutter_test/flutter_test.dart';

Lead _lead({List<String> team = const []}) => Lead(
  id: 'l1',
  name: 'A',
  phone: '',
  email: '',
  company: 'C',
  status: 'New',
  assignedTo: 'owner',
  createdAt: DateTime(2026, 10, 1),
  remark: '',
  location: '',
  website: '',
  teamMembers: team,
);

void main() {
  test('owner and team members can work on a lead, others cannot', () {
    final lead = _lead(team: ['mate']);
    expect(lead.canWorkOn('owner'), isTrue);
    expect(lead.canWorkOn('mate'), isTrue);
    expect(lead.isTeamMember('owner'), isFalse);
    expect(lead.canWorkOn('other'), isFalse);
    expect(lead.canWorkOn(''), isFalse);
  });

  test('a full-document save never writes the team', () {
    // The lead sheet saves the whole form; a stale copy must not wipe or
    // revert a team change made meanwhile.
    final data = _lead(team: ['mate']).toFirestore();
    expect(data.containsKey('teamMembers'), isFalse);
  });

  test('copyWith keeps the team unless told otherwise', () {
    final lead = _lead(team: ['mate']);
    expect(lead.copyWith(status: 'Contacted').teamMembers, ['mate']);
    expect(lead.copyWith(teamMembers: const []).teamMembers, isEmpty);
  });
}
