import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/flexible_date_parse.dart';

class BulkUploadProgress {
  const BulkUploadProgress({
    required this.processedRows,
    required this.totalRows,
    required this.uploadedRows,
    required this.failedRows,
  });

  final int processedRows;
  final int totalRows;
  final int uploadedRows;
  final int failedRows;
}

class BulkUploadSummary {
  const BulkUploadSummary({
    required this.uploadedRows,
    required this.failedRows,
    required this.totalRows,
    required this.failureMessages,
  });

  final int uploadedRows;
  final int failedRows;
  final int totalRows;
  final List<String> failureMessages;
}

class BulkUploadService {
  BulkUploadService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const int _maxBulkProductLines = 5;

  static const List<String> _adminHeaders = <String>[
    'Source',
    'Lead Date',
    'Company Name',
    'Customer Name',
    'Contact No.',
    'Email ID',
    'Location',
    'Requirement',
    'Model No',
    'Requirement 2',
    'Model No 2',
    'Requirement 3',
    'Model No 3',
    'Requirement 4',
    'Model No 4',
    'Requirement 5',
    'Model No 5',
    'Remark',
    'Assigned To',
  ];

  static const List<String> _employeeHeaders = <String>[
    'Source',
    'Lead Date',
    'Company Name',
    'Customer Name',
    'Contact No.',
    'Email ID',
    'Location',
    'Requirement',
    'Model No',
    'Requirement 2',
    'Model No 2',
    'Requirement 3',
    'Model No 3',
    'Requirement 4',
    'Model No 4',
    'Requirement 5',
    'Model No 5',
    'Remark',
  ];

  static const List<String> _adminTenderHeaders = <String>[
    'Organization Name',
    'Lead Date',
    'Bid No',
    'QTY',
    'Product Name',
    'Model No',
    'Product Name 2',
    'Model No 2',
    'Product Name 3',
    'Model No 3',
    'Product Name 4',
    'Model No 4',
    'Product Name 5',
    'Model No 5',
    'Due Date',
    'Price',
    'Technical',
    'Commercial',
    'Assigned To',
  ];

  static const List<String> _employeeTenderHeaders = <String>[
    'Organization Name',
    'Lead Date',
    'Bid No',
    'QTY',
    'Product Name',
    'Model No',
    'Product Name 2',
    'Model No 2',
    'Product Name 3',
    'Model No 3',
    'Product Name 4',
    'Model No 4',
    'Product Name 5',
    'Model No 5',
    'Due Date',
    'Price',
    'Technical',
    'Commercial',
  ];

  Future<String> getCurrentUserRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'employee';
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final roleRaw = userDoc.data()?['role'];
    if (roleRaw is String && roleRaw.trim().toLowerCase() == 'admin') {
      return 'admin';
    }
    return 'employee';
  }

  Future<String> getCurrentUserName() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'System';
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final nameRaw = userDoc.data()?['name'];
    if (nameRaw is String && nameRaw.trim().isNotEmpty) {
      return nameRaw.trim();
    }
    final email = _auth.currentUser?.email;
    if (email != null && email.trim().isNotEmpty) {
      return email.trim();
    }
    return 'System';
  }

  Future<Uint8List> buildTemplateBytes({required bool isAdmin}) async {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Leads') {
      workbook.rename(defaultSheet, 'Leads');
    }
    workbook.setDefaultSheet('Leads');
    final leadsSheet = workbook['Leads'];
    final headers = isAdmin ? _adminHeaders : _employeeHeaders;
    leadsSheet.appendRow(
      headers.map(TextCellValue.new).toList(growable: false),
    );

    List<String> activeEmployeeNames = const <String>[];
    if (isAdmin) {
      activeEmployeeNames = await _getActiveEmployeeNames();
      final employeeSheet = workbook['Employees'];
      employeeSheet.appendRow(<CellValue?>[TextCellValue('Name')]);
      for (final name in activeEmployeeNames) {
        employeeSheet.appendRow(<CellValue?>[TextCellValue(name)]);
      }
      employeeSheet.setColumnAutoFit(0);
    }

    for (var i = 0; i < headers.length; i++) {
      leadsSheet.setColumnAutoFit(i);
    }

    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('Could not generate Excel template.');
    }

    if (!isAdmin || activeEmployeeNames.isEmpty) {
      return Uint8List.fromList(encoded);
    }
    return _injectAssignedToValidation(
      Uint8List.fromList(encoded),
      activeEmployeeNames.length,
    );
  }

  Future<Uint8List> buildTenderTemplateBytes({required bool isAdmin}) async {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Tenders') {
      workbook.rename(defaultSheet, 'Tenders');
    }
    workbook.setDefaultSheet('Tenders');
    final leadsSheet = workbook['Tenders'];
    final headers = isAdmin ? _adminTenderHeaders : _employeeTenderHeaders;
    leadsSheet.appendRow(
      headers.map(TextCellValue.new).toList(growable: false),
    );

    List<String> activeEmployeeNames = const <String>[];
    if (isAdmin) {
      activeEmployeeNames = await _getActiveEmployeeNames();
      final employeeSheet = workbook['Employees'];
      employeeSheet.appendRow(<CellValue?>[TextCellValue('Name')]);
      for (final name in activeEmployeeNames) {
        employeeSheet.appendRow(<CellValue?>[TextCellValue(name)]);
      }
      employeeSheet.setColumnAutoFit(0);
    }

    for (var i = 0; i < headers.length; i++) {
      leadsSheet.setColumnAutoFit(i);
    }

    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('Could not generate Excel template.');
    }

    if (!isAdmin || activeEmployeeNames.isEmpty) {
      return Uint8List.fromList(encoded);
    }
    return _injectAssignedToValidation(
      Uint8List.fromList(encoded),
      activeEmployeeNames.length,
    );
  }

  Future<BulkUploadSummary> uploadLeadsFromExcelBytes(
    Uint8List bytes, {
    required String uploaderUid,
    required String uploaderRole,
    required String uploaderName,
    void Function(BulkUploadProgress progress)? onProgress,
  }) async {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('The selected workbook has no sheets.');
    }

    final sheet = workbook.tables.values.first;
    if (sheet.maxRows < 2) {
      return const BulkUploadSummary(
        uploadedRows: 0,
        failedRows: 0,
        totalRows: 0,
        failureMessages: <String>[],
      );
    }

    final headerMap = _buildHeaderMap(sheet);
    final totalRows = sheet.maxRows - 1;
    var uploadedRows = 0;
    var failedRows = 0;
    final failureMessages = <String>[];
    var processedRows = 0;

    final isAdmin = uploaderRole.trim().toLowerCase() == 'admin';
    final employeeLookup = isAdmin
        ? await _getEmployeeLookup()
        : <String, _EmployeeInfo>{};

    var batch = _firestore.batch();
    var pendingWrites = 0;

    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = _rowAsMap(
        sheet: sheet,
        headerMap: headerMap,
        rowIndex: rowIndex,
      );
      final isRowEmpty = row.values.every((val) => val.isEmpty);
      if (isRowEmpty) {
        continue;
      }

      final name = _readFirst(row, const <String>['Customer Name', 'Client Name', 'Name']);
      final phone = _readFirst(row, const <String>[
        'Contact No.',
        'Phone',
        'Mobile',
        'Phone Number',
      ]);

      final assignment = _resolveAssignment(
        isAdmin: isAdmin,
        row: row,
        employeeLookup: employeeLookup,
        uploaderUid: uploaderUid,
        uploaderName: uploaderName,
      );

      final leadDateStr = _readFirst(row, const <String>[
        'Lead Date',
        'Lead Generation Date',
        'Generation Date',
        'Lead Received Date',
      ]);
      final leadDate = parseFlexibleDate(leadDateStr) ?? todayDateOnly();

      final productLines = _parseProductLinesFromRow(row, isTender: false);
      final firstReq = productLines.isNotEmpty
          ? productLines.first['requirement']!
          : '';
      final firstModel =
          productLines.isNotEmpty ? productLines.first['modelNo']! : '';

      final leadRef = _firestore.collection('leads').doc();
      batch.set(leadRef, <String, dynamic>{
        'name': name,
        'phone': phone,
        'email': _readFirst(row, const <String>['Email ID', 'Email']),
        'company': _readFirst(row, const <String>['Company Name', 'Company']),
        'productLines': productLines,
        'requirement': firstReq,
        'location': _readFirst(row, const <String>['Location']),
        'website': _readFirst(row, const <String>['Website']),
        'source': _readFirst(row, const <String>['Source']),
        'modelNo': firstModel,
        'remark': _readFirst(row, const <String>['Remark']),
        'assignedTo': assignment.uid,
        'assignedToName': assignment.name,
        'status': 'New',
        'targetGas': '',
        'measuringRange': '',
        'industrySector': '',
        'isAmcLead': false,
        'totalAmount': 0,
        'creatorName': uploaderName,
        'leadDate': Timestamp.fromDate(leadDate),
        'createdAt': Timestamp.fromDate(leadDate),
        'lastModified': FieldValue.serverTimestamp(),
      });
      pendingWrites++;
      uploadedRows++;
      processedRows++;

      if (pendingWrites >= 350) {
        await batch.commit();
        batch = _firestore.batch();
        pendingWrites = 0;
      }

      onProgress?.call(
        BulkUploadProgress(
          processedRows: processedRows,
          totalRows: totalRows,
          uploadedRows: uploadedRows,
          failedRows: failedRows,
        ),
      );
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }

    return BulkUploadSummary(
      uploadedRows: uploadedRows,
      failedRows: failedRows,
      totalRows: totalRows,
      failureMessages: failureMessages,
    );
  }

  Future<BulkUploadSummary> uploadTenderLeadsFromExcelBytes(
    Uint8List bytes, {
    required String uploaderUid,
    required String uploaderRole,
    required String uploaderName,
    void Function(BulkUploadProgress progress)? onProgress,
  }) async {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('The selected workbook has no sheets.');
    }

    final sheet = workbook.tables.values.first;
    if (sheet.maxRows < 2) {
      return const BulkUploadSummary(
        uploadedRows: 0,
        failedRows: 0,
        totalRows: 0,
        failureMessages: <String>[],
      );
    }

    final headerMap = _buildHeaderMap(sheet);
    final totalRows = sheet.maxRows - 1;
    var uploadedRows = 0;
    var failedRows = 0;
    final failureMessages = <String>[];
    var processedRows = 0;

    final isAdmin = uploaderRole.trim().toLowerCase() == 'admin';
    final employeeLookup = isAdmin
        ? await _getEmployeeLookup()
        : <String, _EmployeeInfo>{};

    var batch = _firestore.batch();
    var pendingWrites = 0;

    for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
      final row = _rowAsMap(
        sheet: sheet,
        headerMap: headerMap,
        rowIndex: rowIndex,
      );
      final isRowEmpty = row.values.every((val) => val.isEmpty);
      if (isRowEmpty) {
        continue;
      }

      final organizationName = _readFirst(row, const <String>['Organization Name', 'Company Name', 'Company']);
      final bidNo = _readFirst(row, const <String>['Bid No', 'Bid']);

      final assignment = _resolveAssignment(
        isAdmin: isAdmin,
        row: row,
        employeeLookup: employeeLookup,
        uploaderUid: uploaderUid,
        uploaderName: uploaderName,
      );

      final leadDateStr = _readFirst(row, const <String>[
        'Lead Date',
        'Lead Generation Date',
        'Generation Date',
        'Lead Received Date',
      ]);
      final leadDate = parseFlexibleDate(leadDateStr) ?? todayDateOnly();

      final dueDateStr = _readFirst(row, const <String>['Due Date']);
      final parsedDueDate = parseFlexibleDate(dueDateStr);

      final productLines = _parseProductLinesFromRow(row, isTender: true);
      final firstReq = productLines.isNotEmpty
          ? productLines.first['requirement']!
          : '';
      final firstModel =
          productLines.isNotEmpty ? productLines.first['modelNo']! : '';

      final leadRef = _firestore.collection('leads').doc();
      batch.set(leadRef, <String, dynamic>{
        'name': '',
        'phone': '',
        'email': '',
        'company': organizationName,
        'productLines': productLines,
        'requirement': firstReq,
        'location': '',
        'website': '',
        'source': 'Tender',
        'modelNo': firstModel,
        'remark': '',
        'assignedTo': assignment.uid,
        'assignedToName': assignment.name,
        'status': 'New',
        'targetGas': '',
        'measuringRange': '',
        'industrySector': '',
        'isAmcLead': false,
        'totalAmount': double.tryParse(_readFirst(row, const <String>['Price', 'Amount'])) ?? 0,
        'creatorName': uploaderName,
        'leadDate': Timestamp.fromDate(leadDate),
        'createdAt': Timestamp.fromDate(leadDate),
        'lastModified': FieldValue.serverTimestamp(),
        'isTender': true,
        'bidNo': bidNo,
        'quantity': int.tryParse(_readFirst(row, const <String>['Qty', 'Quantity'])) ?? 1,
        'dueDate': parsedDueDate != null ? Timestamp.fromDate(parsedDueDate) : null,
        'technicalStatus': _readFirst(row, const <String>['Technical']),
        'commercialStatus': _readFirst(row, const <String>['Commercial']),
      });
      pendingWrites++;
      uploadedRows++;
      processedRows++;

      if (pendingWrites >= 350) {
        await batch.commit();
        batch = _firestore.batch();
        pendingWrites = 0;
      }

      onProgress?.call(
        BulkUploadProgress(
          processedRows: processedRows,
          totalRows: totalRows,
          uploadedRows: uploadedRows,
          failedRows: failedRows,
        ),
      );
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }

    return BulkUploadSummary(
      uploadedRows: uploadedRows,
      failedRows: failedRows,
      totalRows: totalRows,
      failureMessages: failureMessages,
    );
  }

  Map<String, int> _buildHeaderMap(Sheet sheet) {
    final headerMap = <String, int>{};
    for (var c = 0; c < sheet.maxColumns; c++) {
      final header = _cellToString(
        sheet
            .cell(CellIndex.indexByColumnRow(rowIndex: 0, columnIndex: c))
            .value,
      );
      if (header.isEmpty) continue;
      headerMap[header.trim().toLowerCase()] = c;
    }
    return headerMap;
  }

  Map<String, String> _rowAsMap({
    required Sheet sheet,
    required Map<String, int> headerMap,
    required int rowIndex,
  }) {
    final result = <String, String>{};
    for (final entry in headerMap.entries) {
      final value = _cellToString(
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                rowIndex: rowIndex,
                columnIndex: entry.value,
              ),
            )
            .value,
      );
      result[entry.key] = value;
    }
    return result;
  }

  String _readFirst(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key.trim().toLowerCase()];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  /// Reads up to [_maxBulkProductLines] product rows from optional Excel columns.
  List<Map<String, String>> _parseProductLinesFromRow(
    Map<String, String> row, {
    required bool isTender,
  }) {
    final lines = <Map<String, String>>[];
    for (var i = 1; i <= _maxBulkProductLines; i++) {
      final requirementKeys = i == 1
          ? (isTender
              ? const <String>['Product Name', 'Requirement']
              : const <String>['Requirement'])
          : (isTender
              ? <String>['Product Name $i', 'Requirement $i']
              : <String>['Requirement $i']);
      final modelKeys = i == 1
          ? const <String>['Model No', 'Model']
          : <String>['Model No $i', 'Model $i'];
      final requirement = _readFirst(row, requirementKeys);
      final modelNo = _readFirst(row, modelKeys);
      if (requirement.isNotEmpty || modelNo.isNotEmpty) {
        lines.add({'requirement': requirement, 'modelNo': modelNo});
      }
    }
    return lines;
  }

  _EmployeeInfo _resolveAssignment({
    required bool isAdmin,
    required Map<String, String> row,
    required Map<String, _EmployeeInfo> employeeLookup,
    required String uploaderUid,
    required String uploaderName,
  }) {
    if (!isAdmin) {
      return _EmployeeInfo(uid: uploaderUid, name: uploaderName);
    }

    final assignedToName = _readFirst(row, const <String>['Assigned To']);
    if (assignedToName.isEmpty) {
      return _EmployeeInfo(uid: uploaderUid, name: uploaderName);
    }
    return employeeLookup[assignedToName.toLowerCase()] ??
        _EmployeeInfo(uid: uploaderUid, name: uploaderName);
  }

  String _cellToString(CellValue? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString().trim();
    if (value is IntCellValue) return value.value.toString().trim();
    if (value is DoubleCellValue) return value.value.toString().trim();
    if (value is BoolCellValue) return value.value.toString().trim();
    if (value is DateCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    return value.toString().trim();
  }

  Future<List<String>> _getActiveEmployeeNames() async {
    final users = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get();

    final names =
        users.docs
            .map((doc) => doc.data())
            .where(_isActiveUser)
            .map((data) => (data['name'] as String? ?? '').trim())
            .where((name) => name.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return names;
  }

  Future<Map<String, _EmployeeInfo>> _getEmployeeLookup() async {
    final users = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get();
    final lookup = <String, _EmployeeInfo>{};
    for (final doc in users.docs) {
      final data = doc.data();
      if (!_isActiveUser(data)) continue;
      final name = (data['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      lookup[name.toLowerCase()] = _EmployeeInfo(uid: doc.id, name: name);
    }
    return lookup;
  }

  bool _isActiveUser(Map<String, dynamic> data) {
    final isActive = data['isActive'];
    final status = (data['status'] as String?)?.trim().toLowerCase();
    if (isActive is bool && !isActive) {
      return false;
    }
    if (status == 'inactive') {
      return false;
    }
    return true;
  }

  Uint8List _injectAssignedToValidation(
    Uint8List xlsxBytes,
    int employeeCount,
  ) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final worksheet = archive.findFile('xl/worksheets/sheet1.xml');
    if (worksheet == null) {
      return xlsxBytes;
    }

    final xmlText = String.fromCharCodes(worksheet.content as List<int>);
    if (xmlText.contains('<dataValidations')) {
      return xlsxBytes;
    }

    final endRow = employeeCount + 1;
    const insertionPoint = '</sheetData>';
    if (!xmlText.contains(insertionPoint)) {
      return xlsxBytes;
    }

    final validationXml =
        '<dataValidations count="1">'
        '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
        'showErrorMessage="1" sqref="J2:J5000">'
        '<formula1>\'Employees\'!\$A\$2:\$A\$$endRow</formula1>'
        '</dataValidation>'
        '</dataValidations>';

    final updatedXml = xmlText.replaceFirst(
      insertionPoint,
      '$insertionPoint$validationXml',
    );
    final updatedArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'xl/worksheets/sheet1.xml') {
        updatedArchive.addFile(ArchiveFile.string(file.name, updatedXml));
      } else {
        updatedArchive.addFile(file);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(updatedArchive) ?? xlsxBytes);
  }
}

class _EmployeeInfo {
  const _EmployeeInfo({required this.uid, required this.name});

  final String uid;
  final String name;
}
