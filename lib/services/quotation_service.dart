import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quotation_model.dart';

/// Why a per-lead quotation read returned what it did.
///
/// The old API collapsed every outcome to `0.0`, which is how a
/// permission-denied query looked exactly like "no quotations exist".
enum QuotationLoadStatus { ok, denied, failed }

class QuotationsForLead {
  const QuotationsForLead(this.status, this.quotations);

  final QuotationLoadStatus status;

  /// Newest first — see [QuotationService.sortForLead].
  final List<QuotationModel> quotations;

  bool get isEmpty => quotations.isEmpty;

  QuotationModel? get latest =>
      quotations.isEmpty ? null : quotations.first;
}

class QuotationService {
  QuotationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _quotationsRef =>
      _firestore.collection('quotations');

  Stream<List<QuotationModel>> getQuotationsStream({String? employeeId}) {
    Query<Map<String, dynamic>> query = _quotationsRef;
    
    if (employeeId != null && employeeId.isNotEmpty) {
      query = query.where('employeeId', isEqualTo: employeeId);
    }
    
    return query.snapshots().map(
          (snapshot) {
            final docs = snapshot.docs.map(QuotationModel.fromFirestore).toList();
            docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return docs;
          }
        );
  }

  Future<QuotationModel> saveQuotation(QuotationModel quotation) async {
    if (quotation.id.isEmpty) {
      final docRef = await _quotationsRef.add(quotation.toFirestore());
      return quotation.copyWith(id: docRef.id);
    }

    final data = quotation.toFirestore()..remove('createdAt');
    await _quotationsRef.doc(quotation.id).set(data, SetOptions(merge: true));
    return quotation;
  }

  Future<void> deleteQuotation(String id) async {
    await _quotationsRef.doc(id).delete();
  }

  /// All quotations on a lead, newest first.
  ///
  /// Query shape matters. firestore.rules only allows a `quotations` read when
  /// `isAdmin()` OR `employeeId == uid`, and a LIST query has to prove that
  /// from the query itself — so the old `where('leadId')`-only query was
  /// rejected outright for every employee. Because that failure was swallowed
  /// by a bare `catch`, the lead simply showed no quotation amount and nobody
  /// could tell why.
  ///
  /// Narrow shape first (legal for everyone), widening only when it finds
  /// nothing:
  ///   narrow: employeeId == uid AND leadId == id
  ///   broad : leadId == id                       (admins only)
  ///
  /// Two equality filters on different fields merge the automatic indexes, so
  /// no composite index is needed. Don't add an `orderBy` here without adding
  /// one to firestore.indexes.json — [sortForLead] sorts client-side instead.
  Future<QuotationsForLead> getQuotationsForLead(
    String leadId, {
    required String currentUid,
  }) async {
    final id = leadId.trim();
    if (id.isEmpty) {
      return const QuotationsForLead(QuotationLoadStatus.ok, <QuotationModel>[]);
    }

    if (currentUid.isNotEmpty) {
      try {
        final snap = await _quotationsRef
            .where('employeeId', isEqualTo: currentUid)
            .where('leadId', isEqualTo: id)
            .get();
        if (snap.docs.isNotEmpty) {
          return QuotationsForLead(
            QuotationLoadStatus.ok,
            sortForLead(snap.docs.map(QuotationModel.fromFirestore).toList()),
          );
        }
      } catch (_) {
        // Fall through and let the broad query report the real outcome.
      }
    }

    // Nothing of our own. Either none exist, or they belong to someone else —
    // only an admin can tell the two apart.
    try {
      final snap = await _quotationsRef.where('leadId', isEqualTo: id).get();
      return QuotationsForLead(
        QuotationLoadStatus.ok,
        sortForLead(snap.docs.map(QuotationModel.fromFirestore).toList()),
      );
    } on FirebaseException catch (e) {
      return QuotationsForLead(
        e.code == 'permission-denied'
            ? QuotationLoadStatus.denied
            : QuotationLoadStatus.failed,
        const <QuotationModel>[],
      );
    } catch (_) {
      return const QuotationsForLead(
        QuotationLoadStatus.failed,
        <QuotationModel>[],
      );
    }
  }

  /// The quotation a lead's amount should follow: the highest revision inside
  /// the newest baseRefNo group. Note this is the LATEST revision, not the
  /// largest amount — a revision that lowers the price must win.
  Future<QuotationModel?> getLatestQuotationForLead(
    String leadId, {
    required String currentUid,
  }) async {
    final result = await getQuotationsForLead(leadId, currentUid: currentUid);
    return result.latest;
  }

  /// Newest baseRefNo group first; highest revision first within a group.
  static List<QuotationModel> sortForLead(List<QuotationModel> quotes) {
    String keyOf(QuotationModel q) =>
        q.baseRefNo.isNotEmpty ? q.baseRefNo : q.id;

    final groupTime = <String, DateTime>{};
    final pending = <String>{};
    for (final q in quotes) {
      final k = keyOf(q);
      if (!q.hasServerCreatedAt) pending.add(k);
      final t = groupTime[k];
      if (t == null || q.createdAt.isAfter(t)) groupTime[k] = q.createdAt;
    }

    final out = [...quotes];
    out.sort((a, b) {
      final ka = keyOf(a);
      final kb = keyOf(b);
      if (ka != kb) {
        // A doc whose serverTimestamp hasn't resolved was written by this
        // client seconds ago, so its group really is the newest.
        final pa = pending.contains(ka);
        final pb = pending.contains(kb);
        if (pa != pb) return pa ? -1 : 1;
        return groupTime[kb]!.compareTo(groupTime[ka]!);
      }
      if (a.revision != b.revision) return b.revision.compareTo(a.revision);
      return b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }
}
