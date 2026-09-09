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
