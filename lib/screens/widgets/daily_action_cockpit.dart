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
import 'lead_details_modal.dart';

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
  int _selectedTab = 0; // 0: Pending Queue, 1: Today Done, 2: Yesterday Review
  DailyPendingType? _pendingFilter;
  String _searchQuery = '';
  String _sortBy = 'dueSoonest'; // dueSoonest, mostOverdue, companyAz
  String? _selectedEmployeeUid; // For Admin filter
  final Set<String> _expandedEmployeeCards = <String>{};

  // Pagination state — per tab
  static const int _pageSize = 30;
  int _pendingPage = 0; // Tab 0: Action Queue
  int _todayPage = 0; // Tab 1: Today's Work
  int _yesterdayPage = 0; // Tab 2: Yesterday Review


  @override
  void initState() {
    super.initState();
    _reload();
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
                  const Expanded(
                    child: Text('Daily Action Cockpit is synchronizing...'),
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
    final totalDone = payload.globalDoneToday;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _TabPill(
            label: 'Action Queue',
            count: totalPending,
            icon: Icons.phone_callback_rounded,
            isSelected: _selectedTab == 0,
            activeColor: const Color(0xFF0D9488),
            onTap: () => setState(() => _selectedTab = 0),
          ),
          _TabPill(
            label: "Today's Work",
            count: totalDone,
            icon: Icons.check_circle_outline_rounded,
            isSelected: _selectedTab == 1,
            activeColor: const Color(0xFF10B981),
            onTap: () => setState(() => _selectedTab = 1),
          ),
          _TabPill(
            label: "Yesterday's Review",
            icon: Icons.history_rounded,
            isSelected: _selectedTab == 2,
            activeColor: const Color(0xFF6366F1),
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
        return _buildPendingQueueTab(payload, isMobile);
      case 1:
        return _buildTodayWorkTab(payload);
      case 2:
        return _buildYesterdayReviewTab(payload);
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
                onChanged: (v) => setState(() {
                  _searchQuery = v.trim();
                  _pendingPage = 0;
                  _todayPage = 0;
                  _yesterdayPage = 0;
                }),
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
          _buildPendingItemList(
            _filterPendingItems(summaries.first.pendingItems),
            showAssignee: false,
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

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildPendingCard(item);
      },
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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ActionButton(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'Call',
                    color: const Color(0xFF0F766E),
                    bgColor: const Color(0xFFCCFBF1),
                    onTap: () => _makeCall(lead.phone),
                  ),
                  _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'WhatsApp',
                    color: const Color(0xFF047857),
                    bgColor: const Color(0xFFD1FAE5),
                    onTap: () => _sendWhatsApp(lead),
                  ),
                  _ActionButton(
                    icon: Icons.calendar_month_outlined,
                    label: 'Reschedule',
                    color: const Color(0xFF2563EB),
                    bgColor: const Color(0xFFDBEAFE),
                    onTap: () => _rescheduleFollowUp(lead),
                  ),
                  _ActionButton(
                    icon: Icons.edit_note_rounded,
                    label: 'Note',
                    color: const Color(0xFF4F46E5),
                    bgColor: const Color(0xFFEEF2FF),
                    onTap: () => _addQuickNote(lead),
                  ),
                  _ActionButton(
                    icon: Icons.sync_alt_rounded,
                    label: lead.status,
                    color: const Color(0xFFB45309),
                    bgColor: const Color(0xFFFEF3C7),
                    onTap: () => _quickChangeStatus(lead),
                  ),
                  _ActionButton(
                    icon: Icons.close_rounded,
                    label: 'Drop',
                    color: const Color(0xFF991B1B),
                    bgColor: const Color(0xFFFEE2E2),
                    onTap: () => _dropLead(lead),
                  ),
                  IconButton(
                    tooltip: 'Open full lead details',
                    icon: const Icon(Icons.open_in_new, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openLeadDetails(lead),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 2: TODAY'S COMPLETED WORK ---

  Widget _buildTodayWorkTab(DailyCockpitPayload payload) {
    final activities = <DailyCompletedActivity>[];
    for (final s in payload.employeeSummaries) {
      if (_selectedEmployeeUid == null || s.employeeUid == _selectedEmployeeUid) {
        activities.addAll(s.todayActivities);
      }
    }
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.assignment_outlined, size: 36, color: _kTextMuted),
            SizedBox(height: 8),
            Text(
              'No completed activities recorded today yet.',
              style: TextStyle(color: _kTextMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${activities.length} completed actions today',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activities.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final act = activities[index];
            return _buildActivityCard(act);
          },
        ),
      ],
    );
  }

  // --- TAB 3: YESTERDAY'S REVIEW ---

  Widget _buildYesterdayReviewTab(DailyCockpitPayload payload) {
    final yesterdayActs = <DailyCompletedActivity>[];
    for (final s in payload.employeeSummaries) {
      if (_selectedEmployeeUid == null || s.employeeUid == _selectedEmployeeUid) {
        yesterdayActs.addAll(s.yesterdayActivities);
      }
    }
    yesterdayActs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (yesterdayActs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: const Text(
          'No activity recorded for yesterday.',
          style: TextStyle(color: _kTextMuted, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Review yesterday’s work and take quick follow-up actions:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: yesterdayActs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final act = yesterdayActs[index];
            return _buildActivityCard(act, isYesterday: true);
          },
        ),
      ],
    );
  }

  Widget _buildActivityCard(DailyCompletedActivity act, {bool isYesterday = false}) {
    IconData icon;
    Color iconColor;
    Color bg;

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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  act.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _kTextDark,
                  ),
                ),
                Text(
                  '${act.subtitle} · ${DateFormat('h:mm a').format(act.timestamp)}',
                  style: const TextStyle(fontSize: 11, color: _kTextMuted),
                ),
              ],
            ),
          ),
          if (act.type == DailyActivityType.quotation && act.quotation != null) ...[
            IconButton(
              tooltip: 'View quotation',
              icon: const Icon(Icons.visibility_outlined, size: 18),
              onPressed: () => _viewQuotationPdf(act.quotation!),
            ),
          ],
          if (act.phone.isNotEmpty) ...[
            IconButton(
              tooltip: 'Quick Call',
              icon: const Icon(Icons.phone, size: 18, color: Color(0xFF0F766E)),
              onPressed: () => _makeCall(act.phone),
            ),
          ],
        ],
      ),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
