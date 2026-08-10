import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/analytics_service.dart';

class DailyWorkReportCard extends StatelessWidget {
  const DailyWorkReportCard({
    super.key,
    required this.report,
    required this.onOpenLeads,
    required this.onOpenQuotations,
  });

  final DailyWorkReport report;
  final void Function(String title, List<String> leadIds) onOpenLeads;
  final void Function(String title, List<String> quoteIds) onOpenQuotations;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.employeeName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1D2638),
            ),
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: 'Leads Added',
            value: report.leadsAdded,
            color: const Color(0xFF3B5BDB),
            onTap: () => onOpenLeads('Leads Added Today', report.addedLeadIds),
          ),
          _MetricRow(
            label: 'Follow-ups Done',
            value: report.followUpsDone,
            color: const Color(0xFF12B886),
            onTap: () => onOpenLeads('Follow-ups Done Today', report.followUpLeadIds),
          ),
          _MetricRow(
            label: 'Overdue Follow-ups',
            value: report.followUpsOverdue,
            color: const Color(0xFFE03131),
            onTap: () =>
                onOpenLeads('Overdue Follow-ups', report.overdueFollowUpLeadIds),
          ),
          _MetricRow(
            label: 'Due Today',
            value: report.followUpsPending,
            color: const Color(0xFFFA5252),
            onTap: () => onOpenLeads('Follow-ups Due Today', report.pendingFollowUpLeadIds),
          ),
          _MetricRow(
            label: 'Status Changed',
            value: report.statusChanges,
            color: const Color(0xFF7950F2),
            onTap: () => onOpenLeads('Status Changed Today', report.statusChangeLeadIds),
          ),
          _MetricRow(
            label: 'Quotations Made',
            value: report.quotesMade,
            color: const Color(0xFFFF922B),
            onTap: () => onOpenQuotations('Quotations Made Today', report.quotedLeadIds),
          ),
          _MetricRow(
            label: 'Deals Won',
            value: report.dealsWon,
            color: const Color(0xFF2B8A3E),
            onTap: () => onOpenLeads('Deals Won Today', report.wonLeadIds),
            subValue: report.dealsWonValue > 0 
                ? NumberFormat.compactCurrency(symbol: '₹').format(report.dealsWonValue) 
                : null,
          ),
        ],
      ),
    );
  }
}

class GlobalDailySummaryCard extends StatelessWidget {
  const GlobalDailySummaryCard({
    super.key,
    required this.summary,
  });

  final GlobalDailySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2638),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global Summary (Today)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _GlobalMetric(label: 'Leads Added', value: summary.totalLeadsAdded),
              _GlobalMetric(
                label: 'Follow-ups Done',
                value: summary.totalFollowUpsDone,
              ),
              _GlobalMetric(
                label: 'Overdue Follow-ups',
                value: summary.totalFollowUpsOverdue,
              ),
              _GlobalMetric(label: 'Quotations', value: summary.totalQuotesMade),
              _GlobalMetric(
                label: 'Deals Won',
                value: summary.totalDealsWon,
                subValue: summary.totalValueWon > 0 
                    ? NumberFormat.compactCurrency(symbol: '₹').format(summary.totalValueWon) 
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalMetric extends StatelessWidget {
  const _GlobalMetric({required this.label, required this.value, this.subValue});

  final String label;
  final int value;
  final String? subValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF8A99B5),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subValue != null) ...[
              const SizedBox(width: 8),
              Text(
                '($subValue)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF2B8A3E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.subValue,
  });

  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;
  final String? subValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: value > 0 ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (subValue != null) ...[
                Text(
                  subValue!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF2B8A3E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: value > 0 ? color.withValues(alpha: 0.1) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$value',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: value > 0 ? color : const Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
