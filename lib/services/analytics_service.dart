import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/daily_cockpit_model.dart';
import '../models/lead_event_model.dart';
import '../models/lead_model.dart';
import '../models/quotation_model.dart';
import '../models/user_model.dart';
import 'lead_service.dart';
import 'quotation_service.dart';
import 'source_service.dart';

/// Open statuses whose deals count towards Expected Revenue, at full value.
///
/// Matches Pactech: a quotation has gone out by these stages, so the money is
/// real enough to forecast. 'New' and 'Contacted' are deliberately absent.
const Set<String> _expectedRevenueLeadStatuses = <String>{
  'Proposal',
  'Follow-up',
};

/// Tender mid/late open stages (past enquiry) that count as Expected Revenue.
const Set<String> _expectedRevenueTenderStatuses = <String>{
  'Technical Evaluation',
  'Query Raised',
  'Query Responded',
  'Qualified',
  'Reverse Auction(RA)',
};

/// Aggregated metrics for the executive dashboard.
class ExecutiveAnalytics {
  const ExecutiveAnalytics({
    required this.totalActiveLeads,
    required this.pipelineValue,
    required this.totalRevenue,
    required this.expectedRevenue,
    required this.leadsAddedToday,
    required this.followUpsToday,
    required this.overdueFollowUps,
    required this.winRate,
    required this.avgWonDealSize,
    required this.conversionToWon,
    required this.closedWonCount,
    required this.closedLostCount,
    required this.activeLeadIds,
    required this.pipelineLeadIds,
    required this.expectedRevenueLeadIds,
    required this.quotedLeadIds,
    required this.leadAmounts,
    required this.wonLeadIds,
    required this.leadsAddedTodayIds,
    required this.followUpsTodayIds,
    required this.overdueFollowUpIds,
    required this.closedDealIds,
    required this.periodCreatedLeadIds,
    required this.statusSlices,
    required this.lossSlices,
    required this.sourceSlices,
    required this.sourceReport,
    required this.monthlySales,
    required this.leaderboard,
    required this.employeeTargetProgress,
  });

  final int totalActiveLeads;
  final double pipelineValue;
  final double totalRevenue;
  final double expectedRevenue;
  final int leadsAddedToday;
  final int followUpsToday;
  final int overdueFollowUps;
  final double winRate;
  final double avgWonDealSize;
  final double conversionToWon;
  final int closedWonCount;
  final int closedLostCount;

  /// All currently-open leads + tenders (Active leads KPI).
  final List<String> activeLeadIds;

  /// Open leads/tenders with effective amount > 0 (Pipeline Value drill-down).
  /// Pipeline *value* still sums every open lead; this list omits zero-value ones.
  final List<String> pipelineLeadIds;

  /// Open leads/tenders in proposal-or-later stages with amount > 0.
  final List<String> expectedRevenueLeadIds;

  /// Any lead/tender id that has a quotation on file (for "Proposal sent" badges).
  final List<String> quotedLeadIds;

  /// Lead id → effective amount (lead.totalAmount, else max quotation).
  final Map<String, double> leadAmounts;

  final List<String> wonLeadIds;
  final List<String> leadsAddedTodayIds;
  final List<String> followUpsTodayIds;
  final List<String> overdueFollowUpIds;
  final List<String> closedDealIds;
  final List<String> periodCreatedLeadIds;

  /// Open status label -> lead count (for pipeline distribution).
  final List<StatusSlice> statusSlices;

  /// Loss reason -> lead count (for diagnostics).
  final List<LossSlice> lossSlices;

  /// Lead source -> lead count (for channels).
  final List<SourceSlice> sourceSlices;

  /// Source × time / status / employee breakdown (Lead Source Report table).
  final SourceReport sourceReport;

  /// Chronological points for the current calendar year (monthly won revenue).
  final List<MonthlySalesPoint> monthlySales;

  final List<LeaderboardEntry> leaderboard;

  /// Target progress values for each rep.
  final List<TargetProgress> employeeTargetProgress;
}

class StatusSlice {
  const StatusSlice({
    required this.label,
    required this.count,
    required this.leadIds,
  });

  final String label;
  final int count;
  final List<String> leadIds;
}

class LossSlice {
  const LossSlice({
    required this.label,
    required this.count,
    required this.leadIds,
  });

  final String label;
  final int count;
  final List<String> leadIds;
}

class SourceSlice {
  const SourceSlice({
    required this.label,
    required this.count,
    required this.leadIds,
  });

  final String label;
  final int count;
  final List<String> leadIds;
}

/// Folds spelling variants of one channel onto a single bucket key, so
/// "Trade India", "Tradeindia" and "tradeindia" stop showing up as three
/// different sources. Display labels still come from the configured list in
/// `settings/sources_config` whenever a bucket matches one.
String sourceBucketKey(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Absolute time buckets for the Lead Source Report. These deliberately ignore
/// the dashboard date filter — "This Month" must always mean this month.
const List<({String key, String label})> kSourceTimeBuckets =
    <({String key, String label})>[
  (key: 'today', label: 'Today'),
  (key: 'yesterday', label: 'Yesterday'),
  (key: 'week', label: 'This Week'),
  (key: 'month', label: 'This Month'),
  (key: 'lastMonth', label: 'Last Month'),
];

/// Column order for the status view; only statuses actually present are shown.
const List<String> _sourceStatusOrder = <String>[
  'New',
  'Contacted',
  'Follow-up',
  'Proposal',
  'Technical Evaluation',
  'Query Raised',
  'Query Responded',
  'Qualified',
  'Reverse Auction(RA)',
  'Won',
  'Lost',
  'Disqualified',
  'Unspecified',
];

/// Key used for leads with no owner. Sorts last in the employee view.
const String kUnassignedUid = '__unassigned__';

/// One number in the Lead Source Report, with the leads behind it so tapping
/// it can open exactly what was counted.
class SourceCell {
  const SourceCell({required this.leadIds, required this.value});

  static const SourceCell empty =
      SourceCell(leadIds: <String>[], value: 0);

  final List<String> leadIds;
  final double value;

  int get count => leadIds.length;
  bool get isEmpty => leadIds.isEmpty;
}

/// A column in the employee view.
class SourceReportEmployee {
  const SourceReportEmployee({required this.uid, required this.name});

  final String uid;
  final String name;

  bool get isUnassigned => uid == kUnassignedUid;
}

/// One source row. Status/employee figures are a snapshot of every lead on
/// that source; time figures are absolute; won figures follow the date filter.
class SourceReportRow {
  const SourceReportRow({
    required this.source,
    required this.byTime,
    required this.byStatus,
    required this.byEmployee,
    required this.employeeByTime,
    required this.employeeByStatus,
    required this.total,
    required this.wonCount,
    required this.wonValue,
  });

  final String source;
  final Map<String, SourceCell> byTime;
  final Map<String, SourceCell> byStatus;
  final Map<String, SourceCell> byEmployee;

  /// uid -> time bucket -> cell (expanded rows in the time view).
  final Map<String, Map<String, SourceCell>> employeeByTime;

  /// uid -> status -> cell (expanded rows in the status view).
  final Map<String, Map<String, SourceCell>> employeeByStatus;

  final SourceCell total;
  final int wonCount;
  final double wonValue;

  SourceCell time(String key) => byTime[key] ?? SourceCell.empty;
  SourceCell status(String key) => byStatus[key] ?? SourceCell.empty;
  SourceCell employee(String uid) => byEmployee[uid] ?? SourceCell.empty;

  SourceCell employeeTime(String uid, String key) =>
      employeeByTime[uid]?[key] ?? SourceCell.empty;

  SourceCell employeeStatus(String uid, String key) =>
      employeeByStatus[uid]?[key] ?? SourceCell.empty;

  /// Employees that actually have leads on this source, in column order.
  List<SourceReportEmployee> ownersFrom(List<SourceReportEmployee> all) => [
        for (final e in all)
          if ((byEmployee[e.uid]?.count ?? 0) > 0) e,
      ];
}

/// Source × (time | status | employee) report backing the analytics table.
class SourceReport {
  const SourceReport({
    required this.employees,
    required this.statuses,
    required this.rows,
    required this.grandTotal,
  });

  static const SourceReport empty = SourceReport(
    employees: <SourceReportEmployee>[],
    statuses: <String>[],
    rows: <SourceReportRow>[],
    grandTotal: SourceReportRow(
      source: 'Total',
      byTime: <String, SourceCell>{},
      byStatus: <String, SourceCell>{},
      byEmployee: <String, SourceCell>{},
      employeeByTime: <String, Map<String, SourceCell>>{},
      employeeByStatus: <String, Map<String, SourceCell>>{},
      total: SourceCell.empty,
      wonCount: 0,
      wonValue: 0,
    ),
  );

  final List<SourceReportEmployee> employees;
  final List<String> statuses;
  final List<SourceReportRow> rows;
  final SourceReportRow grandTotal;

  bool get isEmpty => rows.isEmpty;
}

/// Mutable accumulator for a single cell while the leads are scanned once.
class _CellBuilder {
  final List<String> leadIds = <String>[];
  double value = 0;

  void add(String leadId, double amount) {
    leadIds.add(leadId);
    value += amount;
  }

  SourceCell freeze() => SourceCell(
        leadIds: List<String>.unmodifiable(leadIds),
        value: value,
      );
}

class _SourceRowBuilder {
  _SourceRowBuilder(this.label);

  String label;
  final Map<String, _CellBuilder> byTime = <String, _CellBuilder>{};
  final Map<String, _CellBuilder> byStatus = <String, _CellBuilder>{};
  final Map<String, _CellBuilder> byEmployee = <String, _CellBuilder>{};
  final Map<String, Map<String, _CellBuilder>> employeeByTime =
      <String, Map<String, _CellBuilder>>{};
  final Map<String, Map<String, _CellBuilder>> employeeByStatus =
      <String, Map<String, _CellBuilder>>{};
  final _CellBuilder total = _CellBuilder();
  int wonCount = 0;
  double wonValue = 0;

  static _CellBuilder _cell(Map<String, _CellBuilder> map, String key) =>
      map.putIfAbsent(key, _CellBuilder.new);

  void record({
    required String leadId,
    required double amount,
    required String uid,
    required String status,
    required List<String> timeBuckets,
  }) {
    total.add(leadId, amount);
    _cell(byStatus, status).add(leadId, amount);
    _cell(byEmployee, uid).add(leadId, amount);
    _cell(employeeByStatus.putIfAbsent(uid, () => <String, _CellBuilder>{}),
            status)
        .add(leadId, amount);
    for (final bucket in timeBuckets) {
      _cell(byTime, bucket).add(leadId, amount);
      _cell(employeeByTime.putIfAbsent(uid, () => <String, _CellBuilder>{}),
              bucket)
          .add(leadId, amount);
    }
  }

  static Map<String, SourceCell> _freezeCells(Map<String, _CellBuilder> map) =>
      Map<String, SourceCell>.unmodifiable(
        map.map((key, cell) => MapEntry(key, cell.freeze())),
      );

  static Map<String, Map<String, SourceCell>> _freezeNested(
    Map<String, Map<String, _CellBuilder>> map,
  ) =>
      Map<String, Map<String, SourceCell>>.unmodifiable(
        map.map((key, inner) => MapEntry(key, _freezeCells(inner))),
      );

  SourceReportRow freeze() => SourceReportRow(
        source: label,
        byTime: _freezeCells(byTime),
        byStatus: _freezeCells(byStatus),
        byEmployee: _freezeCells(byEmployee),
        employeeByTime: _freezeNested(employeeByTime),
        employeeByStatus: _freezeNested(employeeByStatus),
        total: total.freeze(),
        wonCount: wonCount,
        wonValue: wonValue,
      );
}

class TargetProgress {
  const TargetProgress({
    required this.employeeUid,
    required this.displayName,
    required this.actualWon,
    required this.targetAmount,
    required this.wonLeadIds,
  });

  final String employeeUid;
  final String displayName;
  final double actualWon;
  final double targetAmount;
  final List<String> wonLeadIds;
}

class MonthlySalesPoint {
  const MonthlySalesPoint({
    required this.monthIndex,
    required this.label,
    required this.amount,
    required this.leadIds,
  });

  final int monthIndex;
  final String label;
  final double amount;
  final List<String> leadIds;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.employeeUid,
    required this.displayName,
    required this.wonDeals,
    required this.wonRevenue,
    required this.winRate,
    required this.wonLeadIds,
  });

  final String employeeUid;
  final String displayName;
  final int wonDeals;
  final double wonRevenue;
  final double winRate;
  final List<String> wonLeadIds;
}

class DailyWorkReport {
  const DailyWorkReport({
    required this.employeeUid,
    required this.employeeName,
    required this.leadsAdded,
    required this.followUpsDone,
    required this.followUpsPending,
    required this.followUpsOverdue,
    required this.statusChanges,
    required this.quotesMade,
    required this.dealsWon,
    required this.dealsWonValue,
    required this.addedLeadIds,
    required this.followUpLeadIds,
    required this.pendingFollowUpLeadIds,
    required this.overdueFollowUpLeadIds,
    required this.statusChangeLeadIds,
    required this.quotedLeadIds,
    required this.wonLeadIds,
  });
  
  final String employeeUid;
  final String employeeName;
  final int leadsAdded;
  final int followUpsDone;
  final int followUpsPending;
  final int followUpsOverdue;
  final int statusChanges;
  final int quotesMade;
  final int dealsWon;
  final double dealsWonValue;

  final List<String> addedLeadIds;
  final List<String> followUpLeadIds;
  final List<String> pendingFollowUpLeadIds;
  final List<String> overdueFollowUpLeadIds;
  final List<String> statusChangeLeadIds;
  final List<String> quotedLeadIds;
  final List<String> wonLeadIds;
}

class GlobalDailySummary {
  const GlobalDailySummary({
    required this.totalLeadsAdded,
    required this.totalFollowUpsDone,
    required this.totalFollowUpsOverdue,
    required this.totalQuotesMade,
    required this.totalDealsWon,
    required this.totalValueWon,
  });

  final int totalLeadsAdded;
  final int totalFollowUpsDone;
  final int totalFollowUpsOverdue;
  final int totalQuotesMade;
  final int totalDealsWon;
  final double totalValueWon;
}

/// One employee row for the Pactech-style CRM Report.
class CrmEmployeeReport {
  const CrmEmployeeReport({
    required this.employeeUid,
    required this.employeeName,
    required this.role,
    required this.leadsAdded,
    required this.tendersAdded,
    required this.calls,
    required this.followUpsDone,
    required this.followUpsPending,
    required this.followUpsOverdue,
    required this.statusChanges,
    required this.quotesMade,
    required this.quoteValue,
    required this.dealsWon,
    required this.dealsWonValue,
    required this.tendersWon,
    required this.tendersWonValue,
    required this.pipelineValue,
    required this.addedLeadIds,
    required this.addedTenderIds,
    required this.callLeadIds,
    required this.followUpLeadIds,
    required this.pendingFollowUpLeadIds,
    required this.overdueFollowUpLeadIds,
    required this.statusChangeLeadIds,
    required this.quotedIds,
    required this.wonLeadIds,
    required this.wonTenderIds,
  });

  final String employeeUid;
  final String employeeName;
  final String role;
  final int leadsAdded;
  final int tendersAdded;

  /// Leads the rep actually worked in the period: a status update or a remark
  /// was logged on them. Counted once per lead, not once per event.
  final int calls;
  final int followUpsDone;
  final int followUpsPending;
  final int followUpsOverdue;
  final int statusChanges;
  final int quotesMade;
  final double quoteValue;
  final int dealsWon;
  final double dealsWonValue;
  final int tendersWon;
  final double tendersWonValue;
  final double pipelineValue;

  final List<String> addedLeadIds;
  final List<String> addedTenderIds;
  final List<String> callLeadIds;

  /// Leads that were due (or overdue) and got worked in the period.
  final List<String> followUpLeadIds;
  final List<String> pendingFollowUpLeadIds;
  final List<String> overdueFollowUpLeadIds;
  final List<String> statusChangeLeadIds;
  final List<String> quotedIds;
  final List<String> wonLeadIds;
  final List<String> wonTenderIds;

  /// Status changes and follow-ups done are both subsets of [calls], so only
  /// [calls] is summed here — otherwise one phone call counted three times.
  int get actionCount =>
      leadsAdded + tendersAdded + calls + quotesMade;
}

class CrmReportData {
  const CrmReportData({
    required this.rows,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final List<CrmEmployeeReport> rows;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  int get totalActions => rows.fold(0, (total, r) => total + r.actionCount);
  int get employeeCount => rows.length;
}

/// Manager Control Center: live pipeline totals, per-rep matrix, and cross-lead activity.
class ManagerDashboardData {
  const ManagerDashboardData({
    required this.totalLeads,
    required this.totalNormalLeads,
    required this.totalTenders,
    required this.statusBreakdown,
    required this.normalStatusBreakdown,
    required this.tenderStatusBreakdown,
    required this.normalStatusLeadIds,
    required this.tenderStatusLeadIds,
    required this.normalLeadIds,
    required this.tenderLeadIds,
    required this.employeeMatrix,
    required this.recentActivity,
    required this.employeePulses,
    required this.lastUpdatedAt,
    this.eventsIndexLink,
  });

  final int totalLeads;
  final int totalNormalLeads;
  final int totalTenders;

  /// Count per canonical [Lead.statuses] value (and any extra keys present in data).
  final Map<String, int> statusBreakdown;
  final Map<String, int> normalStatusBreakdown;
  final Map<String, int> tenderStatusBreakdown;

  /// Status -> lead IDs for normal (non-tender) leads.
  final Map<String, List<String>> normalStatusLeadIds;

  /// Status -> lead IDs for tender leads.
  final Map<String, List<String>> tenderStatusLeadIds;

  /// All normal lead IDs (for Total leads card).
  final List<String> normalLeadIds;

  /// All tender lead IDs (for Total tenders card).
  final List<String> tenderLeadIds;

  /// Display name -> status -> count for assigned leads.
  final Map<String, Map<String, int>> employeeMatrix;

  /// Up to 10 most recent events across all leads (newest first).
  final List<ManagerActivityEvent> recentActivity;

  /// One row per employee user document (for pulse cards).
  final List<EmployeePulse> employeePulses;

  /// Local timestamp for when this dashboard payload was fetched and computed.
  final DateTime lastUpdatedAt;

  /// Firebase console URL generated when the collection-group query needs an index.
  final String? eventsIndexLink;
}

class ManagerActivityEvent {
  const ManagerActivityEvent({
    required this.leadId,
    required this.leadCompany,
    required this.userName,
    required this.action,
    required this.description,
    required this.timestamp,
  });

  final String leadId;
  final String leadCompany;
  final String userName;
  final String action;
  final String description;
  final DateTime timestamp;
}

class EmployeePulse {
  const EmployeePulse({
    required this.uid,
    required this.displayName,
    required this.isOnline,
    required this.lastActive,
    required this.statusCounts,
    required this.hasStagnantLeads,
    this.statusLeadIds = const <String, List<String>>{},
  });

  final String uid;
  final String displayName;
  final bool isOnline;
  final DateTime? lastActive;
  final Map<String, int> statusCounts;
  final bool hasStagnantLeads;

  /// Lead ids behind each entry in [statusCounts], so tapping a number can
  /// open exactly the leads it counted. Both are built from the same pass over
  /// the data, so the tile and the list it opens can never disagree.
  final Map<String, List<String>> statusLeadIds;

  List<String> leadIdsForStatus(String status) =>
      statusLeadIds[status] ?? const <String>[];

  /// Every lead id counted for this employee, across all statuses.
  List<String> get allLeadIds =>
      statusLeadIds.values.expand((ids) => ids).toList(growable: false);
}

/// Loads leads and computes executive pipeline/revenue analytics.
class AnalyticsService {
  AnalyticsService({FirebaseFirestore? firestore, LeadService? leadService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _leadService = leadService ?? LeadService();

  final FirebaseFirestore _firestore;
  final LeadService _leadService;
  static const Duration _dashboardThrottleWindow = Duration(minutes: 5);

  StreamController<ManagerDashboardData>? _managerDashboardController;
  Timer? _dashboardPollTimer;
  int _dashboardListenerCount = 0;
  bool _dashboardFetchInProgress = false;

  ManagerDashboardData? _cachedManagerDashboardData;
  DateTime? _lastManagerDashboardFetchedAt;
  
  DateTime? _dashboardStartDate;
  DateTime? _dashboardEndDate;

  void setDashboardDateRange(DateTime? start, DateTime? end) {
    _dashboardStartDate = start;
    _dashboardEndDate = end;
    if (_dashboardListenerCount > 0) {
      unawaited(_loadManagerDashboardData(force: true));
    }
  }

  static const List<String> _monthShort = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Future<List<Lead>> _fetchLeads({String? assignedToUid}) async {
    final trimmedUid = assignedToUid?.trim();
    final snapshot = (trimmedUid != null && trimmedUid.isNotEmpty)
        ? await _firestore
              .collection('leads')
              .where('assignedTo', isEqualTo: trimmedUid)
              .get()
        : await _firestore.collection('leads').get();
    return leadsFromDocs(snapshot.docs);
  }

  Future<ExecutiveAnalytics> computeAnalytics({
    String? assignedToUid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final leads = await _fetchLeads(assignedToUid: assignedToUid);
    // A null assignedToUid IS the admin signal here: the admin dashboard omits
    // it, the employee dashboard passes their own uid.
    final scopedUid = assignedToUid?.trim() ?? '';
    final quoteAmountByLeadId = await _loadLatestQuotationAmountsByLeadId(
      isAdmin: scopedUid.isEmpty,
      currentUid: scopedUid,
    );
    final configuredSources = await SourceService.instance.getSources();
    final now = DateTime.now();
    final year = now.year;
    final startOfToday = DateTime(now.year, now.month, now.day);

    // Absolute windows for the Lead Source Report — independent of the filter.
    final startOfTomorrow = startOfToday.add(const Duration(days: 1));
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final startOfWeek =
        startOfToday.subtract(Duration(days: startOfToday.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month);
    final startOfLastMonth = DateTime(now.year, now.month - 1);

    List<String> timeBucketsFor(DateTime date) {
      final buckets = <String>[];
      if (!date.isBefore(startOfToday) && date.isBefore(startOfTomorrow)) {
        buckets.add('today');
      }
      if (!date.isBefore(startOfYesterday) && date.isBefore(startOfToday)) {
        buckets.add('yesterday');
      }
      if (!date.isBefore(startOfWeek) && date.isBefore(startOfTomorrow)) {
        buckets.add('week');
      }
      if (!date.isBefore(startOfMonth) && date.isBefore(startOfTomorrow)) {
        buckets.add('month');
      }
      if (!date.isBefore(startOfLastMonth) && date.isBefore(startOfMonth)) {
        buckets.add('lastMonth');
      }
      return buckets;
    }

    // Canonical display label per folded source key ("tradeindia" -> the
    // spelling configured in settings, not whatever an old lead happens to use).
    final canonicalSourceLabels = <String, String>{
      for (final s in configuredSources)
        if (s.trim().isNotEmpty) sourceBucketKey(s.trim()): s.trim(),
    };

    bool inDateRange(DateTime date) {
      if (startDate != null && date.isBefore(startDate)) return false;
      if (endDate != null && date.isAfter(endDate)) return false;
      return true;
    }

    bool isClosedStatus(String status) =>
        status == 'Won' ||
        status == 'Lost' ||
        status == 'Loss' ||
        status == 'Disqualified';

    double effectiveAmount(Lead lead) {
      if (lead.totalAmount > 0) return lead.totalAmount;
      return quoteAmountByLeadId[lead.id] ?? 0.0;
    }

    var active = 0;
    var pipeline = 0.0;
    var revenue = 0.0;
    var expectedRevenue = 0.0;
    var leadsAddedToday = 0;
    var followUpsToday = 0;
    var overdueFollowUps = 0;
    var closedWonCount = 0;
    var closedLostCount = 0;

    final activeLeadIds = <String>[];
    final pipelineLeadIds = <String>[];
    final expectedRevenueLeadIds = <String>[];
    final leadAmounts = <String, double>{};
    final wonLeadIds = <String>[];
    final leadsAddedTodayIds = <String>[];
    final followUpsTodayIds = <String>[];
    final overdueFollowUpIds = <String>[];
    final closedDealIds = <String>[];
    final periodCreatedLeadIds = <String>[];

    final statusLeadIds = <String, List<String>>{};
    final lossLeadIds = <String, List<String>>{};
    final sourceLeadIds = <String, List<String>>{};
    final sourceRowBuilders = <String, _SourceRowBuilder>{};
    final sourceGrandTotal = _SourceRowBuilder('Total');
    final sourceOwnerUids = <String>{};
    final winsByUid = <String, int>{};
    final winRevenueByUid = <String, double>{};
    final winLeadIdsByUid = <String, List<String>>{};
    final closedLostByUid = <String, int>{};
    final monthlyWonAmount = List<double>.filled(12, 0);
    final monthlyWonLeadIds = List.generate(12, (_) => <String>[]);
    var leadsCreatedInPeriod = 0;
    // Wins belonging to the SAME cohort as leadsCreatedInPeriod, so the
    // conversion figure divides like by like.
    var wonFromPeriodCohort = 0;

    bool countsForExpected(Lead lead) {
      final status = lead.status.trim();
      if (lead.isTender) {
        return _expectedRevenueTenderStatuses.contains(status);
      }
      return _expectedRevenueLeadStatuses.contains(status);
    }

    for (final lead in leads) {
      final amount = effectiveAmount(lead);
      leadAmounts[lead.id] = amount;
      final isClosed = isClosedStatus(lead.status);

      // ---- Lead Source Report (one pass, no extra reads) ----
      final rawSource = lead.source.trim();
      final sourceKey = rawSource.isEmpty ? '' : sourceBucketKey(rawSource);
      final sourceRow = sourceRowBuilders.putIfAbsent(
        sourceKey,
        () => _SourceRowBuilder(
          rawSource.isEmpty
              ? 'Unspecified'
              : (canonicalSourceLabels[sourceKey] ?? rawSource),
        ),
      );
      final ownerUid =
          lead.assignedTo.trim().isEmpty ? kUnassignedUid : lead.assignedTo.trim();
      sourceOwnerUids.add(ownerUid);
      final migrated = Lead.migrateLegacyTenderStatus(lead.status.trim());
      final reportStatus = migrated.isEmpty
          ? 'Unspecified'
          : (migrated == 'Loss' ? 'Lost' : migrated);
      final buckets = timeBucketsFor(lead.leadDate);
      sourceRow.record(
        leadId: lead.id,
        amount: amount,
        uid: ownerUid,
        status: reportStatus,
        timeBuckets: buckets,
      );
      sourceGrandTotal.record(
        leadId: lead.id,
        amount: amount,
        uid: ownerUid,
        status: reportStatus,
        timeBuckets: buckets,
      );

      // Pipeline Value: snapshot of ALL open leads + tenders (date filter
      // does not shrink this). Same spirit as Pactech.
      // Most open leads carry no deal value — they add nothing to the sum,
      // and [pipelineLeadIds] keeps only amount > 0 for the drill-down list.
      if (!isClosed) {
        active++;
        pipeline += amount;
        activeLeadIds.add(lead.id);
        final openStatus =
            lead.status.trim().isEmpty ? 'Unspecified' : lead.status.trim();
        statusLeadIds.putIfAbsent(openStatus, () => <String>[]).add(lead.id);

        if (amount > 0) {
          pipelineLeadIds.add(lead.id);
          // Expected Revenue: Proposal / Follow-up (leads) or tender mid-stages,
          // at full value — not New/Contacted enquiries.
          if (countsForExpected(lead)) {
            expectedRevenue += amount;
            expectedRevenueLeadIds.add(lead.id);
          }
        }
      }

      if (lead.leadDate.year == now.year &&
          lead.leadDate.month == now.month &&
          lead.leadDate.day == now.day) {
        leadsAddedToday++;
        leadsAddedTodayIds.add(lead.id);
      }

      if (lead.nextFollowUpDate != null) {
        final nextDate = lead.nextFollowUpDate!;
        final isToday = nextDate.year == now.year &&
            nextDate.month == now.month &&
            nextDate.day == now.day;
        if (!isClosed && isToday) {
          followUpsToday++;
          followUpsTodayIds.add(lead.id);
        }
        if (!isClosed && nextDate.isBefore(startOfToday)) {
          overdueFollowUps++;
          overdueFollowUpIds.add(lead.id);
        }
      }

      final createdInPeriod = inDateRange(lead.leadDate);
      if (createdInPeriod) {
        leadsCreatedInPeriod++;
        if (lead.status == 'Won') wonFromPeriodCohort++;
        periodCreatedLeadIds.add(lead.id);
        // Fold spelling variants so "Trade India" and "Tradeindia" are one slice.
        // (sourceRow.label is the canonical spelling for this folded key.)
        sourceLeadIds
            .putIfAbsent(sourceRow.label, () => <String>[])
            .add(lead.id);
      }

      // Period won: count if CRM close (lastModified) OR installation date falls in range.
      final wonCloseDate = lead.lastModified;
      final installDate = lead.installationDate;
      final wonInPeriod = lead.status == 'Won' &&
          (inDateRange(wonCloseDate) ||
              (installDate != null && inDateRange(installDate)));
      if (wonInPeriod) {
        revenue += amount;
        closedWonCount++;
        wonLeadIds.add(lead.id);
        closedDealIds.add(lead.id);
        sourceRow.wonCount++;
        sourceRow.wonValue += amount;
        sourceGrandTotal.wonCount++;
        sourceGrandTotal.wonValue += amount;
        final uid = lead.assignedTo.trim();
        if (uid.isNotEmpty) {
          winsByUid[uid] = (winsByUid[uid] ?? 0) + 1;
          winRevenueByUid[uid] = (winRevenueByUid[uid] ?? 0) + amount;
          winLeadIdsByUid.putIfAbsent(uid, () => <String>[]).add(lead.id);
        }

        // Monthly sales: prefer install month, else close month (current calendar year).
        final booked = installDate ?? wonCloseDate;
        if (booked.year == year) {
          final m = booked.month;
          if (m >= 1 && m <= 12) {
            monthlyWonAmount[m - 1] += amount;
            monthlyWonLeadIds[m - 1].add(lead.id);
          }
        }
      }

      final lostDate = lead.lastModified;
      final lostInPeriod = (lead.status == 'Lost' ||
              lead.status == 'Loss' ||
              lead.status == 'Disqualified') &&
          inDateRange(lostDate);
      if (lostInPeriod) {
        closedLostCount++;
        closedDealIds.add(lead.id);
        final uid = lead.assignedTo.trim();
        if (uid.isNotEmpty) {
          closedLostByUid[uid] = (closedLostByUid[uid] ?? 0) + 1;
        }
        final reason = lead.lossReason.trim();
        final key = reason.isEmpty ? 'Unspecified' : reason;
        lossLeadIds.putIfAbsent(key, () => <String>[]).add(lead.id);
      }
    }

    final statusSlices = _topStatusSlices(statusLeadIds);
    final lossSlices = _topLossSlices(lossLeadIds);
    final sourceSlices = _topSourceSlices(sourceLeadIds);
    final totalClosedDeals = closedWonCount + closedLostCount;
    final winRate = totalClosedDeals > 0 ? closedWonCount / totalClosedDeals : 0.0;
    final avgWonDealSize = closedWonCount > 0 ? revenue / closedWonCount : 0.0;
    // Cohort conversion: of the leads CREATED in this period, how many have
    // been won. It used to divide wins closed in the period by leads created
    // in the period — two different sets of leads, so for a short range it was
    // meaningless and could even exceed 100%.
    final conversionToWon = leadsCreatedInPeriod > 0
        ? wonFromPeriodCohort / leadsCreatedInPeriod
        : 0.0;

    final monthlySales = List<MonthlySalesPoint>.generate(
      12,
      (i) => MonthlySalesPoint(
        monthIndex: i,
        label: _monthShort[i],
        amount: monthlyWonAmount[i],
        leadIds: List<String>.unmodifiable(monthlyWonLeadIds[i]),
      ),
    );

    final sortedUids = winsByUid.keys.toList()
      ..sort((a, b) {
        final revenueCmp =
            (winRevenueByUid[b] ?? 0).compareTo(winRevenueByUid[a] ?? 0);
        if (revenueCmp != 0) return revenueCmp;
        return (winsByUid[b] ?? 0).compareTo(winsByUid[a] ?? 0);
      });

    // One name lookup for both the leaderboard and the source report columns.
    final labels = await _leadService.getUserDisplayLabels(<String>{
      ...sortedUids,
      ...sourceOwnerUids.where((uid) => uid != kUnassignedUid),
    }.toList(growable: false));

    final leaderboard = <LeaderboardEntry>[
      for (final uid in sortedUids)
        LeaderboardEntry(
          employeeUid: uid,
          displayName: labels[uid] ?? uid,
          wonDeals: winsByUid[uid] ?? 0,
          wonRevenue: winRevenueByUid[uid] ?? 0,
          winRate: _calculateWinRate(
            wonDeals: winsByUid[uid] ?? 0,
            lostDeals: closedLostByUid[uid] ?? 0,
          ),
          wonLeadIds: List<String>.unmodifiable(winLeadIdsByUid[uid] ?? const []),
        ),
    ];

    // Compute employee target progression
    final usersSnap = await _firestore.collection('users').get();
    final employees = usersSnap.docs
        .map(AppUser.fromFirestore)
        .where(
          (u) =>
              u.role == 'employee' &&
              (assignedToUid == null || assignedToUid.isEmpty || u.uid == assignedToUid),
        )
        .toList();
    final userDataById = {
      for (final doc in usersSnap.docs) doc.id: doc.data(),
    };

    final targetProgressList = <TargetProgress>[];
    for (final emp in employees) {
      final wonAmt = winRevenueByUid[emp.uid] ?? 0.0;

      final rawData = userDataById[emp.uid] ?? const <String, dynamic>{};
      final quotaValue = rawData['monthlyQuota'] ?? rawData['targetQuota'];
      final quota = quotaValue is num ? quotaValue.toDouble() : 0.0;

      targetProgressList.add(TargetProgress(
        employeeUid: emp.uid,
        displayName: emp.name.isNotEmpty ? emp.name : emp.uid,
        actualWon: wonAmt,
        targetAmount: quota,
        wonLeadIds: List<String>.unmodifiable(winLeadIdsByUid[emp.uid] ?? const []),
      ));
    }

    // ---- Freeze the Lead Source Report ----
    final reportEmployees = <SourceReportEmployee>[
      for (final uid in sourceOwnerUids.where((u) => u != kUnassignedUid))
        SourceReportEmployee(uid: uid, name: labels[uid] ?? uid),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (sourceOwnerUids.contains(kUnassignedUid)) {
      reportEmployees.add(
        const SourceReportEmployee(uid: kUnassignedUid, name: 'Unassigned'),
      );
    }

    // Keep the canonical order, drop statuses nobody uses, append strays.
    final seenStatuses = sourceGrandTotal.byStatus.keys.toSet();
    final reportStatuses = <String>[
      for (final s in _sourceStatusOrder)
        if (seenStatuses.remove(s)) s,
      ...seenStatuses.toList()..sort(),
    ];

    final reportRows = sourceRowBuilders.values
        .map((b) => b.freeze())
        .toList(growable: false)
      ..sort((a, b) {
        // 'Unspecified' always last, everything else by volume.
        if (a.source == 'Unspecified') return 1;
        if (b.source == 'Unspecified') return -1;
        return b.total.count.compareTo(a.total.count);
      });

    final sourceReport = SourceReport(
      employees: List<SourceReportEmployee>.unmodifiable(reportEmployees),
      statuses: List<String>.unmodifiable(reportStatuses),
      rows: List<SourceReportRow>.unmodifiable(reportRows),
      grandTotal: sourceGrandTotal.freeze(),
    );

    // Biggest deals first — same order Pactech uses for these drill-downs.
    int byAmountDesc(String a, String b) =>
        (leadAmounts[b] ?? 0).compareTo(leadAmounts[a] ?? 0);
    pipelineLeadIds.sort(byAmountDesc);
    expectedRevenueLeadIds.sort(byAmountDesc);

    return ExecutiveAnalytics(
      totalActiveLeads: active,
      pipelineValue: pipeline,
      totalRevenue: revenue,
      expectedRevenue: expectedRevenue,
      leadsAddedToday: leadsAddedToday,
      followUpsToday: followUpsToday,
      overdueFollowUps: overdueFollowUps,
      winRate: winRate,
      avgWonDealSize: avgWonDealSize,
      conversionToWon: conversionToWon,
      closedWonCount: closedWonCount,
      closedLostCount: closedLostCount,
      activeLeadIds: List<String>.unmodifiable(activeLeadIds),
      pipelineLeadIds: List<String>.unmodifiable(pipelineLeadIds),
      expectedRevenueLeadIds: List<String>.unmodifiable(expectedRevenueLeadIds),
      quotedLeadIds: List<String>.unmodifiable(quoteAmountByLeadId.keys),
      leadAmounts: Map<String, double>.unmodifiable(leadAmounts),
      wonLeadIds: List<String>.unmodifiable(wonLeadIds),
      leadsAddedTodayIds: List<String>.unmodifiable(leadsAddedTodayIds),
      followUpsTodayIds: List<String>.unmodifiable(followUpsTodayIds),
      overdueFollowUpIds: List<String>.unmodifiable(overdueFollowUpIds),
      closedDealIds: List<String>.unmodifiable(closedDealIds),
      periodCreatedLeadIds: List<String>.unmodifiable(periodCreatedLeadIds),
      statusSlices: statusSlices,
      lossSlices: lossSlices,
      sourceSlices: sourceSlices,
      sourceReport: sourceReport,
      monthlySales: monthlySales,
      leaderboard: leaderboard,
      employeeTargetProgress: targetProgressList,
    );
  }

  /// Latest quotation amount per lead, used only where a lead carries no
  /// Amount of its own.
  ///
  /// Two things this deliberately does NOT do any more:
  ///
  /// * It no longer takes the MAX across revisions. A revision that lowers the
  ///   price has to win, otherwise analytics books a figure the customer was
  ///   never quoted — and disagrees with the lead page, which follows the
  ///   latest revision.
  /// * It no longer swallows a permission failure into an empty map. An
  ///   employee cannot read the whole `quotations` collection (rules allow it
  ///   for admins only), so the query threw, was caught, and their dashboard
  ///   silently showed smaller pipeline and revenue than an admin's. The
  ///   employee query is now scoped to their own quotations instead.
  Future<Map<String, double>> _loadLatestQuotationAmountsByLeadId({
    required bool isAdmin,
    required String currentUid,
  }) async {
    final byLead = <String, QuotationModel>{};
    try {
      final Query<Map<String, dynamic>> query = isAdmin
          ? _firestore.collection('quotations')
          : _firestore
                .collection('quotations')
                .where('employeeId', isEqualTo: currentUid);
      final snap = await query.get();
      for (final doc in snap.docs) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          final leadId = quote.leadId.trim();
          if (leadId.isEmpty) continue;
          final current = byLead[leadId];
          if (current == null ||
              QuotationService.sortForLead(<QuotationModel>[quote, current])
                      .first ==
                  quote) {
            byLead[leadId] = quote;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AnalyticsService] Quotation amounts unavailable: $e');
    }
    return byLead.map(
      (leadId, quote) => MapEntry(leadId, quote.quoteRequest.totalAmount),
    );
  }

  Future<void> updateEmployeeQuota({
    required String employeeUid,
    required double monthlyQuota,
  }) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) {
      throw ArgumentError('employeeUid is required');
    }
    if (monthlyQuota < 0) {
      throw ArgumentError('monthlyQuota must be >= 0');
    }
    await _firestore.collection('users').doc(uid).update({
      'monthlyQuota': monthlyQuota,
      'targetQuota': monthlyQuota,
    });
  }

  Future<({List<DailyWorkReport> employeeReports, GlobalDailySummary summary})> getDailyWorkReport({
    DateTime? targetDate,
    String? forEmployeeUid,
  }) async {
    try {
      return await _getDailyWorkReportImpl(
        targetDate: targetDate,
        forEmployeeUid: forEmployeeUid,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => (
          employeeReports: const <DailyWorkReport>[],
          summary: const GlobalDailySummary(
            totalLeadsAdded: 0,
            totalFollowUpsDone: 0,
            totalFollowUpsOverdue: 0,
            totalQuotesMade: 0,
            totalDealsWon: 0,
            totalValueWon: 0,
          ),
        ),
      );
    } catch (_) {
      return (
        employeeReports: const <DailyWorkReport>[],
        summary: const GlobalDailySummary(
          totalLeadsAdded: 0,
          totalFollowUpsDone: 0,
          totalFollowUpsOverdue: 0,
          totalQuotesMade: 0,
          totalDealsWon: 0,
          totalValueWon: 0,
        ),
      );
    }
  }

  Future<({List<DailyWorkReport> employeeReports, GlobalDailySummary summary})> _getDailyWorkReportImpl({
    DateTime? targetDate,
    String? forEmployeeUid,
  }) async {
    final date = targetDate ?? DateTime.now();
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    Query<Map<String, dynamic>> leadsQuery = _firestore.collection('leads');
    if (forEmployeeUid != null) {
      leadsQuery = leadsQuery.where('assignedTo', isEqualTo: forEmployeeUid);
    }
    final leadsSnap = await leadsQuery.get();
    
    List<AppUser> employees = [];
    if (forEmployeeUid != null) {
      final userDoc = await _firestore.collection('users').doc(forEmployeeUid).get();
      if (userDoc.exists) {
        employees = [AppUser.fromFirestore(userDoc)];
      }
    } else {
      final usersSnap = await _firestore.collection('users').get();
      employees = usersSnap.docs
          .map(AppUser.fromFirestore)
          .where((u) => u.role == 'employee')
          .toList();
    }

    final leads = leadsFromDocs(leadsSnap.docs);
    
    final allEventsDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (forEmployeeUid != null) {
      // Employee scope is smaller; still cap to avoid hangs.
      final sample = leads.take(80).toList();
      for (final l in sample) {
        try {
          final evSnap = await _firestore
              .collection('leads')
              .doc(l.id)
              .collection('events')
              .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
              .where('timestamp', isLessThanOrEqualTo: endOfDay)
              .get();
          allEventsDocs.addAll(evSnap.docs);
        } catch (_) {}
      }
    } else {
      try {
        final eventsSnap = await _firestore
            .collectionGroup('events')
            .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
            .where('timestamp', isLessThanOrEqualTo: endOfDay)
            .get();
        allEventsDocs.addAll(eventsSnap.docs);
      } catch (e) {
        // Cap fallback — never scan every lead (hangs the dashboard).
        final sample = leads.take(40).toList();
        for (final l in sample) {
          try {
            final evSnap = await _firestore
                .collection('leads')
                .doc(l.id)
                .collection('events')
                .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
                .where('timestamp', isLessThanOrEqualTo: endOfDay)
                .get();
            allEventsDocs.addAll(evSnap.docs);
          } catch (_) {}
        }
      }
    }

    Query quotesQuery = _firestore.collection('quotations')
        .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
        .where('createdAt', isLessThanOrEqualTo: endOfDay);
        
    if (forEmployeeUid != null) {
      quotesQuery = quotesQuery.where('employeeId', isEqualTo: forEmployeeUid);
    }
    
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allQuotations = [];
    try {
      final quotationsSnap = await quotesQuery.get();
      allQuotations = quotationsSnap.docs as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    } catch (_) {}

    int gTotalLeadsAdded = 0;
    int gTotalFollowUpsDone = 0;
    int gTotalFollowUpsOverdue = 0;
    int gTotalQuotesMade = 0;
    int gTotalDealsWon = 0;
    double gTotalValueWon = 0;

    final employeeReports = <DailyWorkReport>[];
    final startOfToday = DateTime(date.year, date.month, date.day);

    bool isClosed(Lead lead) =>
        lead.status == 'Won' ||
        lead.status == 'Lost' ||
        lead.status == 'Loss' ||
        lead.status == 'Disqualified';

    for (final emp in employees) {
      final String uid = emp.uid;
      final String name = emp.name.isNotEmpty ? emp.name : emp.uid;

      final addedIds = <String>{};
      final followUpIds = <String>{};
      final pendingFollowUpIds = <String>{};
      final overdueFollowUpIds = <String>{};
      final statusChangeIds = <String>{};
      final quoteIds = <String>{};
      final wonIds = <String>{};
      double wonValue = 0;

      // 1. Leads added, due-today, and overdue follow-ups
      // Overdue matches Follow-ups page: nextFollowUpDate before today.
      for (final lead in leads) {
        if (lead.assignedTo == uid) {
          if (lead.leadDate.year == date.year && lead.leadDate.month == date.month && lead.leadDate.day == date.day) {
            addedIds.add(lead.id);
            gTotalLeadsAdded++;
          }
          if (lead.nextFollowUpDate != null) {
            final next = lead.nextFollowUpDate!;
            final isDueToday = next.year == date.year &&
                next.month == date.month &&
                next.day == date.day;
            if (isDueToday && !isClosed(lead)) {
              pendingFollowUpIds.add(lead.id);
            } else if (next.isBefore(startOfToday)) {
              overdueFollowUpIds.add(lead.id);
            }
          }
        }
      }

      // 2. Events (Follow-ups and Status Changes)
      for (final doc in allEventsDocs) {
        final ev = LeadEvent.fromFirestore(doc);
        final parent = doc.reference.parent.parent;
        if (parent == null) continue;
        
        final eventUid = doc.data()['userId'] as String? ?? '';
        final eventUserName = ev.userName;
        
        // Match by UID if present in event, otherwise match by employee name fallback
        if (eventUid == uid || (eventUid.isEmpty && eventUserName == name) || (eventUid.isEmpty && ev.action.contains(name))) {
          if (ev.action.toLowerCase().contains('follow-up') || ev.action.toLowerCase().contains('remark') || ev.action.toLowerCase().contains('called')) {
            followUpIds.add(parent.id);
            gTotalFollowUpsDone++;
            pendingFollowUpIds.remove(parent.id); // If done, not pending
            overdueFollowUpIds.remove(parent.id);
            // Global overdue recount from final sets below.
          }
          if (ev.action.toLowerCase().contains('status')) {
            statusChangeIds.add(parent.id);
            if (ev.description.toLowerCase().contains('won')) {
              wonIds.add(parent.id);
              final lead = leads.firstWhere((l) => l.id == parent.id, orElse: () => leads.first);
              if (lead.id == parent.id) {
                wonValue += lead.totalAmount;
                gTotalDealsWon++;
                gTotalValueWon += lead.totalAmount;
              }
            }
          }
        }
      }

      // 3. Quotations
      for (final doc in allQuotations) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          if (quote.employeeId == uid) {
            quoteIds.add(quote.id); // Storing quotation IDs instead of lead IDs for quotes
            gTotalQuotesMade++;
          }
        } catch (_) {}
      }

      employeeReports.add(DailyWorkReport(
        employeeUid: uid,
        employeeName: name,
        leadsAdded: addedIds.length,
        followUpsDone: followUpIds.length,
        followUpsPending: pendingFollowUpIds.length,
        followUpsOverdue: overdueFollowUpIds.length,
        statusChanges: statusChangeIds.length,
        quotesMade: quoteIds.length,
        dealsWon: wonIds.length,
        dealsWonValue: wonValue,
        addedLeadIds: addedIds.toList(),
        followUpLeadIds: followUpIds.toList(),
        pendingFollowUpLeadIds: pendingFollowUpIds.toList(),
        overdueFollowUpLeadIds: overdueFollowUpIds.toList(),
        statusChangeLeadIds: statusChangeIds.toList(),
        quotedLeadIds: quoteIds.toList(),
        wonLeadIds: wonIds.toList(),
      ));
      gTotalFollowUpsOverdue += overdueFollowUpIds.length;
    }

    return (
      employeeReports: employeeReports,
      summary: GlobalDailySummary(
        totalLeadsAdded: gTotalLeadsAdded,
        totalFollowUpsDone: gTotalFollowUpsDone,
        totalFollowUpsOverdue: gTotalFollowUpsOverdue,
        totalQuotesMade: gTotalQuotesMade,
        totalDealsWon: gTotalDealsWon,
        totalValueWon: gTotalValueWon,
      ),
    );
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static bool _dateInRange(DateTime value, DateTime start, DateTime end) {
    final day = _dayStart(value);
    return !day.isBefore(_dayStart(start)) && !day.isAfter(_dayStart(end));
  }

  Future<CrmReportData> getCrmReport({
    required DateTime start,
    required DateTime end,
    String? forEmployeeUid,
  }) async {
    try {
      return await _getCrmReportImpl(
        start: start,
        end: end,
        forEmployeeUid: forEmployeeUid,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => CrmReportData(
          rows: const [],
          rangeStart: start,
          rangeEnd: end,
        ),
      );
    } catch (_) {
      return CrmReportData(rows: const [], rangeStart: start, rangeEnd: end);
    }
  }

  Future<CrmReportData> _getCrmReportImpl({
    required DateTime start,
    required DateTime end,
    String? forEmployeeUid,
  }) async {
    final rangeStart = _dayStart(start);
    final rangeEnd = _dayEnd(end);

    Query<Map<String, dynamic>> leadsQuery = _firestore.collection('leads');
    if (forEmployeeUid != null) {
      leadsQuery = leadsQuery.where('assignedTo', isEqualTo: forEmployeeUid);
    }
    final leadsSnap = await leadsQuery.get();
    final leads = leadsFromDocs(leadsSnap.docs);

    List<AppUser> employees = [];
    if (forEmployeeUid != null) {
      final userDoc = await _firestore
          .collection('users')
          .doc(forEmployeeUid)
          .get();
      if (userDoc.exists) {
        employees = [AppUser.fromFirestore(userDoc)];
      } else {
        employees = [
          AppUser(uid: forEmployeeUid, name: 'You', role: 'employee'),
        ];
      }
    } else {
      final usersSnap = await _firestore.collection('users').get();
      final allUsers = usersSnap.docs.map(AppUser.fromFirestore).toList();
      final userMap = {for (final u in allUsers) u.uid: u};

      final assignedUids = leads
          .map((l) => l.assignedTo.trim())
          .where((u) => u.isNotEmpty)
          .toSet();

      final matched = <AppUser>[];
      for (final u in allUsers) {
        final r = (u.role ?? '').trim().toLowerCase();
        if (r == 'employee' ||
            r == 'sales' ||
            r == 'staff' ||
            assignedUids.contains(u.uid) ||
            r.isEmpty) {
          if (r != 'admin' || assignedUids.contains(u.uid)) {
            matched.add(u);
          }
        }
      }
      for (final uid in assignedUids) {
        if (!matched.any((e) => e.uid == uid)) {
          final u = userMap[uid];
          if (u != null) {
            matched.add(u);
          } else {
            matched.add(AppUser(uid: uid, name: uid, role: 'employee'));
          }
        }
      }
      employees = matched;
    }

    final allEventsDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    bool collectionGroupSucceeded = false;
    try {
      final eventsSnap = await _firestore
          .collectionGroup('events')
          .where('timestamp', isGreaterThanOrEqualTo: rangeStart)
          .where('timestamp', isLessThanOrEqualTo: rangeEnd)
          .get();
      allEventsDocs.addAll(eventsSnap.docs);
      collectionGroupSucceeded = true;
    } catch (_) {}

    if (!collectionGroupSucceeded) {
      final activeLeads = leads.where((l) {
        if (_dateInRange(l.lastModified, rangeStart, rangeEnd)) return true;
        if (_dateInRange(l.leadDate, rangeStart, rangeEnd)) return true;
        if (_dateInRange(l.createdAt, rangeStart, rangeEnd)) return true;
        if (l.nextFollowUpDate != null &&
            _dateInRange(l.nextFollowUpDate!, rangeStart, rangeEnd)) {
          return true;
        }
        return false;
      }).toList();

      final recentCutoff = rangeStart.subtract(const Duration(days: 2));
      for (final l in leads) {
        if (!activeLeads.contains(l) && l.lastModified.isAfter(recentCutoff)) {
          activeLeads.add(l);
        }
      }

      await Future.wait(
        activeLeads.take(30).map((l) async {
          try {
            final evSnap = await _firestore
                .collection('leads')
                .doc(l.id)
                .collection('events')
                .where('timestamp', isGreaterThanOrEqualTo: rangeStart)
                .where('timestamp', isLessThanOrEqualTo: rangeEnd)
                .get();
            allEventsDocs.addAll(evSnap.docs);
          } catch (_) {}
        }),
      );
    }

    Query quotesQuery = _firestore
        .collection('quotations')
        .where('createdAt', isGreaterThanOrEqualTo: rangeStart)
        .where('createdAt', isLessThanOrEqualTo: rangeEnd);
    if (forEmployeeUid != null) {
      quotesQuery = quotesQuery.where('employeeId', isEqualTo: forEmployeeUid);
    }

    List<QueryDocumentSnapshot<Map<String, dynamic>>> allQuotations = [];
    try {
      final quotationsSnap = await quotesQuery.get();
      allQuotations =
          quotationsSnap.docs as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    } catch (_) {}

    bool isClosed(Lead lead) =>
        lead.status == 'Won' ||
        lead.status == 'Lost' ||
        lead.status == 'Loss' ||
        lead.status == 'Disqualified';

    final rows = <CrmEmployeeReport>[];
    for (final emp in employees) {
      final uid = emp.uid;
      final name = emp.name.isNotEmpty ? emp.name : emp.uid;
      final role = (emp.role ?? 'employee').trim();

      final addedLeadIds = <String>{};
      final addedTenderIds = <String>{};
      final callIds = <String>{};
      final rescheduledIds = <String>{};
      final wasDueIds = <String>{};
      final followUpIds = <String>{};
      final pendingFollowUpIds = <String>{};
      final overdueFollowUpIds = <String>{};
      final statusChangeIds = <String>{};
      final quoteIds = <String>{};
      final wonLeadIds = <String>{};
      final wonTenderIds = <String>{};
      var wonLeadValue = 0.0;
      var wonTenderValue = 0.0;
      var quoteValue = 0.0;
      var pipelineValue = 0.0;

      for (final lead in leads) {
        if (lead.assignedTo != uid) continue;

        if (_dateInRange(lead.leadDate, rangeStart, rangeEnd) ||
            _dateInRange(lead.createdAt, rangeStart, rangeEnd)) {
          if (lead.isTender) {
            addedTenderIds.add(lead.id);
          } else {
            addedLeadIds.add(lead.id);
          }
        }

        if (!isClosed(lead)) {
          pipelineValue += lead.totalAmount;
        }

        if (lead.nextFollowUpDate != null) {
          final next = lead.nextFollowUpDate!;
          if (!next.isAfter(rangeEnd)) {
            wasDueIds.add(lead.id);
          }
          if (!isClosed(lead)) {
            if (_dateInRange(next, rangeStart, rangeEnd)) {
              pendingFollowUpIds.add(lead.id);
            } else if (next.isBefore(rangeStart)) {
              overdueFollowUpIds.add(lead.id);
            }
          }
        } else if (!isClosed(lead) &&
            lead.status.trim().toLowerCase() == 'follow-up') {
          pendingFollowUpIds.add(lead.id);
        }
      }

      for (final doc in allEventsDocs) {
        final ev = LeadEvent.fromFirestore(doc);
        final parent = doc.reference.parent.parent;
        if (parent == null) continue;

        final eventUid = ev.userId;
        final eventUserName = ev.userName;
        final matches =
            eventUid == uid ||
            (eventUid.isEmpty && eventUserName == name) ||
            (eventUid.isEmpty && ev.action.contains(name));
        if (!matches) continue;

        final action = ev.action.toLowerCase();
        if (ev.isLeadTouch ||
            ev.isFollowUpScheduling ||
            action.contains('follow-up') ||
            action.contains('call') ||
            action.contains('note') ||
            action.contains('remark')) {
          callIds.add(parent.id);
        }
        if (ev.isFollowUpScheduling || action.contains('follow-up')) {
          rescheduledIds.add(parent.id);
          followUpIds.add(parent.id);
        }
        if (action.contains('status')) {
          statusChangeIds.add(parent.id);
          if (ev.description.toLowerCase().contains('won')) {
            Lead? matched;
            for (final l in leads) {
              if (l.id == parent.id) {
                matched = l;
                break;
              }
            }
            if (matched != null) {
              if (matched.isTender) {
                wonTenderIds.add(parent.id);
                wonTenderValue += matched.totalAmount;
              } else {
                wonLeadIds.add(parent.id);
                wonLeadValue += matched.totalAmount;
              }
            }
          }
        }
      }

      for (final id in callIds) {
        if (wasDueIds.contains(id) || rescheduledIds.contains(id)) {
          followUpIds.add(id);
        }
      }
      pendingFollowUpIds.removeAll(followUpIds);
      overdueFollowUpIds.removeAll(followUpIds);

      for (final doc in allQuotations) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          if (quote.employeeId == uid ||
              quote.employeeName.toLowerCase() == name.toLowerCase()) {
            quoteIds.add(quote.id);
            quoteValue += quote.quoteRequest.totalAmount;
          }
        } catch (_) {}
      }

      rows.add(
        CrmEmployeeReport(
          employeeUid: uid,
          employeeName: name,
          role: role,
          leadsAdded: addedLeadIds.length,
          tendersAdded: addedTenderIds.length,
          calls: callIds.length,
          followUpsDone: followUpIds.length,
          followUpsPending: pendingFollowUpIds.length,
          followUpsOverdue: overdueFollowUpIds.length,
          statusChanges: statusChangeIds.length,
          quotesMade: quoteIds.length,
          quoteValue: quoteValue,
          dealsWon: wonLeadIds.length,
          dealsWonValue: wonLeadValue,
          tendersWon: wonTenderIds.length,
          tendersWonValue: wonTenderValue,
          pipelineValue: pipelineValue,
          addedLeadIds: addedLeadIds.toList(),
          addedTenderIds: addedTenderIds.toList(),
          callLeadIds: callIds.toList(),
          followUpLeadIds: followUpIds.toList(),
          pendingFollowUpLeadIds: pendingFollowUpIds.toList(),
          overdueFollowUpLeadIds: overdueFollowUpIds.toList(),
          statusChangeLeadIds: statusChangeIds.toList(),
          quotedIds: quoteIds.toList(),
          wonLeadIds: wonLeadIds.toList(),
          wonTenderIds: wonTenderIds.toList(),
        ),
      );
    }

    rows.sort((a, b) => b.actionCount.compareTo(a.actionCount));

    return CrmReportData(
      rows: rows,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  /// Live daily action data for the Daily Action Cockpit container.
  Future<DailyCockpitPayload> getDailyCockpitData({
    String? forEmployeeUid,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart.subtract(const Duration(milliseconds: 1));

    Query<Map<String, dynamic>> leadsQuery = _firestore.collection('leads');
    if (forEmployeeUid != null) {
      leadsQuery = leadsQuery.where('assignedTo', isEqualTo: forEmployeeUid);
    }
    final leadsSnap = await leadsQuery.get();
    final allLeads = leadsFromDocs(leadsSnap.docs);
    final leadsMap = {for (final l in allLeads) l.id: l};

    List<AppUser> employees = [];
    if (forEmployeeUid != null) {
      final userDoc =
          await _firestore.collection('users').doc(forEmployeeUid).get();
      if (userDoc.exists) {
        employees = [AppUser.fromFirestore(userDoc)];
      } else {
        employees = [
          AppUser(uid: forEmployeeUid, name: 'You', role: 'employee'),
        ];
      }
    } else {
      final usersSnap = await _firestore.collection('users').get();
      final allUsers = usersSnap.docs.map(AppUser.fromFirestore).toList();
      final userMap = {for (final u in allUsers) u.uid: u};
      final assignedUids = allLeads
          .map((l) => l.assignedTo.trim())
          .where((u) => u.isNotEmpty)
          .toSet();

      final matched = <AppUser>[];
      for (final u in allUsers) {
        final r = (u.role ?? '').trim().toLowerCase();
        if (r == 'employee' ||
            r == 'sales' ||
            r == 'staff' ||
            assignedUids.contains(u.uid) ||
            r.isEmpty) {
          if (r != 'admin' || assignedUids.contains(u.uid)) {
            matched.add(u);
          }
        }
      }
      for (final uid in assignedUids) {
        if (!matched.any((e) => e.uid == uid)) {
          final u = userMap[uid];
          if (u != null) {
            matched.add(u);
          } else {
            matched.add(AppUser(uid: uid, name: uid, role: 'employee'));
          }
        }
      }
      employees = matched;
    }

    Query quotesQuery = _firestore
        .collection('quotations')
        .where('createdAt', isGreaterThanOrEqualTo: yesterdayStart);
    if (forEmployeeUid != null) {
      quotesQuery = quotesQuery.where('employeeId', isEqualTo: forEmployeeUid);
    }

    final warnings = <String>[];

    final quotes = <QuotationModel>[];
    try {
      final quotesSnap = await quotesQuery.get();
      for (final doc in quotesSnap.docs) {
        try {
          quotes.add(QuotationModel.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>));
        } catch (_) {}
      }
    } catch (e) {
      // Scoped to an employee this is equality + range on different fields,
      // which needs the quotations(employeeId, createdAt) composite index.
      // Without it the whole query fails, and swallowing that made the Today
      // Done tab look like a day with no quotations.
      debugPrint('[Cockpit] Quotations unavailable: $e');
      warnings.add(
        "Quotations could not be loaded, so today's quote activity is missing.",
      );
    }

    final recentEvents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    bool cgSucceeded = false;
    try {
      final evSnap = await _firestore
          .collectionGroup('events')
          .where('timestamp', isGreaterThanOrEqualTo: yesterdayStart)
          .where('timestamp', isLessThanOrEqualTo: todayEnd)
          .get();
      recentEvents.addAll(evSnap.docs);
      cgSucceeded = true;
    } catch (_) {}

    if (!cgSucceeded) {
      // collectionGroup('events') is admin-only under firestore.rules, so this
      // is the path every employee takes.
      final cutoff = yesterdayStart.subtract(const Duration(hours: 12));
      final candidateLeads =
          allLeads.where((l) => l.lastModified.isAfter(cutoff)).toList()
            // Most recently touched first, so a cap keeps the useful subset
            // rather than an arbitrary one — the mistake the old
            // `leads.take(80)` made in the CRM report.
            ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
      const perLeadCap = 200;
      if (candidateLeads.length > perLeadCap) {
        warnings.add(
          "Only the $perLeadCap most recently updated leads were checked for "
          'activity.',
        );
      }
      // Parallel fetch — all at once instead of sequential round-trips
      final snapshots = await Future.wait(
        candidateLeads.take(perLeadCap).map((l) async {
          try {
            return await _firestore
                .collection('leads')
                .doc(l.id)
                .collection('events')
                .where('timestamp', isGreaterThanOrEqualTo: yesterdayStart)
                .where('timestamp', isLessThanOrEqualTo: todayEnd)
                .get();
          } catch (_) {
            return null;
          }
        }),
      );
      for (final snap in snapshots) {
        if (snap != null) recentEvents.addAll(snap.docs);
      }
    }

    bool isClosed(Lead lead) =>
        lead.status == 'Won' ||
        lead.status == 'Lost' ||
        lead.status == 'Loss' ||
        lead.status == 'Disqualified';

    final summaries = <EmployeeDailySummary>[];

    for (final emp in employees) {
      final uid = emp.uid;
      final name = emp.name.isNotEmpty ? emp.name : emp.uid;
      final role = (emp.role ?? 'employee').trim();

      final empLeads = allLeads.where((l) => l.assignedTo == uid).toList();

      final pendingItems = <DailyPendingItem>[];
      for (final lead in empLeads) {
        if (isClosed(lead)) continue;

        if (lead.nextFollowUpDate != null) {
          final next = lead.nextFollowUpDate!;
          if (next.isBefore(todayStart)) {
            final days = todayStart.difference(next).inDays;
            pendingItems.add(DailyPendingItem(
              lead: lead,
              type: DailyPendingType.overdue,
              daysOverdue: days <= 0 ? 1 : days,
            ));
          } else if (_dateInRange(next, todayStart, todayEnd)) {
            pendingItems.add(DailyPendingItem(
              lead: lead,
              type: DailyPendingType.dueToday,
            ));
          }
        } else if (lead.status.trim().toLowerCase() == 'follow-up') {
          pendingItems.add(DailyPendingItem(
            lead: lead,
            type: DailyPendingType.missingDate,
          ));
        } else {
          final daysInactive = now.difference(lead.lastModified).inDays;
          // A quoted lead that has gone quiet is the warmest thing in this
          // list, so it is called out separately from a plain stale lead.
          //
          // lastModified is the proxy for "nothing has happened since the
          // quote": linking a quotation writes the lead, and so does every
          // later touch. It needs no extra read, unlike fetching each lead's
          // quotation history.
          final hasQuote = lead.quotationRefNo.trim().isNotEmpty ||
              lead.quotationId.trim().isNotEmpty;
          if (hasQuote && daysInactive >= 5) {
            pendingItems.add(DailyPendingItem(
              lead: lead,
              type: DailyPendingType.awaitingQuoteReply,
              daysInactive: daysInactive,
            ));
          } else if (daysInactive >= 7) {
            pendingItems.add(DailyPendingItem(
              lead: lead,
              type: DailyPendingType.stale,
              daysInactive: daysInactive,
            ));
          }
        }
      }

      pendingItems.sort((a, b) {
        // Quoted-but-quiet ranks just under the dated work: the deal is
        // further along than anything below it.
        const rank = {
          DailyPendingType.overdue: 0,
          DailyPendingType.dueToday: 1,
          DailyPendingType.awaitingQuoteReply: 2,
          DailyPendingType.missingDate: 3,
          DailyPendingType.stale: 4,
        };
        final rA = rank[a.type] ?? 4;
        final rB = rank[b.type] ?? 4;
        if (rA != rB) return rA.compareTo(rB);
        if (a.type == DailyPendingType.overdue) {
          return b.daysOverdue.compareTo(a.daysOverdue);
        }
        return a.lead.company
            .toLowerCase()
            .compareTo(b.lead.company.toLowerCase());
      });

      final todayActivities = <DailyCompletedActivity>[];
      final yesterdayActivities = <DailyCompletedActivity>[];
      var todayQuotesVal = 0.0;

      for (final q in quotes) {
        if (q.employeeId == uid ||
            q.employeeName.toLowerCase() == name.toLowerCase()) {
          final isToday = _dateInRange(q.createdAt, todayStart, todayEnd);
          final isYesterday =
              _dateInRange(q.createdAt, yesterdayStart, yesterdayEnd);
          if (!isToday && !isYesterday) continue;

          final matchedLead = leadsMap[q.leadId];
          final compName = q.quoteRequest.companyName.isNotEmpty
              ? q.quoteRequest.companyName
              : (matchedLead?.company ?? 'ATS Customer');
          final client = q.quoteRequest.customerName.isNotEmpty
              ? q.quoteRequest.customerName
              : (matchedLead?.name ?? '');
          final phone = q.quoteRequest.phone.isNotEmpty
              ? q.quoteRequest.phone
              : (matchedLead?.phone ?? '');
          final amount = q.quoteRequest.totalAmount;

          final act = DailyCompletedActivity(
            id: q.id,
            type: DailyActivityType.quotation,
            leadId: q.leadId,
            title: 'Quotation ${q.currentRefNo} Sent',
            subtitle: '₹${amount.toStringAsFixed(0)} · $compName',
            companyName: compName,
            clientName: client,
            phone: phone,
            timestamp: q.createdAt,
            employeeUid: uid,
            employeeName: name,
            quotationRefNo: q.currentRefNo,
            quotation: q,
          );

          if (isToday) {
            todayActivities.add(act);
            todayQuotesVal += amount;
          } else {
            yesterdayActivities.add(act);
          }
        }
      }

      for (final doc in recentEvents) {
        final ev = LeadEvent.fromFirestore(doc);
        final parent = doc.reference.parent.parent;
        if (parent == null) continue;

        final eventUid = ev.userId;
        final eventUserName = ev.userName;
        final matches = eventUid == uid ||
            (eventUid.isEmpty && eventUserName == name) ||
            (eventUid.isEmpty && ev.action.contains(name));
        if (!matches) continue;

        final isToday = _dateInRange(ev.timestamp, todayStart, todayEnd);
        final isYesterday =
            _dateInRange(ev.timestamp, yesterdayStart, yesterdayEnd);
        if (!isToday && !isYesterday) continue;

        final matchedLead = leadsMap[parent.id];
        final compName = matchedLead?.company ?? 'Lead #${parent.id}';
        final client = matchedLead?.name ?? '';
        final phone = matchedLead?.phone ?? '';

        final action = ev.action.toLowerCase();
        DailyActivityType aType = DailyActivityType.note;
        String title = ev.action;
        if (ev.isFollowUpScheduling || action.contains('follow-up')) {
          aType = DailyActivityType.followUp;
          title = 'Follow-up: ${ev.description}';
        } else if (action.contains('status')) {
          aType = DailyActivityType.statusChange;
          title = ev.description.isNotEmpty ? ev.description : 'Status updated';
        } else if (action.contains('create')) {
          aType = DailyActivityType.leadCreated;
          title = 'New lead added';
        }

        final act = DailyCompletedActivity(
          id: doc.id,
          type: aType,
          leadId: parent.id,
          title: title,
          subtitle: '$compName · ${ev.userName}',
          companyName: compName,
          clientName: client,
          phone: phone,
          timestamp: ev.timestamp,
          employeeUid: uid,
          employeeName: name,
        );

        if (isToday) {
          todayActivities.add(act);
        } else {
          yesterdayActivities.add(act);
        }
      }

      todayActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      yesterdayActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final dueCount =
          pendingItems.where((p) => p.type == DailyPendingType.dueToday).length;
      final overdueCount =
          pendingItems.where((p) => p.type == DailyPendingType.overdue).length;

      summaries.add(
        EmployeeDailySummary(
          employeeUid: uid,
          employeeName: name,
          role: role,
          pendingItems: pendingItems,
          todayActivities: todayActivities,
          yesterdayActivities: yesterdayActivities,
          dueTodayCount: dueCount,
          overdueCount: overdueCount,
          todayDoneCount: todayActivities.length,
          todayQuotesValue: todayQuotesVal,
        ),
      );
    }

    return DailyCockpitPayload(
      employeeSummaries: summaries,
      timestamp: now,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  /// Throttled stream for the manager strip above the Kanban board.
  ///
  /// Avoids raw realtime snapshots to reduce read frequency, emits cached data
  /// for up to five minutes, and allows manual refresh through
  /// [refreshManagerDashboardData].
  Stream<ManagerDashboardData> getManagerDashboardData() {
    _managerDashboardController ??=
        StreamController<ManagerDashboardData>.broadcast(
          onListen: _onDashboardListen,
          onCancel: _onDashboardCancel,
        );
    return _managerDashboardController!.stream;
  }

  Future<void> refreshManagerDashboardData({bool force = true}) async {
    await _loadManagerDashboardData(force: force);
  }

  void _onDashboardListen() {
    _dashboardListenerCount++;
    final cached = _cachedManagerDashboardData;
    if (cached != null) {
      _managerDashboardController?.add(cached);
    }

    if (_dashboardListenerCount == 1) {
      unawaited(_loadManagerDashboardData());
      _dashboardPollTimer?.cancel();
      _dashboardPollTimer = Timer.periodic(_dashboardThrottleWindow, (_) {
        unawaited(_loadManagerDashboardData(force: true));
      });
    }
  }

  void _onDashboardCancel() {
    _dashboardListenerCount--;
    if (_dashboardListenerCount > 0) return;
    _dashboardListenerCount = 0;
    _dashboardPollTimer?.cancel();
    _dashboardPollTimer = null;
  }

  Future<void> _loadManagerDashboardData({bool force = false}) async {
    if (_dashboardFetchInProgress) return;
    final now = DateTime.now();
    final hasFreshCache =
        !force &&
        _cachedManagerDashboardData != null &&
        _lastManagerDashboardFetchedAt != null &&
        now.difference(_lastManagerDashboardFetchedAt!) <
            _dashboardThrottleWindow;
    if (hasFreshCache) {
      _managerDashboardController?.add(_cachedManagerDashboardData!);
      return;
    }

    _dashboardFetchInProgress = true;
    try {
      final leadsSnap = await _firestore.collection('leads').get();
      final usersSnap = await _firestore.collection('users').get();

      final leads = leadsFromDocs(leadsSnap.docs);
      final eventFetch = await _fetchRecentEventDocs(leads);

      List<QueryDocumentSnapshot<Map<String, dynamic>>> quotationDocs =
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        final quotationSnap = await _firestore
            .collection('quotations')
            .orderBy('createdAt', descending: true)
            .limit(15)
            .get();
        quotationDocs = quotationSnap.docs;
      } catch (_) {}

      final merged = _buildManagerDashboard(
        leadsSnap: leadsSnap,
        usersSnap: usersSnap,
        eventDocs: eventFetch.docs,
        quotationDocs: quotationDocs,
        eventsIndexLink: eventFetch.indexLink,
        lastUpdatedAt: now,
        startDate: _dashboardStartDate,
        endDate: _dashboardEndDate,
      );

      _cachedManagerDashboardData = merged;
      _lastManagerDashboardFetchedAt = now;
      _managerDashboardController?.add(merged);
    } catch (error, stackTrace) {
      _managerDashboardController?.addError(error, stackTrace);
    } finally {
      _dashboardFetchInProgress = false;
    }
  }

  Future<({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String? indexLink})>
  _fetchRecentEventDocs(List<Lead> leads) async {
    String? indexLink;

    try {
      final snap = await _firestore
          .collectionGroup('events')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        return (docs: snap.docs, indexLink: null);
      }
    } catch (error) {
      indexLink = _extractIndexLink(error);
    }

    try {
      final snap = await _firestore.collectionGroup('events').limit(50).get();
      if (snap.docs.isNotEmpty) {
        return (docs: snap.docs, indexLink: indexLink);
      }
    } catch (error) {
      indexLink ??= _extractIndexLink(error);
    }

    final sortedLeads = List<Lead>.from(leads)
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    final collected = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final lead in sortedLeads.take(25)) {
      try {
        final snap = await _firestore
            .collection('leads')
            .doc(lead.id)
            .collection('events')
            .orderBy('timestamp', descending: true)
            .limit(3)
            .get();
        collected.addAll(snap.docs);
      } catch (_) {
        try {
          final snap = await _firestore
              .collection('leads')
              .doc(lead.id)
              .collection('events')
              .limit(3)
              .get();
          collected.addAll(snap.docs);
        } catch (_) {}
      }
    }

    return (docs: collected, indexLink: indexLink);
  }

  ManagerDashboardData _buildManagerDashboard({
    required QuerySnapshot<Map<String, dynamic>> leadsSnap,
    required QuerySnapshot<Map<String, dynamic>> usersSnap,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> eventDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> quotationDocs,
    required String? eventsIndexLink,
    required DateTime lastUpdatedAt,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    var leads = leadsFromDocs(leadsSnap.docs);
    if (startDate != null || endDate != null) {
      leads = leads.where((l) {
        if (startDate != null && l.leadDate.isBefore(startDate)) return false;
        if (endDate != null && l.leadDate.isAfter(endDate)) return false;
        return true;
      }).toList();
    }

    final usersByUid = <String, AppUser>{
      for (final d in usersSnap.docs) d.id: AppUser.fromFirestore(d),
    };

    final statusBreakdown = <String, int>{for (final s in Lead.statuses) s: 0, for (final s in Lead.tenderStatuses) s: 0};
    final normalStatusBreakdown = <String, int>{for (final s in Lead.statuses) s: 0};
    final tenderStatusBreakdown = <String, int>{for (final s in Lead.tenderStatuses) s: 0};
    final normalStatusLeadIds = <String, List<String>>{};
    final tenderStatusLeadIds = <String, List<String>>{};
    final normalLeadIds = <String>[];
    final tenderLeadIds = <String>[];
    
    int totalNormalLeads = 0;
    int totalTenders = 0;

    for (final l in leads) {
      statusBreakdown[l.status] = (statusBreakdown[l.status] ?? 0) + 1;
      if (l.isTender) {
        totalTenders++;
        tenderStatusBreakdown[l.status] = (tenderStatusBreakdown[l.status] ?? 0) + 1;
        tenderLeadIds.add(l.id);
        tenderStatusLeadIds.putIfAbsent(l.status, () => <String>[]).add(l.id);
      } else {
        totalNormalLeads++;
        normalStatusBreakdown[l.status] = (normalStatusBreakdown[l.status] ?? 0) + 1;
        normalLeadIds.add(l.id);
        normalStatusLeadIds.putIfAbsent(l.status, () => <String>[]).add(l.id);
      }
    }

    final employeeMatrix = <String, Map<String, int>>{};
    final statusCountsByUid = <String, Map<String, int>>{};
    final statusLeadIdsByUid = <String, Map<String, List<String>>>{};
    final stagnantLeadsByUid = <String, bool>{};
    final stagnationCutoff = DateTime.now().subtract(const Duration(hours: 24));
    for (final l in leads) {
      final uid = l.assignedTo.trim();
      final name = uid.isEmpty
          ? 'Unassigned'
          : (usersByUid[uid]?.name.isNotEmpty == true
                ? usersByUid[uid]!.name
                : (uid.length > 10 ? '${uid.substring(0, 10)}…' : uid));
      employeeMatrix.putIfAbsent(name, () => <String, int>{});
      final m = employeeMatrix[name]!;
      m[l.status] = (m[l.status] ?? 0) + 1;

      if (uid.isNotEmpty) {
        final perUidCounts = statusCountsByUid.putIfAbsent(
          uid,
          () => <String, int>{},
        );
        perUidCounts[l.status] = (perUidCounts[l.status] ?? 0) + 1;
        // Same pass, same filter — so the drill-down list always matches the
        // number shown on the tile.
        statusLeadIdsByUid
            .putIfAbsent(uid, () => <String, List<String>>{})
            .putIfAbsent(l.status, () => <String>[])
            .add(l.id);
        if (l.status == 'New' && l.leadDate.isBefore(stagnationCutoff)) {
          stagnantLeadsByUid[uid] = true;
        }
      }
    }

    final leadById = {for (final l in leads) l.id: l};
    final recentActivity = <ManagerActivityEvent>[];
    for (final doc in eventDocs) {
      final parent = doc.reference.parent.parent;
      if (parent == null) continue;
      final leadId = parent.id;
      final lead = leadById[leadId];
      final ev = LeadEvent.fromFirestore(doc);
      final company = (lead?.company ?? '').trim();
      final timestamp = ev.timestamp.millisecondsSinceEpoch <= 0
          ? (lead?.lastModified ?? ev.timestamp)
          : ev.timestamp;
      if (startDate != null && timestamp.isBefore(startDate)) continue;
      if (endDate != null && timestamp.isAfter(endDate)) continue;

      recentActivity.add(
        ManagerActivityEvent(
          leadId: leadId,
          leadCompany: company.isEmpty ? 'Lead' : company,
          userName: ev.userName,
          action: ev.action,
          description: ev.description,
          timestamp: timestamp,
        ),
      );
    }

    for (final doc in quotationDocs) {
      try {
        final quote = QuotationModel.fromFirestore(doc);
        final company = quote.quoteRequest.companyName.trim();
        final customer = quote.quoteRequest.customerName.trim();
        final label = company.isNotEmpty
            ? company
            : (customer.isNotEmpty ? customer : 'Customer');
        if (startDate != null && quote.createdAt.isBefore(startDate)) continue;
        if (endDate != null && quote.createdAt.isAfter(endDate)) continue;

        recentActivity.add(
          ManagerActivityEvent(
            leadId: quote.leadId,
            leadCompany: label,
            userName: quote.employeeName,
            action: 'Quotation Created',
            description: quote.currentRefNo,
            timestamp: quote.createdAt,
          ),
        );
      } catch (_) {}
    }

    if (recentActivity.isEmpty) {
      final sortedLeads = List<Lead>.from(leads)
        ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
      for (final lead in sortedLeads.take(10)) {
        final company = lead.company.trim();
        final isNew =
            lead.lastModified.difference(lead.createdAt).inMinutes.abs() < 2;
        recentActivity.add(
          ManagerActivityEvent(
            leadId: lead.id,
            leadCompany: company.isEmpty ? 'Lead' : company,
            userName: lead.creatorName.isNotEmpty ? lead.creatorName : 'Team',
            action: isNew ? 'Created' : 'Updated',
            description: isNew ? 'Lead created' : 'Status: ${lead.status}',
            timestamp: lead.lastModified,
          ),
        );
      }
    }

    recentActivity.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final topRecent = recentActivity.length <= 10
        ? recentActivity
        : recentActivity.sublist(0, 10);

    final employees =
        usersSnap.docs
            .map(AppUser.fromFirestore)
            .where((u) => u.role == 'employee')
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final pulses = <EmployeePulse>[];
    for (final u in employees) {
      final displayName = u.name.isNotEmpty ? u.name : u.uid;
      pulses.add(
        EmployeePulse(
          uid: u.uid,
          displayName: displayName,
          isOnline: u.isOnline,
          lastActive: u.lastActive,
          statusCounts: Map<String, int>.from(
            statusCountsByUid[u.uid] ?? const <String, int>{},
          ),
          hasStagnantLeads: stagnantLeadsByUid[u.uid] ?? false,
          statusLeadIds: <String, List<String>>{
            for (final entry
                in (statusLeadIdsByUid[u.uid] ??
                        const <String, List<String>>{})
                    .entries)
              entry.key: List<String>.unmodifiable(entry.value),
          },
        ),
      );
    }

    return ManagerDashboardData(
      totalLeads: leads.length,
      totalNormalLeads: totalNormalLeads,
      totalTenders: totalTenders,
      statusBreakdown: statusBreakdown,
      normalStatusBreakdown: normalStatusBreakdown,
      tenderStatusBreakdown: tenderStatusBreakdown,
      normalStatusLeadIds: {
        for (final e in normalStatusLeadIds.entries)
          e.key: List<String>.unmodifiable(e.value),
      },
      tenderStatusLeadIds: {
        for (final e in tenderStatusLeadIds.entries)
          e.key: List<String>.unmodifiable(e.value),
      },
      normalLeadIds: List<String>.unmodifiable(normalLeadIds),
      tenderLeadIds: List<String>.unmodifiable(tenderLeadIds),
      employeeMatrix: employeeMatrix,
      recentActivity: topRecent,
      employeePulses: pulses,
      lastUpdatedAt: lastUpdatedAt,
      eventsIndexLink: eventsIndexLink,
    );
  }

  String? _extractIndexLink(Object error) {
    final match = RegExp(
      r'https://console\.firebase\.google\.com/[^\s\]\)]+',
    ).firstMatch(error.toString());
    final raw = match?.group(0);
    if (raw == null) return null;
    return raw.replaceAll(RegExp(r'[),.;]+$'), '');
  }

  double _calculateWinRate({required int wonDeals, required int lostDeals}) {
    final total = wonDeals + lostDeals;
    if (total == 0) return 0;
    return wonDeals / total;
  }

  List<StatusSlice> _topStatusSlices(Map<String, List<String>> raw) {
    if (raw.isEmpty) {
      return const <StatusSlice>[];
    }
    final entries = raw.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    const maxSlices = 8;
    if (entries.length <= maxSlices) {
      return [
        for (final e in entries)
          StatusSlice(
            label: e.key,
            count: e.value.length,
            leadIds: List<String>.unmodifiable(e.value),
          ),
      ];
    }
    final top = entries.take(maxSlices - 1).toList();
    final otherIds = <String>[];
    for (var i = maxSlices - 1; i < entries.length; i++) {
      otherIds.addAll(entries[i].value);
    }
    return [
      for (final e in top)
        StatusSlice(
          label: e.key,
          count: e.value.length,
          leadIds: List<String>.unmodifiable(e.value),
        ),
      StatusSlice(
        label: 'Other',
        count: otherIds.length,
        leadIds: List<String>.unmodifiable(otherIds),
      ),
    ];
  }

  List<LossSlice> _topLossSlices(Map<String, List<String>> raw) {
    if (raw.isEmpty) {
      return const <LossSlice>[];
    }
    final entries = raw.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    const maxSlices = 6;
    if (entries.length <= maxSlices) {
      return [
        for (final e in entries)
          LossSlice(
            label: e.key,
            count: e.value.length,
            leadIds: List<String>.unmodifiable(e.value),
          ),
      ];
    }
    final top = entries.take(maxSlices - 1).toList();
    final otherIds = <String>[];
    for (var i = maxSlices - 1; i < entries.length; i++) {
      otherIds.addAll(entries[i].value);
    }
    return [
      for (final e in top)
        LossSlice(
          label: e.key,
          count: e.value.length,
          leadIds: List<String>.unmodifiable(e.value),
        ),
      LossSlice(
        label: 'Other',
        count: otherIds.length,
        leadIds: List<String>.unmodifiable(otherIds),
      ),
    ];
  }

  List<SourceSlice> _topSourceSlices(Map<String, List<String>> raw) {
    if (raw.isEmpty) {
      return const <SourceSlice>[];
    }
    final entries = raw.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    const maxSlices = 6;
    if (entries.length <= maxSlices) {
      return [
        for (final e in entries)
          SourceSlice(
            label: e.key,
            count: e.value.length,
            leadIds: List<String>.unmodifiable(e.value),
          ),
      ];
    }
    final top = entries.take(maxSlices - 1).toList();
    final otherIds = <String>[];
    for (var i = maxSlices - 1; i < entries.length; i++) {
      otherIds.addAll(entries[i].value);
    }
    return [
      for (final e in top)
        SourceSlice(
          label: e.key,
          count: e.value.length,
          leadIds: List<String>.unmodifiable(e.value),
        ),
      SourceSlice(
        label: 'Other',
        count: otherIds.length,
        leadIds: List<String>.unmodifiable(otherIds),
      ),
    ];
  }
}
