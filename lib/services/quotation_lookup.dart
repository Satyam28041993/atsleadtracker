import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quotation_model.dart';
import 'quotation_service.dart';

/// Session cache of quotations grouped by lead id.
///
/// Lead lists (Kanban, follow-ups, analytics…) use it to decide whether to
/// show a "Quotation view" button without one Firestore query per row.
/// Admins read every quotation; other users fall back to their own (matches
/// `firestore.rules`).
class QuotationLookup {
  QuotationLookup._();

  static final QuotationLookup instance = QuotationLookup._();

  static const Duration _maxAge = Duration(minutes: 5);

  Future<Map<String, List<QuotationModel>>>? _pending;
  DateTime? _loadedAt;

  /// Drops the cache; call after a quotation is created, edited or deleted.
  void invalidate() {
    _pending = null;
    _loadedAt = null;
  }

  Future<Map<String, List<QuotationModel>>> _byLead() {
    final loadedAt = _loadedAt;
    if (_pending != null &&
        (loadedAt == null || DateTime.now().difference(loadedAt) < _maxAge)) {
      return _pending!;
    }
    final future = _load();
    _pending = future;
    _loadedAt = DateTime.now();
    // A failed load must not stay cached.
    future.catchError((_) {
      if (identical(_pending, future)) invalidate();
      return const <String, List<QuotationModel>>{};
    });
    return future;
  }

  Future<Map<String, List<QuotationModel>>> _load() async {
    final col = FirebaseFirestore.instance.collection('quotations');
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await col.get();
    } on FirebaseException catch (e) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (e.code != 'permission-denied' || uid == null) rethrow;
      snap = await col.where('employeeId', isEqualTo: uid).get();
    }

    final map = <String, List<QuotationModel>>{};
    for (final doc in snap.docs) {
      try {
        final quote = QuotationModel.fromFirestore(doc);
        final leadId = quote.leadId.trim();
        if (leadId.isEmpty) continue;
        map.putIfAbsent(leadId, () => []).add(quote);
      } catch (_) {}
    }
    return map.map((k, v) => MapEntry(k, QuotationService.sortForLead(v)));
  }

  /// Quotations for [leadId], latest first (empty when none / on error).
  Future<List<QuotationModel>> quotesFor(String leadId) async {
    try {
      final map = await _byLead();
      return map[leadId.trim()] ?? const <QuotationModel>[];
    } catch (_) {
      return const <QuotationModel>[];
    }
  }
}
