import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quotation_model.dart';

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

  /// Highest quotation total for a lead (0 if none).
  Future<double> getMaxAmountForLead(String leadId) async {
    final trimmed = leadId.trim();
    if (trimmed.isEmpty) return 0;
    try {
      final snap = await _quotationsRef
          .where('leadId', isEqualTo: trimmed)
          .get();
      var maxAmt = 0.0;
      for (final doc in snap.docs) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          final amt = quote.quoteRequest.totalAmount;
          if (amt > maxAmt) maxAmt = amt;
        } catch (_) {}
      }
      return maxAmt;
    } catch (_) {
      return 0;
    }
  }
}
