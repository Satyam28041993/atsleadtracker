import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/daily_cockpit_model.dart';
import '../../models/quotation_model.dart';

const Color _kBorder = Color(0xFFE2E8F0);
const Color _kTextDark = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);

/// Shared lead card used by Daily Action Cockpit and CRM Report.
class LeadDayWorkCard extends StatelessWidget {
  const LeadDayWorkCard({
    super.key,
    required this.work,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onOpenLead,
    this.onCall,
    this.onViewQuote,
    this.updatesLabel = 'today',
  });

  final LeadDayWork work;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpenLead;
  final VoidCallback? onCall;
  final ValueChanged<QuotationModel>? onViewQuote;

  /// Shown after the update count, e.g. "today" or "in this period".
  final String updatesLabel;

  String? _followUpText() {
    final act = work.followUpActivity;
    if (act == null) return null;
    final detail = act.followUpDetail?.trim();
    if (detail != null && detail.isNotEmpty) return detail;
    final date = work.scheduledFollowUp;
    if (date == null) return null;
    return 'Follow-up set for ${DateFormat('dd MMM yyyy, h:mm a').format(date)}';
  }

  bool _isFollowUpCancelled() {
    final text = (work.followUpActivity?.followUpDetail ??
            work.followUpActivity?.title ??
            '')
        .toLowerCase();
    return text.contains('cancel');
  }

  @override
  Widget build(BuildContext context) {
    final followUpText = _followUpText();
    final followUpCancelled = _isFollowUpCancelled();
    final company = work.companyName.trim().isNotEmpty
        ? work.companyName.trim()
        : 'No Company';
    final client = work.clientName.trim();
    final hasPhone = work.phone.trim().isNotEmpty;
    final canCall = hasPhone && onCall != null;

    final Color leftBorderColor = followUpCancelled
        ? const Color(0xFFEF4444)
        : followUpText != null
            ? const Color(0xFF10B981)
            : const Color(0xFF94A3B8);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: leftBorderColor, width: 3),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      company,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (work.isNewLead || work.quotation != null) ...[
                    const SizedBox(width: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (work.isNewLead)
                          const LeadDayWorkBadge(
                            label: 'New Lead',
                            bgColor: Color(0xFFDBEAFE),
                            textColor: Color(0xFF1D4ED8),
                          ),
                        if (work.quotation != null)
                          const LeadDayWorkBadge(
                            label: 'Quote',
                            bgColor: Color(0xFFEDE9FE),
                            textColor: Color(0xFF6D28D9),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              if (client.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  client,
                  style: const TextStyle(fontSize: 12, color: _kTextMuted),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: followUpText == null
                      ? const Color(0xFFF1F5F9)
                      : followUpCancelled
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      followUpText == null
                          ? Icons.info_outline_rounded
                          : followUpCancelled
                              ? Icons.event_busy_rounded
                              : Icons.event_available_rounded,
                      size: 16,
                      color: followUpText == null
                          ? _kTextMuted
                          : followUpCancelled
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF047857),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        followUpText ??
                            '${work.activities.length} update${work.activities.length == 1 ? '' : 's'} logged, no follow-up set',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: followUpText == null
                              ? _kTextMuted
                              : followUpCancelled
                                  ? const Color(0xFF991B1B)
                                  : const Color(0xFF065F46),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onToggleExpand,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: _kTextMuted,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${work.activities.length} update${work.activities.length == 1 ? '' : 's'} $updatesLabel',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _kTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                for (final act in work.activities) _WorkActionRow(act: act),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _PrimaryActionButton(
                      icon: canCall
                          ? Icons.phone_in_talk_rounded
                          : Icons.open_in_new_rounded,
                      label: canCall ? 'Call' : 'Lead View',
                      onTap: canCall ? onCall! : onOpenLead,
                    ),
                  ),
                  if (canCall || work.quotation != null) ...[
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: _kTextMuted,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'lead':
                            onOpenLead();
                          case 'quote':
                            if (work.quotation != null && onViewQuote != null) {
                              onViewQuote!(work.quotation!);
                            }
                        }
                      },
                      itemBuilder: (context) => [
                        if (canCall)
                          const PopupMenuItem(
                            value: 'lead',
                            child: Text('Lead View'),
                          ),
                        if (work.quotation != null && onViewQuote != null)
                          const PopupMenuItem(
                            value: 'quote',
                            child: Text('Quote View'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LeadDayWorkBadge extends StatelessWidget {
  const LeadDayWorkBadge({
    super.key,
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _WorkActionRow extends StatelessWidget {
  const _WorkActionRow({required this.act});

  final DailyCompletedActivity act;

  @override
  Widget build(BuildContext context) {
    late IconData icon;
    late Color iconColor;
    late Color bg;

    switch (act.type) {
      case DailyActivityType.quotation:
        icon = Icons.picture_as_pdf_rounded;
        iconColor = const Color(0xFF6D28D9);
        bg = const Color(0xFFEDE9FE);
        break;
      case DailyActivityType.followUp:
        icon = Icons.calendar_today_rounded;
        iconColor = const Color(0xFF047857);
        bg = const Color(0xFFD1FAE5);
        break;
      case DailyActivityType.statusChange:
        icon = Icons.sync_alt_rounded;
        iconColor = const Color(0xFFB45309);
        bg = const Color(0xFFFEF3C7);
        break;
      case DailyActivityType.leadCreated:
        icon = Icons.add_circle_outline_rounded;
        iconColor = const Color(0xFF1D4ED8);
        bg = const Color(0xFFDBEAFE);
        break;
      case DailyActivityType.note:
        icon = Icons.notes_rounded;
        iconColor = const Color(0xFF475569);
        bg = const Color(0xFFF1F5F9);
        break;
    }

    final extra = act.type == DailyActivityType.quotation &&
            act.subtitle.trim().isNotEmpty
        ? ' · ${act.subtitle.trim()}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${act.title}$extra',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('d MMM, h:mm a').format(act.timestamp),
            style: const TextStyle(fontSize: 11, color: _kTextMuted),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D9488),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
