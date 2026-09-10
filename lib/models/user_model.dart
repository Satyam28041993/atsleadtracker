import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore `users/{uid}` profile for presence and display.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    this.role,
    this.lastActive,
    this.isOnline = false,
    this.canManageCatalog = false,
  });

  final String uid;
  final String name;
  final String? role;
  final DateTime? lastActive;
  final bool isOnline;

  /// When true, this employee can add/edit/delete catalog products like admin.
  final bool canManageCatalog;

  factory AppUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final name = (data['name'] as String? ?? '').trim();
    final flagged = data['canManageCatalog'] == true;
    return AppUser(
      uid: doc.id,
      name: name,
      role: data['role'] is String ? (data['role'] as String).trim() : null,
      lastActive: _parseTimestamp(data['lastActive']),
      isOnline: data['isOnline'] as bool? ?? false,
      canManageCatalog: flagged || isNamedCatalogEditor(name),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'name': name.trim(),
      if (role != null) 'role': role,
      if (lastActive != null) 'lastActive': Timestamp.fromDate(lastActive!),
      'isOnline': isOnline,
      'canManageCatalog': canManageCatalog,
    };
  }

  /// Pratima and Pooja get catalog CRUD by name until/alongside the flag.
  static bool isNamedCatalogEditor(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    return n.contains('pratima') || n.contains('pooja');
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
