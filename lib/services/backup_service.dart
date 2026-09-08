import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/lead_model.dart';
import '../models/product_model.dart';
import '../models/quotation_model.dart';
import 'pdf_service.dart';

enum BackupKind { leads, tenders, quotations, products }

enum QuotationBackupOption { csv, zip, both }

class BackupFile {
  const BackupFile({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class BackupService {
  BackupService({FirebaseFirestore? firestore, PdfService? pdfService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _pdfService = pdfService ?? PdfService();

  final FirebaseFirestore _firestore;
  final PdfService _pdfService;
  static final DateFormat _stamp = DateFormat('yyyy-MM-dd_HHmmss');

  Future<BackupFile> buildBackup(BackupKind kind) async {
    switch (kind) {
      case BackupKind.leads:
        return _buildLeadsBackup(isTender: false);
      case BackupKind.tenders:
        return _buildLeadsBackup(isTender: true);
      case BackupKind.quotations:
        throw UnsupportedError(
          'Use buildQuotationBackups() for quotation exports.',
        );
      case BackupKind.products:
        return _buildProductsBackup();
    }
  }

  Future<BackupFile> _buildLeadsBackup({required bool isTender}) async {
    final snap = await _firestore.collection('leads').get();
    // A backup is a full archive, so it deliberately keeps the legacy AMC
    // clones that the rest of the app now hides.
    final leads = leadsFromDocs(snap.docs, includeAmc: true)
        .where((l) => l.isTender == isTender)
        .toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));

    final namesByUid = await _loadEmployeeNames();

    final headers = isTender
        ? <String>[
            'Name',
            'Company',
            'Phone',
            'Email',
            'Status',
            'Assigned To',
            'Lead Date',
            'Created At',
            'Location',
            'Website',
            'Source',
            'Remark',
            'Requirement',
            'Model No',
            'Target Gas',
            'Measuring Range',
            'Industry Sector',
            'Total Amount',
            'Creator Name',
            'Is AMC Lead',
            'Installation Date',
            'Next Follow Up Date',
            'Last Modified',
            'Bid No',
            'Quantity',
            'Due Date',
            'Technical Status',
            'Commercial Status',
            'Loss Reason',
          ]
        : <String>[
            'Name',
            'Company',
            'Phone',
            'Email',
            'Status',
            'Assigned To',
            'Lead Date',
            'Created At',
            'Location',
            'Website',
            'Source',
            'Remark',
            'Requirement',
            'Model No',
            'Target Gas',
            'Measuring Range',
            'Industry Sector',
            'Total Amount',
            'Creator Name',
            'Is AMC Lead',
            'Installation Date',
            'Next Follow Up Date',
            'Last Modified',
          ];

    final rows = <List<String>>[
      for (final lead in leads)
        isTender
            ? _tenderRow(lead, namesByUid)
            : _leadRow(lead, namesByUid),
    ];

    final prefix = isTender ? 'tenders_backup' : 'leads_backup';
    return BackupFile(
      bytes: _toCsvBytes(headers, rows),
      fileName: '${prefix}_${_stamp.format(DateTime.now())}.csv',
    );
  }

  List<String> _leadRow(Lead lead, Map<String, String> namesByUid) {
    final first = lead.activeProductLines.isNotEmpty
        ? lead.activeProductLines.first
        : null;
    return <String>[
      lead.name,
      lead.company,
      lead.phone,
      lead.email,
      lead.status,
      _assignedLabel(lead.assignedTo, namesByUid),
      _fmt(lead.leadDate),
      _fmt(lead.createdAt),
      lead.location,
      lead.website,
      lead.source,
      lead.remark,
      first?.requirement ?? lead.requirement,
      first?.modelNo ?? lead.modelNo,
      lead.targetGas,
      lead.measuringRange,
      lead.industrySector,
      lead.totalAmount.toString(),
      lead.creatorName,
      lead.isAmcLead.toString(),
      _fmtOpt(lead.installationDate),
      _fmtOpt(lead.nextFollowUpDate),
      _fmt(lead.lastModified),
    ];
  }

  List<String> _tenderRow(Lead lead, Map<String, String> namesByUid) {
    return <String>[
      ..._leadRow(lead, namesByUid),
      lead.bidNo,
      lead.quantity.toString(),
      _fmtOpt(lead.dueDate),
      lead.technicalStatus,
      lead.commercialStatus,
      lead.lossReason,
    ];
  }

  Future<List<BackupFile>> buildQuotationBackups(
    QuotationBackupOption option,
  ) async {
    final stamp = _stamp.format(DateTime.now());
    final files = <BackupFile>[];

    if (option == QuotationBackupOption.csv ||
        option == QuotationBackupOption.both) {
      files.add(await _buildQuotationsCsvBackup(stamp: stamp));
    }
    if (option == QuotationBackupOption.zip ||
        option == QuotationBackupOption.both) {
      files.add(await _buildQuotationsPdfZipBackup(stamp: stamp));
    }
    return files;
  }

  Future<BackupFile> _buildQuotationsCsvBackup({String? stamp}) async {
    final snap = await _firestore.collection('quotations').get();
    final quotes = snap.docs.map(QuotationModel.fromFirestore).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    const headers = <String>[
      'Employee Name',
      'Created At',
      'Base Ref No',
      'Current Ref No',
      'Revision',
      'Customer Name',
      'Company Name',
      'Location',
      'Phone',
      'Email',
      'Product Name',
      'Total Amount',
      'Ref No',
    ];

    final namesByUid = await _loadEmployeeNames();

    final rows = <List<String>>[
      for (final q in quotes)
        <String>[
          _employeeLabel(q.employeeId, q.employeeName, namesByUid),
          _fmt(q.createdAt),
          q.baseRefNo,
          q.currentRefNo,
          q.revision.toString(),
          q.quoteRequest.customerName,
          q.quoteRequest.companyName,
          q.quoteRequest.location,
          q.quoteRequest.phone,
          q.quoteRequest.email,
          q.quoteRequest.productName,
          q.quoteRequest.totalAmount.toStringAsFixed(2),
          q.quoteRequest.refNo,
        ],
    ];

    return BackupFile(
      bytes: _toCsvBytes(headers, rows),
      fileName: 'quotations_backup_${stamp ?? _stamp.format(DateTime.now())}.csv',
    );
  }

  Future<BackupFile> _buildQuotationsPdfZipBackup({String? stamp}) async {
    final snap = await _firestore.collection('quotations').get();
    final quotes = snap.docs.map(QuotationModel.fromFirestore).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final mobiles = await _loadEmployeeMobiles();
    final archive = Archive();
    final usedNames = <String>{};
    var generated = 0;

    for (final quote in quotes) {
      try {
        final lead = _leadForQuotation(quote);
        final mobile = mobiles[quote.employeeId];
        final bytes = await _pdfService.generateQuoteData(
          lead,
          quote.quoteRequest,
          creatorMobile: mobile?.isNotEmpty == true ? mobile : null,
          creatorName: quote.employeeName,
        );
        final fileName = _uniquePdfName(quote, usedNames);
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        generated++;
      } catch (_) {}
    }

    if (generated == 0) {
      throw StateError('No quotation PDFs could be generated.');
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null || zipData.isEmpty) {
      throw StateError('Could not create quotation ZIP file.');
    }

    return BackupFile(
      bytes: Uint8List.fromList(zipData),
      fileName:
          'quotations_pdfs_${stamp ?? _stamp.format(DateTime.now())}.zip',
    );
  }

  Future<Map<String, String>> _loadEmployeeMobiles() async {
    final snap = await _firestore.collection('users').get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final mobile = doc.data()['mobile']?.toString().trim() ?? '';
      if (mobile.isNotEmpty) {
        out[doc.id] = mobile;
      }
    }
    return out;
  }

  Future<Map<String, String>> _loadEmployeeNames() async {
    final snap = await _firestore.collection('users').get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final name = doc.data()['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        out[doc.id] = name;
      }
    }
    return out;
  }

  String _assignedLabel(String uid, Map<String, String> namesByUid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return 'Unassigned';
    return namesByUid[trimmed] ?? 'Unknown Employee';
  }

  String _employeeLabel(
    String uid,
    String storedName,
    Map<String, String> namesByUid,
  ) {
    final fromProfile = namesByUid[uid.trim()];
    if (fromProfile != null && fromProfile.isNotEmpty) {
      return fromProfile;
    }
    return _formatStoredEmployeeLabel(storedName);
  }

  String _formatStoredEmployeeLabel(String storedName) {
    var label = storedName.trim();
    if (label.isEmpty) return 'Unknown';
    if (label.toLowerCase() == 'atsadmin@gmail.com') return 'Admin';
    if (label.contains('@')) {
      label = label.split('@').first;
      if (label.isNotEmpty) {
        label = label[0].toUpperCase() + label.substring(1);
      }
    }
    return label;
  }

  Lead _leadForQuotation(QuotationModel quote) {
    return Lead(
      id: quote.leadId,
      source: 'Backup',
      createdAt: quote.createdAt,
      name: quote.quoteRequest.customerName,
      company: quote.quoteRequest.companyName,
      location: quote.quoteRequest.location,
      phone: quote.quoteRequest.phone,
      email: quote.quoteRequest.email,
      requirement: quote.quoteRequest.productName,
      status: 'Generated',
      assignedTo: quote.employeeId,
      remark: '',
      website: '',
    );
  }

  String _uniquePdfName(QuotationModel quote, Set<String> usedNames) {
    final nameSource = quote.quoteRequest.companyName.isNotEmpty
        ? quote.quoteRequest.companyName
        : quote.quoteRequest.customerName;
    final safeName = nameSource.isEmpty
        ? 'quotation'
        : nameSource.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final number = _shortQuoteNumber(quote.currentRefNo);
    var base = number.isEmpty
        ? '${safeName}_quotation.pdf'
        : '${safeName}_$number.pdf';
    if (!usedNames.contains(base)) {
      usedNames.add(base);
      return base;
    }
    final stem = base.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    var i = 2;
    while (usedNames.contains('${stem}_$i.pdf')) {
      i++;
    }
    base = '${stem}_$i.pdf';
    usedNames.add(base);
    return base;
  }

  String _shortQuoteNumber(String ref) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split('/');
    final candidate = parts.length >= 2 ? parts[1].trim() : trimmed;
    return candidate.replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  Future<BackupFile> _buildProductsBackup() async {
    final snap = await _firestore.collection('products').get();
    final products = snap.docs.map(Product.fromFirestore).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    const headers = <String>[
      'ID',
      'Name',
      'Make',
      'Model',
      'HSN No',
      'Specification',
      'Accessories',
      'Parameters Measured',
      'Base Price',
      'Image URL',
    ];

    final rows = <List<String>>[
      for (final p in products)
        <String>[
          p.id,
          p.name,
          p.make,
          p.model,
          p.hsnNo,
          p.specification,
          p.accessories,
          p.parametersMeasured,
          p.basePrice.toString(),
          p.imageUrl,
        ],
    ];

    return BackupFile(
      bytes: _toCsvBytes(headers, rows),
      fileName: 'products_backup_${_stamp.format(DateTime.now())}.csv',
    );
  }

  static String _fmt(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value);

  static String _fmtOpt(DateTime? value) =>
      value == null ? '' : _fmt(value);

  static Uint8List _toCsvBytes(List<String> headers, List<List<String>> rows) {
    final buffer = StringBuffer();
    buffer.write(_csvLine(headers));
    for (final row in rows) {
      buffer.write(_csvLine(row));
    }
    // UTF-8 BOM helps Excel on Windows open Unicode correctly.
    return Uint8List.fromList(utf8.encode('\uFEFF${buffer.toString()}'));
  }

  static String _csvLine(List<String> cells) {
    return '${cells.map(_escapeCsvCell).join(',')}\n';
  }

  static String _escapeCsvCell(String value) {
    final normalized = value.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    if (normalized.contains('"') ||
        normalized.contains(',') ||
        normalized.contains('\r')) {
      return '"${normalized.replaceAll('"', '""')}"';
    }
    return normalized;
  }
}
