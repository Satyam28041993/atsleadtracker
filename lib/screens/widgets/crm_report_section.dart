import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/export_io.dart';
import '../../models/lead_model.dart';
import '../../services/analytics_excel_service.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'daily_report_list_modal.dart';

const Color _kTextPrimary = Color(0xFF1D2638);
const Color _kTextMuted = Color(0xFF69758D);
const Color _kBorder = Color(0xFFE6EAF2);
const Color _kChipActive = Color(0xFF0D9488);

enum _CrmPeriod {
  today,
  thisMonth,
  thisQuarter,
  halfYear,
  thisYear,
  custom,
}

class CrmReportSection extends StatefulWidget {
  const CrmReportSection({
    super.key,
    required this.analyticsService,
    required this.authService,
    required this.leadService,
    this.productService,
    this.forEmployeeUid,
  });

  final AnalyticsService analyticsService;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  /// When set, only that employee's row is loaded.
  final String? forEmployeeUid;

  @override
  State<CrmReportSection> createState() => _CrmReportSectionState();
}

class _CrmReportSectionState extends State<CrmReportSection> {
  _CrmPeriod _period = _CrmPeriod.today;
  DateTimeRange? _customRange;
  Future<CrmReportData>? _future;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DateTimeRange _rangeFor(_CrmPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case _CrmPeriod.today:
        return DateTimeRange(start: today, end: today);
      case _CrmPeriod.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case _CrmPeriod.thisQuarter:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
          start: DateTime(now.year, qStartMonth, 1),
          end: today,
        );
      case _CrmPeriod.halfYear:
        final hStart = now.month <= 6 ? 1 : 7;
        return DateTimeRange(start: DateTime(now.year, hStart, 1), end: today);
      case _CrmPeriod.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      case _CrmPeriod.custom:
        return _customRange ?? DateTimeRange(start: today, end: today);
    }
  }

  void _reload() {
    final range = _rangeFor(_period);
    setState(() {
      _future = widget.analyticsService.getCrmReport(
        start: range.start,
        end: range.end,
        forEmployeeUid: widget.forEmployeeUid,
      );
    });
  }

  Future<void> _exportToExcel(CrmReportData? crmData) async {
    if (_isExporting || crmData == null) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      Query<Map<String, dynamic>> query =
          FirebaseFirestore.instance.collection('leads');
      if (widget.forEmployeeUid != null) {
        query = query.where('assignedTo', isEqualTo: widget.forEmployeeUid);
      }
      final snap = await query.get();
      final leads = leadsFromDocs(snap.docs)
        ..sort((a, b) => b.leadDate.compareTo(a.leadDate));

      const service = AnalyticsExcelService();
      final bytes = service.buildCrmReport(
        crmData: crmData,
        leads: leads,
        periodLabel: _periodLabel(_period),
      );

      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not build the CRM report Excel file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final fileName = service.suggestedCrmFileName();
      // Report what actually happened: this used to claim success even when
      // the user cancelled the save dialog.
      final saved = await saveExportBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Export CRM Report',
      );
      if (!mounted || !saved) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? 'Download started: $fileName' : 'CRM report exported.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customRange ?? _rangeFor(_CrmPeriod.today),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = _CrmPeriod.custom;
      _customRange = picked;
    });
    _reload();
  }

  void _selectPeriod(_CrmPeriod period) {
    if (period == _CrmPeriod.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _period = period);
    _reload();
  }

  String _periodLabel(_CrmPeriod period) {
    switch (period) {
      case _CrmPeriod.today:
        return 'Today';
      case _CrmPeriod.thisMonth:
        return 'This Month';
      case _CrmPeriod.thisQuarter:
        return 'This Quarter';
      case _CrmPeriod.halfYear:
        return 'Half Year';
      case _CrmPeriod.thisYear:
        return 'This Year';
      case _CrmPeriod.custom:
        return 'Custom';
    }
  }

  String _subtitle(CrmReportData data) {
    final dateLabel = DateFormat('d MMM yyyy').format(DateTime.now());
    return '${data.totalActions} actions · ${data.employeeCount} ${data.employeeCount == 1 ? 'employee' : 'employees'} · $dateLabel';
  }

  void _openLeads(String title, List<String> ids) {
    DailyReportListModal.show(
      context,
      title: title,
      itemIds: ids,
      isQuotation: false,
      authService: widget.authService,
      leadService: widget.leadService,
      productService: widget.productService,
    );
  }

  void _openQuotes(String title, List<String> ids) {
    DailyReportListModal.show(
      context,
      title: title,
      itemIds: ids,
      isQuotation: true,
      authService: widget.authService,
      leadService: widget.leadService,
      productService: widget.productService,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  size: 18,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CRM Report',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kTextPrimary,
                      ),
                    ),
                    FutureBuilder<CrmReportData>(
                      future: _future,
                      builder: (context, snapshot) {
                        final text = snapshot.hasData
                            ? _subtitle(snapshot.data!)
                            : 'Loading…';
                        return Text(
                          text,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextMuted,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              FutureBuilder<CrmReportData>(
                future: _future,
                builder: (context, snapshot) {
                  return IconButton(
                    tooltip: 'Export CRM report to Excel',
                    onPressed: (_isExporting || !snapshot.hasData)
                        ? null
                        : () => _exportToExcel(snapshot.data),
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined, size: 20),
                  );
                },
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final period in _CrmPeriod.values)
                _PeriodChip(
                  label: period == _CrmPeriod.custom && _customRange != null
                      ? '${DateFormat('d MMM').format(_customRange!.start)} – ${DateFormat('d MMM').format(_customRange!.end)}'
                      : _periodLabel(period),
                  selected: _period == period,
                  onTap: () => _selectPeriod(period),
                ),
              IconButton(
                tooltip: 'Custom range',
                visualDensity: VisualDensity.compact,
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.calendar_month_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<CrmReportData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const Text(
                  'CRM report unavailable.',
                  style: TextStyle(color: _kTextMuted),
                );
              }
              final rows = snapshot.data?.rows ?? const <CrmEmployeeReport>[];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No employee activity in this period.',
                    style: TextStyle(color: _kTextMuted),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 24, color: _kBorder),
                    _CrmEmployeeRow(
                      report: rows[i],
                      onOpenLeads: _openLeads,
                      onOpenQuotes: _openQuotes,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kChipActive : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _kTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CrmEmployeeRow extends StatelessWidget {
  const _CrmEmployeeRow({
    required this.report,
    required this.onOpenLeads,
    required this.onOpenQuotes,
  });

  final CrmEmployeeReport report;
  final void Function(String title, List<String> ids) onOpenLeads;
  final void Function(String title, List<String> ids) onOpenQuotes;

  String _inr(double value) {
    if (value <= 0) return '';
    return NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 2)
        .format(value)
        .replaceAll('.00', '');
  }

  @override
  Widget build(BuildContext context) {
    final initial = report.employeeName.isNotEmpty
        ? report.employeeName[0].toUpperCase()
        : '?';
    final pipeline = report.pipelineValue > 0
        ? 'Pipeline ${_inr(report.pipelineValue)}'
        : 'Pipeline ₹0';

    final tiles = <_MetricTileData>[
      _MetricTileData(
        count: report.leadsAdded,
        label: 'New Leads',
        color: const Color(0xFFDBEAFE),
        accent: const Color(0xFF1D4ED8),
        onTap: () => onOpenLeads('New Leads', report.addedLeadIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.tendersAdded,
        label: 'New Tenders',
        color: const Color(0xFFE0E7FF),
        accent: const Color(0xFF4338CA),
        onTap: () => onOpenLeads('New Tenders', report.addedTenderIds),
      ),
      _MetricTileData(
        count: report.calls,
        label: 'Calls',
        color: const Color(0xFFCCFBF1),
        accent: const Color(0xFF0F766E),
        onTap: () => onOpenLeads('Calls', report.callLeadIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.quotesMade,
        label: report.quoteValue > 0
            ? 'Quotations ${_inr(report.quoteValue)}'
            : 'Quotations',
        color: const Color(0xFFEDE9FE),
        accent: const Color(0xFF6D28D9),
        onTap: () => onOpenQuotes('Quotations', report.quotedIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.statusChanges,
        label: 'Status Changes',
        color: const Color(0xFFFEF3C7),
        accent: const Color(0xFFB45309),
        onTap: () => onOpenLeads('Status Changes', report.statusChangeLeadIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.followUpsDone,
        label: 'Follow-ups Done',
        color: const Color(0xFFD1FAE5),
        accent: const Color(0xFF047857),
        onTap: () => onOpenLeads('Follow-ups Done', report.followUpLeadIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.followUpsPending,
        label: 'Follow-ups Due',
        color: const Color(0xFFFFEDD5),
        accent: const Color(0xFFC2410C),
        onTap: () => onOpenLeads('Follow-ups Due', report.pendingFollowUpLeadIds),
        alwaysShow: true,
      ),
      _MetricTileData(
        count: report.followUpsOverdue,
        label: 'Follow-ups Overdue',
        color: const Color(0xFFFCE7F3),
        accent: const Color(0xFFBE185D),
        onTap: () =>
            onOpenLeads('Follow-ups Overdue', report.overdueFollowUpLeadIds),
      ),
      _MetricTileData(
        count: report.dealsWon,
        label: report.dealsWonValue > 0
            ? 'Deals Won ${_inr(report.dealsWonValue)}'
            : 'Deals Won',
        color: const Color(0xFFDCFCE7),
        accent: const Color(0xFF15803D),
        onTap: () => onOpenLeads('Deals Won', report.wonLeadIds),
      ),
      _MetricTileData(
        count: report.tendersWon,
        label: report.tendersWonValue > 0
            ? 'Tender Won ${_inr(report.tendersWonValue)}'
            : 'Tender Won',
        color: const Color(0xFFF3E8FF),
        accent: const Color(0xFF7E22CE),
        onTap: () => onOpenLeads('Tender Won', report.wonTenderIds),
      ),
    ].where((t) => t.alwaysShow || t.count > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF1D2638),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.employeeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _kTextPrimary,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${report.role} · ${report.actionCount} actions',
                    style: const TextStyle(fontSize: 12, color: _kTextMuted),
                  ),
                ],
              ),
            ),
            Text(
              pipeline,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles)
              _MetricTile(data: tile),
          ],
        ),
      ],
    );
  }
}

class _MetricTileData {
  const _MetricTileData({
    required this.count,
    required this.label,
    required this.color,
    required this.accent,
    required this.onTap,
    this.alwaysShow = false,
  });

  final int count;
  final String label;
  final Color color;
  final Color accent;
  final VoidCallback onTap;
  final bool alwaysShow;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricTileData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: data.color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: data.count > 0 ? data.onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${data.count}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: data.accent,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                data.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: data.accent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
