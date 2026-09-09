import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/lead_model.dart';
import '../../services/auth_service.dart';
import '../../services/lead_export_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/export_io.dart';
import 'lead_details_modal.dart';

/// Row ordering inside each Kanban column.
enum LeadSort {
  /// Leads that need a touch today come first: a follow-up that is overdue or
  /// due today, then everything else by most recently worked.
  ///
  /// The default, because a stage column sorted purely by date buries the
  /// deals that are actually waiting on you behind whichever lead happened to
  /// arrive last.
  needsAttention,

  recentlyUpdated,
  newestFirst,
  oldestFirst,
  valueHighToLow,
  companyAz,
}

extension LeadSortLabel on LeadSort {
  String get label {
    switch (this) {
      case LeadSort.needsAttention:
        return 'Needs attention';
      case LeadSort.recentlyUpdated:
        return 'Recently updated';
      case LeadSort.newestFirst:
        return 'Newest first';
      case LeadSort.oldestFirst:
        return 'Oldest first';
      case LeadSort.valueHighToLow:
        return 'Value: high to low';
      case LeadSort.companyAz:
        return 'Company A-Z';
    }
  }
}

/// True when this lead is waiting on the rep today: a follow-up that is due
/// today or already missed, on a lead that is not closed.
bool leadNeedsAttention(Lead l, DateTime now) {
  final due = l.nextFollowUpDate;
  if (due == null) return false;
  const closed = {'won', 'lost', 'loss', 'disqualified'};
  if (closed.contains(l.status.toLowerCase())) return false;
  final endOfToday = DateTime(now.year, now.month, now.day + 1);
  return due.isBefore(endOfToday);
}

/// Comparator for the cards inside one Kanban column.
int Function(Lead, Lead) leadSortComparator(LeadSort sort, DateTime now) {
  switch (sort) {
    case LeadSort.needsAttention:
      return (a, b) {
        final na = leadNeedsAttention(a, now);
        final nb = leadNeedsAttention(b, now);
        if (na != nb) return na ? -1 : 1;
        // Inside the attention group, the most overdue goes first.
        if (na && nb) {
          return a.nextFollowUpDate!.compareTo(b.nextFollowUpDate!);
        }
        return b.lastModified.compareTo(a.lastModified);
      };
    case LeadSort.recentlyUpdated:
      return (a, b) => b.lastModified.compareTo(a.lastModified);
    case LeadSort.newestFirst:
      return (a, b) => b.leadDate.compareTo(a.leadDate);
    case LeadSort.oldestFirst:
      return (a, b) => a.leadDate.compareTo(b.leadDate);
    case LeadSort.valueHighToLow:
      return (a, b) {
        final c = b.totalAmount.compareTo(a.totalAmount);
        return c != 0 ? c : b.lastModified.compareTo(a.lastModified);
      };
    case LeadSort.companyAz:
      return (a, b) {
        final c = a.company.toLowerCase().compareTo(b.company.toLowerCase());
        return c != 0 ? c : b.lastModified.compareTo(a.lastModified);
      };
  }
}

class KanbanBoard extends StatefulWidget {
  const KanbanBoard({
    super.key,
    this.leadService,
    this.assignedToUid,
    this.authService,
    this.isAdmin = false,
    this.productService,
    this.isTender = false,
  });

  final LeadService? leadService;

  /// When set (e.g. employee dashboard), passed to [LeadService.getLeadsStream]
  /// so `assignedTo` is filtered to this Firebase Auth uid.
  final String? assignedToUid;

  final AuthService? authService;

  /// When true, shows assignee filter and uses resolved employee names.
  final bool isAdmin;

  /// Optional catalog lookup for quote prefill from lead details.
  final ProductService? productService;

  /// Whether to show only tender leads with tender statuses.
  final bool isTender;

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> {
  late LeadService _leadService;
  final WhatsAppService _whatsAppService = WhatsAppService();
  late Stream<List<Lead>> _leadsStream;
  final ScrollController _horizontalScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String? _locationFilter;
  String? _employeeUidFilter;
  /// null = all dates; today | last7 | last30 | custom
  String? _leadDateFilterPreset;
  DateTime? _leadDateFrom;
  DateTime? _leadDateTo;
  LeadSort _sort = LeadSort.needsAttention;

  Future<Map<String, String>>? _assigneeLabelsFuture;
  String _assigneeLabelsSig = '';

  @override
  void initState() {
    super.initState();
    _leadService = widget.leadService ?? LeadService();
    _leadsStream = _leadService.getLeadsStream(
      filterAssignedToUid: widget.assignedToUid,
    );
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KanbanBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leadService != widget.leadService ||
        oldWidget.assignedToUid != widget.assignedToUid) {
      _leadService = widget.leadService ?? LeadService();
      _leadsStream = _leadService.getLeadsStream(
        filterAssignedToUid: widget.assignedToUid,
      );
    }
  }

  Future<Map<String, String>> _resolveAssigneeLabelsFuture(Set<String> uids) {
    final sorted = uids.toList()..sort();
    final sig = sorted.join('\u001e');
    if (sig != _assigneeLabelsSig || _assigneeLabelsFuture == null) {
      _assigneeLabelsSig = sig;
      _assigneeLabelsFuture = uids.isEmpty
          ? Future<Map<String, String>>.value(<String, String>{})
          : _leadService.getUserDisplayLabels(uids);
    }
    return _assigneeLabelsFuture!;
  }

  Future<void> _exportData(
    List<Lead> leads,
    ExportFormat format,
    String filterSummary,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (leads.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing matches those filters.')),
      );
      return;
    }

    final service = LeadExportService();
    try {
      final Uint8List bytes;
      if (format == ExportFormat.csv) {
        bytes = await service.buildCsv(leads);
      } else {
        final progress = ValueNotifier<String>('Starting…');
        var cancelled = false;
        var dialogOpen = true;
        unawaited(
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _ExportProgressDialog(
              progress: progress,
              onCancel: () => cancelled = true,
            ),
          ).then((_) => dialogOpen = false),
        );
        try {
          final bundle = await service.gather(
            leads: leads,
            isAdmin: widget.isAdmin,
            currentUid: (widget.authService ?? AuthService()).currentUser?.uid ?? '',
            filterSummary: filterSummary,
            onProgress: (stage, done, total) =>
                progress.value = total <= 1 ? '$stage…' : '$stage… $done/$total',
            isCancelled: () => cancelled,
          );
          progress.value = 'Building workbook…';
          final built = service.buildWorkbook(bundle);
          if (built == null) {
            throw StateError('Could not build the Excel file.');
          }
          bytes = built;
        } finally {
          if (mounted && dialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          progress.dispose();
        }
      }

      final name = service.suggestedFileName(
        format: format,
        isTender: widget.isTender,
      );
      final saved = await saveExportBytes(
        bytes: bytes,
        fileName: name,
        dialogTitle: format == ExportFormat.csv
            ? 'Export leads (CSV)'
            : 'Export leads (Excel)',
      );
      if (!mounted) return;
      // saveExportBytes already accounts for web, where file_picker always
      // reports null because it hands the blob to the browser instead.
      if (saved) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Download started: $name'
                  : 'Exported ${leads.length} leads.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _openExportDialog(
    BuildContext context,
    List<Lead> leads,
    List<String> locationOptions,
    List<String> assigneeUids,
    Map<String, String> assigneeLabels,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExportDialog(
        leads: leads,
        locationOptions: locationOptions,
        assigneeUids: assigneeUids,
        assigneeLabels: assigneeLabels,
        isAdmin: widget.isAdmin,
        isTender: widget.isTender,
        initialLocation: _locationFilter,
        initialAssignee: _employeeUidFilter,
        searchQuery: _searchController.text,
        onExport: (exportedLeads, format, filterSummary) {
          _exportData(exportedLeads, format, filterSummary);
        },
      ),
    );
  }

  void _schedulePruneStaleFilters(
    Set<String> locationOptions,
    Set<String> assigneeUids,
  ) {
    final locInvalid =
        _locationFilter != null &&
        _locationFilter!.isNotEmpty &&
        !locationOptions.contains(_locationFilter);
    final empInvalid =
        widget.isAdmin &&
        _employeeUidFilter != null &&
        _employeeUidFilter!.isNotEmpty &&
        !assigneeUids.contains(_employeeUidFilter);
    if (!locInvalid && !empInvalid) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (locInvalid) _locationFilter = null;
        if (empInvalid) _employeeUidFilter = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FC),
      child: StreamBuilder<List<Lead>>(
        stream: _leadsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final message = snapshot.error.toString();
            // ignore: avoid_print — Firestore/index diagnostics in console
            print('KanbanBoard leads stream error: $message');
            if (kDebugMode) {
              debugPrintStack(
                label: 'KanbanBoard leads stream',
                stackTrace: snapshot.stackTrace,
              );
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final leads = snapshot.data ?? const <Lead>[];
          final locationOptions = _uniqueLocations(leads);
          final assigneeUids = widget.isAdmin
              ? leads
                    .map((l) => l.assignedTo.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet()
              : <String>{};

          _schedulePruneStaleFilters(locationOptions.toSet(), assigneeUids);

          if (!widget.isAdmin) {
            return _buildBoardContent(
              context,
              leads: leads,
              assigneeLabels: const <String, String>{},
              locationOptions: locationOptions,
              assigneeUids: const <String>[],
            );
          }

          return FutureBuilder<Map<String, String>>(
            future: _resolveAssigneeLabelsFuture(assigneeUids),
            builder: (context, labelSnap) {
              final labels = labelSnap.data ?? const <String, String>{};
              return _buildBoardContent(
                context,
                leads: leads,
                assigneeLabels: labels,
                locationOptions: locationOptions,
                assigneeUids: assigneeUids.toList(),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBoardContent(
    BuildContext context, {
    required List<Lead> leads,
    required Map<String, String> assigneeLabels,
    required List<String> locationOptions,
    required List<String> assigneeUids,
  }) {
    final filtered = _applyFilters(
      leads,
      searchQuery: _searchController.text,
      locationFilter: _locationFilter,
      assignedToFilter: _employeeUidFilter,
      applyAssigneeFilter: widget.isAdmin,
      isTender: widget.isTender,
      leadDateFrom: _leadDateFrom,
      leadDateTo: _leadDateTo,
    );

    final columns = widget.isTender ? Lead.tenderStatuses : Lead.statuses;

    final grouped = <String, List<Lead>>{
      for (final status in columns) status: <Lead>[],
    };

    for (final lead in filtered) {
      final status = Lead.kanbanColumnFor(
        lead.status,
        isTender: widget.isTender,
      );
      grouped[status]!.add(lead);
    }

    final sortNow = DateTime.now();
    final comparator = leadSortComparator(_sort, sortNow);
    for (final list in grouped.values) {
      list.sort(comparator);
    }

    final columnWidth = _kanbanColumnWidth(context);
    final thumbAlwaysVisible = _scrollbarThumbAlwaysVisible(context);

    final sortedAssigneeUids = List<String>.from(assigneeUids)
      ..sort(
        (a, b) => (assigneeLabels[a] ?? a).toLowerCase().compareTo(
          (assigneeLabels[b] ?? b).toLowerCase(),
        ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KanbanFilterBar(
          searchController: _searchController,
          locationOptions: locationOptions,
          selectedLocation: _locationFilter,
          onLocationChanged: (v) => setState(() => _locationFilter = v),
          leadDateFilterPreset: _leadDateFilterPreset,
          leadDateFilterLabel: _leadDateFilterLabel(),
          onLeadDateFilterChanged: _onLeadDateFilterChanged,
          isAdmin: widget.isAdmin,
          assigneeUids: sortedAssigneeUids,
          assigneeLabels: assigneeLabels,
          selectedAssigneeUid: _employeeUidFilter,
          onAssigneeChanged: (v) => setState(() => _employeeUidFilter = v),
          sort: _sort,
          onSortChanged: (v) => setState(() => _sort = v),
          onExport: () => _openExportDialog(
            context,
            leads,
            locationOptions,
            sortedAssigneeUids,
            assigneeLabels,
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: thumbAlwaysVisible,
            trackVisibility: thumbAlwaysVisible,
            child: ListView.separated(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 48, 16),
              itemBuilder: (context, index) {
                final status = columns[index];
                return SizedBox(
                  width: columnWidth,
                  child: _KanbanColumn(
                    status: status,
                    leads: grouped[status]!,
                    isTender: widget.isTender,
                    cardDragWidth: columnWidth - 28,
                    onLeadMoved: _onLeadMoved,
                    onWhatsAppTap: _openWhatsApp,
                    onLeadTap: _openLeadDetails,
                    assigneeLabels: assigneeLabels,
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemCount: columns.length,
            ),
          ),
        ),
      ],
    );
  }

  static List<String> _uniqueLocations(List<Lead> leads) {
    final set = <String>{};
    for (final l in leads) {
      final t = l.location.trim();
      if (t.isNotEmpty) set.add(t);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _leadDateFilterLabel() {
    switch (_leadDateFilterPreset) {
      case 'today':
        return 'Today';
      case 'last7':
        return 'Last 7 days';
      case 'last30':
        return 'Last 30 days';
      case 'custom':
        if (_leadDateFrom != null && _leadDateTo != null) {
          final from = DateFormat('dd MMM yyyy').format(_leadDateFrom!);
          final to = DateFormat('dd MMM yyyy').format(_leadDateTo!);
          return from == to ? from : '$from – $to';
        }
        return 'Custom range';
      default:
        return 'All dates';
    }
  }

  Future<void> _onLeadDateFilterChanged(String? preset) async {
    if (preset == 'custom') {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _leadDateFrom != null && _leadDateTo != null
            ? DateTimeRange(start: _leadDateFrom!, end: _leadDateTo!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 7)),
                end: now,
              ),
        helpText: 'Filter by lead date',
      );
      if (!mounted || range == null) return;
      setState(() {
        _leadDateFilterPreset = 'custom';
        _leadDateFrom = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        _leadDateTo = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        );
      });
      return;
    }

    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    setState(() {
      _leadDateFilterPreset = preset;
      switch (preset) {
        case 'today':
          _leadDateFrom = startOfToday;
          _leadDateTo = DateTime(
            today.year,
            today.month,
            today.day,
            23,
            59,
            59,
            999,
          );
        case 'last7':
          _leadDateFrom = startOfToday.subtract(const Duration(days: 6));
          _leadDateTo = DateTime(
            today.year,
            today.month,
            today.day,
            23,
            59,
            59,
            999,
          );
        case 'last30':
          _leadDateFrom = startOfToday.subtract(const Duration(days: 29));
          _leadDateTo = DateTime(
            today.year,
            today.month,
            today.day,
            23,
            59,
            59,
            999,
          );
        default:
          _leadDateFrom = null;
          _leadDateTo = null;
      }
    });
  }

  static List<Lead> _applyFilters(
    List<Lead> leads, {
    required String searchQuery,
    required String? locationFilter,
    required String? assignedToFilter,
    required bool applyAssigneeFilter,
    required bool isTender,
    DateTime? leadDateFrom,
    DateTime? leadDateTo,
  }) {
    var out = List<Lead>.from(leads).where((l) => l.isTender == isTender).toList();

    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out
          .where(
            (lead) =>
                lead.name.toLowerCase().contains(q) ||
                lead.company.toLowerCase().contains(q) ||
                lead.phone.toLowerCase().contains(q) ||
                lead.bidNo.toLowerCase().contains(q),
          )
          .toList();
    }

    if (locationFilter != null && locationFilter.trim().isNotEmpty) {
      final loc = locationFilter.trim().toLowerCase();
      out = out
          .where((lead) => lead.location.trim().toLowerCase() == loc)
          .toList();
    }

    if (applyAssigneeFilter &&
        assignedToFilter != null &&
        assignedToFilter.trim().isNotEmpty) {
      final uid = assignedToFilter.trim();
      out = out.where((lead) => lead.assignedTo.trim() == uid).toList();
    }

    if (leadDateFrom != null) {
      out = out
          .where(
            (lead) =>
                !lead.leadDate.isBefore(leadDateFrom) ||
                lead.leadDate.isAtSameMomentAs(leadDateFrom),
          )
          .toList();
    }
    if (leadDateTo != null) {
      out = out
          .where(
            (lead) =>
                !lead.leadDate.isAfter(leadDateTo) ||
                lead.leadDate.isAtSameMomentAs(leadDateTo),
          )
          .toList();
    }

    return out;
  }

  Future<void> _onLeadMoved(Lead lead, String targetStatus) async {
    if (lead.status == targetStatus) return;
    final messenger = ScaffoldMessenger.of(context);
    final previousStatus = lead.status;

    DateTime? installationDate;
    if (targetStatus == 'Won') {
      installationDate = await _pickInstallationDate();
      if (installationDate == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Installation date required to mark as Won.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    try {
      await _leadService.updateLeadStatus(
        lead.id,
        targetStatus,
        sourceLead: lead,
        installationDate: installationDate,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Moved "${lead.name}" to $targetStatus'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await _leadService.updateLeadStatus(
                  lead.id,
                  previousStatus,
                  sourceLead: lead,
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not undo the move.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to move lead right now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<DateTime?> _pickInstallationDate() async {
    return showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Installation Date',
    );
  }

  Future<void> _openWhatsApp(Lead lead) async {
    final messenger = ScaffoldMessenger.of(context);
    final digitsOnly = lead.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This lead does not have a valid phone number.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Uri uri;
    try {
      uri = await _whatsAppService.buildTemplateUri(lead);
    } catch (_) {
      uri = _whatsAppService.buildUriFromMessage(
        lead,
        'Hi ${lead.name.trim().isEmpty ? 'there' : lead.name.trim()},',
      );
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openLeadDetails(Lead lead) {
    LeadDetailsModal.show(
      context,
      lead: lead,
      leadService: _leadService,
      authService: widget.authService ?? AuthService(),
      productService: widget.productService,
    );
  }

  static double _kanbanColumnWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1400) return 320;
    if (w >= 1000) return 300;
    return 280;
  }

  static bool _scrollbarThumbAlwaysVisible(BuildContext context) {
    if (kIsWeb) return true;
    switch (Theme.of(context).platform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }
}

/// Top filter row for the Kanban board: search, location, optional assignee (admin), sort.
class KanbanFilterBar extends StatelessWidget {
  const KanbanFilterBar({
    super.key,
    required this.searchController,
    required this.locationOptions,
    required this.selectedLocation,
    required this.onLocationChanged,
    required this.leadDateFilterPreset,
    required this.leadDateFilterLabel,
    required this.onLeadDateFilterChanged,
    required this.isAdmin,
    required this.assigneeUids,
    required this.assigneeLabels,
    required this.selectedAssigneeUid,
    required this.onAssigneeChanged,
    required this.sort,
    required this.onSortChanged,
    required this.onExport,
  });

  final TextEditingController searchController;
  final List<String> locationOptions;
  final String? selectedLocation;
  final ValueChanged<String?> onLocationChanged;

  final String? leadDateFilterPreset;
  final String leadDateFilterLabel;
  final Future<void> Function(String?) onLeadDateFilterChanged;

  final bool isAdmin;
  final List<String> assigneeUids;
  final Map<String, String> assigneeLabels;
  final String? selectedAssigneeUid;
  final ValueChanged<String?> onAssigneeChanged;

  final LeadSort sort;
  final ValueChanged<LeadSort> onSortChanged;
  final VoidCallback onExport;

  static InputDecoration _fieldDecoration(
    BuildContext context, {
    String? hint,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: _fieldDecoration(
                  context,
                  hint: 'Name, company, or phone…',
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value:
                    selectedLocation != null &&
                        locationOptions.contains(selectedLocation)
                    ? selectedLocation
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Location',
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: border,
                  enabledBorder: border,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All locations'),
                  ),
                  ...locationOptions.map(
                    (loc) => DropdownMenuItem<String?>(
                      value: loc,
                      child: Text(loc, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: onLocationChanged,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value: leadDateFilterPreset,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Lead date',
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: border,
                  enabledBorder: border,
                ),
                selectedItemBuilder: (context) => [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All dates'),
                  ),
                  const DropdownMenuItem<String?>(
                    value: 'today',
                    child: Text('Today'),
                  ),
                  const DropdownMenuItem<String?>(
                    value: 'last7',
                    child: Text('Last 7 days'),
                  ),
                  const DropdownMenuItem<String?>(
                    value: 'last30',
                    child: Text('Last 30 days'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'custom',
                    child: Text(
                      leadDateFilterLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All dates'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'today',
                    child: Text('Today'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'last7',
                    child: Text('Last 7 days'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'last30',
                    child: Text('Last 30 days'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'custom',
                    child: Text('Custom range…'),
                  ),
                ],
                onChanged: (v) => onLeadDateFilterChanged(v),
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  value:
                      selectedAssigneeUid != null &&
                          assigneeUids.contains(selectedAssigneeUid)
                      ? selectedAssigneeUid
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Employee',
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: border,
                    enabledBorder: border,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All employees'),
                    ),
                    ...assigneeUids.map(
                      (uid) => DropdownMenuItem<String?>(
                        value: uid,
                        child: Text(
                          assigneeLabels[uid] ?? uid,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onAssigneeChanged,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Tooltip(
              message: 'Sort cards inside each column',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<LeadSort>(
                  value: sort,
                  icon: const Icon(Icons.sort_rounded, size: 20),
                  items: [
                    for (final s in LeadSort.values)
                      DropdownMenuItem<LeadSort>(
                        value: s,
                        child: Text(s.label),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onSortChanged(v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Export data',
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.leads,
    required this.isTender,
    required this.cardDragWidth,
    required this.onLeadMoved,
    required this.onWhatsAppTap,
    required this.onLeadTap,
    required this.assigneeLabels,
  });

  final String status;
  final List<Lead> leads;
  final bool isTender;
  final double cardDragWidth;
  final Future<void> Function(Lead lead, String targetStatus) onLeadMoved;
  final Future<void> Function(Lead lead) onWhatsAppTap;
  final void Function(Lead lead) onLeadTap;
  final Map<String, String> assigneeLabels;

  bool get _useClickDrag {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DragTarget<Lead>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => onLeadMoved(details.data, status),
      builder: (context, candidates, rejected) {
        final isHovering = candidates.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isHovering
                ? colorScheme.primary.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: isHovering ? 2 : 1,
              color: isHovering
                  ? colorScheme.primary.withValues(alpha: 0.55)
                  : const Color(0xFFE6EAF2),
            ),
            boxShadow: [
              BoxShadow(
                color: isHovering
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : const Color(0x100B1324),
                blurRadius: isHovering ? 18 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F5FC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${leads.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF44516B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: leads.isEmpty
                    ? Center(
                        child: Text(
                          'Drop lead here',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF7A869D)),
                        ),
                      )
                    : ListView.separated(
                        itemBuilder: (context, index) {
                          final lead = leads[index];
                          final feedback = Material(
                            color: Colors.transparent,
                            elevation: 8,
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: cardDragWidth,
                              child: _LeadCard(
                                lead: lead,
                                onWhatsAppTap: null,
                                assigneeLabels: assigneeLabels,
                              ),
                            ),
                          );
                          final childWhenDragging = Opacity(
                            opacity: 0.38,
                            child: _LeadCard(
                              lead: lead,
                              onWhatsAppTap: () {
                                onWhatsAppTap(lead);
                              },
                              assigneeLabels: assigneeLabels,
                            ),
                          );
                          final child = Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => onLeadTap(lead),
                              borderRadius: BorderRadius.circular(14),
                              child: _LeadCard(
                                lead: lead,
                                onWhatsAppTap: () {
                                  onWhatsAppTap(lead);
                                },
                                assigneeLabels: assigneeLabels,
                              ),
                            ),
                          );

                          if (_useClickDrag) {
                            return Draggable<Lead>(
                              key: ValueKey<String>(lead.id),
                              data: lead,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: feedback,
                              childWhenDragging: childWhenDragging,
                              child: child,
                            );
                          }
                          return LongPressDraggable<Lead>(
                            key: ValueKey<String>(lead.id),
                            data: lead,
                            delay: const Duration(milliseconds: 220),
                            feedback: feedback,
                            childWhenDragging: childWhenDragging,
                            child: child,
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: leads.length,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeadCard extends StatefulWidget {
  const _LeadCard({
    required this.lead,
    required this.onWhatsAppTap,
    required this.assigneeLabels,
  });

  final Lead lead;
  final VoidCallback? onWhatsAppTap;
  final Map<String, String> assigneeLabels;

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard> {
  bool _hover = false;

  bool get _webHoverEffect => kIsWeb;

  bool get _pointerCursor {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final assigneeName = widget.assigneeLabels[lead.assignedTo.trim()] ?? '';
    final companyLabel = lead.company.trim();
    final nameLabel = lead.name.trim();
    final cardHeadline =
        companyLabel.isNotEmpty ? companyLabel : nameLabel;
    final borderColor = _webHoverEffect && _hover
        ? const Color(0xFF3B5BDB).withValues(alpha: 0.38)
        : const Color(0xFFE7EAF2);
    final shadowBlur = _webHoverEffect && _hover ? 14.0 : 10.0;
    final shadowDy = _webHoverEffect && _hover ? 6.0 : 4.0;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0x120C172B),
            blurRadius: shadowBlur,
            offset: Offset(0, shadowDy),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cardHeadline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (lead.isTender) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'TENDER',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!lead.isTender && companyLabel.isNotEmpty && nameLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                nameLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF69758D)),
              ),
            ],
            if (lead.isTender) ...[
              if (lead.bidNo != null && lead.bidNo!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Bid: ${lead.bidNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (lead.productsSummary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  lead.productsSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4B5870)),
                ),
              ],
            ] else ...[
              if (lead.email.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  lead.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (lead.phone.isNotEmpty && lead.phone != 'N/A') ...[
                const SizedBox(height: 2),
                Text(
                  lead.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4B5870)),
                ),
              ],
            ],
            if (lead.remark.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                lead.remark,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D7890)),
              ),
            ],
            if (assigneeName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      assigneeName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDate(lead.leadDate),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF7D879A),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Chat on WhatsApp',
                  onPressed: widget.onWhatsAppTap,
                  icon: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Color(0xFF25D366),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (_pointerCursor) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: _webHoverEffect ? (_) => setState(() => _hover = true) : null,
        onExit: _webHoverEffect ? (_) => setState(() => _hover = false) : null,
        child: card,
      );
    }

    return card;
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.leads,
    required this.locationOptions,
    required this.assigneeUids,
    required this.assigneeLabels,
    required this.isAdmin,
    required this.isTender,
    required this.initialLocation,
    required this.initialAssignee,
    required this.searchQuery,
    required this.onExport,
  });

  final List<Lead> leads;
  final List<String> locationOptions;
  final List<String> assigneeUids;
  final Map<String, String> assigneeLabels;
  final bool isAdmin;
  final bool isTender;
  final String? initialLocation;
  final String? initialAssignee;
  final String searchQuery;
  final void Function(List<Lead> leads, ExportFormat format, String filterSummary)
      onExport;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  ExportFormat _format = ExportFormat.csv;
  String _leadType = 'All';
  String? _selectedStatus = 'All';
  String? _selectedLocation = 'All';
  String? _selectedAssignee = 'All';
  final TextEditingController _minValueController = TextEditingController();
  final TextEditingController _maxValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _leadType = widget.isTender ? 'Tenders Only' : 'Leads Only';
    _selectedLocation = widget.initialLocation ?? 'All';
    _selectedAssignee = widget.initialAssignee ?? 'All';
  }

  @override
  void dispose() {
    _minValueController.dispose();
    _maxValueController.dispose();
    super.dispose();
  }

  List<String> _getUniqueStatuses() {
    final set = <String>{'All'};
    if (_leadType == 'All' || _leadType == 'Leads Only') {
      set.addAll(Lead.statuses);
    }
    if (_leadType == 'All' || _leadType == 'Tenders Only') {
      set.addAll(Lead.tenderStatuses);
    }
    return set.toList();
  }

  void _submit() {
    var out = List<Lead>.from(widget.leads);

    // Apply search query first if it exists
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out
          .where(
            (lead) =>
                lead.name.toLowerCase().contains(q) ||
                lead.company.toLowerCase().contains(q) ||
                lead.phone.toLowerCase().contains(q) ||
                lead.bidNo.toLowerCase().contains(q),
          )
          .toList();
    }

    // 1. Date filter (Start Date)
    if (_startDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      out = out.where((l) => l.leadDate.isAfter(start) || l.leadDate.isAtSameMomentAs(start)).toList();
    }

    // 2. Date filter (End Date)
    if (_endDate != null) {
      final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999);
      out = out.where((l) => l.leadDate.isBefore(end) || l.leadDate.isAtSameMomentAs(end)).toList();
    }

    // 3. Status filter
    if (_selectedStatus != 'All' && _selectedStatus != null) {
      out = out
          .where(
            (l) =>
                Lead.kanbanColumnFor(l.status, isTender: l.isTender) ==
                _selectedStatus,
          )
          .toList();
    }

    // 4. Lead Type filter
    if (_leadType == 'Leads Only') {
      out = out.where((l) => !l.isTender).toList();
    } else if (_leadType == 'Tenders Only') {
      out = out.where((l) => l.isTender).toList();
    }

    // 5. Location filter
    if (_selectedLocation != 'All' && _selectedLocation != null) {
      out = out.where((l) => l.location.trim().toLowerCase() == _selectedLocation!.trim().toLowerCase()).toList();
    }

    // 6. Assignee filter
    if (widget.isAdmin && _selectedAssignee != 'All' && _selectedAssignee != null) {
      out = out.where((l) => l.assignedTo.trim() == _selectedAssignee!.trim()).toList();
    }

    // 7. Price Min Filter
    final minVal = double.tryParse(_minValueController.text.trim());
    if (minVal != null) {
      out = out.where((l) => l.totalAmount >= minVal).toList();
    }

    // 8. Price Max Filter
    final maxVal = double.tryParse(_maxValueController.text.trim());
    if (maxVal != null) {
      out = out.where((l) => l.totalAmount <= maxVal).toList();
    }

    Navigator.of(context).pop();
    widget.onExport(out, _format, _filterSummary());
  }

  /// Plain-English record of what this export covers, for the Export Info
  /// sheet — so a filtered workbook cannot be mistaken for the whole database.
  String _filterSummary() {
    final parts = <String>[_leadType];
    if (_selectedStatus != null && _selectedStatus != 'All') {
      parts.add('Status: $_selectedStatus');
    }
    if (_selectedLocation != null && _selectedLocation != 'All') {
      parts.add('Location: $_selectedLocation');
    }
    if (_selectedAssignee != null && _selectedAssignee != 'All') {
      parts.add(
        'Assignee: ${widget.assigneeLabels[_selectedAssignee] ?? _selectedAssignee}',
      );
    }
    if (_startDate != null || _endDate != null) {
      final f = DateFormat('dd MMM yyyy');
      final from = _startDate == null ? 'start' : f.format(_startDate!);
      final to = _endDate == null ? 'today' : f.format(_endDate!);
      parts.add('$from to $to');
    }
    final minV = _minValueController.text.trim();
    final maxV = _maxValueController.text.trim();
    if (minV.isNotEmpty) parts.add('Min ₹$minV');
    if (maxV.isNotEmpty) parts.add('Max ₹$maxV');
    if (widget.searchQuery.trim().isNotEmpty) {
      parts.add('Search: ${widget.searchQuery.trim()}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final uniqueStatuses = _getUniqueStatuses();
    if (!uniqueStatuses.contains(_selectedStatus)) {
      _selectedStatus = 'All';
    }

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.filter_list_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Export Leads Data', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<ExportFormat>(
                segments: const [
                  ButtonSegment(
                    value: ExportFormat.csv,
                    icon: Icon(Icons.description_outlined, size: 16),
                    label: Text('CSV'),
                  ),
                  ButtonSegment(
                    value: ExportFormat.excel,
                    icon: Icon(Icons.table_chart_outlined, size: 16),
                    label: Text('Excel'),
                  ),
                ],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _format = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                _format == ExportFormat.csv
                    ? 'One row per lead. Fast.'
                    : 'Six sheets — leads, quotations, follow-up history, '
                        'remarks and a pivot-ready summary. Pulls extra data, '
                        'so it takes a few seconds.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              // Date picker fields
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Start Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _startDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(10),
                              color: isDark ? Colors.grey[900] : Colors.grey[50],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_outlined, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _startDate == null 
                                        ? 'Select' 
                                        : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_startDate != null)
                                  InkWell(
                                    onTap: () => setState(() => _startDate = null),
                                    child: const Icon(Icons.clear, size: 14),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('End Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _endDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(10),
                              color: isDark ? Colors.grey[900] : Colors.grey[50],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_outlined, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _endDate == null 
                                        ? 'Select' 
                                        : '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_endDate != null)
                                  InkWell(
                                    onTap: () => setState(() => _endDate = null),
                                    child: const Icon(Icons.clear, size: 14),
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
              const SizedBox(height: 16),
              
              // Lead Type Dropdown
              DropdownButtonFormField<String>(
                value: _leadType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Lead Type',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: border,
                  enabledBorder: border,
                ),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All (Leads & Tenders)')),
                  DropdownMenuItem(value: 'Leads Only', child: Text('Leads Only')),
                  DropdownMenuItem(value: 'Tenders Only', child: Text('Tenders Only')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _leadType = val;
                      _selectedStatus = 'All'; // Reset status filter on type change
                    });
                  }
                },
              ),
              const SizedBox(height: 14),

              // Status Dropdown
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Status',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: border,
                  enabledBorder: border,
                ),
                items: uniqueStatuses.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStatus = val);
                  }
                },
              ),
              const SizedBox(height: 14),

              // Location Dropdown
              DropdownButtonFormField<String>(
                value: _selectedLocation,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Location',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: border,
                  enabledBorder: border,
                ),
                items: [
                  const DropdownMenuItem(value: 'All', child: Text('All Locations')),
                  ...widget.locationOptions.map(
                    (loc) => DropdownMenuItem(value: loc, child: Text(loc)),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedLocation = val);
                  }
                },
              ),
              const SizedBox(height: 14),

              // Assignee Dropdown (Admin only)
              if (widget.isAdmin) ...[
                DropdownButtonFormField<String>(
                  value: _selectedAssignee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assigned Employee',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: border,
                    enabledBorder: border,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'All', child: Text('All Employees')),
                    ...widget.assigneeUids.map(
                      (uid) => DropdownMenuItem(
                        value: uid,
                        child: Text(widget.assigneeLabels[uid] ?? uid),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedAssignee = val);
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],

              // Budget / Value Range
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minValueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Min Value (INR)',
                        prefixText: '₹ ',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: border,
                        enabledBorder: border,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxValueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Max Value (INR)',
                        prefixText: '₹ ',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: border,
                        enabledBorder: border,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(
            _format == ExportFormat.csv ? 'Export CSV' : 'Export Excel',
          ),
        ),
      ],
    );
  }
}

/// Modal shown while the Excel export walks several Firestore collections.
///
/// Cancellation is cooperative: the flag is polled between batches, and a
/// cancelled run still produces a workbook, flagged truncated on Export Info.
class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog({
    required this.progress,
    required this.onCancel,
  });

  final ValueNotifier<String> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
      actions: [
        TextButton(
          onPressed: () {
            onCancel();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
