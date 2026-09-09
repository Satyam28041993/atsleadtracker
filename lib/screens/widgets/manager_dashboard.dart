import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/export_io.dart';
import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/analytics_excel_service.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import '../../services/quotation_service.dart';
import 'analytics_lead_list_modal.dart';
import 'crm_report_section.dart';
import 'daily_action_cockpit.dart';
import 'lead_details_modal.dart';

const double _kDashboardRadius = 16;

/// High-level manager strip: global stats, employee pulse, recent activity.
class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({
    super.key,
    required this.analyticsService,
    required this.leadService,
    required this.productService,
    required this.authService,
  });

  final AnalyticsService analyticsService;
  final LeadService leadService;
  final ProductService productService;
  final AuthService authService;

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  bool _isRefreshing = false;
  bool _isExporting = false;
  String _dateFilter = 'All Time';

  DateTime? _getStartDate(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case 'Today':
        return DateTime(now.year, now.month, now.day);
      case 'This Week':
        return DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      case 'YTD':
        return DateTime(now.year, 1, 1);
      default:
        return null;
    }
  }

  DateTime? _getEndDate(String filter) {
    if (filter == 'All Time') return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  void _onDateFilterChanged(String? newValue) {
    if (newValue != null && newValue != _dateFilter) {
      setState(() {
        _dateFilter = newValue;
      });
      widget.analyticsService.setDashboardDateRange(
        _getStartDate(newValue),
        _getEndDate(newValue),
      );
    }
  }

  Future<void> _refreshDashboard() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      await widget.analyticsService.refreshManagerDashboardData(force: true);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  /// Exports what the dashboard is currently showing to an .xlsx file.
  ///
  /// The lead rows come from the same ids the KPI cards were built from, so the
  /// spreadsheet always agrees with the screen it was exported from.
  Future<void> _exportToExcel(ManagerDashboardData data) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final ids = <String>{...data.normalLeadIds, ...data.tenderLeadIds}
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false);

      final leads = <Lead>[];
      const chunkSize = 30;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        final snap = await FirebaseFirestore.instance
            .collection('leads')
            .where(FieldPath.documentId, whereIn: ids.sublist(i, end))
            .get();
        leads.addAll(leadsFromDocs(snap.docs));
      }
      leads.sort((a, b) => b.leadDate.compareTo(a.leadDate));

      const service = AnalyticsExcelService();
      final bytes = service.build(
        dashboard: data,
        leads: leads,
        dateRangeLabel: _dateFilter,
      );
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not build the Excel file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final saved = await FilePicker.saveFile(
        dialogTitle: 'Export analytics',
        fileName: service.suggestedFileName(),
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (wasSaved(saved)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Exported ${leads.length} leads to Excel.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ManagerDashboardData>(
      stream: widget.analyticsService.getManagerDashboardData(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Dashboard data unavailable: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final theme = Theme.of(context);
        final wonCount = data.statusBreakdown['Won'] ?? 0;
        final conversionRate = data.totalLeads == 0
            ? 0.0
            : wonCount / data.totalLeads;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Last updated: ${DateFormat('dd MMM, HH:mm').format(data.lastUpdatedAt)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF6A7589),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _dateFilter,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    elevation: 16,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF1D2638),
                      fontWeight: FontWeight.w600,
                    ),
                    underline: Container(
                      height: 0,
                      color: Colors.transparent,
                    ),
                    onChanged: _onDateFilterChanged,
                    items: <String>[
                      'All Time',
                      'Today',
                      'This Week',
                      'This Month',
                      'YTD'
                    ].map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _isExporting ? null : () => _exportToExcel(data),
                    tooltip: 'Export dashboard to Excel',
                    visualDensity: VisualDensity.compact,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                  ),
                  IconButton(
                    onPressed: _isRefreshing ? null : _refreshDashboard,
                    tooltip: 'Refresh dashboard data',
                    visualDensity: VisualDensity.compact,
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DailyActionCockpit(
                analyticsService: widget.analyticsService,
                leadService: widget.leadService,
                authService: widget.authService,
                productService: widget.productService,
                isAdmin: true,
              ),
              CrmReportSection(
                analyticsService: widget.analyticsService,
                authService: widget.authService,
                leadService: widget.leadService,
                productService: widget.productService,
              ),
              const SizedBox(height: 16),
              _GlobalStatsGrid(
                data: data,
                authService: widget.authService,
                leadService: widget.leadService,
                productService: widget.productService,
              ),
              const SizedBox(height: 16),

              Text(
                'Team pulse',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D2638),
                ),
              ),
              const SizedBox(height: 12),
              _TeamPulseGrid(
                pulses: data.employeePulses,
                leadService: widget.leadService,
                productService: widget.productService,
                authService: widget.authService,
              ),
              const SizedBox(height: 14),
              Text(
                'Recent activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D2638),
                ),
              ),
              const SizedBox(height: 12),
              _ActivityTimeline(
                events: data.recentActivity.take(4).toList(),
                eventsIndexLink: data.eventsIndexLink,
              ),
              const SizedBox(height: 14),
              _PipelineHealthCard(
                wonCount: wonCount,
                totalLeads: data.totalLeads,
                conversionRate: conversionRate,
                // 'Won' lives in both the lead and tender maps, so combine
                // them — the headline count above is across both too.
                wonLeadIds: <String>[
                  ...?data.normalStatusLeadIds['Won'],
                  ...?data.tenderStatusLeadIds['Won'],
                ],
                allLeadIds: <String>[
                  ...data.normalLeadIds,
                  ...data.tenderLeadIds,
                ],
                authService: widget.authService,
                leadService: widget.leadService,
                productService: widget.productService,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF1D2638) : const Color(0xFF6B778C),
          ),
        ),
      ),
    );
  }
}

class _GlobalStatsGrid extends StatefulWidget {
  const _GlobalStatsGrid({
    required this.data,
    required this.authService,
    required this.leadService,
    this.productService,
  });

  final ManagerDashboardData data;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  @override
  State<_GlobalStatsGrid> createState() => _GlobalStatsGridState();
}

class _GlobalStatsGridState extends State<_GlobalStatsGrid> {
  bool _showTenders = false;

  void _openStatusLeads(String label) {
    final isTotal = label == 'Total leads' || label == 'Total tenders';
    final List<String> ids;
    final String title;
    if (isTotal) {
      ids = _showTenders ? widget.data.tenderLeadIds : widget.data.normalLeadIds;
      title = label;
    } else {
      final map = _showTenders
          ? widget.data.tenderStatusLeadIds
          : widget.data.normalStatusLeadIds;
      ids = map[label] ?? const <String>[];
      title = '${_showTenders ? 'Tender' : 'Lead'} status: $label';
    }
    AnalyticsLeadListModal.show(
      context,
      title: '$title (${ids.length})',
      leadIds: ids,
      authService: widget.authService,
      leadService: widget.leadService,
      productService: widget.productService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _showTenders ? widget.data.tenderStatusBreakdown : widget.data.normalStatusBreakdown;
    final total = _showTenders ? widget.data.totalTenders : widget.data.totalNormalLeads;
    final canonicalStatuses = _showTenders ? List<String>.from(Lead.tenderStatuses) : List<String>.from(Lead.statuses);
    final extraStatuses =
        m.keys.where((status) => !canonicalStatuses.contains(status)).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final cards = <_StatCardData>[
      _StatCardData(
        value: '$total',
        label: _showTenders ? 'Total tenders' : 'Total leads',
        icon: Icons.hub_outlined,
        accent: const Color(0xFF3B5BDB),
      ),
      for (final status in canonicalStatuses)
        _buildStatusCard(status, m[status] ?? 0),
      for (final status in extraStatuses)
        _buildStatusCard(status, m[status] ?? 0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Control center',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToggleTab(
                    label: 'Leads',
                    isSelected: !_showTenders,
                    onTap: () => setState(() => _showTenders = false),
                  ),
                  _ToggleTab(
                    label: 'Tenders',
                    isSelected: _showTenders,
                    onTap: () => setState(() => _showTenders = true),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _responsiveColumns(constraints.maxWidth);
            final spacing = 12.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width,
                    child: _ControlCenterStatCard(
                      data: card,
                      onTap: () => _openStatusLeads(card.label),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  int _responsiveColumns(double maxWidth) {
    if (maxWidth >= 1240) return 5;
    if (maxWidth >= 920) return 3;
    if (maxWidth >= 620) return 2;
    return 1;
  }

  _StatCardData _buildStatusCard(String status, int value) {
    return _StatCardData(
      value: '$value',
      label: status,
      icon: _iconForStatus(status),
      accent: _accentForStatus(status),
    );
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'New':
        return Icons.fiber_new_rounded;
      case 'Contacted':
        return Icons.call_outlined;
      case 'Proposal':
        return Icons.description_outlined;
      case 'Follow-up':
        return Icons.event_repeat_rounded;
      case 'Won':
        return Icons.emoji_events_outlined;
      case 'Lost':
      case 'Loss':
      case 'Disqualified':
        return Icons.outbound_rounded;
      case 'Technical Evaluation':
        return Icons.science_outlined;
      case 'Query Raised':
        return Icons.help_outline_rounded;
      case 'Query Responded':
        return Icons.mark_chat_read_outlined;
      case 'Qualified':
        return Icons.check_circle_outline_rounded;
      case 'Reverse Auction(RA)':
        return Icons.gavel_rounded;
      default:
        return Icons.label_outline_rounded;
    }
  }

  Color _accentForStatus(String status) {
    switch (status) {
      case 'New':
        return const Color(0xFF12B886);
      case 'Contacted':
        return const Color(0xFF7950F2);
      case 'Proposal':
      case 'Technical Evaluation':
      case 'Query Raised':
        return const Color(0xFFFF922B);
      case 'Query Responded':
        return const Color(0xFF22B8CF);
      case 'Follow-up':
      case 'Qualified':
      case 'Reverse Auction(RA)':
        return const Color(0xFF228BE6);
      case 'Won':
        return const Color(0xFF2B8A3E);
      case 'Lost':
      case 'Loss':
      case 'Disqualified':
        return const Color(0xFFFA5252);
      default:
        return const Color(0xFF4C6EF5);
    }
  }
}

class _StatCardData {
  const _StatCardData({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;
}

class _ControlCenterStatCard extends StatelessWidget {
  const _ControlCenterStatCard({required this.data, this.onTap});

  final _StatCardData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashboardRadius),
        border: Border.all(width: 1, color: const Color(0xFFF1F3F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_kDashboardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(data.icon, size: 20, color: data.accent),
                    ),
                    const Spacer(),
                    Text(
                      data.value,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1D2638),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  data.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF6B778C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamPulseGrid extends StatelessWidget {
  const _TeamPulseGrid({
    required this.pulses,
    required this.leadService,
    required this.productService,
    required this.authService,
  });

  final List<EmployeePulse> pulses;
  final LeadService leadService;
  final ProductService productService;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    if (pulses.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kDashboardRadius),
          border: Border.all(color: const Color(0xFFE1E6EE)),
        ),
        child: Text(
          'No employees in users collection yet.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF7C8798)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _pulseColumns(constraints.maxWidth);
        final spacing = 12.0;
        final cardWidth = (constraints.maxWidth - (columns - 1) * spacing) / columns;
        
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: pulses.map((p) => SizedBox(
            width: cardWidth,
            child: _EmployeePulseCard(
              pulse: p,
              leadService: leadService,
              productService: productService,
              authService: authService,
            ),
          )).toList(),
        );
      },
    );
  }

  int _pulseColumns(double maxWidth) {
    if (maxWidth >= 1180) return 3;
    if (maxWidth >= 740) return 2;
    return 1;
  }
}

class _EmployeePulseCard extends StatelessWidget {
  const _EmployeePulseCard({
    required this.pulse,
    required this.leadService,
    required this.productService,
    required this.authService,
  });

  final EmployeePulse pulse;
  final LeadService leadService;
  final ProductService productService;
  final AuthService authService;

  Future<void> _openEmployeeDetails(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EmployeeDetailsDialog(
        pulse: pulse,
        leadService: leadService,
        productService: productService,
        authService: authService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online =
        pulse.isOnline ||
        (pulse.lastActive != null &&
            DateTime.now().difference(pulse.lastActive!) <
                const Duration(minutes: 3));
    final dotColor = online ? const Color(0xFF40C057) : const Color(0xFFADB5BD);
    final onlineLabel = online ? 'Online' : 'Offline';
    final lastLine = pulse.lastActive != null
        ? _formatRelative(pulse.lastActive!)
        : '—';
    final uniqueStatuses = <String>{...Lead.statuses, ...Lead.tenderStatuses};
    final entries = <MapEntry<String, int>>[
      for (final s in uniqueStatuses)
        if ((pulse.statusCounts[s] ?? 0) > 0)
          MapEntry(s, pulse.statusCounts[s]!),
    ];
    if (entries.isEmpty) {
      entries.add(const MapEntry('New', 0));
    }
    entries.sort((a, b) {
      final aIsLoss = a.key == 'Lost' || a.key == 'Loss' || a.key == 'Disqualified';
      final bIsLoss = b.key == 'Lost' || b.key == 'Loss' || b.key == 'Disqualified';
      if (aIsLoss && !bIsLoss) return 1;
      if (!aIsLoss && bIsLoss) return -1;
      return b.value.compareTo(a.value);
    });
    final total = entries.fold<int>(0, (acc, e) => acc + e.value);

    return GestureDetector(
      onTap: () => _openEmployeeDetails(context),
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kDashboardRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kDashboardRadius),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.86),
                    Colors.white.withValues(alpha: 0.68),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: pulse.hasStagnantLeads
                      ? const Color(0xFFF3B2B2)
                      : Colors.white.withValues(alpha: 0.95),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 13,
                        height: 13,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: online
                              ? [
                                  BoxShadow(
                                    color: dotColor.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pulse.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E2638),
                                    ),
                                  ),
                                ),
                                if (pulse.hasStagnantLeads) ...[
                                  const SizedBox(width: 6),
                                  const Tooltip(
                                    message: 'Alert: Leads untouched for >24h',
                                    child: Icon(
                                      Icons.whatshot,
                                      color: Color(0xFFE03131),
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Last active: $lastLine',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF6A7589),
                              ),
                            ),
                            if (pulse.hasStagnantLeads) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Alert: Leads untouched for >24h',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFFC92A2A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (online
                                      ? const Color(0xFFDDFCE7)
                                      : const Color(0xFFF1F3F5))
                                  .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          onlineLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: online
                                ? const Color(0xFF2B8A3E)
                                : const Color(0xFF6C757D),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: entries.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 2.2,
                        ),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final ids = pulse.leadIdsForStatus(entry.key);
                      return _StatusMetricCell(
                        label: entry.key,
                        value: entry.value,
                        // Opens exactly the leads counted in this cell, rather
                        // than the whole employee dialog behind it.
                        onTap: ids.isEmpty
                            ? null
                            : () => AnalyticsLeadListModal.show(
                                  context,
                                  title:
                                      '${pulse.displayName} — ${entry.key} (${ids.length})',
                                  leadIds: ids,
                                  authService: authService,
                                  leadService: leadService,
                                  productService: productService,
                                ),
                      );
                    },
                  ),
                  const Divider(height: 14, color: Color(0xFFDCE3EC)),
                  Builder(
                    builder: (cellContext) {
                      final allIds = pulse.allLeadIds;
                      final label = Text(
                        'Total Leads: $total',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF324053),
                          fontWeight: FontWeight.w700,
                          decoration: allIds.isEmpty
                              ? null
                              : TextDecoration.underline,
                          decorationColor: const Color(0xFF8894A6),
                        ),
                      );
                      if (allIds.isEmpty) return label;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => AnalyticsLeadListModal.show(
                            cellContext,
                            title:
                                '${pulse.displayName} — all leads (${allIds.length})',
                            leadIds: allIds,
                            authService: authService,
                            leadService: leadService,
                            productService: productService,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: label,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMetricCell extends StatelessWidget {
  const _StatusMetricCell({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = _statusBackground(label);
    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF1F2937),
              fontWeight: FontWeight.w800,
              decoration: onTap != null ? TextDecoration.underline : null,
              decorationColor: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return cell;

    // The whole pulse card is already tappable, so this cell has to claim the
    // gesture first — Material's InkWell wins over the outer GestureDetector.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cell,
      ),
    );
  }

  Color _statusBackground(String status) {
    switch (status) {
      case 'New':
        return const Color(0xFFEAF2FF);
      case 'Contacted':
        return const Color(0xFFEEE8FF);
      case 'Proposal':
        return const Color(0xFFFFF5DD);
      case 'Follow-up':
        return const Color(0xFFEAF7FF);
      case 'Won':
        return const Color(0xFFE5FAEA);
      case 'Lost':
        return const Color(0xFFFFEBEE);
      default:
        return const Color(0xFFF1F3F5);
    }
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({
    required this.events,
    required this.eventsIndexLink,
  });

  final List<ManagerActivityEvent> events;
  final String? eventsIndexLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kDashboardRadius),
          border: Border.all(color: const Color(0xFFE1E6EE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eventsIndexLink == null
                  ? 'No recent events yet.'
                  : 'Recent activity is unavailable until the events index is created.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B778C),
              ),
            ),
            if (eventsIndexLink != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                eventsIndexLink!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF2B6CB0),
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashboardRadius),
        border: Border.all(color: const Color(0xFFE1E6EE)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            _ActivityTimelineTile(
              event: events[i],
              isLast: i == events.length - 1,
            ),
            if (i < events.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _ActivityTimelineTile extends StatelessWidget {
  const _ActivityTimelineTile({required this.event, required this.isLast});

  final ManagerActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = event.userName.isEmpty ? 'Someone' : event.userName;
    final when = _formatRelative(event.timestamp);
    final icon = _iconForAction(event.action);
    final verb = _verbForAction(event.action);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE9F2FF),
                  border: Border.all(color: const Color(0xFFD4E5FF)),
                ),
                child: Icon(icon, size: 13, color: const Color(0xFF245DAF)),
              ),
              if (!isLast)
                Container(width: 2, height: 54, color: const Color(0xFFD7E0EC)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFEFF),
              borderRadius: BorderRadius.circular(_kDashboardRadius),
              border: Border.all(color: const Color(0xFFE9EDF3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E2638),
                        ),
                      ),
                    ),
                    Text(
                      when,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF748095),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(icon, size: 16, color: const Color(0xFF245DAF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF2F3A4A),
                          ),
                          children: [
                            TextSpan(text: '$verb '),
                            TextSpan(
                              text: event.leadCompany,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PipelineHealthCard extends StatelessWidget {
  const _PipelineHealthCard({
    required this.wonCount,
    required this.totalLeads,
    required this.conversionRate,
    required this.wonLeadIds,
    required this.allLeadIds,
    required this.authService,
    required this.leadService,
    required this.productService,
  });

  final int wonCount;
  final int totalLeads;
  final double conversionRate;
  final List<String> wonLeadIds;
  final List<String> allLeadIds;
  final AuthService authService;
  final LeadService leadService;
  final ProductService productService;

  void _open(BuildContext context, String title, List<String> ids) {
    if (ids.isEmpty) return;
    AnalyticsLeadListModal.show(
      context,
      title: '$title (${ids.length})',
      leadIds: ids,
      authService: authService,
      leadService: leadService,
      productService: productService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashboardRadius),
        border: Border.all(color: const Color(0xFFE1E6EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pipeline health',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF1D2638),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${(conversionRate * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF2B8A3E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: conversionRate.clamp(0.0, 1.0).toDouble(),
              backgroundColor: const Color(0xFFE9ECEF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2B8A3E),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PipelineLink(
                text: 'Won $wonCount',
                enabled: wonLeadIds.isNotEmpty,
                onTap: () => _open(context, 'Won leads', wonLeadIds),
              ),
              Text(
                'of',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF6C7788),
                  fontWeight: FontWeight.w600,
                ),
              ),
              _PipelineLink(
                text: '$totalLeads leads',
                enabled: allLeadIds.isNotEmpty,
                onTap: () => _open(context, 'All leads', allLeadIds),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Underlined, tappable fragment inside the pipeline-health sentence.
class _PipelineLink extends StatelessWidget {
  const _PipelineLink({
    required this.text,
    required this.enabled,
    required this.onTap,
  });

  final String text;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: enabled ? const Color(0xFF245DAF) : const Color(0xFF6C7788),
          fontWeight: FontWeight.w700,
          decoration: enabled ? TextDecoration.underline : null,
          decorationColor: const Color(0xFF245DAF),
        );
    if (!enabled) return Text(text, style: style);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text(text, style: style),
        ),
      ),
    );
  }
}

IconData _iconForAction(String action) {
  switch (action) {
    case 'Note':
      return Icons.sticky_note_2_outlined;
    case 'Created':
      return Icons.add_circle_outline_rounded;
    case 'Status Change':
      return Icons.sync_alt_rounded;
    case 'Follow-up Scheduled':
      return Icons.event_repeat_rounded;
    case 'Follow-up Cancelled':
      return Icons.event_busy_outlined;
    case 'Quotation Created':
      return Icons.request_quote_outlined;
    case 'Smart Follow-up Scheduled':
      return Icons.schedule_send_outlined;
    default:
      return Icons.bolt_rounded;
  }
}

String _verbForAction(String action) {
  switch (action) {
    case 'Note':
      return 'added a note to';
    case 'Created':
      return 'created';
    case 'Status Change':
      return 'updated status for';
    case 'Follow-up Scheduled':
      return 'scheduled follow-up for';
    case 'Follow-up Cancelled':
      return 'cancelled follow-up for';
    case 'Quotation Created':
      return 'created quotation for';
    case 'Smart Follow-up Scheduled':
      return 'scheduled smart follow-up for';
    default:
      return 'updated';
  }
}

String _formatRelative(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 1) return 'moments ago';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m min${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  return DateFormat('dd MMM, HH:mm').format(t);
}

class _EmployeeDetailsDialog extends StatefulWidget {
  const _EmployeeDetailsDialog({
    required this.pulse,
    required this.leadService,
    required this.productService,
    required this.authService,
  });

  final EmployeePulse pulse;
  final LeadService leadService;
  final ProductService productService;
  final AuthService authService;

  @override
  State<_EmployeeDetailsDialog> createState() => _EmployeeDetailsDialogState();
}

class _EmployeeDetailsDialogState extends State<_EmployeeDetailsDialog> {
  late final Stream<List<Lead>> _leadsStream;
  late final Stream<List<QuotationModel>> _quotesStream;

  @override
  void initState() {
    super.initState();
    _leadsStream = FirebaseFirestore.instance
        .collection('leads')
        .where('assignedTo', isEqualTo: widget.pulse.uid)
        .snapshots()
        .map((snapshot) {
          final leads = leadsFromDocs(snapshot.docs);
          leads.sort((a, b) => b.leadDate.compareTo(a.leadDate));
          return leads;
        });

    _quotesStream = QuotationService(firestore: FirebaseFirestore.instance)
        .getQuotationsStream(employeeId: widget.pulse.uid);
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return format.format(amount);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isOverdue(DateTime date, String status) {
    if (status == 'Won' || status == 'Lost' || status == 'Loss' || status == 'Disqualified') return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    return compareDate.isBefore(todayDate);
  }

  bool _isUpcomingThisMonth(DateTime date, String status) {
    if (status == 'Won' || status == 'Lost' || status == 'Loss' || status == 'Disqualified') return false;
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    final isSameMonth = date.year == now.year && date.month == now.month;
    return isSameMonth && !compareDate.isBefore(todayDate);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'New':
        return const Color(0xFF12B886);
      case 'Contacted':
        return const Color(0xFF7950F2);
      case 'Proposal':
        return const Color(0xFFFF922B);
      case 'Follow-up':
        return const Color(0xFF228BE6);
      case 'Won':
        return const Color(0xFF2B8A3E);
      case 'Lost':
        return const Color(0xFFFA5252);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildFollowUpSection({
    required String title,
    required List<Lead> list,
    required Color color,
  }) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${list.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final lead = list[index];
            final fDate = lead.nextFollowUpDate;
            final dateStr = fDate != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(fDate)
                : 'N/A';
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                title: Text(
                  lead.company.isEmpty ? 'No Company' : lead.company,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.event, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (lead.remark.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lead.remark,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                onTap: () {
                  LeadDetailsModal.show(
                    context,
                    lead: lead,
                    leadService: widget.leadService,
                    authService: widget.authService,
                    productService: widget.productService,
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 850),
        child: DefaultTabController(
          length: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: widget.pulse.isOnline
                          ? const Color(0xFFDDFCE7)
                          : const Color(0xFFF1F3F5),
                      child: Text(
                        widget.pulse.displayName.isNotEmpty
                            ? widget.pulse.displayName[0].toUpperCase()
                            : 'E',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: widget.pulse.isOnline
                              ? const Color(0xFF2B8A3E)
                              : const Color(0xFF495057),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.pulse.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1D2638),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.pulse.isOnline
                                      ? const Color(0xFF40C057)
                                      : const Color(0xFFADB5BD),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.pulse.isOnline ? 'Online' : 'Offline',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6C757D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              // Tab bar
              Material(
                color: Colors.white,
                child: TabBar(
                  dividerColor: Colors.transparent,
                  labelColor: const Color(0xFF245DAF),
                  unselectedLabelColor: const Color(0xFF64748B),
                  indicatorColor: const Color(0xFF245DAF),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Summary'),
                    Tab(text: 'Leads by Status'),
                    Tab(text: 'Follow-ups'),
                    Tab(text: 'Quotations'),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              // Tab view content
              Expanded(
                child: StreamBuilder<List<Lead>>(
                  stream: _leadsStream,
                  builder: (context, leadsSnapshot) {
                    if (leadsSnapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading leads: ${leadsSnapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }
                    if (!leadsSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final leads = leadsSnapshot.data!;

                    return StreamBuilder<List<QuotationModel>>(
                      stream: _quotesStream,
                      builder: (context, quotesSnapshot) {
                        if (quotesSnapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading quotations: ${quotesSnapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        if (!quotesSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final quotes = quotesSnapshot.data!;

                        // 1. Summary calculations
                        double totalWonAmount = 0.0;
                        int wonCount = 0;
                        double wonThisMonthAmount = 0.0;
                        int wonThisMonthCount = 0;
                        double activePipelineAmount = 0.0;
                        int activeCount = 0;
                        int totalLeads = leads.length;

                        final now = DateTime.now();

                        final leadQuoteValues = <String, double>{};
                        for (final q in quotes) {
                          final amt = q.quoteRequest.totalAmount;
                          if (amt > (leadQuoteValues[q.leadId] ?? 0.0)) {
                            leadQuoteValues[q.leadId] = amt;
                          }
                        }

                        for (final lead in leads) {
                          final effectiveAmount = lead.totalAmount > 0 
                              ? lead.totalAmount 
                              : (leadQuoteValues[lead.id] ?? 0.0);

                          if (lead.status == 'Won') {
                            totalWonAmount += effectiveAmount;
                            wonCount++;

                            final wonDate = lead.installationDate ?? lead.leadDate;
                            if (wonDate.year == now.year && wonDate.month == now.month) {
                              wonThisMonthAmount += effectiveAmount;
                              wonThisMonthCount++;
                            }
                          } else if (lead.status != 'Lost' && lead.status != 'Loss' && lead.status != 'Disqualified') {
                            activePipelineAmount += effectiveAmount;
                            activeCount++;
                          }
                        }

                        double conversionRate = totalLeads == 0 ? 0.0 : wonCount / totalLeads;
                        int quotesCount = quotes.length;
                        double totalQuotesValue = leadQuoteValues.values.fold<double>(0.0, (acc, val) => acc + val);

                        // 2. Follow-ups grouping
                        final missed = <Lead>[];
                        final today = <Lead>[];
                        final upcoming = <Lead>[];

                        for (final lead in leads) {
                          final fDate = lead.nextFollowUpDate;
                          if (fDate == null) continue;

                          if (_isOverdue(fDate, lead.status)) {
                            missed.add(lead);
                          } else if (_isToday(fDate)) {
                            today.add(lead);
                          } else if (_isUpcomingThisMonth(fDate, lead.status)) {
                            upcoming.add(lead);
                          }
                        }

                        // 3. Leads grouping by status
                        final groupedLeads = <String, List<Lead>>{};
                        final uniqueStatuses = <String>{...Lead.statuses, ...Lead.tenderStatuses};
                        for (final status in uniqueStatuses) {
                          groupedLeads[status] = [];
                        }
                        for (final lead in leads) {
                          final status = lead.status;
                          if (groupedLeads.containsKey(status)) {
                            groupedLeads[status]!.add(lead);
                          } else {
                            groupedLeads[status] = [lead];
                          }
                        }

                        return TabBarView(
                          children: [
                            // 1. Summary Tab View
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final cols = constraints.maxWidth > 550 ? 2 : 1;
                                    return GridView.count(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      crossAxisCount: cols,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: cols == 2 ? 2.5 : 3.2,
                                      children: [
                                        _KpiCard(
                                          title: 'Total Won Business',
                                          value: _formatCurrency(totalWonAmount),
                                          subtitle: '$wonCount Won Deal${wonCount == 1 ? '' : 's'}',
                                          icon: Icons.emoji_events_outlined,
                                          color: const Color(0xFF2B8A3E),
                                        ),
                                        _KpiCard(
                                          title: 'Won This Month',
                                          value: _formatCurrency(wonThisMonthAmount),
                                          subtitle: '$wonThisMonthCount Deal${wonThisMonthCount == 1 ? '' : 's'}',
                                          icon: Icons.calendar_month_outlined,
                                          color: const Color(0xFF0CA678),
                                        ),
                                        _KpiCard(
                                          title: 'Active Pipeline',
                                          value: _formatCurrency(activePipelineAmount),
                                          subtitle: '$activeCount Active Deal${activeCount == 1 ? '' : 's'}',
                                          icon: Icons.bar_chart_rounded,
                                          color: const Color(0xFF228BE6),
                                        ),
                                        _KpiCard(
                                          title: 'Quotations Sent',
                                          value: '$quotesCount',
                                          subtitle: 'Value: ${_formatCurrency(totalQuotesValue)}',
                                          icon: Icons.request_quote_outlined,
                                          color: const Color(0xFF7950F2),
                                        ),
                                        _KpiCard(
                                          title: 'Conversion Rate',
                                          value: '${(conversionRate * 100).toStringAsFixed(1)}%',
                                          subtitle: 'Won of Total assigned',
                                          icon: Icons.percent_rounded,
                                          color: const Color(0xFFFF922B),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.info_outline, color: Color(0xFF245DAF), size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Manager Insights',
                                            style: theme.textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'This employee has a total of $totalLeads assigned lead(s) in their database. '
                                        'Currently, $activeCount lead(s) are active and in the pipeline. '
                                        'Their follow-up task health shows ${missed.length} overdue follow-up(s), '
                                        '${today.length} scheduled for today, and ${upcoming.length} upcoming for the rest of this calendar month.',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: const Color(0xFF475569),
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // 2. Leads by Status Tab View
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: Lead.statuses.map((status) {
                                final list = groupedLeads[status] ?? [];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  child: ExpansionTile(
                                    shape: const RoundedRectangleBorder(side: BorderSide.none),
                                    collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                                    title: Row(
                                      children: [
                                        Text(
                                          status,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '${list.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _statusColor(status),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    children: list.isEmpty
                                        ? [
                                            const Padding(
                                              padding: EdgeInsets.all(16.0),
                                              child: Text(
                                                'No leads under this status',
                                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                              ),
                                            )
                                          ]
                                        : list.map((lead) {
                                            return ListTile(
                                              title: Text(
                                                lead.company.isEmpty ? 'No Company' : lead.company,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                              subtitle: Text(
                                                'Contact: ${lead.name.isEmpty ? 'N/A' : lead.name}',
                                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _formatCurrency(lead.totalAmount),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                                                ],
                                              ),
                                              onTap: () {
                                                LeadDetailsModal.show(
                                                  context,
                                                  lead: lead,
                                                  leadService: widget.leadService,
                                                  authService: widget.authService,
                                                  productService: widget.productService,
                                                );
                                              },
                                            );
                                          }).toList(),
                                  ),
                                );
                              }).toList(),
                            ),
                            // 3. Follow-ups Tab View
                            SingleChildScrollView(
                              child: Column(
                                children: [
                                  if (missed.isEmpty && today.isEmpty && upcoming.isEmpty)
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(32.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.event_note, size: 48, color: Color(0xFF94A3B8)),
                                            SizedBox(height: 12),
                                            Text(
                                              'No follow-up activities found',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF475569),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'This employee has no active or missed follow-ups scheduled.',
                                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else ...[
                                    _buildFollowUpSection(
                                      title: 'Missed / Overdue Follow-ups',
                                      list: missed,
                                      color: const Color(0xFFFA5252),
                                    ),
                                    _buildFollowUpSection(
                                      title: "Today's Follow-ups",
                                      list: today,
                                      color: const Color(0xFF228BE6),
                                    ),
                                    _buildFollowUpSection(
                                      title: 'Upcoming (This Month)',
                                      list: upcoming,
                                      color: const Color(0xFF40C057),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 4. Quotations Tab View
                            quotes.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(32.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.request_quote_outlined, size: 48, color: Color(0xFF94A3B8)),
                                          SizedBox(height: 12),
                                          Text(
                                            'No quotations sent yet',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'This employee has not generated any quotations.',
                                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: quotes.length,
                                    itemBuilder: (context, index) {
                                      final quote = quotes[index];
                                      final dateStr =
                                          DateFormat('dd MMM yyyy, hh:mm a')
                                              .format(quote.createdAt);
                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                                        ),
                                        child: ListTile(
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  quote.currentRefNo,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1E293B),
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatCurrency(quote.quoteRequest.totalAmount),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF2B8A3E),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.business, size: 14, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      quote.quoteRequest.companyName,
                                                      style: const TextStyle(
                                                        color: Color(0xFF475569),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.person, size: 14, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    quote.quoteRequest.customerName,
                                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    'Created: $dateStr',
                                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
