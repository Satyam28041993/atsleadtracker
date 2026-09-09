import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/lead_model.dart';
import 'analytics_service.dart';
import '../utils/xlsx_features.dart';

/// Builds a multi-sheet Excel workbook out of what the dashboard is showing.
///
/// Read-only: everything comes from data already loaded in the UI, so exporting
/// never triggers extra Firestore reads and never writes anything back.
class AnalyticsExcelService {
  const AnalyticsExcelService();

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

  /// Returns the encoded .xlsx bytes, or `null` if the package failed to
  /// encode (callers surface that as a friendly error).
  Uint8List? build({
    required ManagerDashboardData dashboard,
    required List<Lead> leads,
    String? dateRangeLabel,
  }) {
    final book = Excel.createExcel();

    // Excel.createExcel() seeds a default sheet we don't use; build ours first
    // then drop it, so the workbook doesn't open on an empty tab.
    const defaultSheet = 'Sheet1';

    _buildSummarySheet(book, dashboard, dateRangeLabel);
    _buildStatusSheet(book, dashboard);
    _buildEmployeeSheet(book, dashboard);
    _buildLeadsSheet(book, leads);

    if (book.sheets.containsKey(defaultSheet)) {
      book.delete(defaultSheet);
    }

    final encoded = book.encode();
    return encoded == null ? null : Uint8List.fromList(encoded);
  }

  String suggestedFileName() {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'ats_analytics_$stamp.xlsx';
  }

  void _row(Sheet sheet, List<CellValue?> values) {
    sheet.appendRow(values);
  }

  void _buildSummarySheet(
    Excel book,
    ManagerDashboardData d,
    String? dateRangeLabel,
  ) {
    final sheet = book['Summary'];
    _row(sheet, [TextCellValue('ATS CRM — Analytics Export')]);
    _row(sheet, [
      TextCellValue('Generated'),
      TextCellValue(_dateTimeFormat.format(DateTime.now())),
    ]);
    _row(sheet, [
      TextCellValue('Date range'),
      TextCellValue(dateRangeLabel ?? 'All Time'),
    ]);
    _row(sheet, [
      TextCellValue('Data last refreshed'),
      TextCellValue(_dateTimeFormat.format(d.lastUpdatedAt)),
    ]);
    _row(sheet, []);

    final won = d.statusBreakdown['Won'] ?? 0;
    final conversion = d.totalLeads == 0 ? 0.0 : won / d.totalLeads * 100;

    _row(sheet, [TextCellValue('Metric'), TextCellValue('Value')]);
    _row(sheet, [TextCellValue('Total leads'), IntCellValue(d.totalLeads)]);
    _row(sheet, [
      TextCellValue('Regular leads'),
      IntCellValue(d.totalNormalLeads),
    ]);
    _row(sheet, [TextCellValue('Tenders'), IntCellValue(d.totalTenders)]);
    _row(sheet, [TextCellValue('Won'), IntCellValue(won)]);
    _row(sheet, [
      TextCellValue('Conversion rate (%)'),
      DoubleCellValue(double.parse(conversion.toStringAsFixed(2))),
    ]);
  }

  void _buildStatusSheet(Excel book, ManagerDashboardData d) {
    final sheet = book['Status Breakdown'];
    _row(sheet, [
      TextCellValue('Status'),
      TextCellValue('Leads'),
      TextCellValue('Tenders'),
      TextCellValue('Total'),
    ]);

    final statuses = <String>{
      ...Lead.statuses,
      ...Lead.tenderStatuses,
      ...d.normalStatusBreakdown.keys,
      ...d.tenderStatusBreakdown.keys,
    };

    for (final status in statuses) {
      final normal = d.normalStatusBreakdown[status] ?? 0;
      final tender = d.tenderStatusBreakdown[status] ?? 0;
      if (normal == 0 && tender == 0) continue;
      _row(sheet, [
        TextCellValue(status),
        IntCellValue(normal),
        IntCellValue(tender),
        IntCellValue(normal + tender),
      ]);
    }
  }

  void _buildEmployeeSheet(Excel book, ManagerDashboardData d) {
    final sheet = book['Employee Performance'];

    final statuses = <String>{...Lead.statuses, ...Lead.tenderStatuses}
        .where((s) => d.employeePulses.any((p) => (p.statusCounts[s] ?? 0) > 0))
        .toList(growable: false);

    _row(sheet, [
      TextCellValue('Employee'),
      TextCellValue('Online'),
      TextCellValue('Last active'),
      TextCellValue('Total leads'),
      for (final s in statuses) TextCellValue(s),
      TextCellValue('Stale leads (>24h)'),
    ]);

    for (final pulse in d.employeePulses) {
      final total = pulse.statusCounts.values.fold<int>(0, (a, b) => a + b);
      _row(sheet, [
        TextCellValue(pulse.displayName),
        TextCellValue(pulse.isOnline ? 'Yes' : 'No'),
        TextCellValue(
          pulse.lastActive == null
              ? '—'
              : _dateTimeFormat.format(pulse.lastActive!),
        ),
        IntCellValue(total),
        for (final s in statuses) IntCellValue(pulse.statusCounts[s] ?? 0),
        TextCellValue(pulse.hasStagnantLeads ? 'Yes' : 'No'),
      ]);
    }
  }

  /// Kept as a named list so the auto-filter range below cannot drift out of
  /// sync when a column is added.
  static const List<String> _leadHeaders = <String>[
    'Company',
    'Contact',
    'Phone',
    'Email',
    'Status',
    'Type',
    'Source',
    'Requirement',
    'Amount',
    'Lead date',
    'Next follow-up',
    'Location',
    'PO number',
    'Invoice number',
    'Created by',
  ];

  void _buildLeadsSheet(Excel book, List<Lead> leads) {
    final sheet = book['Leads'];
    _row(sheet, _leadHeaders.map<CellValue?>(TextCellValue.new).toList());

    for (final l in leads) {
      _row(sheet, [
        TextCellValue(l.company),
        TextCellValue(l.name),
        TextCellValue(l.phone),
        TextCellValue(l.email),
        TextCellValue(l.status),
        TextCellValue(l.isTender ? 'Tender' : 'Lead'),
        TextCellValue(l.source),
        TextCellValue(l.productsSummary),
        DoubleCellValue(l.totalAmount),
        TextCellValue(_dateFormat.format(l.leadDate)),
        TextCellValue(
          l.nextFollowUpDate == null
              ? ''
              : _dateFormat.format(l.nextFollowUpDate!),
        ),
        TextCellValue(l.location),
        TextCellValue(l.poNumber),
        TextCellValue(l.invoiceNumber),
        TextCellValue(l.creatorName),
      ]);
    }
  }

  /// Builds a dedicated Excel workbook for the CRM report.
  Uint8List? buildCrmReport({
    required CrmReportData crmData,
    required List<Lead> leads,
    String? periodLabel,
  }) {
    final book = Excel.createExcel();
    const defaultSheet = 'Sheet1';

    _buildCrmEmployeeSummarySheet(book, crmData, periodLabel);
    _buildLeadsSheet(book, leads);

    if (book.sheets.containsKey(defaultSheet)) {
      book.delete(defaultSheet);
    }

    final encoded = book.encode();
    if (encoded == null) return null;

    // Match the other workbooks: a frozen header row and working filters. The
    // excel package has no API for either, so patch the package directly.
    return XlsxFeatures.apply(
      Uint8List.fromList(encoded),
      <String, SheetFeature>{
        'Employee Activity': const SheetFeature(freezeRows: 1),
        'Leads': SheetFeature(
          freezeRows: 1,
          freezeCols: 2,
          autoFilterRef: XlsxFeatures.rangeRef(_leadHeaders.length, leads.length),
        ),
      },
    );
  }

  void _buildCrmEmployeeSummarySheet(
    Excel book,
    CrmReportData crmData,
    String? periodLabel,
  ) {
    final sheet = book['Employee Activity'];
    _row(sheet, [TextCellValue('ATS CRM — Daily Employee Performance Report')]);
    _row(sheet, [
      TextCellValue('Generated'),
      TextCellValue(_dateTimeFormat.format(DateTime.now())),
    ]);
    _row(sheet, [
      TextCellValue('Period'),
      TextCellValue(periodLabel ?? 'Today'),
    ]);
    _row(sheet, []);

    _row(sheet, [
      TextCellValue('Employee Name'),
      TextCellValue('Role'),
      TextCellValue('New Leads'),
      TextCellValue('New Tenders'),
      TextCellValue('Calls / Touches'),
      TextCellValue('Follow-ups Done'),
      TextCellValue('Follow-ups Due'),
      TextCellValue('Follow-ups Overdue'),
      TextCellValue('Status Changes'),
      TextCellValue('Quotes Made'),
      TextCellValue('Quotes Value (₹)'),
      TextCellValue('Deals Won'),
      TextCellValue('Deals Won Value (₹)'),
      TextCellValue('Tenders Won'),
      TextCellValue('Tenders Won Value (₹)'),
      TextCellValue('Pipeline Value (₹)'),
    ]);

    for (final r in crmData.rows) {
      _row(sheet, [
        TextCellValue(r.employeeName),
        TextCellValue(r.role),
        IntCellValue(r.leadsAdded),
        IntCellValue(r.tendersAdded),
        IntCellValue(r.calls),
        IntCellValue(r.followUpsDone),
        IntCellValue(r.followUpsPending),
        IntCellValue(r.followUpsOverdue),
        IntCellValue(r.statusChanges),
        IntCellValue(r.quotesMade),
        DoubleCellValue(r.quoteValue),
        IntCellValue(r.dealsWon),
        DoubleCellValue(r.dealsWonValue),
        IntCellValue(r.tendersWon),
        DoubleCellValue(r.tendersWonValue),
        DoubleCellValue(r.pipelineValue),
      ]);
    }
  }

  String suggestedCrmFileName() {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'ats_crm_report_$stamp.xlsx';
  }
}
