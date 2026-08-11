import 'package:cloud_firestore/cloud_firestore.dart';

/// Single timeline row stored under `leads/{leadId}/events/{eventId}`.
class LeadEvent {
  const LeadEvent({
    required this.id,
    required this.action,
    required this.description,
    required this.userName,
    required this.timestamp,
    this.userId = '',
  });

  final String id;
  final String action;
  final String description;
  final String userName;
  final DateTime timestamp;

  /// Author's uid. Empty on events written before uid stamping was added —
  /// those still fall back to [userName] matching in the reports.
  final String userId;

  factory LeadEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return LeadEvent(
      id: doc.id,
      action: (data['action'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      userName: (data['userName'] as String? ?? '').trim(),
      userId: (data['userId'] as String? ?? '').trim(),
      timestamp: _parseTimestamp(data['timestamp']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'action': action.trim(),
      'description': description.trim(),
      'userName': userName.trim(),
      'userId': userId.trim(),
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  /// True for the events that mean "the rep actually worked this lead" —
  /// a status update or a remark. Used for the Calls metric.
  bool get isLeadTouch {
    final a = action.toLowerCase();
    return a.contains('status') || a.contains('note') || a.contains('remark');
  }

  /// True when this event scheduled (or rescheduled) a follow-up.
  bool get isFollowUpScheduling =>
      action.toLowerCase().contains('follow-up');

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
