import 'package:cloud_firestore/cloud_firestore.dart';

/// Single timeline row stored under `leads/{leadId}/events/{eventId}`.
class LeadEvent {
  const LeadEvent({
    required this.id,
    required this.action,
    required this.description,
    required this.userName,
    required this.timestamp,
  });

  final String id;
  final String action;
  final String description;
  final String userName;
  final DateTime timestamp;

  factory LeadEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return LeadEvent(
      id: doc.id,
      action: (data['action'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      userName: (data['userName'] as String? ?? '').trim(),
      timestamp: _parseTimestamp(data['timestamp']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'action': action.trim(),
      'description': description.trim(),
      'userName': userName.trim(),
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
