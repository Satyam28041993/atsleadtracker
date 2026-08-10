import 'package:cloud_firestore/cloud_firestore.dart';
import 'quote_request.dart';

class QuotationModel {
  const QuotationModel({
    required this.id,
    required this.leadId,
    required this.employeeId,
    required this.employeeName,
    required this.createdAt,
    required this.baseRefNo,
    required this.currentRefNo,
    required this.revision,
    required this.quoteRequest,
  });

  final String id;
  final String leadId;
  final String employeeId;
  final String employeeName;
  final DateTime createdAt;
  final String baseRefNo;
  final String currentRefNo;
  final int revision;
  final QuoteRequest quoteRequest;

  factory QuotationModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return QuotationModel(
      id: doc.id,
      leadId: data['leadId'] as String? ?? '',
      employeeId: data['employeeId'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      baseRefNo: data['baseRefNo'] as String? ?? '',
      currentRefNo: data['currentRefNo'] as String? ?? '',
      revision: data['revision'] as int? ?? 0,
      quoteRequest: QuoteRequest.fromJson(
        data['quoteRequest'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'leadId': leadId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'createdAt': FieldValue.serverTimestamp(),
      'baseRefNo': baseRefNo,
      'currentRefNo': currentRefNo,
      'revision': revision,
      'quoteRequest': quoteRequest.toJson(),
    };
  }

  QuotationModel copyWith({
    String? id,
    String? leadId,
    String? employeeId,
    String? employeeName,
    DateTime? createdAt,
    String? baseRefNo,
    String? currentRefNo,
    int? revision,
    QuoteRequest? quoteRequest,
  }) {
    return QuotationModel(
      id: id ?? this.id,
      leadId: leadId ?? this.leadId,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      createdAt: createdAt ?? this.createdAt,
      baseRefNo: baseRefNo ?? this.baseRefNo,
      currentRefNo: currentRefNo ?? this.currentRefNo,
      revision: revision ?? this.revision,
      quoteRequest: quoteRequest ?? this.quoteRequest,
    );
  }
}
