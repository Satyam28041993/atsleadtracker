import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead_event_model.dart';
import '../models/lead_model.dart';
import '../models/quotation_model.dart';
import '../models/user_model.dart';
import 'lead_service.dart';

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
    required this.wonLeadIds,
    required this.leadsAddedTodayIds,
    required this.followUpsTodayIds,
    required this.overdueFollowUpIds,
    required this.closedDealIds,
    required this.periodCreatedLeadIds,
    required this.statusSlices,
    required this.lossSlices,
    required this.sourceSlices,
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

  final List<String> activeLeadIds;
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
    return snapshot.docs.map(Lead.fromFirestore).toList(growable: false);
  }

  Future<ExecutiveAnalytics> computeAnalytics({
    String? assignedToUid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final leads = await _fetchLeads(assignedToUid: assignedToUid);
    final quoteAmountByLeadId = await _loadMaxQuotationAmountsByLeadId();
    final now = DateTime.now();
    final year = now.year;
    final startOfToday = DateTime(now.year, now.month, now.day);

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
    final wonLeadIds = <String>[];
    final leadsAddedTodayIds = <String>[];
    final followUpsTodayIds = <String>[];
    final overdueFollowUpIds = <String>[];
    final closedDealIds = <String>[];
    final periodCreatedLeadIds = <String>[];

    final statusLeadIds = <String, List<String>>{};
    final lossLeadIds = <String, List<String>>{};
    final sourceLeadIds = <String, List<String>>{};
    final winsByUid = <String, int>{};
    final winRevenueByUid = <String, double>{};
    final winLeadIdsByUid = <String, List<String>>{};
    final closedLostByUid = <String, int>{};
    final monthlyWonAmount = List<double>.filled(12, 0);
    final monthlyWonLeadIds = List.generate(12, (_) => <String>[]);
    var leadsCreatedInPeriod = 0;

    for (final lead in leads) {
      final amount = effectiveAmount(lead);
      final isClosed = isClosedStatus(lead.status);

      if (!isClosed) {
        active++;
        pipeline += amount;
        activeLeadIds.add(lead.id);
        final openStatus =
            lead.status.trim().isEmpty ? 'Unspecified' : lead.status.trim();
        statusLeadIds.putIfAbsent(openStatus, () => <String>[]).add(lead.id);
      }

      // Expected revenue is only for open pipeline.
      if (!isClosed) {
        double probability = 0.10; // Default for New
        if (lead.status == 'Contacted') probability = 0.30;
        if (lead.status == 'Proposal') probability = 0.60;
        if (lead.status == 'Follow-up') probability = 0.85;
        if (lead.status == 'Technical Evaluation') probability = 0.40;
        if (lead.status == 'Query Raised') probability = 0.35;
        if (lead.status == 'Query Responded') probability = 0.50;
        if (lead.status == 'Qualified') probability = 0.60;
        if (lead.status == 'Reverse Auction(RA)') probability = 0.85;
        expectedRevenue += amount * probability;
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
        periodCreatedLeadIds.add(lead.id);
        final src = lead.source.trim();
        final srcKey = src.isEmpty ? 'Unspecified' : src;
        sourceLeadIds.putIfAbsent(srcKey, () => <String>[]).add(lead.id);
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
    final conversionToWon =
        leadsCreatedInPeriod > 0 ? closedWonCount / leadsCreatedInPeriod : 0.0;

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

    final uids = sortedUids.toList(growable: false);
    final labels = await _leadService.getUserDisplayLabels(uids);

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
      wonLeadIds: List<String>.unmodifiable(wonLeadIds),
      leadsAddedTodayIds: List<String>.unmodifiable(leadsAddedTodayIds),
      followUpsTodayIds: List<String>.unmodifiable(followUpsTodayIds),
      overdueFollowUpIds: List<String>.unmodifiable(overdueFollowUpIds),
      closedDealIds: List<String>.unmodifiable(closedDealIds),
      periodCreatedLeadIds: List<String>.unmodifiable(periodCreatedLeadIds),
      statusSlices: statusSlices,
      lossSlices: lossSlices,
      sourceSlices: sourceSlices,
      monthlySales: monthlySales,
      leaderboard: leaderboard,
      employeeTargetProgress: targetProgressList,
    );
  }

  Future<Map<String, double>> _loadMaxQuotationAmountsByLeadId() async {
    final byLead = <String, double>{};
    try {
      final snap = await _firestore.collection('quotations').get();
      for (final doc in snap.docs) {
        try {
          final quote = QuotationModel.fromFirestore(doc);
          final leadId = quote.leadId.trim();
          if (leadId.isEmpty) continue;
          final amt = quote.quoteRequest.totalAmount;
          if (amt > (byLead[leadId] ?? 0)) {
            byLead[leadId] = amt;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return byLead;
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

    final leads = leadsSnap.docs.map(Lead.fromFirestore).toList();
    
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

      final leads = leadsSnap.docs.map(Lead.fromFirestore).toList();
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
    var leads = leadsSnap.docs.map(Lead.fromFirestore).toList();
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
