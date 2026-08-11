import 'package:flutter/widgets.dart';

import '../models/lead_draft.dart';

/// One minimised lead: the captured form plus how to put it back on screen.
class MinimizedLead {
  MinimizedLead({required this.draft, required this.restore});

  final LeadDraft draft;

  /// Reopens the panel with [draft] applied. Takes a context because the
  /// context that minimised the lead may be long gone by the time the user
  /// clicks the chip.
  final Future<void> Function(BuildContext context) restore;
}

/// Holds lead detail forms that were minimised instead of saved or closed.
///
/// The app has no state-management package, so this is a plain singleton with
/// a [ValueNotifier]; the minimised bar listens to it and the dashboards do
/// not need to know it exists.
class LeadDraftStore {
  LeadDraftStore._();

  static final LeadDraftStore instance = LeadDraftStore._();

  final ValueNotifier<List<MinimizedLead>> drafts =
      ValueNotifier<List<MinimizedLead>>(const []);

  bool isMinimized(String leadId) =>
      drafts.value.any((d) => d.draft.leadId == leadId);

  /// Adds [entry], replacing any earlier draft for the same lead so a lead
  /// minimised twice does not end up with two chips.
  void add(MinimizedLead entry) {
    drafts.value = [
      ...drafts.value.where((d) => d.draft.leadId != entry.draft.leadId),
      entry,
    ];
  }

  void remove(String leadId) {
    final next = drafts.value.where((d) => d.draft.leadId != leadId).toList();
    if (next.length != drafts.value.length) drafts.value = next;
  }

  void clear() {
    if (drafts.value.isNotEmpty) drafts.value = const [];
  }
}
