import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/daily_cockpit_model.dart';
import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/pdf_service.dart';
import '../../services/product_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/quote_pdf_view.dart';
import 'cancel_follow_up_dialog.dart';
import 'lead_day_work_card.dart';
import 'lead_details_modal.dart';

/// Minimum width a cockpit card is given before another column is added.
const double kCockpitMinCardWidth = 300.0;

/// Gap between cockpit cards, both directions.
const double kCockpitCardGap = 10.0;

/// How many card columns fit [availableWidth] — 1 on a phone, more as the
/// dashboard widens, capped so cards never get absurdly narrow on an
/// ultra-wide monitor.
int cockpitColumnsFor(double availableWidth) {
  return ((availableWidth + kCockpitCardGap) /
          (kCockpitMinCardWidth + kCockpitCardGap))
      .floor()
      .clamp(1, 4);
}

/// The width one card gets once split into [columns] evenly-spaced columns
/// across [availableWidth].
double cockpitCardWidthFor(double availableWidth, int columns) {
  return columns <= 1
      ? availableWidth
      : (availableWidth - kCockpitCardGap * (columns - 1)) / columns;
}

const Color _kBrandNavy = Color(0xFF1D2638);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kTextDark = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);

class DailyActionCockpit extends StatefulWidget {
  const DailyActionCockpit({
    super.key,
    required this.analyticsService,
    required this.leadService,
    required this.authService,
    this.productService,
    this.forEmployeeUid,
    this.isAdmin = false,
    this.onActionTaken,
  });

  final AnalyticsService analyticsService;
  final LeadService leadService;
  final AuthService authService;
  final ProductService? productService;
  final String? forEmployeeUid;
  final bool isAdmin;
  final VoidCallback? onActionTaken;

  @override
  State<DailyActionCockpit> createState() => _DailyActionCockpitState();
}

class _DailyActionCockpitState extends State<DailyActionCockpit> {
  Future<DailyCockpitPayload>? _future;
  bool _isCollapsed = false;
  int _selectedTab = 0; // 0: Today's Work, 1: Yesterday Review, 2: Action Queue
  DailyPendingType? _pendingFilter;
  String _searchQuery = '';
  String _sortBy = 'dueSoonest'; // dueSoonest, mostOverdue, companyAz
  String? _selectedEmployeeUid; // For Admin filter
  final Set<String> _expandedEmployeeCards = <String>{};
  final Set<String> _expandedWorkEmployees = <String>{};

  /// Per-lead activity history is collapsed by default on the Today's Work /
  /// Yesterday's Review cards — this tracks which leads' histories are open.
  final Set<String> _expandedWorkCards = <String>{};

  // Pagination state — per tab
  static const int _pageSize = 30;
  int _pendingPage = 0; // Tab 2: Action Queue
  int _todayPage = 0; // Tab 0: Today's Work — the "done today" half
  int _todayDuePage = 0; // Tab 0: Today's Work — the "due today" half
  int _yesterdayPage = 0; // Tab 1: Yesterday Review

  /// Search rebuilds the whole filtered tree, so wait for a pause in typing
  /// rather than doing it on every keystroke.
  Timer? _searchDebounce;


  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DailyActionCockpit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forEmployeeUid != widget.forEmployeeUid) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = widget.analyticsService.getDailyCockpitData(
        forEmployeeUid: widget.forEmployeeUid,
      );
    });
  }

  void _notifyAction() {
    _reload();
    widget.onActionTaken?.call();
  }

  // --- Actions on leads ---

  Future<void> _makeCall(String phone) async {
    final raw = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid phone number for calling.')),
      );
      return;
    }
    final uri = Uri.parse('tel:$raw');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _sendWhatsApp(Lead lead) async {
    final service = WhatsAppService();
    final template = await service.getTemplate();
    final uri = service.parseTemplate(template, lead);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _rescheduleFollowUp(Lead lead) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: lead.nextFollowUpDate != null &&
              lead.nextFollowUpDate!.isAfter(now)
          ? lead.nextFollowUpDate!
          : now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 11, minute: 0),
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.leadService.scheduleFollowUp(lead.id, combined);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Follow-up rescheduled to ${DateFormat('d MMM, h:mm a').format(combined)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _notifyAction();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not reschedule: $e')),
      );
    }
  }

  Future<void> _addQuickNote(Lead lead) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Note for ${lead.company}'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Called client, requested quotation revision...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save Note'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final updatedRemark = lead.remark.trim().isEmpty
          ? result
          : '${lead.remark.trim()}\n\n---\n$result';
      await widget.leadService.updateLead(lead.copyWith(remark: updatedRemark));
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Note added to timeline.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _notifyAction();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save note: $e')),
      );
    }
  }

  Future<void> _quickChangeStatus(Lead lead) async {
    final statuses = lead.isTender ? Lead.tenderStatuses : Lead.statuses;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Change Status: ${lead.company}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: statuses.map((st) {
                  final isCurrent = lead.status == st;
                  return ListTile(
                    leading: Icon(
                      isCurrent
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isCurrent ? const Color(0xFF0D9488) : _kTextMuted,
                    ),
                    title: Text(
                      st,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    onTap: () => Navigator.of(ctx).pop(st),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || selected == lead.status || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.leadService.updateLeadStatus(lead.id, selected, sourceLead: lead);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Status updated to $selected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _notifyAction();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update status: $e')),
      );
    }
  }

  Future<void> _dropLead(Lead lead) async {
    final reason = await showCancelFollowUpDialog(
      context,
      leadName: lead.company.isNotEmpty ? lead.company : lead.name,
    );
    if (reason == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.leadService.cancelFollowUp(lead.id, reason: reason);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Follow-up cleared and removed from pending queue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _notifyAction();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not drop follow-up: $e')),
      );
    }
  }

  void _openLeadDetails(Lead lead) {
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

  // --- Filtering & Sorting Helpers ---

  List<DailyPendingItem> _filterPendingItems(List<DailyPendingItem> items) {
    var list = items;
    if (_pendingFilter != null) {
      list = list.where((p) => p.type == _pendingFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        return p.lead.company.toLowerCase().contains(q) ||
            p.lead.name.toLowerCase().contains(q) ||
            p.lead.phone.contains(q);
      }).toList();
    }
    switch (_sortBy) {
      case 'mostOverdue':
        list.sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));
      case 'companyAz':
        list.sort((a, b) =>
            a.lead.company.toLowerCase().compareTo(b.lead.company.toLowerCase()));
      case 'dueSoonest':
      default:
        // already sorted in service
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<DailyCockpitPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    // Say what actually happened. Calling a failure
                    // "synchronizing" leaves the user waiting for something
                    // that is never going to arrive.
                    child: Text(
                      "Could not load today's work. ${snapshot.error}",
                    ),
                  ),
                  IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            );
          }

          final payload = snapshot.data;
          if (payload == null) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(payload),
              if (!_isCollapsed) ...[
                if (payload.isDegraded) _buildWarningBanner(payload),
                const Divider(height: 1, color: _kBorder),
                _buildTabNavigation(payload),
                const Divider(height: 1, color: _kBorder),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _buildTabBody(payload, isMobile),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Tells the user the day is incomplete rather than letting an empty tab
  /// read as "you did nothing".
  Widget _buildWarningBanner(DailyCockpitPayload payload) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This view is incomplete',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFF92400E),
                  ),
                ),
                for (final w in payload.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Header ---

  Widget _buildHeader(DailyCockpitPayload payload) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Color(0xFF0D9488),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Daily Action Cockpit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kBrandNavy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        DateFormat('d MMM').format(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.isAdmin
                      ? '${payload.globalDueToday} due today · ${payload.globalOverdue} overdue across team'
                      : '${payload.globalDueToday} calls due today · ${payload.globalDoneToday} tasks completed',
                  style: const TextStyle(fontSize: 12, color: _kTextMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          IconButton(
            tooltip: _isCollapsed ? 'Expand cockpit' : 'Minimize cockpit',
            onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
            icon: Icon(
              _isCollapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab Navigation ---

  Widget _buildTabNavigation(DailyCockpitPayload payload) {
    final totalPending = payload.globalDueToday + payload.globalOverdue;
    // The tab now holds today's plan as well as what is finished, so the pill
    // counts both — showing a bare 0 every morning made the tab look broken.
    final totalDone = widget.isAdmin
        ? payload.globalDoneToday
        : payload.globalDoneToday + payload.globalDueToday;
    final yesterdayCount = payload.employeeSummaries.fold<int>(
      0,
      (sum, e) => sum + e.yesterdayActivities.length,
    );

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _TabPill(
            label: "Today's Work",
            count: totalDone,
            icon: Icons.check_circle_outline_rounded,
            isSelected: _selectedTab == 0,
            activeColor: const Color(0xFF10B981),
            onTap: () => setState(() => _selectedTab = 0),
          ),
          _TabPill(
            label: "Yesterday's Review",
            count: yesterdayCount,
            icon: Icons.history_rounded,
            isSelected: _selectedTab == 1,
            activeColor: const Color(0xFF6366F1),
            onTap: () => setState(() => _selectedTab = 1),
          ),
          _TabPill(
            label: 'Action Queue',
            count: totalPending,
            icon: Icons.phone_callback_rounded,
            isSelected: _selectedTab == 2,
            activeColor: const Color(0xFF0D9488),
            onTap: () => setState(() => _selectedTab = 2),
          ),
        ],
      ),
    );
  }

  // --- Tab Body ---

  Widget _buildTabBody(DailyCockpitPayload payload, bool isMobile) {
    switch (_selectedTab) {
      case 0:
        return _buildTodayWorkTab(payload);
      case 1:
        return _buildYesterdayReviewTab(payload);
      case 2:
        return _buildPendingQueueTab(payload, isMobile);
      default:
        return const SizedBox.shrink();
    }
  }

  // --- TAB 1: PENDING QUEUE ---

  Widget _buildPendingQueueTab(DailyCockpitPayload payload, bool isMobile) {
    // Collect summaries
    final summaries = widget.isAdmin
        ? payload.employeeSummaries
        : payload.employeeSummaries.take(1).toList();

    if (summaries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No employees found.', style: TextStyle(color: _kTextMuted)),
        ),
      );
    }

    // Admin employee filter bar
    Widget? employeeFilterWidget;
    if (widget.isAdmin && payload.employeeSummaries.length > 1) {
      employeeFilterWidget = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Employees'),
                selected: _selectedEmployeeUid == null,
                onSelected: (_) => setState(() => _selectedEmployeeUid = null),
              ),
              const SizedBox(width: 8),
              for (final emp in payload.employeeSummaries) ...[
                FilterChip(
                  label: Text('${emp.employeeName} (${emp.totalPendingCount})'),
                  selected: _selectedEmployeeUid == emp.employeeUid,
                  onSelected: (_) => setState(
                    () => _selectedEmployeeUid = emp.employeeUid,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      );
    }

    // Bucket filters (Due Today, Overdue, etc.)
    final bucketFiltersWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipItem(
            label: 'All',
            isSelected: _pendingFilter == null,
            onTap: () => setState(() {
              _pendingFilter = null;
              _pendingPage = 0;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'Due Today',
            count: payload.globalDueToday,
            color: const Color(0xFFF59E0B),
            isSelected: _pendingFilter == DailyPendingType.dueToday,
            onTap: () => setState(() {
              _pendingFilter = DailyPendingType.dueToday;
              _pendingPage = 0;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'Overdue',
            count: payload.globalOverdue,
            color: const Color(0xFFEF4444),
            isSelected: _pendingFilter == DailyPendingType.overdue,
            onTap: () => setState(() {
              _pendingFilter = DailyPendingType.overdue;
              _pendingPage = 0;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'Needs Date',
            isSelected: _pendingFilter == DailyPendingType.missingDate,
            onTap: () => setState(() {
              _pendingFilter = DailyPendingType.missingDate;
              _pendingPage = 0;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'Quote, no reply',
            color: const Color(0xFF0E7490),
            isSelected: _pendingFilter == DailyPendingType.awaitingQuoteReply,
            onTap: () => setState(() {
              _pendingFilter = DailyPendingType.awaitingQuoteReply;
              _pendingPage = 0;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'Stale (>7d)',
            isSelected: _pendingFilter == DailyPendingType.stale,
            onTap: () => setState(() {
              _pendingFilter = DailyPendingType.stale;
              _pendingPage = 0;
            }),
          ),
        ],
      ),
    );

    // Search and sort bar
    final searchSortBar = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 250),
                    () {
                      if (!mounted) return;
                      setState(() {
                        _searchQuery = v.trim();
                        _pendingPage = 0;
                        _todayPage = 0;
                        _yesterdayPage = 0;
                      });
                    },
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Search by client, company, phone…',
                  hintStyle: const TextStyle(fontSize: 12, color: _kTextMuted),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sortBy,
              icon: const Icon(Icons.sort, size: 18),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
              items: const [
                DropdownMenuItem(value: 'dueSoonest', child: Text('Due soonest')),
                DropdownMenuItem(value: 'mostOverdue', child: Text('Most overdue')),
                DropdownMenuItem(value: 'companyAz', child: Text('Company A-Z')),
              ],
              onChanged: (v) => setState(() => _sortBy = v ?? 'dueSoonest'),
            ),
          ),
        ],
      ),
    );

    // Filter summaries if employee selected
    final filteredSummaries = _selectedEmployeeUid == null
        ? summaries
        : summaries.where((s) => s.employeeUid == _selectedEmployeeUid).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (employeeFilterWidget != null) employeeFilterWidget,
        bucketFiltersWidget,
        searchSortBar,
        if (widget.isAdmin)
          ...filteredSummaries.map((summary) => _buildEmployeePendingAccordion(summary))
        else ...[
          // For Employee view: render items directly
          _cardShelf(
            _buildPendingItemList(
              _filterPendingItems(summaries.first.pendingItems),
              showAssignee: false,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmployeePendingAccordion(EmployeeDailySummary summary) {
    final filteredItems = _filterPendingItems(summary.pendingItems);
    final isExpanded = _expandedEmployeeCards.contains(summary.employeeUid) ||
        _selectedEmployeeUid != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                if (_expandedEmployeeCards.contains(summary.employeeUid)) {
                  _expandedEmployeeCards.remove(summary.employeeUid);
                } else {
                  _expandedEmployeeCards.add(summary.employeeUid);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _kBrandNavy,
                    child: Text(
                      summary.employeeName.isNotEmpty
                          ? summary.employeeName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary.employeeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (summary.overdueCount > 0) ...[
                    _Badge(
                      label: '${summary.overdueCount} overdue',
                      bgColor: const Color(0xFFFEE2E2),
                      textColor: const Color(0xFFB91C1C),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (summary.dueTodayCount > 0) ...[
                    _Badge(
                      label: '${summary.dueTodayCount} due today',
                      bgColor: const Color(0xFFFEF3C7),
                      textColor: const Color(0xFFB45309),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _Badge(
                    label: '${summary.todayDoneCount} done',
                    bgColor: const Color(0xFFD1FAE5),
                    textColor: const Color(0xFF047857),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _kTextMuted,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _buildPendingItemList(filteredItems, showAssignee: false),
            ),
          ],
        ],
      ),
    );
  }

  /// Light surface every card list sits inside — the "shelf" the cards sit
  /// on, so a row of them reads as one grouped panel rather than floating
  /// loose against the white cockpit background.
  Widget _cardShelf(Widget child) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }

  /// Renders at most [page + 1] pages of [items] with a "show more" footer,
  /// flowing cards into as many columns as the available width allows —
  /// e.g. a desktop dashboard shows 3, a phone shows 1 — so the same card
  /// design scales from mobile to a wide admin screen without a separate
  /// layout for each.
  ///
  /// Pagination is not cosmetic here. These lists sit inside the dashboard's
  /// scroll view, so they use shrinkWrap, which defeats lazy building: without
  /// a cap every row is constructed to measure its height, and the whole tree
  /// rebuilds on each setState — including every keystroke in the search box.
  Widget _paginatedList<T>({
    required List<T> items,
    required int page,
    required ValueChanged<int> onPageChanged,
    required Widget Function(T item) itemBuilder,
  }) {
    final shown = ((page + 1) * _pageSize).clamp(0, items.length);
    final remaining = items.length - shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _wrapCards([
          for (var i = 0; i < shown; i++) itemBuilder(items[i]),
        ]),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: () => onPageChanged(page + 1),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(
                remaining > _pageSize
                    ? "Show $_pageSize more ($remaining left)"
                    : "Show last $remaining",
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPendingItemList(
    List<DailyPendingItem> items, {
    required bool showAssignee,
  }) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: const Text(
          'No pending follow-ups or calls matching filter.',
          style: TextStyle(color: _kTextMuted, fontSize: 13),
        ),
      );
    }

    return _paginatedList<DailyPendingItem>(
      items: items,
      page: _pendingPage,
      onPageChanged: (p) => setState(() => _pendingPage = p),
      itemBuilder: _buildPendingCard,
    );
  }

  Widget _buildPendingCard(DailyPendingItem item) {
    final lead = item.lead;

    Color leftBorderColor;
    String statusBadgeText;
    Color statusBadgeBg;
    Color statusBadgeFg;

    switch (item.type) {
      case DailyPendingType.overdue:
        leftBorderColor = const Color(0xFFEF4444);
        statusBadgeText = '${item.daysOverdue}d overdue';
        statusBadgeBg = const Color(0xFFFEE2E2);
        statusBadgeFg = const Color(0xFFB91C1C);
        break;
      case DailyPendingType.dueToday:
        leftBorderColor = const Color(0xFFF59E0B);
        statusBadgeText = 'Due Today';
        statusBadgeBg = const Color(0xFFFEF3C7);
        statusBadgeFg = const Color(0xFFB45309);
        break;
      case DailyPendingType.missingDate:
        leftBorderColor = const Color(0xFF8B5CF6);
        statusBadgeText = 'Needs Follow-up Date';
        statusBadgeBg = const Color(0xFFEDE9FE);
        statusBadgeFg = const Color(0xFF6D28D9);
        break;
      case DailyPendingType.awaitingQuoteReply:
        // Teal, not another shade of alarm: this is a warm deal waiting on a
        // reply, not a mistake.
        leftBorderColor = const Color(0xFF0E7490);
        statusBadgeText = 'Quote sent ${item.daysInactive}d ago';
        statusBadgeBg = const Color(0xFFCFFAFE);
        statusBadgeFg = const Color(0xFF155E75);
        break;
      case DailyPendingType.stale:
        leftBorderColor = const Color(0xFF94A3B8);
        statusBadgeText = 'Inactive ${item.daysInactive}d';
        statusBadgeBg = const Color(0xFFF1F5F9);
        statusBadgeFg = const Color(0xFF475569);
        break;
    }

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
              left: BorderSide(color: leftBorderColor, width: 4),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                lead.company.isNotEmpty
                                    ? lead.company
                                    : 'No Company',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _kTextDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _Badge(
                              label: statusBadgeText,
                              bgColor: statusBadgeBg,
                              textColor: statusBadgeFg,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${lead.name} · ${lead.phone} ${lead.location.isNotEmpty ? "· ${lead.location}" : ""}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextMuted,
                          ),
                        ),
                        if (lead.productsSummary.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            lead.productsSummary,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (lead.totalAmount > 0)
                    Text(
                      NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
                          .format(lead.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _kBrandNavy,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // One clear thing to do (Call) plus everything else tucked
              // behind a menu — six equal-weight buttons made every card a
              // wall of chips with no obvious first move.
              Row(
                children: [
                  Expanded(
                    child: _PrimaryActionButton(
                      icon: Icons.phone_in_talk_rounded,
                      label: 'Call',
                      onTap: () => _makeCall(lead.phone),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildLeadActionsMenu(lead),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The rest of [_buildPendingCard]'s actions, one tap away instead of six
  /// buttons wide.
  Widget _buildLeadActionsMenu(Lead lead) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_horiz_rounded, color: _kTextMuted),
      onSelected: (value) {
        switch (value) {
          case 'whatsapp':
            _sendWhatsApp(lead);
          case 'reschedule':
            _rescheduleFollowUp(lead);
          case 'note':
            _addQuickNote(lead);
          case 'status':
            _quickChangeStatus(lead);
          case 'drop':
            _dropLead(lead);
          case 'open':
            _openLeadDetails(lead);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'whatsapp',
          child: Text('WhatsApp'),
        ),
        const PopupMenuItem(
          value: 'reschedule',
          child: Text('Reschedule follow-up'),
        ),
        const PopupMenuItem(value: 'note', child: Text('Add note')),
        PopupMenuItem(
          value: 'status',
          child: Text('Change status (${lead.status})'),
        ),
        const PopupMenuItem(
          value: 'drop',
          child: Text('Drop follow-up'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'open',
          child: Text('Open lead details'),
        ),
      ],
    );
  }

  // --- TAB 2 / 3: TODAY'S WORK & YESTERDAY'S REVIEW ---

  List<EmployeeDailySummary> _visibleWorkSummaries(DailyCockpitPayload payload) {
    return payload.employeeSummaries
        .where((s) =>
            _selectedEmployeeUid == null || s.employeeUid == _selectedEmployeeUid)
        .toList();
  }

  Widget _buildTodayWorkTab(DailyCockpitPayload payload) {
    final done = _buildWorkReviewTab(
      summaries: _visibleWorkSummaries(payload),
      activitiesOf: (s) => s.todayActivities,
      emptyIcon: Icons.assignment_turned_in_outlined,
      emptyText: 'Nothing logged today yet — finish a call to see it here.',
      headerForAdmin:
          'Open an employee to see their leads and actions today.',
      headerForSelf: (leads, actions) => '$leads leads · $actions actions today',
      page: _todayPage,
      onPageChanged: (p) => setState(() => _todayPage = p),
      expandKeyPrefix: 'today',
    );

    if (widget.isAdmin) return done;

    // A day starts with nothing done, so a tab that only listed completed
    // work was empty every morning — the exact hours it is most needed.
    // Today's plan comes first, what is already finished sits under it.
    final summaries = _visibleWorkSummaries(payload);
    final dueToday = summaries.isEmpty
        ? const <DailyPendingItem>[]
        : summaries.first.pendingItems
            .where((i) => i.type == DailyPendingType.dueToday)
            .toList();
    final overdueCount = summaries.isEmpty ? 0 : summaries.first.overdueCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          'Due today',
          count: dueToday.length,
          color: const Color(0xFFF59E0B),
        ),
        if (dueToday.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              overdueCount > 0
                  ? 'No follow-up is dated today — but $overdueCount are '
                      'overdue, waiting in the Action Queue.'
                  : 'No follow-up is dated for today.',
              style: const TextStyle(color: _kTextMuted, fontSize: 13),
            ),
          )
        else
          _cardShelf(
            _paginatedList<DailyPendingItem>(
              items: dueToday,
              page: _todayDuePage,
              onPageChanged: (p) => setState(() => _todayDuePage = p),
              itemBuilder: _buildPendingCard,
            ),
          ),
        const SizedBox(height: 14),
        _sectionHeading(
          'Done today',
          count: summaries.isEmpty ? 0 : summaries.first.todayActivities.length,
          color: const Color(0xFF10B981),
        ),
        done,
      ],
    );
  }

  /// Small titled divider between the two halves of the Today tab.
  Widget _sectionHeading(String label, {required int count, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _kTextDark,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(fontSize: 12, color: _kTextMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildYesterdayReviewTab(DailyCockpitPayload payload) {
    return _buildWorkReviewTab(
      summaries: _visibleWorkSummaries(payload),
      activitiesOf: (s) => s.yesterdayActivities,
      emptyIcon: Icons.history_rounded,
      emptyText: 'No activity recorded for yesterday.',
      headerForAdmin:
          'Open an employee to review yesterday’s leads and follow-ups.',
      headerForSelf: (leads, actions) =>
          '$leads leads · $actions actions yesterday',
      page: _yesterdayPage,
      onPageChanged: (p) => setState(() => _yesterdayPage = p),
      expandKeyPrefix: 'yday',
    );
  }

  Widget _buildWorkReviewTab({
    required List<EmployeeDailySummary> summaries,
    required List<DailyCompletedActivity> Function(EmployeeDailySummary)
        activitiesOf,
    required IconData emptyIcon,
    required String emptyText,
    required String headerForAdmin,
    required String Function(int leads, int actions) headerForSelf,
    required int page,
    required ValueChanged<int> onPageChanged,
    required String expandKeyPrefix,
  }) {
    final withWork = summaries
        .where((s) => activitiesOf(s).isNotEmpty)
        .toList()
      ..sort(
        (a, b) => activitiesOf(b).length.compareTo(activitiesOf(a).length),
      );

    if (withWork.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(emptyIcon, size: 36, color: _kTextMuted),
            const SizedBox(height: 8),
            Text(
              emptyText,
              style: const TextStyle(color: _kTextMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (widget.isAdmin) {
      final totalActions =
          withWork.fold<int>(0, (sum, s) => sum + activitiesOf(s).length);
      final totalLeads = withWork.fold<int>(
        0,
        (sum, s) => sum + groupActivitiesByLead(activitiesOf(s)).length,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$totalLeads leads · $totalActions actions · tap a name to open or hide',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: _kTextDark,
              ),
            ),
          ),
          Text(
            headerForAdmin,
            style: const TextStyle(fontSize: 12, color: _kTextMuted),
          ),
          const SizedBox(height: 10),
          for (final summary in withWork)
            _buildEmployeeWorkAccordion(
              summary: summary,
              activities: activitiesOf(summary),
              expandKey: '$expandKeyPrefix:${summary.employeeUid}',
            ),
        ],
      );
    }

    final activities = activitiesOf(withWork.first);
    final groups = groupActivitiesByLead(activities);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            headerForSelf(groups.length, activities.length),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        _cardShelf(
          _paginatedList<LeadDayWork>(
            items: groups,
            page: page,
            onPageChanged: onPageChanged,
            itemBuilder: _buildLeadWorkCard,
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeWorkAccordion({
    required EmployeeDailySummary summary,
    required List<DailyCompletedActivity> activities,
    required String expandKey,
  }) {
    final groups = groupActivitiesByLead(activities);
    final isExpanded = _expandedWorkEmployees.contains(expandKey);
    final quoteCount = groups.where((g) => g.quotation != null).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                  _expandedWorkEmployees.remove(expandKey);
                } else {
                  _expandedWorkEmployees.add(expandKey);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _kBrandNavy,
                    child: Text(
                      summary.employeeName.isNotEmpty
                          ? summary.employeeName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.employeeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _kTextDark,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${groups.length} leads · ${activities.length} actions',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (quoteCount > 0) ...[
                    _Badge(
                      label: '$quoteCount quote${quoteCount == 1 ? '' : 's'}',
                      bgColor: const Color(0xFFEDE9FE),
                      textColor: const Color(0xFF6D28D9),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _kTextMuted,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _wrapCards(groups.map(_buildLeadWorkCard).toList()),
            ),
          ],
        ],
      ),
    );
  }

  /// Flows already-fetched cards (no pagination — these are small per-employee
  /// subsets) into as many columns as the available width allows, same sizing
  /// rule as [_paginatedList].
  Widget _wrapCards(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = cockpitColumnsFor(constraints.maxWidth);
        final cardWidth = cockpitCardWidthFor(constraints.maxWidth, columns);
        return Wrap(
          spacing: kCockpitCardGap,
          runSpacing: kCockpitCardGap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
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
    _openLeadDetails(lead);
  }

  Widget _buildLeadWorkCard(LeadDayWork work) {
    final isExpanded = _expandedWorkCards.contains(work.leadId);
    final hasPhone = work.phone.trim().isNotEmpty;
    return LeadDayWorkCard(
      work: work,
      isExpanded: isExpanded,
      onToggleExpand: () => setState(() {
        if (isExpanded) {
          _expandedWorkCards.remove(work.leadId);
        } else {
          _expandedWorkCards.add(work.leadId);
        }
      }),
      onOpenLead: () => _openLeadFromWork(work),
      onCall: hasPhone ? () => _makeCall(work.phone) : null,
      onViewQuote: work.quotation != null
          ? (q) => _viewQuotationPdf(q)
          : null,
      updatesLabel: 'today',
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? activeColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? activeColor : _kBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : _kTextDark,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : _kTextDark,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : _kTextDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.count,
    this.color,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              count != null ? '$label ($count)' : label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : _kTextDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
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

/// The one clear next step on a cockpit card — filled, solid colour, always
/// the same shape whichever card it sits on, so the eye finds it without
/// having to compare it against five other equal-weight buttons.
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
