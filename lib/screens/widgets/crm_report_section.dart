import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/export_io.dart';
import '../../models/daily_cockpit_model.dart';
import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/analytics_excel_service.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/pdf_service.dart';
import '../../services/product_service.dart';
import '../../utils/quote_pdf_view.dart';
import 'daily_report_list_modal.dart';
import 'lead_day_work_card.dart';
import 'lead_details_modal.dart';

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
  final Set<String> _expandedEmployees = <String>{};
  final Set<String> _expandedWorkCards = <String>{};
  final Map<String, int> _workPages = <String, int>{};
  static const int _pageSize = 30;

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
      _expandedEmployees.clear();
      _expandedWorkCards.clear();
      _workPages.clear();
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

  Future<void> _makeCall(String phone) async {
    final raw = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid phone number for calling.')),
      );
      return;
    }
    await launchUrl(Uri.parse('tel:$raw'), mode: LaunchMode.externalApplication);
  }

  Future<void> _openLeadFromWork(LeadDayWork work) async {
    var lead = work.lead;
    if (lead == null && work.leadId.isNotEmpty) {
      try {
        lead = await widget.leadService.getLead(work.leadId);
      } catch (_) {}
    }
    if (!mounted) return;
    if (lead == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this lead.')),
      );
      return;
    }
    LeadDetailsModal.show(
      context,
      lead: lead,
      leadService: widget.leadService,
      authService: widget.authService,
      productService: widget.productService,
    );
  }

  Future<void> _viewQuotationPdf(QuotationModel q) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generating quotation preview…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      final lead = Lead(
        id: q.leadId,
        name: q.quoteRequest.customerName,
        phone: q.quoteRequest.phone,
        email: q.quoteRequest.email,
        company: q.quoteRequest.companyName,
        status: 'Proposal',
        assignedTo: q.employeeId,
        createdAt: q.createdAt,
        remark: '',
        location: q.quoteRequest.location,
        website: '',
      );
      final pdfBytes = await PdfService().generateQuoteData(
        lead,
        q.quoteRequest,
        creatorName: q.employeeName,
      );
      if (!mounted) return;
      await showQuotePdfPreview(
        context,
        bytes: pdfBytes,
        title: q.currentRefNo,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open quotation: $e')),
      );
    }
  }

  List<CrmEmployeeReport> _sortedRows(List<CrmEmployeeReport> rows) {
    final copy = List<CrmEmployeeReport>.from(rows);
    int rank(CrmEmployeeReport r) {
      if (r.work.isNotEmpty || r.actionCount > 0) return 0;
      if (r.followUpsPending > 0 || r.followUpsOverdue > 0) return 1;
      return 2;
    }

    copy.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.actionCount.compareTo(a.actionCount);
    });
    return copy;
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
              final sorted = _sortedRows(rows);
              return Column(
                children: [
                  for (var i = 0; i < sorted.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildEmployeeAccordion(sorted[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeAccordion(CrmEmployeeReport report) {
    final isExpanded = _expandedEmployees.contains(report.employeeUid);
    final initial = report.employeeName.isNotEmpty
        ? report.employeeName[0].toUpperCase()
        : '?';
    final pipeline = report.pipelineValue > 0
        ? NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
            .format(report.pipelineValue)
        : '₹0';
    final leadCount = report.work.length;
    final actionLabel =
        '$leadCount lead${leadCount == 1 ? '' : 's'} · ${report.actionCount} actions';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedEmployees.remove(report.employeeUid);
                } else {
                  _expandedEmployees.add(report.employeeUid);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          '${report.role} · $actionLabel',
                          style: const TextStyle(fontSize: 12, color: _kTextMuted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (report.leadsAdded > 0)
                              _HeaderBadge(
                                label: '${report.leadsAdded} New Leads',
                                bgColor: const Color(0xFFDBEAFE),
                                textColor: const Color(0xFF1D4ED8),
                                onTap: () => _openLeads(
                                  'New Leads',
                                  report.addedLeadIds,
                                ),
                              ),
                            if (report.quotesMade > 0)
                              _HeaderBadge(
                                label: report.quoteValue > 0
                                    ? '${report.quotesMade} Quotes ${NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0).format(report.quoteValue)}'
                                    : '${report.quotesMade} Quotes',
                                bgColor: const Color(0xFFEDE9FE),
                                textColor: const Color(0xFF6D28D9),
                                onTap: () => _openQuotes(
                                  'Quotations',
                                  report.quotedIds,
                                ),
                              ),
                            if (report.followUpsPending > 0)
                              _HeaderBadge(
                                label: '${report.followUpsPending} Due',
                                bgColor: const Color(0xFFFFEDD5),
                                textColor: const Color(0xFFC2410C),
                                onTap: () => _openLeads(
                                  'Follow-ups Due',
                                  report.pendingFollowUpLeadIds,
                                ),
                              ),
                            if (report.followUpsOverdue > 0)
                              _HeaderBadge(
                                label: '${report.followUpsOverdue} Overdue',
                                bgColor: const Color(0xFFFCE7F3),
                                textColor: const Color(0xFFBE185D),
                                onTap: () => _openLeads(
                                  'Follow-ups Overdue',
                                  report.overdueFollowUpLeadIds,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Pipeline $pipeline',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: _kTextMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.all(10),
              child: report.work.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No lead activity in this period. Due / overdue counts stay on the badges above.',
                        style: TextStyle(color: _kTextMuted, fontSize: 13),
                      ),
                    )
                  : _buildWorkCards(report),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkCards(CrmEmployeeReport report) {
    final page = _workPages[report.employeeUid] ?? 0;
    final shown = ((page + 1) * _pageSize).clamp(0, report.work.length);
    final remaining = report.work.length - shown;
    final slice = report.work.take(shown).toList();
    final updatesLabel = _period == _CrmPeriod.today ? 'today' : 'in this period';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final cardWidth = wide
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;

        final cards = <Widget>[
          for (final work in slice)
            SizedBox(
              width: cardWidth,
              child: LeadDayWorkCard(
                work: work,
                isExpanded: _expandedWorkCards.contains(work.leadId),
                onToggleExpand: () => setState(() {
                  if (_expandedWorkCards.contains(work.leadId)) {
                    _expandedWorkCards.remove(work.leadId);
                  } else {
                    _expandedWorkCards.add(work.leadId);
                  }
                }),
                onOpenLead: () => _openLeadFromWork(work),
                onCall: work.phone.trim().isNotEmpty
                    ? () => _makeCall(work.phone)
                    : null,
                onViewQuote: work.quotation != null
                    ? (q) => _viewQuotationPdf(q)
                    : null,
                updatesLabel: updatesLabel,
              ),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards,
            ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _workPages[report.employeeUid] = page + 1;
                  }),
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(
                    remaining > _pageSize
                        ? 'Show $_pageSize more ($remaining left)'
                        : 'Show last $remaining',
                  ),
                ),
              ),
          ],
        );
      },
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

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
