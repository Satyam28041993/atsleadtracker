import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/lead_model.dart';
import '../models/quotation_model.dart';
import 'analytics_service.dart';
import 'quotation_service.dart';
import '../utils/xlsx_features.dart';

/// Where a lead's headline value came from.
enum AmountSource {
  /// Typed or auto-filled into the lead's own Amount column.
  leadColumn,

  /// The lead has no Amount, so analytics fell back to its latest quotation.
  quotationFallback,

  /// Neither — this lead contributes nothing to pipeline or revenue.
  none,
}

/// Builds the analytics workbook: the KPI figures, the rows behind them, and
/// the data-quality gaps that make those figures understate reality.
class AnalyticsExportService {
  AnalyticsExportService({FirebaseFirestore? firestore})
    : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  static final DateFormat _stampFmt = DateFormat('yyyyMMdd_HHmm');
  static final DateFormat _dmyHm = DateFormat('dd MMM yyyy, hh:mm a');

  static final ExcelColor _brand = ExcelColor.fromHexString('FF1D2638');
  static final ExcelColor _warn = ExcelColor.fromHexString('FFB3261E');
  static final CellStyle _headerStyle = CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: _brand,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );
  static const CustomNumericNumFormat _moneyFormat = CustomNumericNumFormat(
    formatCode: '"₹"#,##0',
  );
  static const CustomDateTimeNumFormat _dateTimeFormat =
      CustomDateTimeNumFormat(formatCode: 'dd-mmm-yyyy hh:mm AM/PM');
  static const CustomNumericNumFormat _percentFormat = CustomNumericNumFormat(
    formatCode: '0.0"%"',
  );
  static final CellStyle _moneyStyle = CellStyle(
    numberFormat: _moneyFormat,
    horizontalAlign: HorizontalAlign.Right,
  );
  static final CellStyle _percentStyle = CellStyle(
    numberFormat: _percentFormat,
    horizontalAlign: HorizontalAlign.Right,
  );
  static final CellStyle _dateTimeStyle = CellStyle(
    numberFormat: _dateTimeFormat,
  );
  static final CellStyle _wrapStyle = CellStyle(
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Top,
  );
  static final CellStyle _warnStyle = CellStyle(
    bold: true,
    fontColorHex: _warn,
  );

  static TextCellValue _t(String v) => TextCellValue(v);
  static DoubleCellValue? _money(double? v) =>
      v == null ? null : DoubleCellValue(v);
  static DateTimeCellValue? _dt(DateTime? v) =>
      v == null ? null : DateTimeCellValue.fromDateTime(v);

  String suggestedFileName() =>
      'analytics_${_stampFmt.format(DateTime.now())}.xlsx';

  // ── Data ────────────────────────────────────────────────────────────────

  /// Leads in the same scope the analytics were computed for, plus the latest
  /// quotation amount per lead — the two inputs every sheet needs.
  Future<({List<Lead> leads, Map<String, QuotationModel> latestQuote})>
  loadInputs({String? assignedToUid}) async {
    final uid = assignedToUid?.trim() ?? '';
    final leadsSnap = uid.isEmpty
        ? await _fs.collection('leads').get()
        : await _fs
              .collection('leads')
              .where('assignedTo', isEqualTo: uid)
              .get();
    final leads = leadsFromDocs(leadsSnap.docs);

    final latest = <String, QuotationModel>{};
    try {
      final q = uid.isEmpty
          ? await _fs.collection('quotations').get()
          : await _fs
                .collection('quotations')
                .where('employeeId', isEqualTo: uid)
                .get();
      for (final doc in q.docs) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          final leadId = quote.leadId.trim();
          if (leadId.isEmpty) continue;
          final cur = latest[leadId];
          if (cur == null ||
              QuotationService.sortForLead(<QuotationModel>[quote, cur]).first ==
                  quote) {
            latest[leadId] = quote;
          }
        } catch (_) {}
      }
    } catch (_) {
      // Same graceful degradation as the dashboard: no quotations means the
      // fallback column is simply empty, flagged on the Data Quality sheet.
    }
    return (leads: leads, latestQuote: latest);
  }

  static AmountSource amountSourceFor(
    Lead lead,
    Map<String, QuotationModel> latestQuote,
  ) {
    if (lead.totalAmount > 0) return AmountSource.leadColumn;
    final q = latestQuote[lead.id];
    if (q != null && q.quoteRequest.totalAmount > 0) {
      return AmountSource.quotationFallback;
    }
    return AmountSource.none;
  }

  static double effectiveAmount(
    Lead lead,
    Map<String, QuotationModel> latestQuote,
  ) {
    if (lead.totalAmount > 0) return lead.totalAmount;
    return latestQuote[lead.id]?.quoteRequest.totalAmount ?? 0;
  }

  static bool isClosed(Lead l) => const {
    'won',
    'lost',
    'loss',
    'disqualified',
  }.contains(l.status.trim().toLowerCase());

  static bool isWon(Lead l) => l.status.trim().toLowerCase() == 'won';

  // ── Workbook ────────────────────────────────────────────────────────────

  Uint8List? buildWorkbook({
    required ExecutiveAnalytics data,
    required List<Lead> leads,
    required Map<String, QuotationModel> latestQuote,
    required Map<String, String> namesByUid,
    required String scopeLabel,
    required String periodLabel,
  }) {
    final book = Excel.createExcel();

    _buildKpiSheet(book, data, scopeLabel, periodLabel);
    final leadRows = _buildLeadsSheet(book, leads, latestQuote, namesByUid);
    final wonRows = _buildWonSheet(book, leads, latestQuote, namesByUid);
    final gapRows = _buildDataQualitySheet(book, leads, latestQuote, namesByUid);
    final sourceRows = _buildSourceSheet(book, data);
    final empRows = _buildEmployeeSheet(book, data);
    final monthRows = _buildMonthlySheet(book, data);

    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

    final encoded = book.encode();
    if (encoded == null) return null;

    return XlsxFeatures.apply(Uint8List.fromList(encoded), <String, SheetFeature>{
      'Leads': SheetFeature(
        freezeCols: 2,
        autoFilterRef: XlsxFeatures.rangeRef(_leadHeaders.length, leadRows),
      ),
      'Won deals': SheetFeature(
        autoFilterRef: XlsxFeatures.rangeRef(_wonHeaders.length, wonRows),
      ),
      'Needs a value': SheetFeature(
        autoFilterRef: XlsxFeatures.rangeRef(_gapHeaders.length, gapRows),
      ),
      'By source': SheetFeature(
        autoFilterRef: XlsxFeatures.rangeRef(_sourceHeaders.length, sourceRows),
      ),
      'By employee': SheetFeature(
        autoFilterRef: XlsxFeatures.rangeRef(_empHeaders.length, empRows),
      ),
      'Monthly won': SheetFeature(
        autoFilterRef: XlsxFeatures.rangeRef(_monthHeaders.length, monthRows),
      ),
      // 'KPI summary' has no filter — it is a definition sheet, not a table.
    });
  }

  void _writeHeader(
    Sheet sheet,
    List<String> headers, {
    Map<int, double> widths = const <int, double>{},
  }) {
    sheet.appendRow(headers.map<CellValue?>(_t).toList());
    for (var c = 0; c < headers.length; c++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle =
          _headerStyle;
      sheet.setColumnWidth(c, widths[c] ?? 18);
    }
  }

  void _styleColumns(
    Sheet sheet,
    int rowCount,
    Map<int, CellStyle> stylesByColumn,
  ) {
    stylesByColumn.forEach((col, style) {
      for (var r = 1; r <= rowCount; r++) {
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r))
                .cellStyle =
            style;
      }
    });
  }

  /// Every headline figure with the exact rule behind it, so the number and
  /// its definition never drift apart in someone's memory.
  void _buildKpiSheet(
    Excel book,
    ExecutiveAnalytics d,
    String scopeLabel,
    String periodLabel,
  ) {
    final sheet = book['KPI summary'];
    _writeHeader(sheet, const [
      'Metric',
      'Value',
      'Counts',
      'How it is calculated',
    ], widths: {0: 26, 1: 18, 2: 14, 3: 96});

    void row(String metric, String value, String counts, String rule) {
      sheet.appendRow(<CellValue?>[
        _t(metric),
        _t(value),
        _t(counts),
        _t(rule),
      ]);
    }

    row('Report scope', scopeLabel, '', 'Team member filter on the dashboard.');
    row(
      'Date filter',
      periodLabel,
      '',
      'Applies to Won revenue, Win rate, Avg won deal and Conversion. The '
          'snapshot tiles (Active leads, Pipeline, Expected revenue) ignore it '
          'on purpose — they describe the pipeline as it stands right now.',
    );
    row('Generated', _dmyHm.format(DateTime.now()), '', '');
    row('', '', '', '');

    row(
      'Active leads',
      d.totalActiveLeads.toString(),
      '${d.activeLeadIds.length} ids',
      'Every lead and tender whose status is NOT Won / Lost / Loss / '
          'Disqualified. A snapshot, not filtered by date.',
    );
    row(
      'Pipeline value',
      _inr(d.pipelineValue),
      '${d.pipelineLeadIds.length} valued',
      'Sum of the value of every open lead. A lead with no value adds nothing, '
          'so this is the value of the ${d.pipelineLeadIds.length} open leads '
          'that carry one — not of all ${d.totalActiveLeads}.',
    );
    row(
      'Expected revenue',
      _inr(d.expectedRevenue),
      '${d.expectedRevenueLeadIds.length} leads',
      'Pipeline value narrowed to leads at Proposal or Follow-up (and tenders '
          'at Technical Evaluation / Query Raised / Query Responded / '
          'Qualified / Reverse Auction). NOT probability-weighted — it is the '
          'full value of those deals, so treat it as an upper bound.',
    );
    row(
      'Won revenue',
      _inr(d.totalRevenue),
      '${d.closedWonCount} won',
      'Value of leads with status Won whose close date (last modified) or '
          'installation date falls in the selected period. A won lead with no '
          'value contributes zero — see the "Needs a value" sheet.',
    );
    row(
      'Win rate',
      '${(d.winRate * 100).toStringAsFixed(1)}%',
      '${d.closedWonCount} / ${d.closedWonCount + d.closedLostCount}',
      'Won divided by (Won + Lost) closed in the period. Open leads are not in '
          'the denominator, so this answers "of the deals we finished, how '
          'many did we win".',
    );
    row(
      'Avg won deal',
      _inr(d.avgWonDealSize),
      'across ${d.closedWonCount}',
      'Won revenue divided by the number of won deals — INCLUDING won deals '
          'that carry no value. Every zero-value win drags this figure down, '
          'so fill the gaps on the "Needs a value" sheet before quoting it.',
    );
    row(
      'Conversion to won',
      '${(d.conversionToWon * 100).toStringAsFixed(1)}%',
      '${d.periodCreatedLeadIds.length} created',
      'Of the leads CREATED in the period, the share now marked Won. Same '
          'cohort top and bottom, so a short date range stays meaningful.',
    );
    row(
      'Leads added today',
      d.leadsAddedToday.toString(),
      '',
      'Leads whose lead date is today. Ignores the date filter.',
    );
    row(
      'Follow-ups today',
      d.followUpsToday.toString(),
      '',
      'Open leads whose next follow-up falls today. Closed leads are excluded.',
    );
    row(
      'Overdue follow-ups',
      d.overdueFollowUps.toString(),
      '',
      'Open leads whose next follow-up is before today. Closed leads are '
          'excluded, so this can read lower than a raw count of stale dates.',
    );

    for (var r = 1; r <= 14; r++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
              .cellStyle =
          _wrapStyle;
    }
  }

  static const List<String> _leadHeaders = <String>[
    'Lead ID',
    'Company',
    'Contact',
    'Type',
    'Status',
    'Open or closed',
    'Owner',
    'Source',
    'Lead date',
    'Last modified',
    'Amount used',
    'Amount source',
    'Lead Amount column',
    'Latest quote no',
    'Latest quote value',
    'In pipeline',
    'In expected revenue',
  ];

  int _buildLeadsSheet(
    Excel book,
    List<Lead> leads,
    Map<String, QuotationModel> latestQuote,
    Map<String, String> namesByUid,
  ) {
    final sheet = book['Leads'];
    _writeHeader(sheet, _leadHeaders, widths: {1: 30, 11: 20});

    const expectedLead = {'Proposal', 'Follow-up'};
    const expectedTender = {
      'Technical Evaluation',
      'Query Raised',
      'Query Responded',
      'Qualified',
      'Reverse Auction(RA)',
    };

    for (final l in leads) {
      final amount = effectiveAmount(l, latestQuote);
      final source = amountSourceFor(l, latestQuote);
      final q = latestQuote[l.id];
      final open = !isClosed(l);
      final inExpected =
          open &&
          amount > 0 &&
          (l.isTender
              ? expectedTender.contains(l.status.trim())
              : expectedLead.contains(l.status.trim()));

      sheet.appendRow(<CellValue?>[
        _t(l.id),
        _t(l.company),
        _t(l.name),
        _t(l.isTender ? 'Tender' : 'Lead'),
        _t(l.status),
        _t(open ? 'Open' : 'Closed'),
        _t(namesByUid[l.assignedTo] ?? 'Unknown'),
        _t(l.source),
        _dt(l.leadDate),
        _dt(l.lastModified),
        _money(amount),
        _t(switch (source) {
          AmountSource.leadColumn => 'Lead Amount column',
          AmountSource.quotationFallback => 'Latest quotation (no lead amount)',
          AmountSource.none => 'NO VALUE',
        }),
        _money(l.totalAmount),
        _t(q?.currentRefNo ?? ''),
        _money(q?.quoteRequest.totalAmount),
        _t(open && amount > 0 ? 'Yes' : 'No'),
        _t(inExpected ? 'Yes' : 'No'),
      ]);
    }

    _styleColumns(sheet, leads.length, {
      8: _dateTimeStyle,
      9: _dateTimeStyle,
      10: _moneyStyle,
      12: _moneyStyle,
      14: _moneyStyle,
    });
    return leads.length;
  }

  static const List<String> _wonHeaders = <String>[
    'Company',
    'Contact',
    'Owner',
    'Closed on',
    'Installation date',
    'Value counted',
    'Amount source',
    'Has a value',
    'Lead ID',
  ];

  int _buildWonSheet(
    Excel book,
    List<Lead> leads,
    Map<String, QuotationModel> latestQuote,
    Map<String, String> namesByUid,
  ) {
    final sheet = book['Won deals'];
    _writeHeader(sheet, _wonHeaders, widths: {0: 34});

    final won = leads.where(isWon).toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));

    var rows = 0;
    for (final l in won) {
      final amount = effectiveAmount(l, latestQuote);
      sheet.appendRow(<CellValue?>[
        _t(l.company),
        _t(l.name),
        _t(namesByUid[l.assignedTo] ?? 'Unknown'),
        _dt(l.lastModified),
        _dt(l.installationDate),
        _money(amount),
        _t(switch (amountSourceFor(l, latestQuote)) {
          AmountSource.leadColumn => 'Lead Amount column',
          AmountSource.quotationFallback => 'Latest quotation',
          AmountSource.none => 'NO VALUE',
        }),
        _t(amount > 0 ? 'Yes' : 'NO'),
        _t(l.id),
      ]);
      rows++;
    }

    _styleColumns(sheet, rows, {
      3: _dateTimeStyle,
      4: _dateTimeStyle,
      5: _moneyStyle,
    });
    return rows;
  }

  static const List<String> _gapHeaders = <String>[
    'Priority',
    'Company',
    'Contact',
    'Phone',
    'Owner',
    'Status',
    'Type',
    'Lead date',
    'Why it matters',
    'Lead ID',
  ];

  /// The leads whose missing or contradictory value distorts the KPIs.
  ///
  /// Won leads come first: each one with no value silently understates both
  /// Won revenue and Avg won deal.
  int _buildDataQualitySheet(
    Excel book,
    List<Lead> leads,
    Map<String, QuotationModel> latestQuote,
    Map<String, String> namesByUid,
  ) {
    final sheet = book['Needs a value'];
    _writeHeader(sheet, _gapHeaders, widths: {1: 34, 8: 62});

    final rows = <List<CellValue?>>[];

    void add(String priority, Lead l, String why) {
      rows.add(<CellValue?>[
        _t(priority),
        _t(l.company),
        _t(l.name),
        _t(l.phone),
        _t(namesByUid[l.assignedTo] ?? 'Unknown'),
        _t(l.status),
        _t(l.isTender ? 'Tender' : 'Lead'),
        _dt(l.leadDate),
        _t(why),
        _t(l.id),
      ]);
    }

    for (final l in leads) {
      final amount = effectiveAmount(l, latestQuote);
      final q = latestQuote[l.id];

      if (isWon(l) && amount <= 0) {
        add(
          '1 - Won, no value',
          l,
          'Counted as a win but adds nothing to Won revenue, and pulls the '
              'average won deal down.',
        );
      } else if (!isClosed(l) && amount <= 0) {
        add(
          '2 - Open, no value',
          l,
          'Missing from Pipeline value and Expected revenue.',
        );
      }

      if (q != null &&
          l.totalAmount > 0 &&
          (q.quoteRequest.totalAmount - l.totalAmount).abs() > 1) {
        add(
          '3 - Amount != latest quote',
          l,
          'Lead Amount is ${_inr(l.totalAmount)} but the latest quotation '
              '${q.currentRefNo} is ${_inr(q.quoteRequest.totalAmount)}. '
              'Analytics uses the Lead Amount.',
        );
      }
    }

    rows.sort((a, b) {
      final pa = (a.first as TextCellValue).value.toString();
      final pb = (b.first as TextCellValue).value.toString();
      return pa.compareTo(pb);
    });
    for (final r in rows) {
      sheet.appendRow(r);
    }

    _styleColumns(sheet, rows.length, {
      0: _warnStyle,
      7: _dateTimeStyle,
      8: _wrapStyle,
    });
    return rows.length;
  }

  static const List<String> _sourceHeaders = <String>[
    'Source',
    'Total leads',
    'Today',
    'Yesterday',
    'This week',
    'This month',
    'Last month',
    'Won',
    'Won value',
  ];

  int _buildSourceSheet(Excel book, ExecutiveAnalytics d) {
    final sheet = book['By source'];
    _writeHeader(sheet, _sourceHeaders, widths: {0: 26});

    int cell(SourceReportRow r, String key) =>
        (r.byTime[key] ?? SourceCell.empty).count;

    var rows = 0;
    for (final r in d.sourceReport.rows) {
      sheet.appendRow(<CellValue?>[
        _t(r.source),
        IntCellValue(r.total.count),
        IntCellValue(cell(r, 'today')),
        IntCellValue(cell(r, 'yesterday')),
        IntCellValue(cell(r, 'week')),
        IntCellValue(cell(r, 'month')),
        IntCellValue(cell(r, 'lastMonth')),
        IntCellValue(r.wonCount),
        _money(r.wonValue),
      ]);
      rows++;
    }
    _styleColumns(sheet, rows, {8: _moneyStyle});
    return rows;
  }

  static const List<String> _empHeaders = <String>[
    'Employee',
    'Deals won',
    'Revenue won',
    'Win rate',
  ];

  int _buildEmployeeSheet(Excel book, ExecutiveAnalytics d) {
    final sheet = book['By employee'];
    _writeHeader(sheet, _empHeaders, widths: {0: 28});

    var rows = 0;
    for (final e in d.leaderboard) {
      sheet.appendRow(<CellValue?>[
        _t(e.displayName),
        IntCellValue(e.wonDeals),
        _money(e.wonRevenue),
        DoubleCellValue(e.winRate * 100),
      ]);
      rows++;
    }
    _styleColumns(sheet, rows, {2: _moneyStyle, 3: _percentStyle});
    return rows;
  }

  static const List<String> _monthHeaders = <String>[
    'Month',
    'Won value',
    'Deals',
  ];

  int _buildMonthlySheet(Excel book, ExecutiveAnalytics d) {
    final sheet = book['Monthly won'];
    _writeHeader(sheet, _monthHeaders);

    var rows = 0;
    for (final m in d.monthlySales) {
      sheet.appendRow(<CellValue?>[
        _t(m.label),
        _money(m.amount),
        IntCellValue(m.leadIds.length),
      ]);
      rows++;
    }
    _styleColumns(sheet, rows, {1: _moneyStyle});
    return rows;
  }

  static String _inr(double v) {
    if (v >= 10000000) return 'INR ${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return 'INR ${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return 'INR ${(v / 1000).toStringAsFixed(1)} K';
    return 'INR ${v.toStringAsFixed(0)}';
  }
}
