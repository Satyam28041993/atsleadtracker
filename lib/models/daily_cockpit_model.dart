import 'lead_model.dart';
import 'quotation_model.dart';

enum DailyPendingType {
  dueToday,
  overdue,
  missingDate,
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
  });

  final List<EmployeeDailySummary> employeeSummaries;
  final DateTime timestamp;

  int get globalDueToday =>
      employeeSummaries.fold(0, (sum, e) => sum + e.dueTodayCount);
  int get globalOverdue =>
      employeeSummaries.fold(0, (sum, e) => sum + e.overdueCount);
  int get globalDoneToday =>
      employeeSummaries.fold(0, (sum, e) => sum + e.todayDoneCount);
  double get globalQuotesValue =>
      employeeSummaries.fold(0.0, (sum, e) => sum + e.todayQuotesValue);
}
