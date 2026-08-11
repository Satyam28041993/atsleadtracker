import 'package:flutter/foundation.dart';

import 'lead_model.dart';

/// A lead detail form that was minimised rather than saved or closed.
///
/// The panel keeps everything in local controllers, so popping its route
/// throws the edits away. Minimising snapshots them here instead: [edited] is
/// the form as it stood, [original] is the record it was opened from.
@immutable
class LeadDraft {
  const LeadDraft({
    required this.original,
    required this.edited,
    this.timelineNote = '',
  });

  final Lead original;
  final Lead edited;

  /// Text typed into the timeline note box but not yet posted.
  final String timelineNote;

  String get leadId => original.id;

  /// Short label for the minimised chip.
  String get label {
    final name = edited.name.trim();
    if (name.isNotEmpty) return name;
    final company = edited.company.trim();
    if (company.isNotEmpty) return company;
    if (edited.isTender) return 'Tender';
    return 'Lead';
  }

  String get subtitle {
    final company = edited.company.trim();
    if (company.isNotEmpty && company != label) return company;
    return edited.status;
  }
}
