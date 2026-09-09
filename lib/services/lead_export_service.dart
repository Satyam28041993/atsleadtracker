import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/lead_event_model.dart';
import '../models/lead_model.dart';
import '../models/quotation_model.dart';
import '../services/quotation_service.dart';
import '../utils/csv_writer.dart';
import '../utils/xlsx_features.dart';

enum ExportFormat { csv, excel }

/// One remark, however it was recorded.
class RemarkEntry {
  const RemarkEntry({
    required this.body,
    required this.at,
    required this.author,
    required this.fromEvent,
  });

  final String body;
  final DateTime? at;
  final String author;

  /// True when this came from a timeline event (reliable timestamp) rather
  /// than from parsing the append-only remark blob.
  final bool fromEvent;
}

/// A scheduled follow-up paired with whatever closed it.
class FollowUpCycle {
  const FollowUpCycle({
    required this.lead,
    required this.scheduled,
    required this.dueAt,
    required this.done,
  });

  final Lead lead;
  final LeadEvent scheduled;
  final DateTime? dueAt;
  final LeadEvent? done;

  bool get isSmart => scheduled.action.toLowerCase().contains('smart');

  String outcome(DateTime now) {
    final due = dueAt;
    if (done == null) {
      if (due == null) return 'Unknown';
      return due.isAfter(now) ? 'Pending' : 'Overdue';
    }
    if (due == null) return 'Done';
    // Compare against the END of the due day: a follow-up due Tuesday and
    // closed Tuesday evening was on time.
    final endOfDay = DateTime(due.year, due.month, due.day, 23, 59, 59);
    return done!.timestamp.isAfter(endOfDay) ? 'Late' : 'On time';
  }

  /// Whole days late; negative when closed early. Null when unknown.
  int? get delayDays {
    final due = dueAt;
    final closed = done?.timestamp;
    if (due == null || closed == null) return null;
    final dueDay = DateTime(due.year, due.month, due.day);
    final doneDay = DateTime(closed.year, closed.month, closed.day);
    return doneDay.difference(dueDay).inDays;
  }

  double? get responseHours {
    final closed = done?.timestamp;
    if (closed == null) return null;
    final mins = closed.difference(scheduled.timestamp).inMinutes;
    return (mins / 60 * 100).round() / 100;
  }
}

/// Everything the workbook needs, fetched once.
class LeadExportBundle {
  LeadExportBundle({
    required this.leads,
    required this.namesByUid,
    required this.quotesByLeadId,
    required this.eventsByLeadId,
    required this.leadsCoveredByEvents,
    required this.eventsTruncated,
    required this.filterSummary,
  });

  final List<Lead> leads;
  final Map<String, String> namesByUid;

  /// Newest revision first, per [QuotationService.sortForLead].
  final Map<String, List<QuotationModel>> quotesByLeadId;

  /// Ascending by timestamp.
  final Map<String, List<LeadEvent>> eventsByLeadId;

  final int leadsCoveredByEvents;
  final bool eventsTruncated;
  final String filterSummary;
}

/// Builds the CSV and the multi-sheet Excel workbook for a set of leads.
///
/// Separate from [AnalyticsExcelService], which promises it never triggers
/// extra Firestore reads and consumes pre-aggregated dashboard data. This one
/// reads three collections.
class LeadExportService {
  LeadExportService({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  // Caps, so a large database cannot hang the export.
  static const int _kEventLeadCap = 120;
  static const int _kEventsPerLead = 200;
  static const int _kEventDocCap = 20000;
  static const int _kWhereInChunk = 30;
  static const int _kBroadQuoteAt = 600;
  static const int _kEventConcurrency = 10;

  static final DateFormat _stampFmt = DateFormat('yyyyMMdd_HHmm');
  static final DateFormat _dmy = DateFormat('dd MMM yyyy');
  static final DateFormat _dmyHm = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd HH:mm:ss');

  static final RegExp _remarkHeader = RegExp(
    r'^\[(\d{1,2} \w{3} \d{4},\s*\d{1,2}:\d{2}\s*[AaPp][Mm])\]\s*',
  );

  String suggestedFileName({
    required ExportFormat format,
    required bool isTender,
  }) {
    final kind = isTender ? 'tenders' : 'leads';
    final ext = format == ExportFormat.csv ? 'csv' : 'xlsx';
    return '${kind}_export_${_stampFmt.format(DateTime.now())}.$ext';
  }

  // ── CSV ────────────────────────────────────────────────────────────────

  static const List<String> csvHeaders = <String>[
    'Lead ID',
    'Type',
    'Name',
    'Company',
    'Phone',
    'Email',
    'Status',
    'Assigned To',
    'Created By',
    'Source',
    'Lead Date',
    'Created At',
    'Next Follow-up',
    'Location',
    'Requirement',
    'Deal Amount',
    'Quotation No',
    'Tender No',
    'PO Number',
    'Invoice Number',
    'Loss Reason',
  ];

  /// One row per lead, with values Excel can actually type.
  static List<String> csvRow(Lead l, Map<String, String> namesByUid) {
    return <String>[
      l.id,
      l.isTender ? 'Tender' : 'Lead',
      l.name,
      l.company,
      l.phone,
      l.email,
      l.status,
      assignedLabel(l.assignedTo, namesByUid),
      l.creatorName,
      l.source,
      _dmy.format(l.leadDate),
      _iso.format(l.createdAt),
      l.nextFollowUpDate == null ? '' : _dmy.format(l.nextFollowUpDate!),
      l.location,
      l.productsSummary,
      // Unquoted and undecorated so Excel reads it as a number.
      l.totalAmount == 0 ? '' : l.totalAmount.toStringAsFixed(2),
      l.quotationRefNo,
      l.bidNo,
      l.poNumber,
      l.invoiceNumber,
      l.lossReason,
    ];
  }

  Future<Uint8List> buildCsv(List<Lead> leads) async {
    final namesByUid = await _loadEmployeeNames();
    return CsvWriter.toBytes(
      csvHeaders,
      [for (final l in leads) csvRow(l, namesByUid)],
    );
  }

  // ── Gathering ──────────────────────────────────────────────────────────

  Future<LeadExportBundle> gather({
    required List<Lead> leads,
    required bool isAdmin,
    required String currentUid,
    required String filterSummary,
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call('Employees', 0, 1);
    final namesByUid = await _loadEmployeeNames();
    onProgress?.call('Employees', 1, 1);

    final quotes = await _loadQuotations(
      leads: leads,
      isAdmin: isAdmin,
      currentUid: currentUid,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    final eventsResult = await _loadEvents(
      leads: leads,
      isAdmin: isAdmin,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    return LeadExportBundle(
      leads: leads,
      namesByUid: namesByUid,
      quotesByLeadId: quotes,
      eventsByLeadId: eventsResult.$1,
      leadsCoveredByEvents: eventsResult.$1.length,
      eventsTruncated: eventsResult.$2,
      filterSummary: filterSummary,
    );
  }

  Future<Map<String, String>> _loadEmployeeNames() async {
    try {
      final snap = await _fs.collection('users').get();
      final out = <String, String>{};
      for (final doc in snap.docs) {
        final name = doc.data()['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) out[doc.id] = name;
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  static String assignedLabel(String uid, Map<String, String> namesByUid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return 'Unassigned';
    return namesByUid[trimmed] ?? 'Unknown Employee';
  }

  /// firestore.rules only allows a quotations read for an admin or the owning
  /// employee, and a LIST query has to prove that from the query itself — so a
  /// non-admin must constrain on employeeId and filter leadId in Dart.
  Future<Map<String, List<QuotationModel>>> _loadQuotations({
    required List<Lead> leads,
    required bool isAdmin,
    required String currentUid,
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final wanted = {for (final l in leads) l.id};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final ref = _fs.collection('quotations');

    try {
      if (!isAdmin) {
        onProgress?.call('Quotations', 0, 1);
        if (currentUid.isNotEmpty) {
          final snap =
              await ref.where('employeeId', isEqualTo: currentUid).get();
          docs.addAll(snap.docs);
        }
        onProgress?.call('Quotations', 1, 1);
      } else if (wanted.length > _kBroadQuoteAt) {
        // 20+ whereIn round trips cost more than one scan.
        onProgress?.call('Quotations', 0, 1);
        docs.addAll((await ref.get()).docs);
        onProgress?.call('Quotations', 1, 1);
      } else {
        final ids = wanted.toList();
        for (var i = 0; i < ids.length; i += _kWhereInChunk) {
          if (isCancelled?.call() ?? false) break;
          final end = math.min(i + _kWhereInChunk, ids.length);
          final snap =
              await ref.where('leadId', whereIn: ids.sublist(i, end)).get();
          docs.addAll(snap.docs);
          onProgress?.call('Quotations', end, ids.length);
        }
      }
    } catch (_) {
      // Permission or connectivity trouble — the sheet degrades to blanks
      // rather than failing the whole export.
    }

    final out = <String, List<QuotationModel>>{};
    for (final doc in docs) {
      try {
        final q = QuotationModel.fromFirestore(doc);
        if (!wanted.contains(q.leadId)) continue;
        (out[q.leadId] ??= <QuotationModel>[]).add(q);
      } catch (_) {}
    }
    for (final entry in out.entries) {
      out[entry.key] = QuotationService.sortForLead(entry.value);
    }
    return out;
  }

  /// Returns the events per lead plus whether the result was capped.
  ///
  /// `events` is a per-lead subcollection and a collection-group read is
  /// admin-only, so this mirrors the admin-first / capped-fallback pattern
  /// analytics already uses.
  Future<(Map<String, List<LeadEvent>>, bool)> _loadEvents({
    required List<Lead> leads,
    required bool isAdmin,
    void Function(String stage, int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final wanted = {for (final l in leads) l.id};
    final out = <String, List<LeadEvent>>{};
    if (leads.isEmpty) return (out, false);

    if (isAdmin) {
      try {
        onProgress?.call('Timeline', 0, 1);
        var oldest = leads.first.leadDate;
        for (final l in leads) {
          if (l.leadDate.isBefore(oldest)) oldest = l.leadDate;
        }
        final floor = DateTime.now().subtract(const Duration(days: 550));
        final from = oldest.isBefore(floor) ? floor : oldest;

        final snap = await _fs
            .collectionGroup('events')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(from),
            )
            .orderBy('timestamp')
            .limit(_kEventDocCap)
            .get();

        for (final d in snap.docs) {
          final leadId = d.reference.parent.parent?.id;
          if (leadId == null || !wanted.contains(leadId)) continue;
          (out[leadId] ??= <LeadEvent>[]).add(LeadEvent.fromFirestore(d));
        }
        onProgress?.call('Timeline', 1, 1);
        return (out, snap.docs.length >= _kEventDocCap);
      } catch (_) {
        out.clear();
        // Fall through to the per-lead path.
      }
    }

    // Newest-touched leads first, so a capped subset is the useful subset.
    final ordered = [...leads]
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    final subject = ordered.take(_kEventLeadCap).toList();
    var truncated = leads.length > subject.length;

    for (var i = 0; i < subject.length; i += _kEventConcurrency) {
      if (isCancelled?.call() ?? false) {
        truncated = true;
        break;
      }
      final slice = subject.skip(i).take(_kEventConcurrency).toList();
      await Future.wait(
        slice.map((l) async {
          try {
            final snap = await _fs
                .collection('leads')
                .doc(l.id)
                .collection('events')
                .orderBy('timestamp')
                .limit(_kEventsPerLead)
                .get();
            out[l.id] = snap.docs.map(LeadEvent.fromFirestore).toList();
          } catch (_) {}
        }),
      );
      onProgress?.call('Timeline', i + slice.length, subject.length);
    }
    return (out, truncated);
  }

  // ── Derivations ────────────────────────────────────────────────────────

  /// Remarks, preferring the timestamped `Note` events and falling back to
  /// parsing the append-only [Lead.remark] blob.
  ///
  /// Both sources are read: the blob is the only one available for leads whose
  /// events were capped out, and it also holds history from before events were
  /// logged. Duplicates are dropped on a normalised prefix.
  static List<RemarkEntry> remarksFor(Lead lead, List<LeadEvent> events) {
    final out = <RemarkEntry>[];
    final seen = <String>{};

    String key(String body) {
      final k = body.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      return k.substring(0, math.min(80, k.length));
    }

    for (final e in events) {
      if (e.action.toLowerCase() != 'note') continue;
      if (e.description.trim().isEmpty) continue;
      if (!seen.add(key(e.description))) continue;
      out.add(
        RemarkEntry(
          body: e.description,
          at: e.timestamp,
          author: e.userName,
          fromEvent: true,
        ),
      );
    }

    for (final chunk in lead.remark.split(RegExp(r'\n\n---\n'))) {
      final raw = chunk.trim();
      if (raw.isEmpty) continue;
      var body = raw;
      DateTime? at;
      final m = _remarkHeader.firstMatch(raw);
      if (m != null) {
        body = raw.substring(m.end).trim();
        try {
          at = _dmyHm.parseLoose(m.group(1)!);
        } catch (_) {}
      }
      if (body.isEmpty) continue;
      if (!seen.add(key(body))) continue;
      out.add(
        RemarkEntry(body: body, at: at, author: '', fromEvent: false),
      );
    }

    out.sort(
      (a, b) => (a.at ?? DateTime(1970)).compareTo(b.at ?? DateTime(1970)),
    );
    return out;
  }

  /// Pairs each scheduling event with the first real touch that followed it.
  ///
  /// Uses [LeadEvent.isLeadTouch] (status / note / remark), which deliberately
  /// excludes scheduling events — unlike the looser analytics heuristic, where
  /// 'Follow-up Scheduled' matches itself and inflates "done".
  static List<FollowUpCycle> followUpsFor(Lead lead, List<LeadEvent> events) {
    final out = <FollowUpCycle>[];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (!e.isFollowUpScheduling) continue;
      if (e.action.toLowerCase().contains('cancel')) continue;

      DateTime? due;
      final m = RegExp(r'set for\s+(.+)$').firstMatch(e.description);
      if (m != null) {
        try {
          due = _dmyHm.parseLoose(m.group(1)!.trim());
        } catch (_) {}
      }

      LeadEvent? done;
      for (var j = i + 1; j < events.length; j++) {
        if (events[j].isLeadTouch) {
          done = events[j];
          break;
        }
      }

      out.add(
        FollowUpCycle(lead: lead, scheduled: e, dueAt: due, done: done),
      );
    }
    return out;
  }

  static String outcomeOfLead(Lead l) {
    const lost = {'lost', 'loss', 'disqualified'};
    final s = l.status.toLowerCase();
    if (s == 'won') return 'Won';
    if (lost.contains(s)) return 'Lost';
    return 'Open';
  }

  // ── Workbook ───────────────────────────────────────────────────────────

  // NOTE: excel 4.0.6 fails silently in two ways worth remembering.
  //  1. backgroundColorHex/fontColorHex take an ExcelColor, and a malformed
  //     hex string falls back to black with no error.
  //  2. A NumFormat has to match the cell type — a numeric format on a date
  //     cell (or the reverse) makes the package discard the ENTIRE style.
  static final ExcelColor _brand = ExcelColor.fromHexString('FF1D2638');
  static final CellStyle _headerStyle = CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: _brand,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );
  static const CustomNumericNumFormat _moneyFormat =
      CustomNumericNumFormat(formatCode: '"₹"#,##0');
  static const CustomDateTimeNumFormat _dateFormat =
      CustomDateTimeNumFormat(formatCode: 'dd-mmm-yyyy');
  static const CustomDateTimeNumFormat _dateTimeFormat =
      CustomDateTimeNumFormat(formatCode: 'dd-mmm-yyyy hh:mm AM/PM');
  static final CellStyle _moneyStyle = CellStyle(
    numberFormat: _moneyFormat,
    horizontalAlign: HorizontalAlign.Right,
  );
  static final CellStyle _dateStyle = CellStyle(numberFormat: _dateFormat);
  static final CellStyle _dateTimeStyle =
      CellStyle(numberFormat: _dateTimeFormat);
  static final CellStyle _wrapStyle = CellStyle(
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Top,
  );

  static DateTimeCellValue? _dt(DateTime? v) =>
      v == null ? null : DateTimeCellValue.fromDateTime(v);
  static DateCellValue? _dOnly(DateTime? v) =>
      v == null ? null : DateCellValue.fromDateTime(v);
  static DoubleCellValue? _money(double? v) =>
      v == null ? null : DoubleCellValue(v);
  static TextCellValue _t(String v) => TextCellValue(v);

  /// Applies a per-column style to every data row of [sheet].
  static void _styleColumns(
    Sheet sheet,
    int rowCount,
    Map<int, CellStyle> stylesByColumn,
  ) {
    stylesByColumn.forEach((col, style) {
      for (var r = 1; r <= rowCount; r++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r))
            .cellStyle = style;
      }
    });
  }

  static void _writeHeader(
    Sheet sheet,
    List<String> headers, {
    Map<int, double> widths = const <int, double>{},
  }) {
    sheet.appendRow(headers.map<CellValue?>(_t).toList());
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .cellStyle = _headerStyle;
      // Explicit widths: setColumnAutoFit walks every row and is slow on the
      // big sheets.
      sheet.setColumnWidth(c, widths[c] ?? 18);
    }
  }

  /// Builds the workbook. Returns null only when encoding fails.
  Uint8List? buildWorkbook(LeadExportBundle b) {
    final now = DateTime.now();
    final book = Excel.createExcel();

    final summaryRows = _buildSummarySheet(book, b, now);
    final leadRows = _buildLeadsSheet(book, b, now);
    final quoteRows = _buildQuotationsSheet(book, b);
    final followUpRows = _buildFollowUpsSheet(book, b, now);
    final remarkRows = _buildRemarksSheet(book, b);
    _buildExportInfoSheet(book, b, now, <String, int>{
      'Summary': summaryRows,
      'Leads': leadRows,
      'Quotations': quoteRows,
      'Follow-ups': followUpRows,
      'Remarks': remarkRows,
    });

    // Excel.createExcel() seeds a Sheet1 we never use.
    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

    final encoded = book.encode();
    if (encoded == null) return null;

    return XlsxFeatures.apply(
      Uint8List.fromList(encoded),
      <String, SheetFeature>{
        'Summary': SheetFeature(
          autoFilterRef:
              XlsxFeatures.rangeRef(_summaryHeaders.length, summaryRows),
        ),
        'Leads': SheetFeature(
          freezeCols: 2,
          autoFilterRef: XlsxFeatures.rangeRef(_leadHeaders.length, leadRows),
        ),
        'Quotations': SheetFeature(
          autoFilterRef: XlsxFeatures.rangeRef(_quoteHeaders.length, quoteRows),
        ),
        'Follow-ups': SheetFeature(
          autoFilterRef:
              XlsxFeatures.rangeRef(_followUpHeaders.length, followUpRows),
        ),
        'Remarks': SheetFeature(
          autoFilterRef:
              XlsxFeatures.rangeRef(_remarkHeaders.length, remarkRows),
        ),
        // 'Export Info' deliberately omitted — it uses merged-style layout.
      },
    );
  }

  // Summary: flat and additive, so Insert -> PivotTable just works. No title
  // block and no merged cells, both of which break filters and pivot
  // detection.
  static const List<String> _summaryHeaders = <String>[
    'Lead ID',
    'Year',
    'Month',
    'Quarter',
    'Type',
    'Stage',
    'Status',
    'Outcome',
    'Assigned To',
    'Source',
    'Location',
    'Has Quotation',
    'Follow-up Status',
    'Leads',
    'Won',
    'Lost',
    'Open',
    'Deal Amount',
    'Won Amount',
    'Pipeline Amount',
    'Quotation Count',
    'Latest Quote Value',
    'Follow-ups Scheduled',
    'Follow-ups Done',
    'Follow-ups Late',
    'Remark Count',
  ];

  int _buildSummarySheet(Excel book, LeadExportBundle b, DateTime now) {
    final sheet = book['Summary'];
    _writeHeader(sheet, _summaryHeaders);

    for (final l in b.leads) {
      final quotes = b.quotesByLeadId[l.id] ?? const <QuotationModel>[];
      final events = b.eventsByLeadId[l.id] ?? const <LeadEvent>[];
      final cycles = followUpsFor(l, events);
      final outcome = outcomeOfLead(l);
      final won = outcome == 'Won';
      final lost = outcome == 'Lost';
      final open = outcome == 'Open';
      final month = l.leadDate.month;

      sheet.appendRow(<CellValue?>[
        _t(l.id),
        IntCellValue(l.leadDate.year),
        _t(DateFormat('yyyy-MM').format(l.leadDate)),
        _t('${l.leadDate.year}-Q${((month - 1) ~/ 3) + 1}'),
        _t(l.isTender ? 'Tender' : 'Lead'),
        _t(Lead.kanbanColumnFor(l.status, isTender: l.isTender)),
        _t(l.status),
        _t(outcome),
        _t(assignedLabel(l.assignedTo, b.namesByUid)),
        _t(l.source.trim().isEmpty ? 'Unspecified' : l.source.trim()),
        _t(l.location.trim().isEmpty ? 'Unknown' : l.location.trim()),
        _t(quotes.isNotEmpty ? 'Yes' : 'No'),
        _t(followUpBucket(l, now)),
        IntCellValue(1),
        IntCellValue(won ? 1 : 0),
        IntCellValue(lost ? 1 : 0),
        IntCellValue(open ? 1 : 0),
        _money(l.totalAmount),
        _money(won ? l.totalAmount : 0),
        _money(open ? l.totalAmount : 0),
        IntCellValue(quotes.length),
        _money(quotes.isEmpty ? 0 : quotes.first.quoteRequest.totalAmount),
        IntCellValue(cycles.length),
        IntCellValue(cycles.where((c) => c.done != null).length),
        IntCellValue(cycles.where((c) => c.outcome(now) == 'Late').length),
        IntCellValue(remarksFor(l, events).length),
      ]);
    }

    _styleColumns(sheet, b.leads.length, <int, CellStyle>{
      17: _moneyStyle,
      18: _moneyStyle,
      19: _moneyStyle,
      21: _moneyStyle,
    });
    return b.leads.length;
  }

  static const List<String> _leadHeaders = <String>[
    'Lead ID',
    'Type',
    'Name',
    'Company',
    'Phone',
    'Email',
    'Location',
    'Website',
    'Status',
    'Stage',
    'Source',
    'Assigned To',
    'Created By',
    'Lead Date',
    'Created At',
    'Last Modified',
    'Next Follow-up',
    'Follow-up Status',
    'Requirement',
    'Model No',
    'Deal Amount',
    'Quotation Count',
    'Latest Quote No',
    'Latest Quote Amount',
    'Quote vs Deal',
    'Is Tender',
    'Bid No',
    'Due Date',
    'Technical Status',
    'Commercial Status',
    'Installation Date',
    'PO Number',
    'Invoice Number',
    'Loss Reason',
    'Remark Count',
    'Latest Remark',
    'Deal Age (days)',
  ];

  int _buildLeadsSheet(Excel book, LeadExportBundle b, DateTime now) {
    final sheet = book['Leads'];
    _writeHeader(
      sheet,
      _leadHeaders,
      widths: <int, double>{3: 28, 18: 34, 35: 60},
    );

    for (final l in b.leads) {
      final quotes = b.quotesByLeadId[l.id] ?? const <QuotationModel>[];
      final events = b.eventsByLeadId[l.id] ?? const <LeadEvent>[];
      final remarks = remarksFor(l, events);
      final latestQuote = quotes.isEmpty ? null : quotes.first;
      final latestAmt = latestQuote?.quoteRequest.totalAmount;

      sheet.appendRow(<CellValue?>[
        _t(l.id),
        _t(l.isTender ? 'Tender' : 'Lead'),
        _t(l.name),
        _t(l.company),
        // Phone stays text: +91 prefixes and leading zeros must survive.
        _t(l.phone),
        _t(l.email),
        _t(l.location),
        _t(l.website),
        _t(l.status),
        _t(Lead.kanbanColumnFor(l.status, isTender: l.isTender)),
        _t(l.source),
        _t(assignedLabel(l.assignedTo, b.namesByUid)),
        _t(l.creatorName),
        _dOnly(l.leadDate),
        _dt(l.createdAt),
        _dt(l.lastModified),
        _dOnly(l.nextFollowUpDate),
        _t(followUpBucket(l, now)),
        _t(l.productsSummary),
        _t(l.modelNo),
        _money(l.totalAmount),
        IntCellValue(quotes.length),
        _t(latestQuote?.currentRefNo ?? l.quotationRefNo),
        _money(latestAmt),
        _money(latestAmt == null ? null : l.totalAmount - latestAmt),
        // Text rather than BoolCellValue so the filter dropdown reads well.
        _t(l.isTender ? 'Yes' : 'No'),
        _t(l.bidNo),
        _dOnly(l.dueDate),
        _t(l.technicalStatus),
        _t(l.commercialStatus),
        _dOnly(l.installationDate),
        _t(l.poNumber),
        _t(l.invoiceNumber),
        _t(l.lossReason),
        IntCellValue(remarks.length),
        _t(remarks.isEmpty ? '' : _truncate(remarks.last.body, 500)),
        IntCellValue(now.difference(l.leadDate).inDays),
      ]);
    }

    _styleColumns(sheet, b.leads.length, <int, CellStyle>{
      13: _dateStyle,
      14: _dateTimeStyle,
      15: _dateTimeStyle,
      16: _dateStyle,
      20: _moneyStyle,
      23: _moneyStyle,
      24: _moneyStyle,
      27: _dateStyle,
      30: _dateStyle,
      35: _wrapStyle,
    });
    return b.leads.length;
  }

  static const List<String> _quoteHeaders = <String>[
    'Quote No',
    'Base Ref No',
    'Revision',
    'Is Latest Revision',
    'Quote Date',
    'Lead ID',
    'Lead Company',
    'Lead Status',
    'Customer Name',
    'Location',
    'Phone',
    'Email',
    'Employee',
    'Company Type',
    'Line Items',
    'Products',
    'Gross Amount',
    'Discount',
    'Quote Total',
    'Printed Ref No',
    'Quote Doc ID',
  ];

  int _buildQuotationsSheet(Excel book, LeadExportBundle b) {
    final sheet = book['Quotations'];
    _writeHeader(
      sheet,
      _quoteHeaders,
      widths: <int, double>{0: 26, 6: 28, 15: 40},
    );

    final leadById = <String, Lead>{for (final l in b.leads) l.id: l};
    var rows = 0;
    for (final l in b.leads) {
      final quotes = b.quotesByLeadId[l.id] ?? const <QuotationModel>[];
      for (var i = 0; i < quotes.length; i++) {
        final q = quotes[i];
        final r = q.quoteRequest;
        final lead = leadById[q.leadId];
        sheet.appendRow(<CellValue?>[
          _t(q.currentRefNo.isNotEmpty ? q.currentRefNo : r.refNo),
          _t(q.baseRefNo),
          IntCellValue(q.revision),
          // Quotes are sorted newest-first, so index 0 is the live one.
          _t(i == 0 ? 'Yes' : 'No'),
          _dt(q.createdAt),
          _t(q.leadId),
          _t(lead?.company ?? r.companyName),
          _t(lead?.status ?? ''),
          _t(r.customerName),
          _t(r.location),
          _t(r.phone),
          _t(r.email),
          _t(_employeeLabel(q, b.namesByUid)),
          _t(r.companyType),
          IntCellValue(r.products.length),
          _t(
            r.products
                .map((p) => p.productName.trim())
                .where((n) => n.isNotEmpty)
                .join(' | '),
          ),
          _money(r.grossAmount),
          _money(r.discountValue),
          _money(r.totalAmount),
          _t(r.refNo),
          _t(q.id),
        ]);
        rows++;
      }
    }

    _styleColumns(sheet, rows, <int, CellStyle>{
      4: _dateTimeStyle,
      16: _moneyStyle,
      17: _moneyStyle,
      18: _moneyStyle,
    });
    return rows;
  }

  static const List<String> _followUpHeaders = <String>[
    'Lead ID',
    'Company',
    'Contact',
    'Assigned To',
    'Lead Status',
    'Scheduled On',
    'Scheduled By',
    'Due At',
    'Smart',
    'Done At',
    'Done Via',
    'Done By',
    'Outcome',
    'Delay (days)',
    'Response Hours',
    'Description',
  ];

  int _buildFollowUpsSheet(Excel book, LeadExportBundle b, DateTime now) {
    final sheet = book['Follow-ups'];
    _writeHeader(
      sheet,
      _followUpHeaders,
      widths: <int, double>{1: 28, 15: 44},
    );

    var rows = 0;
    for (final l in b.leads) {
      final events = b.eventsByLeadId[l.id] ?? const <LeadEvent>[];
      for (final c in followUpsFor(l, events)) {
        final delay = c.delayDays;
        final hours = c.responseHours;
        sheet.appendRow(<CellValue?>[
          _t(l.id),
          _t(l.company),
          _t(l.name),
          _t(assignedLabel(l.assignedTo, b.namesByUid)),
          _t(l.status),
          _dt(c.scheduled.timestamp),
          _t(
            c.scheduled.userName.isNotEmpty
                ? c.scheduled.userName
                : (b.namesByUid[c.scheduled.userId] ?? ''),
          ),
          _dt(c.dueAt),
          _t(c.isSmart ? 'Yes' : 'No'),
          _dt(c.done?.timestamp),
          _t(c.done?.action ?? ''),
          _t(c.done?.userName ?? ''),
          _t(c.outcome(now)),
          delay == null ? null : IntCellValue(delay),
          hours == null ? null : DoubleCellValue(hours),
          _t(c.scheduled.description),
        ]);
        rows++;
      }
    }

    _styleColumns(sheet, rows, <int, CellStyle>{
      5: _dateTimeStyle,
      7: _dateTimeStyle,
      9: _dateTimeStyle,
      15: _wrapStyle,
    });
    return rows;
  }

  static const List<String> _remarkHeaders = <String>[
    'Lead ID',
    'Company',
    'Contact',
    'Assigned To',
    'Lead Status',
    'Entry No',
    'Noted At',
    'Noted By',
    'Source',
    'Edited',
    'Remark',
    'Length',
  ];

  int _buildRemarksSheet(Excel book, LeadExportBundle b) {
    final sheet = book['Remarks'];
    _writeHeader(
      sheet,
      _remarkHeaders,
      widths: <int, double>{1: 28, 10: 80},
    );

    var rows = 0;
    for (final l in b.leads) {
      final events = b.eventsByLeadId[l.id] ?? const <LeadEvent>[];
      final remarks = remarksFor(l, events);
      for (var i = 0; i < remarks.length; i++) {
        final r = remarks[i];
        sheet.appendRow(<CellValue?>[
          _t(l.id),
          _t(l.company),
          _t(l.name),
          _t(assignedLabel(l.assignedTo, b.namesByUid)),
          _t(l.status),
          IntCellValue(i + 1),
          _dt(r.at),
          _t(r.author),
          _t(r.fromEvent ? 'Timeline event' : 'Remark field'),
          _t(r.body.contains('(Edited:') ? 'Yes' : 'No'),
          _t(r.body),
          IntCellValue(r.body.length),
        ]);
        rows++;
      }
    }

    _styleColumns(sheet, rows, <int, CellStyle>{
      6: _dateTimeStyle,
      10: _wrapStyle,
    });
    return rows;
  }

  /// Says what this export actually covers — without it, a capped export looks
  /// exactly like a complete one.
  void _buildExportInfoSheet(
    Excel book,
    LeadExportBundle b,
    DateTime now,
    Map<String, int> rowCounts,
  ) {
    final sheet = book['Export Info'];
    sheet.setColumnWidth(0, 26);
    sheet.setColumnWidth(1, 70);

    var written = 0;
    void row(String label, String value) {
      sheet.appendRow(<CellValue?>[_t(label), _t(value)]);
      written++;
    }

    row('Generated', _dmyHm.format(now));
    row('Leads exported', b.leads.length.toString());
    row('Filters', b.filterSummary.isEmpty ? 'None' : b.filterSummary);
    for (final entry in rowCounts.entries) {
      row('${entry.key} rows', entry.value.toString());
    }
    if (b.eventsTruncated) {
      row(
        'WARNING',
        'Timeline history was capped, so the Follow-ups sheet covers only '
            '${b.leadsCoveredByEvents} of ${b.leads.length} leads. The Remarks '
            'sheet is unaffected. Narrow the filters for a complete history.',
      );
    }

    for (var r = 0; r < written; r++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(bold: true);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .cellStyle = _wrapStyle;
    }
  }

  static String _employeeLabel(
    QuotationModel q,
    Map<String, String> namesByUid,
  ) {
    final fromProfile = namesByUid[q.employeeId.trim()];
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    return q.employeeName.trim().isEmpty ? 'Unknown' : q.employeeName.trim();
  }

  static String _truncate(String v, int max) =>
      v.length <= max ? v : '${v.substring(0, max)}…';

  static String followUpBucket(Lead l, DateTime now) {
    if (outcomeOfLead(l) != 'Open') return 'Closed';
    final d = l.nextFollowUpDate;
    if (d == null) return 'None';
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    if (d.isBefore(startOfToday)) return 'Overdue';
    if (d.isBefore(endOfToday)) return 'Due today';
    return 'Scheduled';
  }
}
