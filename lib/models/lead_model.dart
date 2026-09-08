import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/flexible_date_parse.dart';
import 'lead_product_line.dart';

class Lead {
  Lead({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.company,
    required this.status,
    required this.assignedTo,
    required this.createdAt,
    DateTime? leadDate,
    required this.remark,
    required this.location,
    required this.website,
    String requirement = '',
    this.source = '',
    String modelNo = '',
    List<LeadProductLine>? productLines,
    this.targetGas = '',
    this.measuringRange = '',
    this.industrySector = '',
    this.installationDate,
    this.nextFollowUpDate,
    this.isAmcLead = false,
    this.quotationId = '',
    this.quotationRefNo = '',
    this.creatorName = 'System',
    this.totalAmount = 0,
    this.isTender = false,
    this.bidNo = '',
    this.quantity = 1,
    this.dueDate,
    this.technicalStatus = '',
    this.commercialStatus = '',
    this.lossReason = '',
    this.designation = '',
    this.projectName = '',
    this.quantityRequired = '',
    this.deliveryArea = '',
    this.deliveryPoc = '',
    this.specification = '',
    this.poNumber = '',
    this.poAttachmentUrl,
    this.poAttachmentName,
    this.invoiceNumber = '',
    this.invoiceAttachmentUrl,
    this.invoiceAttachmentName,
    DateTime? lastModified,
  }) : productLines = _normalizeProductLines(
         productLines,
         requirement,
         modelNo,
       ),
       requirement = _normalizeProductLines(
         productLines,
         requirement,
         modelNo,
       ).first.requirement,
       modelNo = _normalizeProductLines(
         productLines,
         requirement,
         modelNo,
       ).first.modelNo,
       leadDate = dateOnly(leadDate ?? createdAt),
       lastModified = lastModified ?? createdAt;

  static List<LeadProductLine> _normalizeProductLines(
    List<LeadProductLine>? lines,
    String requirement,
    String modelNo,
  ) {
    if (lines != null && lines.isNotEmpty) {
      final filtered = lines
          .where((l) => !l.isEmpty)
          .map(
            (l) => LeadProductLine(
              requirement: l.requirement.trim(),
              modelNo: l.modelNo.trim(),
            ),
          )
          .toList();
      if (filtered.isNotEmpty) return filtered;
    }
    final req = requirement.trim();
    final model = modelNo.trim();
    if (req.isNotEmpty || model.isNotEmpty) {
      return [LeadProductLine(requirement: req, modelNo: model)];
    }
    return const [LeadProductLine()];
  }

  /// Non-empty product lines only (for display / quote prefill).
  List<LeadProductLine> get activeProductLines =>
      productLines.where((l) => !l.isEmpty).toList();

  /// Short summary for Kanban cards: "Prod A, Prod B" or "Prod A (+2 more)".
  String get productsSummary {
    final active = activeProductLines;
    if (active.isEmpty) return '';
    if (active.length == 1) return active.first.requirement;
    if (active.length == 2) {
      return '${active[0].requirement}, ${active[1].requirement}';
    }
    return '${active.first.requirement} (+${active.length - 1} more)';
  }

  static const List<String> statuses = <String>[
    'New',
    'Contacted',
    'Proposal',
    'Follow-up',
    'Won',
    'Lost',
  ];

  static const List<String> tenderStatuses = <String>[
    'New',
    'Technical Evaluation',
    'Query Raised',
    'Query Responded',
    'Qualified',
    'Reverse Auction(RA)',
    'Won',
    'Loss',
    'Disqualified',
  ];

  /// Maps retired tender status labels to current pipeline columns.
  static String migrateLegacyTenderStatus(String status) {
    switch (status) {
      case 'In Process':
        return 'Technical Evaluation';
      case 'Query':
        return 'Query Raised';
      default:
        return status;
    }
  }

  /// Column key for Kanban grouping (handles legacy stored statuses).
  static String kanbanColumnFor(String status, {required bool isTender}) {
    if (!isTender) {
      return statuses.contains(status) ? status : statuses.first;
    }
    final migrated = migrateLegacyTenderStatus(status);
    return tenderStatuses.contains(migrated) ? migrated : tenderStatuses.first;
  }

  final String id;
  final String name;
  final String phone;
  final String email;
  final String company;
  final String status;
  final String assignedTo;

  /// When the lead/tender was received (may differ from CRM entry time).
  final DateTime leadDate;

  /// When this record was created in the CRM.
  final DateTime createdAt;
  final String remark;
  final String location;
  final String website;

  /// First product name (legacy + WhatsApp templates).
  final String requirement;
  final String source;

  /// First product model (legacy).
  final String modelNo;

  /// All quoted / interested products on this lead or tender.
  final List<LeadProductLine> productLines;

  final String targetGas;
  final String measuringRange;
  final String industrySector;
  final DateTime? installationDate;
  final DateTime? nextFollowUpDate;
  final bool isAmcLead;

  /// Quotation document backing [totalAmount], and its display number.
  ///
  /// Two fields on purpose: the id answers "is the linked quote still the
  /// latest revision?", while the ref number is what the UI and exports show
  /// without needing a join. Empty means no quotation is linked yet.
  final String quotationId;
  final String quotationRefNo;
  final String creatorName;

  /// Deal value in account currency (e.g. INR) for pipeline and revenue analytics.
  final double totalAmount;

  /// Last time this lead document was modified (server or client writes).
  final DateTime lastModified;

  // Tender specific fields
  final bool isTender;
  final String bidNo;
  final int quantity;
  final DateTime? dueDate;
  final String technicalStatus;
  final String commercialStatus;
  final String lossReason;
  final String designation;

  // ── Enquiry detail ────────────────────────────────────────────────────────
  // Optional throughout: leads created before these existed simply read back
  // as empty strings, and nothing in the app requires them to be filled.

  /// Customer's name for the project this enquiry belongs to.
  final String projectName;

  /// Quantity as the customer stated it — free text ("2 nos", "500 mtr/day").
  final String quantityRequired;

  /// Where the goods must be delivered.
  final String deliveryArea;

  /// Contact person at the delivery site.
  final String deliveryPoc;

  /// Technical specification / scope notes for this enquiry.
  final String specification;

  // ── Order & billing ───────────────────────────────────────────────────────

  /// Customer's purchase order number, once the deal is won.
  final String poNumber;

  /// Firebase Storage download URL of the uploaded PO copy.
  final String? poAttachmentUrl;

  /// Original file name of the uploaded PO copy, for display.
  final String? poAttachmentName;

  /// Our invoice number raised against this order.
  final String invoiceNumber;

  /// Firebase Storage download URL of the uploaded invoice copy.
  final String? invoiceAttachmentUrl;

  /// Original file name of the uploaded invoice copy, for display.
  final String? invoiceAttachmentName;

  bool get hasPoAttachment => (poAttachmentUrl ?? '').trim().isNotEmpty;

  bool get hasInvoiceAttachment =>
      (invoiceAttachmentUrl ?? '').trim().isNotEmpty;

  factory Lead.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final remarkRaw = data['remark'] ?? data['notes'];
    final legacyReq = (data['requirement'] as String? ?? '').trim();
    final legacyModel =
        (data['modelNo'] as String? ?? data['modelCode'] as String? ?? '')
            .trim();

    List<LeadProductLine>? parsedLines;
    final rawLines = data['productLines'] as List<dynamic>?;
    if (rawLines != null && rawLines.isNotEmpty) {
      parsedLines = rawLines
          .map((e) => LeadProductLine.fromJson(e as Map<String, dynamic>))
          .where((l) => !l.isEmpty)
          .toList();
    }

    return Lead(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      phone: (data['phone'] as String? ?? '').trim(),
      email: (data['email'] as String? ?? '').trim(),
      company: (data['company'] as String? ?? '').trim(),
      status: _normalizeStatus(
        data['status'] as String?,
        isTender: data['isTender'] as bool? ?? false,
      ),
      assignedTo: (data['assignedTo'] as String? ?? '').trim(),
      createdAt: _parseCreatedAt(data['createdAt']),
      leadDate: _parseLeadDate(data),
      remark: (remarkRaw is String ? remarkRaw : '').trim(),
      location: (data['location'] as String? ?? '').trim(),
      website: (data['website'] as String? ?? '').trim(),
      productLines: parsedLines,
      requirement: legacyReq,
      source: (data['source'] as String? ?? '').trim(),
      modelNo: legacyModel,
      targetGas: (data['targetGas'] as String? ?? '').trim(),
      measuringRange: (data['measuringRange'] as String? ?? '').trim(),
      industrySector: (data['industrySector'] as String? ?? '').trim(),
      installationDate: _parseOptionalDate(data['installationDate']),
      nextFollowUpDate: _parseOptionalDate(data['nextFollowUpDate']),
      isAmcLead: data['isAmcLead'] as bool? ?? false,
      quotationId: (data['quotationId'] as String? ?? '').trim(),
      quotationRefNo: (data['quotationRefNo'] as String? ?? '').trim(),
      creatorName: _parseCreatorName(data['creatorName']),
      totalAmount: _parseAmount(data['totalAmount']),
      lastModified: _parseLastModified(data['lastModified'], data['createdAt']),
      isTender: data['isTender'] as bool? ?? false,
      bidNo: (data['bidNo'] as String? ?? '').trim(),
      quantity: data['quantity'] as int? ?? 1,
      dueDate: _parseOptionalDate(data['dueDate']),
      technicalStatus: (data['technicalStatus'] as String? ?? '').trim(),
      commercialStatus: (data['commercialStatus'] as String? ?? '').trim(),
      lossReason: (data['lossReason'] as String? ?? '').trim(),
      designation: (data['designation'] as String? ?? '').trim(),
      projectName: (data['projectName'] as String? ?? '').trim(),
      quantityRequired: (data['quantityRequired'] as String? ?? '').trim(),
      deliveryArea: (data['deliveryArea'] as String? ?? '').trim(),
      deliveryPoc: (data['deliveryPoc'] as String? ?? '').trim(),
      specification: (data['specification'] as String? ?? '').trim(),
      poNumber: (data['poNumber'] as String? ?? '').trim(),
      poAttachmentUrl: _parseOptionalString(data['poAttachmentUrl']),
      poAttachmentName: _parseOptionalString(data['poAttachmentName']),
      invoiceNumber: (data['invoiceNumber'] as String? ?? '').trim(),
      invoiceAttachmentUrl: _parseOptionalString(data['invoiceAttachmentUrl']),
      invoiceAttachmentName: _parseOptionalString(data['invoiceAttachmentName']),
    );
  }

  static String? _parseOptionalString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  Map<String, dynamic> toFirestore() {
    final active = activeProductLines;
    final first = active.isNotEmpty ? active.first : const LeadProductLine();
    return <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'company': company.trim(),
      'status': _normalizeStatus(status, isTender: isTender),
      'assignedTo': assignedTo.trim(),
      'leadDate': Timestamp.fromDate(leadDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'remark': remark.trim(),
      'location': location.trim(),
      'website': website.trim(),
      'productLines': active.map((e) => e.toJson()).toList(),
      'requirement': first.requirement,
      'source': source.trim(),
      'modelNo': first.modelNo,
      'targetGas': targetGas.trim(),
      'measuringRange': measuringRange.trim(),
      'industrySector': industrySector.trim(),
      'installationDate': installationDate != null
          ? Timestamp.fromDate(installationDate!)
          : null,
      'nextFollowUpDate': nextFollowUpDate != null
          ? Timestamp.fromDate(nextFollowUpDate!)
          : null,
      'isAmcLead': isAmcLead,
      'quotationId': quotationId.trim(),
      'quotationRefNo': quotationRefNo.trim(),
      'creatorName': creatorName.trim(),
      'totalAmount': totalAmount,
      'lastModified': Timestamp.fromDate(lastModified),
      'isTender': isTender,
      'bidNo': bidNo.trim(),
      'quantity': quantity,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'technicalStatus': technicalStatus.trim(),
      'commercialStatus': commercialStatus.trim(),
      'lossReason': lossReason.trim(),
      'designation': designation.trim(),
      'projectName': projectName.trim(),
      'quantityRequired': quantityRequired.trim(),
      'deliveryArea': deliveryArea.trim(),
      'deliveryPoc': deliveryPoc.trim(),
      'specification': specification.trim(),
      'poNumber': poNumber.trim(),
      'poAttachmentUrl': poAttachmentUrl,
      'poAttachmentName': poAttachmentName,
      'invoiceNumber': invoiceNumber.trim(),
      'invoiceAttachmentUrl': invoiceAttachmentUrl,
      'invoiceAttachmentName': invoiceAttachmentName,
    };
  }

  Lead copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? company,
    String? status,
    String? assignedTo,
    DateTime? createdAt,
    DateTime? leadDate,
    String? remark,
    String? location,
    String? website,
    List<LeadProductLine>? productLines,
    String? requirement,
    String? modelNo,
    String? source,
    String? targetGas,
    String? measuringRange,
    String? industrySector,
    DateTime? installationDate,
    DateTime? nextFollowUpDate,
    bool? isAmcLead,
    String? quotationId,
    String? quotationRefNo,
    String? creatorName,
    double? totalAmount,
    bool? isTender,
    String? bidNo,
    int? quantity,
    DateTime? dueDate,
    String? technicalStatus,
    String? commercialStatus,
    String? lossReason,
    String? designation,
    String? projectName,
    String? quantityRequired,
    String? deliveryArea,
    String? deliveryPoc,
    String? specification,
    String? poNumber,
    String? poAttachmentUrl,
    String? poAttachmentName,
    String? invoiceNumber,
    String? invoiceAttachmentUrl,
    String? invoiceAttachmentName,
    DateTime? lastModified,
  }) {
    return Lead(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      company: company ?? this.company,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      createdAt: createdAt ?? this.createdAt,
      leadDate: leadDate ?? this.leadDate,
      remark: remark ?? this.remark,
      location: location ?? this.location,
      website: website ?? this.website,
      productLines: productLines ?? this.productLines,
      requirement: requirement ?? this.requirement,
      modelNo: modelNo ?? this.modelNo,
      source: source ?? this.source,
      targetGas: targetGas ?? this.targetGas,
      measuringRange: measuringRange ?? this.measuringRange,
      industrySector: industrySector ?? this.industrySector,
      installationDate: installationDate ?? this.installationDate,
      nextFollowUpDate: nextFollowUpDate ?? this.nextFollowUpDate,
      isAmcLead: isAmcLead ?? this.isAmcLead,
      quotationId: quotationId ?? this.quotationId,
      quotationRefNo: quotationRefNo ?? this.quotationRefNo,
      creatorName: creatorName ?? this.creatorName,
      totalAmount: totalAmount ?? this.totalAmount,
      isTender: isTender ?? this.isTender,
      bidNo: bidNo ?? this.bidNo,
      quantity: quantity ?? this.quantity,
      dueDate: dueDate ?? this.dueDate,
      technicalStatus: technicalStatus ?? this.technicalStatus,
      commercialStatus: commercialStatus ?? this.commercialStatus,
      lossReason: lossReason ?? this.lossReason,
      designation: designation ?? this.designation,
      projectName: projectName ?? this.projectName,
      quantityRequired: quantityRequired ?? this.quantityRequired,
      deliveryArea: deliveryArea ?? this.deliveryArea,
      deliveryPoc: deliveryPoc ?? this.deliveryPoc,
      specification: specification ?? this.specification,
      poNumber: poNumber ?? this.poNumber,
      poAttachmentUrl: poAttachmentUrl ?? this.poAttachmentUrl,
      poAttachmentName: poAttachmentName ?? this.poAttachmentName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceAttachmentUrl: invoiceAttachmentUrl ?? this.invoiceAttachmentUrl,
      invoiceAttachmentName:
          invoiceAttachmentName ?? this.invoiceAttachmentName,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  static DateTime _parseLastModified(dynamic lastModified, dynamic createdAt) {
    if (lastModified is Timestamp) return lastModified.toDate();
    if (lastModified is DateTime) return lastModified;
    return _parseCreatedAt(createdAt);
  }

  static double _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
    }
    return 0;
  }

  static String _parseCreatorName(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'System';
  }

  static String _normalizeStatus(String? value, {required bool isTender}) {
    if (value == null || value.trim().isEmpty) {
      return isTender ? tenderStatuses.first : statuses.first;
    }
    final trimmed = value.trim();
    if (isTender) {
      final migrated = migrateLegacyTenderStatus(trimmed);
      if (tenderStatuses.contains(migrated)) return migrated;
      return tenderStatuses.first;
    }
    if (statuses.contains(trimmed)) return trimmed;
    return statuses.first;
  }

  static DateTime _parseCreatedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static DateTime _parseLeadDate(Map<String, dynamic> data) {
    final raw = data['leadDate'];
    if (raw != null) {
      final parsed = _parseOptionalDate(raw);
      if (parsed != null) return dateOnly(parsed);
    }
    return dateOnly(_parseCreatedAt(data['createdAt']));
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// Maps Firestore documents to [Lead]s, dropping the auto-generated AMC
/// clones.
///
/// Winning a lead used to write a full duplicate lead document (`isAmcLead:
/// true`) dated 11 months out as an "AMC follow-up". That auto-creation is
/// gone, but the clones already in Firestore would still pad lead counts,
/// skew the conversion rate, and — being future-dated — sit at the top of
/// every list. They are hidden rather than deleted, so nothing is lost.
///
/// Use this instead of `.map(Lead.fromFirestore)` wherever leads are read.
List<Lead> leadsFromDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
  bool includeAmc = false,
}) {
  final leads = docs.map(Lead.fromFirestore);
  return (includeAmc ? leads : leads.where((l) => !l.isAmcLead))
      .toList(growable: false);
}
