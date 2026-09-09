import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/analytics_export_service.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import '../widgets/analytics_lead_list_modal.dart';
import '../widgets/source_report_section.dart';
import '../../utils/export_io.dart';

/// Executive KPIs, pipeline charts, monthly sales, and rep leaderboard.
class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({
    super.key,
    required this.analyticsService,
    required this.authService,
    required this.leadService,
    this.productService,
    this.assignedToUid,
  });

  final AnalyticsService analyticsService;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;
  final String? assignedToUid;

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  Future<ExecutiveAnalytics>? _future;

  String _selectedTimeframe = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedEmployeeUid;
  List<MapEntry<String, String>> _assignableEmployees = [];

  bool get _canEditTargets => widget.assignedToUid == null;

  @override
  void initState() {
    super.initState();
    _selectedEmployeeUid = widget.assignedToUid;
    _setTimeframeDates('All Time');
    _fetchEmployees();
    _reload();
  }

  Future<void> _fetchEmployees() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'employee')
          .get();
      final list = snap.docs.map((doc) {
        final name = (doc.data()['name'] as String? ?? '').trim();
        return MapEntry(doc.id, name.isNotEmpty ? name : doc.id);
      }).toList();
      setState(() {
        _assignableEmployees = list;
      });
    } catch (_) {
      // fail silently
    }
  }

  void _setTimeframeDates(String timeframe) {
    _selectedTimeframe = timeframe;
    final now = DateTime.now();
    if (timeframe == 'Today') {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (timeframe == 'This Week') {
      final weekday = now.weekday;
      final start = now.subtract(Duration(days: weekday - 1));
      _startDate = DateTime(start.year, start.month, start.day);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (timeframe == 'This Month') {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (timeframe == 'Last Month') {
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      _startDate = DateTime(prevYear, prevMonth, 1);
      final lastDay = DateTime(prevYear, prevMonth + 1, 0).day;
      _endDate = DateTime(prevYear, prevMonth, lastDay, 23, 59, 59, 999);
    } else if (timeframe == 'This Quarter') {
      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      _startDate = DateTime(now.year, quarterStartMonth, 1);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (timeframe == 'This Year') {
      _startDate = DateTime(now.year, 1, 1);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (timeframe == 'All Time') {
      _startDate = null;
      _endDate = null;
    }
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedTimeframe = 'Custom';
        _startDate = picked.start;
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        );
        _reload();
      });
    }
  }

  void _reload() {
    setState(() {
      _future = widget.analyticsService.computeAnalytics(
        assignedToUid: _selectedEmployeeUid,
        startDate: _startDate,
        endDate: _endDate,
      );
    });
  }

  /// Builds the analytics workbook from the figures currently on screen.
  Future<void> _exportWorkbook(ExecutiveAnalytics data) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = AnalyticsExportService();
    final scopedUid = widget.assignedToUid ?? _selectedEmployeeUid;

    final progress = ValueNotifier<String>('Reading leads…');
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Building workbook'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (context, value, _) => Text(value),
              ),
            ],
          ),
        ),
      ).then((_) => dialogOpen = false),
    );

    try {
      final inputs = await service.loadInputs(assignedToUid: scopedUid);
      progress.value = 'Reading team…';
      final namesByUid = <String, String>{};
      try {
        final users = await FirebaseFirestore.instance
            .collection('users')
            .get();
        for (final doc in users.docs) {
          final name = doc.data()['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) namesByUid[doc.id] = name;
        }
      } catch (_) {
        // Falls back to "Unknown" per row rather than failing the export.
      }

      progress.value = 'Building workbook…';
      final scopeLabel = scopedUid == null
          ? 'All team members'
          : (namesByUid[scopedUid] ?? scopedUid);
      final bytes = service.buildWorkbook(
        data: data,
        leads: inputs.leads,
        latestQuote: inputs.latestQuote,
        namesByUid: namesByUid,
        scopeLabel: scopeLabel,
        periodLabel: _selectedTimeframe,
      );
      if (bytes == null) throw StateError('Could not build the Excel file.');

      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      final name = service.suggestedFileName();
      final saved = await saveExportBytes(
        bytes: bytes,
        fileName: name,
        dialogTitle: 'Export analytics',
      );
      if (!mounted) return;
      if (saved) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb ? 'Download started: $name' : 'Analytics exported.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
  }

  void _openLeads(
    String title,
    List<String> leadIds, {
    Set<String>? quotedLeadIds,
    Map<String, double>? leadAmounts,
  }) {
    AnalyticsLeadListModal.show(
      context,
      title: '$title (${leadIds.length})',
      leadIds: leadIds,
      authService: widget.authService,
      leadService: widget.leadService,
      productService: widget.productService,
      quotedLeadIds: quotedLeadIds,
      leadAmounts: leadAmounts,
    );
  }

  Future<void> _editQuota(TargetProgress entry) async {
    final controller = TextEditingController(
      text: entry.targetAmount.toStringAsFixed(0),
    );
    final saved = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Set target — ${entry.displayName}'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Monthly quota (INR)',
              hintText: 'e.g. 500000',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim().replaceAll(',', '');
                final value = double.tryParse(raw);
                if (value == null || value < 0) return;
                Navigator.of(context).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (saved == null || !mounted) return;

    try {
      await widget.analyticsService.updateEmployeeQuota(
        employeeUid: entry.employeeUid,
        monthlyQuota: saved,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Target updated for ${entry.displayName}')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update target: $e')),
      );
    }
  }

  Widget _buildFiltersToolbar(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedTimeframe == 'Custom'
                      ? 'Custom'
                      : _selectedTimeframe,
                  underline: const SizedBox.shrink(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Today', child: Text('Today')),
                    DropdownMenuItem(
                      value: 'This Week',
                      child: Text('This Week'),
                    ),
                    DropdownMenuItem(
                      value: 'This Month',
                      child: Text('This Month'),
                    ),
                    DropdownMenuItem(
                      value: 'Last Month',
                      child: Text('Last Month'),
                    ),
                    DropdownMenuItem(
                      value: 'This Quarter',
                      child: Text('This Quarter'),
                    ),
                    DropdownMenuItem(
                      value: 'This Year',
                      child: Text('This Year'),
                    ),
                    DropdownMenuItem(
                      value: 'All Time',
                      child: Text('All Time'),
                    ),
                    DropdownMenuItem(
                      value: 'Custom',
                      child: Text('Custom Range...'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    if (val == 'Custom') {
                      _selectCustomRange();
                    } else {
                      setState(() {
                        _setTimeframeDates(val);
                        _reload();
                      });
                    }
                  },
                ),
                if (_selectedTimeframe == 'Custom' &&
                    _startDate != null &&
                    _endDate != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
            if (widget.assignedToUid == null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: _selectedEmployeeUid,
                    hint: const Text('All Team Members'),
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Team Members'),
                      ),
                      for (final emp in _assignableEmployees)
                        DropdownMenuItem(
                          value: emp.key,
                          child: Text(emp.value),
                        ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedEmployeeUid = val;
                        _reload();
                      });
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Employee view (your data)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static const List<Color> _pieColors = <Color>[
    Color(0xFF3B5BDB),
    Color(0xFF2F9E44),
    Color(0xFFF08C00),
    Color(0xFFBE4BDB),
    Color(0xFF228BE6),
    Color(0xFF7950F2),
    Color(0xFF0CA678),
    Color(0xFFE03131),
    Color(0xFF495057),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<ExecutiveAnalytics>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Could not load analytics.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;

        void openLeads(
          String title,
          List<String> leadIds, {
          Set<String>? quotedLeadIds,
          Map<String, double>? leadAmounts,
        }) {
          _openLeads(
            title,
            leadIds,
            quotedLeadIds: quotedLeadIds ?? data.quotedLeadIds.toSet(),
            leadAmounts: leadAmounts ?? data.leadAmounts,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            final fut = widget.analyticsService.computeAnalytics(
              assignedToUid: _selectedEmployeeUid,
              startDate: _startDate,
              endDate: _endDate,
            );
            setState(() => _future = fut);
            await fut;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFiltersToolbar(theme),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => _exportWorkbook(data),
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('Export analytics (Excel)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _KpiRow(
                      wide: wide,
                      data: data,
                      onOpenLeads: openLeads,
                    ),
                    const SizedBox(height: 20),
                    SourceReportSection(
                      report: data.sourceReport,
                      colors: _pieColors,
                      onOpenLeads: openLeads,
                      showEmployeeView: _selectedEmployeeUid == null ||
                          _selectedEmployeeUid!.isEmpty,
                    ),
                    const SizedBox(height: 20),
                    wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _StatusPipelineCard(
                                  slices: data.statusSlices,
                                  colors: _pieColors,
                                  onOpenLeads: openLeads,
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _SourcePieCard(
                                  slices: data.sourceSlices,
                                  colors: _pieColors,
                                  onOpenLeads: openLeads,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _StatusPipelineCard(
                                slices: data.statusSlices,
                                colors: _pieColors,
                                onOpenLeads: openLeads,
                              ),
                              const SizedBox(height: 18),
                              _SourcePieCard(
                                slices: data.sourceSlices,
                                colors: _pieColors,
                                onOpenLeads: openLeads,
                              ),
                            ],
                          ),
                    const SizedBox(height: 20),
                    wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _MonthlySalesCard(
                                  points: data.monthlySales,
                                  onOpenLeads: openLeads,
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _LossReasonsBarCard(
                                  slices: data.lossSlices,
                                  colors: _pieColors,
                                  onOpenLeads: openLeads,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _MonthlySalesCard(
                                points: data.monthlySales,
                                onOpenLeads: openLeads,
                              ),
                              const SizedBox(height: 18),
                              _LossReasonsBarCard(
                                slices: data.lossSlices,
                                colors: _pieColors,
                                onOpenLeads: openLeads,
                              ),
                            ],
                          ),
                    const SizedBox(height: 20),
                    wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LeaderboardCard(
                                  entries: data.leaderboard,
                                  onOpenLeads: openLeads,
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _EmployeeTargetsCard(
                                  entries: data.employeeTargetProgress,
                                  canEdit: _canEditTargets,
                                  onOpenLeads: openLeads,
                                  onEditQuota: _editQuota,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _LeaderboardCard(
                                entries: data.leaderboard,
                                onOpenLeads: openLeads,
                              ),
                              const SizedBox(height: 18),
                              _EmployeeTargetsCard(
                                entries: data.employeeTargetProgress,
                                canEdit: _canEditTargets,
                                onOpenLeads: openLeads,
                                onEditQuota: _editQuota,
                              ),
                            ],
                          ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

typedef _OpenLeadsFn =
    void Function(
      String title,
      List<String> leadIds, {
      Set<String>? quotedLeadIds,
      Map<String, double>? leadAmounts,
    });

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.wide,
    required this.data,
    required this.onOpenLeads,
  });

  final bool wide;
  final ExecutiveAnalytics data;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final amounts = data.leadAmounts;
    final quoted = data.quotedLeadIds.toSet();
    final cards = [
      _KpiCard(
        title: 'Active leads',
        subtitle: 'All open leads + tenders (snapshot)',
        value: data.totalActiveLeads.toString(),
        icon: Icons.track_changes_rounded,
        color: const Color(0xFF3B5BDB),
        onTap: data.activeLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Active leads',
                data.activeLeadIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Pipeline value',
        subtitle: data.pipelineLeadIds.isEmpty
            ? 'Open deals with value (snapshot)'
            : '${data.pipelineLeadIds.length} valued open (snapshot)',
        value: 'INR ${_fmtMoney(data.pipelineValue)}',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFF08C00),
        onTap: data.pipelineLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Pipeline leads',
                data.pipelineLeadIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Expected revenue',
        subtitle: data.expectedRevenueLeadIds.isEmpty
            ? 'Proposal / Follow-up open (snapshot)'
            : '${data.expectedRevenueLeadIds.length} proposal+ open (snapshot)',
        value: 'INR ${_fmtMoney(data.expectedRevenue)}',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF0CA678),
        onTap: data.expectedRevenueLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Expected revenue leads',
                data.expectedRevenueLeadIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Won revenue',
        subtitle: data.closedWonCount == 0
            ? 'No won deals in period'
            : '${data.closedWonCount} won deal${data.closedWonCount == 1 ? '' : 's'} in period',
        value: 'INR ${_fmtMoney(data.totalRevenue)}',
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFF2F9E44),
        onTap: data.wonLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Won deals',
                data.wonLeadIds,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Win rate',
        subtitle: 'Won vs closed in period',
        value: _fmtPercent(data.winRate),
        icon: Icons.insights_rounded,
        color: const Color(0xFF1864AB),
        onTap: data.closedDealIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Closed deals (won + lost)',
                data.closedDealIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Avg won deal',
        subtitle: data.closedWonCount == 0
            ? 'No won deals in period'
            : 'Across ${data.closedWonCount} won',
        value: 'INR ${_fmtMoney(data.avgWonDealSize)}',
        icon: Icons.show_chart_rounded,
        color: const Color(0xFF5F3DC4),
        onTap: data.wonLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Won deals',
                data.wonLeadIds,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Conversion to won',
        subtitle: 'Won deals in period',
        value: _fmtPercent(data.conversionToWon),
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF2B8A3E),
        onTap: data.wonLeadIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Won deals',
                data.wonLeadIds,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Leads added today',
        subtitle: 'New entries',
        value: data.leadsAddedToday.toString(),
        icon: Icons.person_add_rounded,
        color: const Color(0xFFBE4BDB),
        onTap: data.leadsAddedTodayIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Leads added today',
                data.leadsAddedTodayIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Follow-ups today',
        subtitle: 'Scheduled action',
        value: data.followUpsToday.toString(),
        icon: Icons.today_rounded,
        color: const Color(0xFFE03131),
        onTap: data.followUpsTodayIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Follow-ups today',
                data.followUpsTodayIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
      _KpiCard(
        title: 'Overdue follow-ups',
        subtitle: 'Open leads pending action',
        value: data.overdueFollowUps.toString(),
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFC92A2A),
        onTap: data.overdueFollowUpIds.isEmpty
            ? null
            : () => onOpenLeads(
                'Overdue follow-ups',
                data.overdueFollowUpIds,
                quotedLeadIds: quoted,
                leadAmounts: amounts,
              ),
      ),
    ];

    if (wide) {
      return Column(
        children: [
          for (var rowStart = 0; rowStart < cards.length; rowStart += 3) ...[
            if (rowStart > 0) const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: cards[rowStart]),
                const SizedBox(width: 14),
                Expanded(
                  child: rowStart + 1 < cards.length
                      ? cards[rowStart + 1]
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: rowStart + 2 < cards.length
                      ? cards[rowStart + 2]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          cards[i],
          if (i < cards.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  static String _fmtMoney(double v) {
    if (v >= 10000000) {
      return '${(v / 10000000).toStringAsFixed(2)} Cr';
    }
    if (v >= 100000) {
      return '${(v / 100000).toStringAsFixed(2)} L';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)} K';
    }
    return v.toStringAsFixed(0);
  }

  static String _fmtPercent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: color, size: 26),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: onTap != null
                            ? const Color(0xFF245DAF)
                            : const Color(0xFF1D2638),
                        decoration:
                            onTap != null ? TextDecoration.underline : null,
                        decorationColor: const Color(0xFF245DAF),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPipelineCard extends StatelessWidget {
  const _StatusPipelineCard({
    required this.slices,
    required this.colors,
    required this.onOpenLeads,
  });

  final List<StatusSlice> slices;
  final List<Color> colors;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<int>(0, (a, b) => a + b.count);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pipeline by status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Open opportunities grouped by current stage (all open snapshot)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (slices.isEmpty || total == 0)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No open pipeline data yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 44,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (event is! FlTapUpEvent) return;
                              final index =
                                  response?.touchedSection?.touchedSectionIndex;
                              if (index == null ||
                                  index < 0 ||
                                  index >= slices.length) {
                                return;
                              }
                              onOpenLeads(
                                'Status: ${slices[index].label}',
                                slices[index].leadIds,
                              );
                            },
                          ),
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                color: colors[i % colors.length],
                                value: slices[i].count.toDouble(),
                                title:
                                    '${slices[i].count}\n${((slices[i].count / total) * 100).round()}%',
                                radius: 52,
                                titleStyle: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (var i = 0; i < slices.length; i++)
                            InkWell(
                              onTap: () => onOpenLeads(
                                'Status: ${slices[i].label}',
                                slices[i].leadIds,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: colors[i % colors.length],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        slices[i].label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    Text(
                                      '${slices[i].count}',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF245DAF),
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourcePieCard extends StatelessWidget {
  const _SourcePieCard({
    required this.slices,
    required this.colors,
    required this.onOpenLeads,
  });

  final List<SourceSlice> slices;
  final List<Color> colors;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<int>(0, (acc, b) => acc + b.count);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lead sources',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Distribution of leads by marketing channel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (slices.isEmpty || total == 0)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No source data available.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 44,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (event is! FlTapUpEvent) return;
                              final index =
                                  response?.touchedSection?.touchedSectionIndex;
                              if (index == null ||
                                  index < 0 ||
                                  index >= slices.length) {
                                return;
                              }
                              onOpenLeads(
                                'Source: ${slices[index].label}',
                                slices[index].leadIds,
                              );
                            },
                          ),
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                color: colors[i % colors.length],
                                value: slices[i].count.toDouble(),
                                title:
                                    '${slices[i].count}\n${((slices[i].count / total) * 100).round()}%',
                                radius: 52,
                                titleStyle: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (var i = 0; i < slices.length; i++)
                            InkWell(
                              onTap: () => onOpenLeads(
                                'Source: ${slices[i].label}',
                                slices[i].leadIds,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: colors[i % colors.length],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        slices[i].label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    Text(
                                      '${slices[i].count}',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF245DAF),
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthlySalesCard extends StatelessWidget {
  const _MonthlySalesCard({
    required this.points,
    required this.onOpenLeads,
  });

  final List<MonthlySalesPoint> points;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawMax = points.fold<double>(
      0,
      (m, p) => p.amount > m ? p.amount : m,
    );
    final maxY = rawMax > 0 ? rawMax : 1;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monthly sales (Won)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Revenue by installation / close month (${DateTime.now().year}) — tap a bar',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY * 1.25,
                  barTouchData: BarTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final i = group.x.toInt();
                        if (i < 0 || i >= points.length) return null;
                        return BarTooltipItem(
                          '${points[i].label}\nINR ${_fmtMoney(points[i].amount)}\n${points[i].leadIds.length} deals',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final i = response?.spot?.touchedBarGroupIndex;
                      if (i == null || i < 0 || i >= points.length) return;
                      if (points[i].leadIds.isEmpty) return;
                      onOpenLeads(
                        'Won in ${points[i].label}',
                        points[i].leadIds,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              points[i].label,
                              style: theme.textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) {
                          if (value <= 0) return const SizedBox.shrink();
                          return Text(
                            _shortMoney(value),
                            style: theme.textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= points.length) {
                            return const SizedBox.shrink();
                          }
                          if (points[i].amount <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _shortMoney(points[i].amount),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        showingTooltipIndicators:
                            points[i].amount > 0 ? const [0] : const [],
                        barRods: [
                          BarChartRodData(
                            toY: points[i].amount,
                            width: 12,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            color: const Color(0xFF3B5BDB),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtMoney(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} K';
    return v.toStringAsFixed(0);
  }

  static String _shortMoney(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _LossReasonsBarCard extends StatelessWidget {
  const _LossReasonsBarCard({
    required this.slices,
    required this.colors,
    required this.onOpenLeads,
  });

  final List<LossSlice> slices;
  final List<Color> colors;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = slices.fold<int>(
      0,
      (m, p) => p.count > m ? p.count : m,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lost deal diagnostics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Full loss reasons — tap a row to view leads',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (slices.isEmpty)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No lost deals data available.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < slices.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onOpenLeads(
                        'Lost: ${slices[i].label}',
                        slices[i].leadIds,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    slices[i].label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${slices[i].count}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF245DAF),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                value: maxCount > 0
                                    ? slices[i].count / maxCount
                                    : 0,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors[i % colors.length],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entries,
    required this.onOpenLeads,
  });

  final List<LeaderboardEntry> entries;
  final _OpenLeadsFn onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales leaderboard',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Won deals, revenue, and conversion by assignee',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No closed deals yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length.clamp(0, 15),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final rank = index + 1;
                  final zeroAmountNote = e.wonDeals > 0 && e.wonRevenue <= 0
                      ? ' • amount not set on won leads'
                      : '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: e.wonLeadIds.isEmpty
                        ? null
                        : () => onOpenLeads(
                              'Won by ${e.displayName}',
                              e.wonLeadIds,
                            ),
                    leading: CircleAvatar(
                      backgroundColor: rank <= 3
                          ? const Color(0xFFFFECB3)
                          : const Color(0xFFE9ECEF),
                      foregroundColor: const Color(0xFF1D2638),
                      child: Text(
                        '$rank',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(
                      e.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'INR ${_KpiRow._fmtMoney(e.wonRevenue)} • ${_KpiRow._fmtPercent(e.winRate)} win rate$zeroAmountNote',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Text(
                      '${e.wonDeals} won',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF245DAF),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeTargetsCard extends StatelessWidget {
  const _EmployeeTargetsCard({
    required this.entries,
    required this.canEdit,
    required this.onOpenLeads,
    required this.onEditQuota,
  });

  final List<TargetProgress> entries;
  final bool canEdit;
  final _OpenLeadsFn onOpenLeads;
  final Future<void> Function(TargetProgress entry) onEditQuota;

  String _formatCurrency(double amount) {
    final format =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return format.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales Targets & Quotas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Closed Won deal value vs monthly target (₹0 won = amount not filled on leads)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No employee targets data available.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final pct = entry.targetAmount > 0
                      ? (entry.actualWon / entry.targetAmount).clamp(0.0, 1.0)
                      : 0.0;
                  final pctDisplay = (pct * 100).toStringAsFixed(1);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'Edit target',
                              onPressed: () => onEditQuota(entry),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          InkWell(
                            onTap: entry.wonLeadIds.isEmpty
                                ? null
                                : () => onOpenLeads(
                                      'Won by ${entry.displayName}',
                                      entry.wonLeadIds,
                                    ),
                            child: Text(
                              '$pctDisplay% achieved',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: pct >= 1.0
                                    ? const Color(0xFF2B8A3E)
                                    : const Color(0xFF245DAF),
                                fontSize: 12,
                                decoration: entry.wonLeadIds.isNotEmpty
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: pct,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct >= 1.0
                                ? const Color(0xFF2B8A3E)
                                : const Color(0xFF245DAF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          InkWell(
                            onTap: entry.wonLeadIds.isEmpty
                                ? null
                                : () => onOpenLeads(
                                      'Won by ${entry.displayName}',
                                      entry.wonLeadIds,
                                    ),
                            child: Text(
                              'Achieved: ${_formatCurrency(entry.actualWon)}'
                              '${entry.wonLeadIds.isNotEmpty && entry.actualWon <= 0 ? ' (${entry.wonLeadIds.length} won @ ₹0)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: entry.wonLeadIds.isNotEmpty
                                    ? const Color(0xFF245DAF)
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                                decoration: entry.wonLeadIds.isNotEmpty
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Quota: ${_formatCurrency(entry.targetAmount)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
