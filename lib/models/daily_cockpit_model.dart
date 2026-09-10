import 'lead_model.dart';
import 'quotation_model.dart';

enum DailyPendingType {
  dueToday,
  overdue,

  /// Status is Follow-up but no date was ever set — invisible work.
  missingDate,

  /// A quotation went out days ago and nothing has happened since. These are
  /// the furthest-along deals in the list, so they rank just under overdue.
  awaitingQuoteReply,

  stale,
}

enum DailyActivityType {
  quotation,
  followUp,
  statusChange,
  note,
  leadCreated,
}

class DailyPendingItem {
  const DailyPendingItem({
    required this.lead,
    required this.type,
    this.daysOverdue = 0,
    this.daysInactive = 0,
  });

  final Lead lead;
  final DailyPendingType type;
  final int daysOverdue;
  final int daysInactive;
}

class DailyCompletedActivity {
  const DailyCompletedActivity({
    required this.id,
    required this.type,
    required this.leadId,
    required this.title,
    required this.subtitle,
    required this.companyName,
    required this.clientName,
    required this.phone,
    required this.timestamp,
    required this.employeeUid,
    required this.employeeName,
    this.quotationRefNo,
    this.quotation,
    this.lead,
    this.followUpDate,
    this.followUpDetail,
  });

  final String id;
  final DailyActivityType type;
  final String leadId;
  final String title;
  final String subtitle;
  final String companyName;
  final String clientName;
  final String phone;
  final DateTime timestamp;
  final String employeeUid;
  final String employeeName;
  final String? quotationRefNo;
  final QuotationModel? quotation;
  final Lead? lead;
  final DateTime? followUpDate;
  final String? followUpDetail;
}

/// One lead's work for a day — company/client plus every action taken on it.
class LeadDayWork {
  const LeadDayWork({
    required this.leadId,
    required this.companyName,
    required this.clientName,
    required this.phone,
    required this.activities,
    this.lead,
    this.quotation,
  });

  final String leadId;
  final String companyName;
  final String clientName;
  final String phone;
  final List<DailyCompletedActivity> activities;
  final Lead? lead;
  final QuotationModel? quotation;

  DateTime get latestAt =>
      activities.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : activities.first.timestamp;

  DailyCompletedActivity? get followUpActivity {
    for (final a in activities) {
      if (a.type == DailyActivityType.followUp) return a;
    }
    return null;
  }

  DateTime? get scheduledFollowUp =>
      followUpActivity?.followUpDate ?? lead?.nextFollowUpDate;

  bool get isNewLead =>
      activities.any((a) => a.type == DailyActivityType.leadCreated);
}

/// Collapses a flat activity feed into one card per lead, newest lead first.
List<LeadDayWork> groupActivitiesByLead(List<DailyCompletedActivity> activities) {
  final map = <String, List<DailyCompletedActivity>>{};
  final order = <String>[];
  for (final act in activities) {
    final key = act.leadId.isNotEmpty ? act.leadId : 'orphan-${act.id}';
    if (!map.containsKey(key)) {
      map[key] = <DailyCompletedActivity>[];
      order.add(key);
    }
    map[key]!.add(act);
  }

  final groups = <LeadDayWork>[];
  for (final key in order) {
    final items = List<DailyCompletedActivity>.from(map[key]!)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    Lead? lead;
    QuotationModel? quotation;
    var company = '';
    var client = '';
    var phone = '';
    for (final a in items) {
      lead ??= a.lead;
      quotation ??= a.quotation;
      if (company.isEmpty) company = a.companyName;
      if (client.isEmpty) client = a.clientName;
      if (phone.isEmpty) phone = a.phone;
    }
    groups.add(
      LeadDayWork(
        leadId: items.first.leadId,
        companyName: company,
        clientName: client,
        phone: phone,
        activities: items,
        lead: lead,
        quotation: quotation,
      ),
    );
  }
  groups.sort((a, b) => b.latestAt.compareTo(a.latestAt));
  return groups;
}

class EmployeeDailySummary {
  const EmployeeDailySummary({
    required this.employeeUid,
    required this.employeeName,
    required this.role,
    required this.pendingItems,
    required this.todayActivities,
    required this.yesterdayActivities,
    required this.dueTodayCount,
    required this.overdueCount,
    required this.todayDoneCount,
    required this.todayQuotesValue,
  });

  final String employeeUid;
  final String employeeName;
  final String role;
  final List<DailyPendingItem> pendingItems;
  final List<DailyCompletedActivity> todayActivities;
  final List<DailyCompletedActivity> yesterdayActivities;
  final int dueTodayCount;
  final int overdueCount;
  final int todayDoneCount;
  final double todayQuotesValue;

  int get totalPendingCount => pendingItems.length;
}

class DailyCockpitPayload {
  const DailyCockpitPayload({
    required this.employeeSummaries,
    required this.timestamp,
    this.warnings = const <String>[],
  });

  final List<EmployeeDailySummary> employeeSummaries;
  final DateTime timestamp;

  /// Parts of the day that could not be loaded — a missing Firestore index, a
  /// permission the signed-in role does not have, a capped read.
  ///
  /// These used to be swallowed by bare catches, so an employee whose
  /// quotations query failed simply saw an empty tab and assumed they had done
  /// no work. Surfacing them is the difference between "nothing happened" and
  /// "we could not check".
  final List<String> warnings;

  bool get isDegraded => warnings.isNotEmpty;

  int get globalDueToday =>
      employeeSummaries.fold(0, (sum, e) => sum + e.dueTodayCount);
  int get globalOverdue =>
      employeeSummaries.fold(0, (sum, e) => sum + e.overdueCount);
  int get globalDoneToday =>
      employeeSummaries.fold(0, (sum, e) => sum + e.todayDoneCount);
  double get globalQuotesValue =>
      employeeSummaries.fold(0.0, (sum, e) => sum + e.todayQuotesValue);
}
