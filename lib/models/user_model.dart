import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore `users/{uid}` profile for presence and display.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    this.role,
    this.lastActive,
    this.isOnline = false,
  });

  final String uid;
  final String name;
  final String? role;
  final DateTime? lastActive;
  final bool isOnline;

  factory AppUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      role: data['role'] is String ? (data['role'] as String).trim() : null,
      lastActive: _parseTimestamp(data['lastActive']),
      isOnline: data['isOnline'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'name': name.trim(),
      if (role != null) 'role': role,
      if (lastActive != null) 'lastActive': Timestamp.fromDate(lastActive!),
      'isOnline': isOnline,
    };
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
