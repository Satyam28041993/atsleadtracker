import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/lead_model.dart';
import '../services/auth_service.dart';
import '../services/lead_service.dart';
import '../services/product_service.dart';
import 'widgets/cancel_follow_up_dialog.dart';
import 'widgets/lead_details_modal.dart';

/// Buckets follow-ups by due date relative to "now" for KPI filtering.
enum _FollowUpBucket { overdue, today, upcoming }

/// Tabbed follow-up lists (no [Scaffold]); use inside a parent [Scaffold] or wrap
/// with [FollowUpsScreen] for a full-screen route.
class FollowUpsTabbedView extends StatefulWidget {
  const FollowUpsTabbedView({
    super.key,
    required this.leadService,
    required this.authService,
    required this.productService,
    this.filterAssignedToUid,
  });

  final LeadService leadService;
  final AuthService authService;
  final ProductService productService;
  final String? filterAssignedToUid;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static _FollowUpBucket _bucketFor(Lead lead, DateTime now) {
    final t = lead.nextFollowUpDate!;
    final start = _startOfDay(now);
    final end = _endOfDay(now);
    if (t.isBefore(start)) return _FollowUpBucket.overdue;
    if (t.isAfter(end)) return _FollowUpBucket.upcoming;
    return _FollowUpBucket.today;
  }

  static (Color bg, Color fg, String label) _badgeStyle(_FollowUpBucket b) {
    switch (b) {
      case _FollowUpBucket.overdue:
        return (const Color(0xFFFFEBEE), const Color(0xFFC62828), 'Overdue');
      case _FollowUpBucket.today:
        return (const Color(0xFFFFF3E0), const Color(0xFFE65100), 'Today');
      case _FollowUpBucket.upcoming:
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0), 'Upcoming');
    }
  }

  /// Leads with a follow-up scheduled on the same calendar day as [day].
  static List<Lead> _getEventsForDay(DateTime day, List<Lead> allLeads) {
    return allLeads.where((lead) {
      final d = lead.nextFollowUpDate;
      if (d == null) return false;
      return isSameDay(d, day);
    }).toList();
  }

  @override
  State<FollowUpsTabbedView> createState() => _FollowUpsTabbedViewState();
}

class _FollowUpsTabbedViewState extends State<FollowUpsTabbedView> {
  String _searchQuery = '';
  String? _selectedStatusFilter;
  bool _isCalendarView = false;
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  /// When non-null, list view shows only this bucket; when null, all buckets.
  _FollowUpBucket? _kpiBucketFilter;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _focusedDay = n;
    _selectedDay = n;
  }

  void _openLeadDetails(BuildContext context, Lead lead) {
    LeadDetailsModal.show(
      context,
      lead: lead,
      leadService: widget.leadService,
      authService: widget.authService,
      productService: widget.productService,
    );
  }

  Future<void> _cancelFollowUp(BuildContext context, Lead lead) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showCancelFollowUpDialog(
      context,
      leadName: lead.name.isNotEmpty ? lead.name : lead.company,
    );
    if (reason == null) return;
    try {
      await widget.leadService.cancelFollowUp(lead.id, reason: reason);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Follow-up cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not cancel the follow-up: $e')),
      );
    }
  }

  bool _matchesSearch(Lead lead) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return lead.name.toLowerCase().contains(q) ||
        lead.company.toLowerCase().contains(q);
  }

  bool _matchesStatus(Lead lead) {
    if (_selectedStatusFilter == null) return true;
    return lead.status == _selectedStatusFilter;
  }

  List<Lead> _baseFiltered(List<Lead> all, DateTime now) {
    return all
        .where((lead) {
          if (lead.nextFollowUpDate == null) return false;
          if (!_matchesSearch(lead) || !_matchesStatus(lead)) return false;
          return true;
        })
        .where((lead) {
          if (_kpiBucketFilter == null) return true;
          return FollowUpsTabbedView._bucketFor(lead, now) == _kpiBucketFilter;
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF0F2F5),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name or company',
                    prefixIcon: const Icon(Icons.search, size: 22),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedStatusFilter,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Status',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF69758D),
                      ),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...Lead.statuses.map(
                      (s) =>
                          DropdownMenuItem<String?>(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedStatusFilter = v),
                ),
              ),
              IconButton(
                tooltip: _isCalendarView ? 'List view' : 'Calendar view',
                onPressed: () =>
                    setState(() => _isCalendarView = !_isCalendarView),
                icon: Icon(
                  _isCalendarView
                      ? Icons.view_list_rounded
                      : Icons.calendar_month,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Lead>>(
            stream: widget.leadService.getFollowUpsStream(
              filterAssignedToUid: widget.filterAssignedToUid,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load follow-ups.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final all = snapshot.data ?? const <Lead>[];
              final now = DateTime.now();

              final withFollowUp = all
                  .where((l) => l.nextFollowUpDate != null)
                  .toList();

              var overdueCount = 0;
              var todayCount = 0;
              var upcomingCount = 0;
              for (final lead in withFollowUp) {
                switch (FollowUpsTabbedView._bucketFor(lead, now)) {
                  case _FollowUpBucket.overdue:
                    overdueCount++;
                  case _FollowUpBucket.today:
                    todayCount++;
                  case _FollowUpBucket.upcoming:
                    upcomingCount++;
                }
              }

              final timeFmt = DateFormat('hh:mm a');

              if (_isCalendarView) {
                final calendarLeads = withFollowUp
                    .where(_matchesSearch)
                    .where(_matchesStatus)
                    .toList();

                final dayLeads = FollowUpsTabbedView._getEventsForDay(
                  _selectedDay,
                  calendarLeads,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TableCalendar<Lead>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2035, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: CalendarFormat.month,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      eventLoader: (day) =>
                          FollowUpsTabbedView._getEventsForDay(
                            day,
                            calendarLeads,
                          ),
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        markerDecoration: const BoxDecoration(
                          color: Color(0xFF1565C0),
                          shape: BoxShape.circle,
                        ),
                        markersMaxCount: 3,
                      ),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: theme.textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onPageChanged: (focusedDay) {
                        setState(() => _focusedDay = focusedDay);
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _FollowUpListView(
                        leads: dayLeads,
                        now: now,
                        timeFmt: timeFmt,
                        onOpen: (l) => _openLeadDetails(context, l),
                        onCancel: (l) => _cancelFollowUp(context, l),
                        emptyMessage:
                            'No follow-ups on ${DateFormat.yMMMd().format(_selectedDay)}.',
                      ),
                    ),
                  ],
                );
              }

              final listLeads = _baseFiltered(withFollowUp, now);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _KpiCard(
                            label: 'Overdue',
                            count: overdueCount,
                            textColor: const Color(0xFFC62828),
                            selected:
                                _kpiBucketFilter == _FollowUpBucket.overdue,
                            onTap: () => setState(() {
                              _kpiBucketFilter =
                                  _kpiBucketFilter == _FollowUpBucket.overdue
                                  ? null
                                  : _FollowUpBucket.overdue;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _KpiCard(
                            label: 'Today',
                            count: todayCount,
                            textColor: const Color(0xFFE65100),
                            selected: _kpiBucketFilter == _FollowUpBucket.today,
                            onTap: () => setState(() {
                              _kpiBucketFilter =
                                  _kpiBucketFilter == _FollowUpBucket.today
                                  ? null
                                  : _FollowUpBucket.today;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _KpiCard(
                            label: 'Upcoming',
                            count: upcomingCount,
                            textColor: const Color(0xFF1565C0),
                            selected:
                                _kpiBucketFilter == _FollowUpBucket.upcoming,
                            onTap: () => setState(() {
                              _kpiBucketFilter =
                                  _kpiBucketFilter == _FollowUpBucket.upcoming
                                  ? null
                                  : _FollowUpBucket.upcoming;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _FollowUpListView(
                      leads: listLeads,
                      now: now,
                      timeFmt: timeFmt,
                      onOpen: (l) => _openLeadDetails(context, l),
                      onCancel: (l) => _cancelFollowUp(context, l),
                      emptyMessage: 'No follow-ups match your filters.',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.count,
    required this.textColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE8EEF5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? textColor.withValues(alpha: 0.45)
                  : const Color(0xFFE6EAF2),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: textColor,
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

/// Full-screen route with [Scaffold] and back navigation (e.g. employee app bar).
class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({
    super.key,
    required this.leadService,
    required this.authService,
    required this.productService,
    this.filterAssignedToUid,
  });

  final LeadService leadService;
  final AuthService authService;
  final ProductService productService;
  final String? filterAssignedToUid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: FollowUpsTabbedView(
        leadService: leadService,
        authService: authService,
        productService: productService,
        filterAssignedToUid: filterAssignedToUid,
      ),
    );
  }
}

String _initialsFor(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  final parts = t.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final a = parts.first.isNotEmpty ? parts.first[0] : '';
    final b = parts.last.isNotEmpty ? parts.last[0] : '';
    return ('$a$b').toUpperCase();
  }
  return t.length >= 2 ? t.substring(0, 2).toUpperCase() : t.toUpperCase();
}

class _FollowUpListView extends StatelessWidget {
  const _FollowUpListView({
    required this.leads,
    required this.now,
    required this.timeFmt,
    required this.onOpen,
    required this.onCancel,
    required this.emptyMessage,
  });

  final List<Lead> leads;
  final DateTime now;
  final DateFormat timeFmt;
  final void Function(Lead lead) onOpen;
  final void Function(Lead lead) onCancel;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (leads.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF69758D),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: leads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final lead = leads[index];
        final bucket = FollowUpsTabbedView._bucketFor(lead, now);
        final badge = FollowUpsTabbedView._badgeStyle(bucket);
        final date = lead.nextFollowUpDate!;
        final timeStr = timeFmt.format(date);
        final company = lead.company.trim().isEmpty ? '—' : lead.company;
        final name = lead.name.trim().isEmpty
            ? 'Unnamed lead'
            : lead.name.trim();

        return Material(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE6EAF2)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE8EEF5),
              foregroundColor: const Color(0xFF1D2638),
              child: Text(
                _initialsFor(lead.name),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1D2638),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$company · $timeStr',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF69758D),
                ),
              ),
            ),
            isThreeLine: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badge.$1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge.$3,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: badge.$2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'View',
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () => onOpen(lead),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'cancel') onCancel(lead);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          const Text('Cancel follow-up'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
