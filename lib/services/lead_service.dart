import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/lead_model.dart';
import 'auth_service.dart';
import 'reminder_service.dart';
import 'whatsapp_service.dart';

class LeadService {
  LeadService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuthService? authService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _authService = authService ?? AuthService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthService _authService;

  CollectionReference<Map<String, dynamic>> get _leadCollection =>
      _firestore.collection('leads');

  CollectionReference<Map<String, dynamic>> get _userCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _eventsCollection(String leadId) =>
      _leadCollection.doc(leadId).collection('events');

  CollectionReference<Map<String, dynamic>> _smartFollowUpCollection(
    String leadId,
  ) => _leadCollection.doc(leadId).collection('smart_follow_ups');

  /// Timeline entry payload. Stamping `userId` lets the CRM report attribute
  /// activity by uid instead of matching display names.
  Map<String, dynamic> _eventData({
    required String action,
    required String description,
    required String userName,
  }) => <String, dynamic>{
        'action': action,
        'description': description,
        'userName': userName,
        'userId': _auth.currentUser?.uid ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      };

  Future<void> addLead(Lead lead) async {
    final userName = await _authService.getCurrentUserDisplayName();
    final data = lead.toFirestore();
    data['creatorName'] = userName;

    data['lastModified'] = FieldValue.serverTimestamp();
    final docRef = await _leadCollection.add(data);
    await _eventsCollection(docRef.id).add(_eventData(
      action: 'Created',
      description: 'Lead created',
      userName: userName,
    ));
  }

  /// [filterAssignedToUid] is the Firebase Auth UID to match on `assignedTo`
  /// for non-admin users. Pass the logged-in employee's uid from the UI so the
  /// query is explicit; when omitted, falls back to [FirebaseAuth.currentUser].
  Stream<List<Lead>> getLeadsStream({String? filterAssignedToUid}) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(const <Lead>[]);
    }

    return Stream.fromFuture(_resolveRole(user.uid)).asyncExpand((role) {
      final isAdmin = role == 'admin';
      final assignedToUid = filterAssignedToUid ?? user.uid;

      if (isAdmin) {
        return _leadCollection.snapshots().map((snapshot) {
          final leads =
              leadsFromDocs(snapshot.docs)
                ..sort((a, b) => b.leadDate.compareTo(a.leadDate));
          return leads;
        });
      }

      // Equality on `assignedTo` alone does not need a composite index.
      // Combining it with orderBy('createdAt') would require one (failed-precondition).
      return _leadCollection
          .where('assignedTo', isEqualTo: assignedToUid)
          .snapshots()
          .map((snapshot) {
            final leads =
                leadsFromDocs(snapshot.docs)
                  ..sort((a, b) => b.leadDate.compareTo(a.leadDate));
            return leads;
          });
    });
  }

  /// Leads with a scheduled follow-up, ordered by [Lead.nextFollowUpDate]
  /// ascending. Non-admin users only see leads assigned to them (same rules as
  /// [getLeadsStream]).
  Stream<List<Lead>> getFollowUpsStream({String? filterAssignedToUid}) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(const <Lead>[]);
    }

    return Stream.fromFuture(_resolveRole(user.uid)).asyncExpand((role) {
      final isAdmin = role == 'admin';
      final assignedToUid = filterAssignedToUid ?? user.uid;
      final epoch = Timestamp.fromDate(DateTime(1970, 1, 1));

      if (isAdmin) {
        return _leadCollection
            .where('nextFollowUpDate', isGreaterThan: epoch)
            .orderBy('nextFollowUpDate')
            .snapshots()
            .map(
              (snapshot) =>
                  leadsFromDocs(snapshot.docs),
            );
      }

      return _leadCollection
          .where('assignedTo', isEqualTo: assignedToUid)
          .snapshots()
          .map((snapshot) {
            final leads =
                leadsFromDocs(snapshot.docs)
                    .where((l) => l.nextFollowUpDate != null)
                    .toList(growable: false)
                  ..sort(
                    (a, b) =>
                        a.nextFollowUpDate!.compareTo(b.nextFollowUpDate!),
                  );
            return leads;
          });
    });
  }

  Future<bool> scheduleFollowUp(String leadId, DateTime followUpDate) async {
    final userName = await _authService.getCurrentUserDisplayName();
    final description =
        'Follow-up set for ${DateFormat('dd MMM yyyy, hh:mm a').format(followUpDate)}';

    await _leadCollection.doc(leadId).update(<String, dynamic>{
      'nextFollowUpDate': Timestamp.fromDate(followUpDate),
      'lastModified': FieldValue.serverTimestamp(),
    });

    await _eventsCollection(leadId).add(_eventData(
      action: 'Follow-up Scheduled',
      description: description,
      userName: userName,
    ));

    final snapshot = await _leadCollection.doc(leadId).get();
    if (!snapshot.exists) return false;
    return ReminderService.instance.scheduleFollowUpReminder(
      Lead.fromFirestore(snapshot),
    );
  }

  /// Clears a lead's scheduled follow-up and records why.
  ///
  /// Used when the customer has said no, so the lead stops showing up as
  /// due/overdue. Nothing is deleted — the reason lands on the timeline and the
  /// date can simply be set again.
  ///
  /// Writes the fields directly rather than going through [Lead.copyWith],
  /// which uses `?? this.x` for every nullable and therefore cannot clear
  /// nextFollowUpDate at all. The local alarm needs no explicit cancel:
  /// ReminderService drops stale ids on its next snapshot once the date is
  /// gone.
  Future<void> cancelFollowUp(String leadId, {String reason = ''}) async {
    final userName = await _authService.getCurrentUserDisplayName();
    final trimmed = reason.trim();

    await updateLeadFields(leadId, <String, dynamic>{
      'nextFollowUpDate': null,
      // Stale server-push bookkeeping; harmless but pointless to keep.
      'followUpReminderSentForDate': FieldValue.delete(),
    });

    await _eventsCollection(leadId).add(_eventData(
      action: 'Follow-up Cancelled',
      description: trimmed.isEmpty
          ? 'Follow-up cancelled'
          : 'Follow-up cancelled — $trimmed',
      userName: userName,
    ));
  }

  Future<void> updateLeadStatus(
    String leadId,
    String newStatus, {
    Lead? sourceLead,
    DateTime? installationDate,
  }) async {
    if (!Lead.statuses.contains(newStatus) && !Lead.tenderStatuses.contains(newStatus)) {
      throw ArgumentError.value(
        newStatus,
        'newStatus',
        'Status must be one of the valid statuses',
      );
    }

    final userName = await _authService.getCurrentUserDisplayName();
    final updateData = <String, dynamic>{
      'status': newStatus,
      'lastModified': FieldValue.serverTimestamp(),
    };
    if (newStatus == 'Won' && installationDate != null) {
      updateData['installationDate'] = Timestamp.fromDate(installationDate);
    }
    if (sourceLead != null && sourceLead.totalAmount > 0) {
      updateData['totalAmount'] = sourceLead.totalAmount;
    }
    if ((newStatus == 'Loss' || newStatus == 'Lost') && sourceLead != null) {
      updateData['lossReason'] = sourceLead.lossReason.trim();
    }
    await _leadCollection.doc(leadId).update(updateData);
    await _eventsCollection(leadId).add(_eventData(
      action: 'Status Change',
      description: 'Status changed to $newStatus',
      userName: userName,
    ));
  }

  /// Persists editable scalar fields from [lead]. Does not overwrite
  /// [Lead.creatorName] (managed at creation / admin flows).
  Future<void> updateLead(Lead lead) async {
    final ref = _leadCollection.doc(lead.id);

    // Read first so the save can be diffed: the details modal pushes the whole
    // form through here, so without this a status change or a new remark left
    // no timeline event and the CRM report never saw the work.
    Lead? previous;
    try {
      final before = await ref.get();
      if (before.exists) previous = Lead.fromFirestore(before);
    } catch (_) {}

    final data = lead.toFirestore()..remove('creatorName');
    data['lastModified'] = FieldValue.serverTimestamp();
    await ref.update(data);

    if (previous == null) return;
    try {
      final userName = await _authService.getCurrentUserDisplayName();

      if (previous.status.trim() != lead.status.trim() &&
          lead.status.trim().isNotEmpty) {
        await _eventsCollection(lead.id).add(_eventData(
          action: 'Status Change',
          description: 'Status changed to ${lead.status.trim()}',
          userName: userName,
        ));
      }

      final addedRemark = _newRemarkText(previous.remark, lead.remark);
      if (addedRemark.isNotEmpty) {
        await _eventsCollection(lead.id).add(_eventData(
          action: 'Note',
          description: addedRemark,
          userName: userName,
        ));
      }
    } catch (_) {
      // The lead itself is saved; a missing timeline entry must not fail it.
    }
  }

  /// The part of [next] that was not already in [previous].
  ///
  /// The remark field is append-only in the UI (`old \n\n---\n new`), so the
  /// event should carry just the new paragraph, not the whole history.
  static String _newRemarkText(String previous, String next) {
    final before = previous.trim();
    final after = next.trim();
    if (after.isEmpty || after == before) return '';
    var added = after;
    if (before.isNotEmpty && after.startsWith(before)) {
      added = after.substring(before.length).replaceFirst(RegExp(r'^\s*-{3,}\s*'), '').trim();
    }
    if (added.isEmpty) return '';
    return added.length > 500 ? '${added.substring(0, 500)}…' : added;
  }

  /// Merges a small set of named fields into a lead.
  ///
  /// Uses `update`, so only the keys passed in are touched — every other field
  /// on the document is left exactly as it is. Used for side-writes that must
  /// land immediately (e.g. an attachment pointer, right after the upload
  /// succeeds) without pushing the whole in-progress form.
  Future<void> updateLeadFields(
    String leadId,
    Map<String, dynamic> fields,
  ) async {
    if (fields.isEmpty) return;
    await _leadCollection.doc(leadId).update(<String, dynamic>{
      ...fields,
      'lastModified': FieldValue.serverTimestamp(),
    });
  }

  /// Points a lead's deal amount at a specific quotation.
  ///
  /// Writes only these keys, unlike [updateLead], which rewrites the whole
  /// document from the form.
  Future<void> updateLeadQuotationLink(
    String leadId, {
    required double amount,
    required String quotationId,
    required String quotationRefNo,
  }) async {
    await updateLeadFields(leadId, <String, dynamic>{
      'totalAmount': amount,
      'quotationId': quotationId,
      'quotationRefNo': quotationRefNo,
    });
  }

  Future<void> updateLeadTotalAmount(String leadId, double amount) async {
    await _leadCollection.doc(leadId).update(<String, dynamic>{
      'totalAmount': amount,
      'lastModified': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addNoteToLead(
    String leadId,
    String note,
    String userName,
  ) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return;

    await _leadCollection.doc(leadId).update(<String, dynamic>{
      'lastModified': FieldValue.serverTimestamp(),
    });
    await _eventsCollection(leadId).add(_eventData(
      action: 'Note',
      description: trimmed,
      userName: userName,
    ));
  }

  Future<List<String>> getRecentLeadMessages(
    String leadId, {
    int limit = 12,
  }) async {
    final snapshot = await _eventsCollection(
      leadId,
    ).orderBy('timestamp', descending: true).limit(limit).get();
    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          final action = (data['action'] as String? ?? '').trim();
          final description = (data['description'] as String? ?? '').trim();
          final merged = '$action $description'.trim();
          return merged;
        })
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> scheduleWhatsAppFollowUpSequence(
    String leadId,
    List<SmartWhatsAppFollowUp> sequence,
  ) async {
    if (sequence.isEmpty) return;

    final userName = await _authService.getCurrentUserDisplayName();
    final sorted = List<SmartWhatsAppFollowUp>.from(sequence)
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final firstDate = sorted.first.scheduledAt;

    final batch = _firestore.batch();
    for (final stage in sorted) {
      final ref = _smartFollowUpCollection(leadId).doc();
      batch.set(ref, <String, dynamic>{
        'channel': 'whatsapp',
        'status': 'scheduled',
        'dayOffset': stage.dayOffset,
        'message': stage.message,
        'scheduledAt': Timestamp.fromDate(stage.scheduledAt),
        'createdBy': userName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(_leadCollection.doc(leadId), <String, dynamic>{
      'nextFollowUpDate': Timestamp.fromDate(firstDate),
      'lastModified': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    await _eventsCollection(leadId).add(_eventData(
      action: 'Smart Follow-up Scheduled',
      description:
          '3-step WhatsApp sequence scheduled for day 0, day 3, and day 7.',
      userName: userName,
    ));
  }

  Future<void> deleteLead(String leadId) async {
    final leadRef = _leadCollection.doc(leadId);
    const chunk = 400;
    while (true) {
      final snap = await _eventsCollection(leadId).limit(chunk).get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await leadRef.delete();
  }

  Stream<List<EmployeeAssignee>> getAssignableEmployeesStream({int limit = 100}) {
    return _userCollection
        .where('role', isEqualTo: 'employee')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final employees =
              snapshot.docs
                  .map((doc) {
                    final data = doc.data();
                    final name = (data['name'] as String?)?.trim();
                    final label = (name != null && name.isNotEmpty)
                        ? name
                        : 'Unknown Employee';

                    return EmployeeAssignee(uid: doc.id, label: label);
                  })
                  .toList(growable: false)
                ..sort(
                  (a, b) =>
                      a.label.toLowerCase().compareTo(b.label.toLowerCase()),
                );
          return employees;
        });
  }

  Future<String> _resolveRole(String uid) async {
    final roleDoc = await _userCollection.doc(uid).get();
    final role = roleDoc.data()?['role'];
    if (role is String) {
      return role;
    }
    return 'employee';
  }


  /// Resolves `users/{uid}.name` for Kanban filters; falls back to a short uid hint.
  Future<Map<String, String>> getUserDisplayLabels(
    Iterable<String> uids,
  ) async {
    final unique = uids.map((u) => u.trim()).where((u) => u.isNotEmpty).toSet();
    if (unique.isEmpty) return {};

    final entries = await Future.wait(
      unique.map((uid) async {
        final doc = await _userCollection.doc(uid).get();
        final name = doc.data()?['name'];
        final label = name is String && name.trim().isNotEmpty
            ? name.trim()
            : 'Deleted Employee';
        return MapEntry(uid, label);
      }),
    );
    return Map<String, String>.fromEntries(entries);
  }
}

class EmployeeAssignee {
  const EmployeeAssignee({required this.uid, required this.label});

  final String uid;
  final String label;
}
