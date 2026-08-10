import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/lead_model.dart';
import 'analytics_service.dart';

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

  void _buildLeadsSheet(Excel book, List<Lead> leads) {
    final sheet = book['Leads'];
    _row(sheet, [
      TextCellValue('Company'),
      TextCellValue('Contact'),
      TextCellValue('Phone'),
      TextCellValue('Email'),
      TextCellValue('Status'),
      TextCellValue('Type'),
      TextCellValue('Source'),
      TextCellValue('Requirement'),
      TextCellValue('Amount'),
      TextCellValue('Lead date'),
      TextCellValue('Next follow-up'),
      TextCellValue('Location'),
      TextCellValue('PO number'),
      TextCellValue('Invoice number'),
      TextCellValue('Created by'),
    ]);

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
}
