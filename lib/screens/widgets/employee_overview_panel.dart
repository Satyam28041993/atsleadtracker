import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lead_model.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'analytics_lead_list_modal.dart';
import 'crm_report_section.dart';

/// Employee-only control center that summarizes the assignee's own leads.
class EmployeeOverviewPanel extends StatefulWidget {
  const EmployeeOverviewPanel({
    super.key,
    required this.leadService,
    required this.analyticsService,
    required this.authService,
    required this.employeeUid,
    this.productService,
  });

  final LeadService leadService;
  final AnalyticsService analyticsService;
  final AuthService authService;
  final ProductService? productService;
  final String employeeUid;

  @override
  State<EmployeeOverviewPanel> createState() => _EmployeeOverviewPanelState();
}

class _EmployeeOverviewPanelState extends State<EmployeeOverviewPanel> {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Lead>>(
      stream: widget.leadService.getLeadsStream(filterAssignedToUid: widget.employeeUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Could not load dashboard data.',
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

        var leads = snapshot.data ?? const <Lead>[];
        final startDate = _getStartDate(_dateFilter);
        final endDate = _getEndDate(_dateFilter);

        if (startDate != null || endDate != null) {
          leads = leads.where((l) {
            if (startDate != null && l.leadDate.isBefore(startDate)) return false;
            if (endDate != null && l.leadDate.isAfter(endDate)) return false;
            return true;
          }).toList();
        }

        final statusBreakdown = <String, int>{
          for (final s in Lead.statuses) s: 0,
        };
        for (final lead in leads) {
          statusBreakdown[lead.status] =
              (statusBreakdown[lead.status] ?? 0) + 1;
        }

        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final startOfTomorrow = startOfToday.add(const Duration(days: 1));

        var overdueFollowUps = 0;
        var todayFollowUps = 0;
        for (final lead in leads) {
          final followUp = lead.nextFollowUpDate;
          if (followUp == null) continue;
          if (followUp.isBefore(startOfToday)) {
            overdueFollowUps++;
          } else if (followUp.isBefore(startOfTomorrow)) {
            todayFollowUps++;
          }
        }

        final wonCount = statusBreakdown['Won'] ?? 0;
        final conversionRate = leads.isEmpty ? 0.0 : wonCount / leads.length;
        final recent = List<Lead>.from(leads)
          ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
        final recentLeads = recent.take(4).toList(growable: false);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CrmReportSection(
                analyticsService: widget.analyticsService,
                authService: widget.authService,
                leadService: widget.leadService,
                productService: widget.productService,
                forEmployeeUid: widget.employeeUid,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Control center',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D2638),
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _dateFilter,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    elevation: 16,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF1D2638),
                      fontWeight: FontWeight.w600,
                    ),
                    underline: Container(
                      height: 0,
                      color: Colors.transparent,
                    ),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _dateFilter) {
                        setState(() {
                          _dateFilter = newValue;
                        });
                      }
                    },
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
                ],
              ),
              const SizedBox(height: 12),
              _StatusSummaryGrid(
                statusBreakdown: statusBreakdown,
                totalLeads: leads.length,
                leads: leads,
                authService: widget.authService,
                leadService: widget.leadService,
                productService: widget.productService,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SmallKpiCard(
                      label: 'Today follow-ups',
                      value: '$todayFollowUps',
                      accent: const Color(0xFFE67700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SmallKpiCard(
                      label: 'Overdue follow-ups',
                      value: '$overdueFollowUps',
                      accent: const Color(0xFFD6336C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ConversionCard(
                wonCount: wonCount,
                totalLeads: leads.length,
                conversionRate: conversionRate,
              ),
              const SizedBox(height: 12),
              _RecentLeadsCard(leads: recentLeads),
            ],
          ),
        );
      },
    );
  }
}

class _StatusSummaryGrid extends StatelessWidget {
  const _StatusSummaryGrid({
    required this.statusBreakdown,
    required this.totalLeads,
    required this.leads,
    required this.authService,
    required this.leadService,
    this.productService,
  });

  final Map<String, int> statusBreakdown;
  final int totalLeads;
  final List<Lead> leads;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  void _open(BuildContext context, String status) {
    final ids = status.isEmpty
        ? leads.map((l) => l.id).toList()
        : leads.where((l) => l.status == status).map((l) => l.id).toList();
    final title = status.isEmpty ? 'Total leads' : 'Status: $status';
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
    final cards = <_StatusCardData>[
      const _StatusCardData(
        label: 'Total leads',
        status: '',
        color: Color(0xFF3B5BDB),
      ),
      for (final status in Lead.statuses)
        _StatusCardData(
          label: status,
          status: status,
          color: _statusColor(status),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _StatusCard(
                  data: card,
                  value: card.status.isEmpty
                      ? totalLeads
                      : (statusBreakdown[card.status] ?? 0),
                  onTap: () => _open(context, card.status),
                ),
              ),
          ],
        );
      },
    );
  }

  int _columnsFor(double maxWidth) {
    if (maxWidth >= 1200) return 4;
    if (maxWidth >= 760) return 3;
    if (maxWidth >= 520) return 2;
    return 1;
  }

  static Color _statusColor(String status) {
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
        return const Color(0xFF3B5BDB);
    }
  }
}

class _StatusCardData {
  const _StatusCardData({
    required this.label,
    required this.status,
    required this.color,
  });

  final String label;
  final String status;
  final Color color;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data, required this.value, this.onTap});

  final _StatusCardData data;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F3F5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
        children: [
          Expanded(
            child: Text(
              data.label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: const Color(0xFF6B778C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: data.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _SmallKpiCard extends StatelessWidget {
  const _SmallKpiCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F3F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFF6B778C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversionCard extends StatelessWidget {
  const _ConversionCard({
    required this.wonCount,
    required this.totalLeads,
    required this.conversionRate,
  });

  final int wonCount;
  final int totalLeads;
  final double conversionRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = conversionRate * 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F3F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'My conversion',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D2638),
                ),
              ),
              const Spacer(),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF2B8A3E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: conversionRate.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: const Color(0xFFE9ECEF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2B8A3E),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Won $wonCount of $totalLeads leads',
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF5B677C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLeadsCard extends StatelessWidget {
  const _RecentLeadsCard({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F3F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent lead updates',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF1D2638),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (leads.isEmpty)
            Text(
              'No leads assigned yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B778C),
              ),
            )
          else
            for (var i = 0; i < leads.length; i++) ...[
              _RecentLeadRow(lead: leads[i]),
              if (i < leads.length - 1) const Divider(height: 10),
            ],
        ],
      ),
    );
  }
}

class _RecentLeadRow extends StatelessWidget {
  const _RecentLeadRow({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = lead.company.trim().isEmpty
        ? 'Unknown company'
        : lead.company;
    final updatedAt = DateFormat('dd MMM, hh:mm a').format(lead.lastModified);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        lead.name.trim().isEmpty ? 'Unnamed lead' : lead.name,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '$company · $updatedAt',
        style: theme.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B778C),
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          lead.status,
          style: theme.textTheme.labelSmall?.copyWith(
            color: const Color(0xFF495057),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
