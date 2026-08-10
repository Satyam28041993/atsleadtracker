import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/lead_model.dart';
import '../models/task_model.dart';

class ReminderService {
  ReminderService._internal();
  static final ReminderService instance = ReminderService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _exactAlarmsAllowed = true;
  String _timezoneName = 'unknown';
  String? _activeEmployeeUid;
  StreamSubscription<List<Lead>>? _syncSubscription;
  StreamSubscription<List<TaskModel>>? _taskSyncSubscription;

  Set<int> _scheduledLeadNotificationIds = {};
  Set<int> _scheduledTaskNotificationIds = {};
  final Set<String> _immediateTaskNotifiedIds = {};

  static const String _followUpChannelId = 'followup_reminders_v5';

  /// Small icon must be a `drawable` resource (the plugin resolves it via
  /// getIdentifier(name, "drawable", ...)). Launcher icons live in `mipmap`
  /// and would fail to resolve, so we ship a dedicated white vector here.
  static const String _smallIcon = 'ic_notification';

  static const RawResourceAndroidNotificationSound _followUpRingtone =
      RawResourceAndroidNotificationSound('pick_up');

  static const AndroidNotificationChannel _followUpChannel =
      AndroidNotificationChannel(
    _followUpChannelId,
    'Follow-up Reminders',
    description: 'Follow-up reminders with custom ringtone',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: _followUpRingtone,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  static const AndroidNotificationDetails _followUpAndroidDetails =
      AndroidNotificationDetails(
    _followUpChannelId,
    'Follow-up Reminders',
    channelDescription: 'Follow-up reminders with custom ringtone',
    icon: _smallIcon,
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    playSound: true,
    enableVibration: true,
    sound: _followUpRingtone,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    ticker: 'Follow-up Reminder',
  );

  static const AndroidNotificationDetails _followUpAndroidDetailsFallback =
      AndroidNotificationDetails(
    _followUpChannelId,
    'Follow-up Reminders',
    channelDescription: 'Follow-up reminders with custom ringtone',
    icon: _smallIcon,
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    ticker: 'Follow-up Reminder',
  );

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isInitialized => _initialized;

  bool get exactAlarmsAllowed => _exactAlarmsAllowed;

  String get timezoneName => _timezoneName;

  Future<void> init() async {
    if (!isAndroid) return;
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
      _timezoneName = timezoneInfo.identifier;
      debugPrint('[ReminderService] Timezone set to ${timezoneInfo.identifier}');
    } catch (e) {
      debugPrint('[ReminderService] Timezone initialization failed, falling back to UTC: $e');
      _timezoneName = 'UTC (fallback)';
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }

    const androidSettings = AndroidInitializationSettings(_smallIcon);
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('[ReminderService] Notification clicked: ${details.payload}');
        },
      );

      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
        await androidImplementation.createNotificationChannel(_followUpChannel);
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'task_reminders',
            'Task Reminders',
            description: 'Reminders for due tasks',
            importance: Importance.max,
          ),
        );
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'new_tasks',
            'New Tasks',
            description: 'Notifications for newly assigned tasks',
            importance: Importance.max,
          ),
        );
        _exactAlarmsAllowed =
            await androidImplementation.canScheduleExactNotifications() ?? false;
        debugPrint('[ReminderService] Exact alarms allowed: $_exactAlarmsAllowed');
      }

      _initialized = true;
      debugPrint('[ReminderService] Initialized successfully.');
    } catch (e) {
      debugPrint('[ReminderService] Local notifications initialization failed: $e');
    }
  }

  void startSync(String employeeUid) {
    if (!isAndroid) return;

    _activeEmployeeUid = employeeUid;
    _syncSubscription?.cancel();

    debugPrint('[ReminderService] Starting real-time sync for user: $employeeUid');

    final Stream<List<Lead>> reminderStream = FirebaseFirestore.instance
        .collection('leads')
        .where('assignedTo', isEqualTo: employeeUid)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Lead.fromFirestore(doc))
              .where((lead) => lead.nextFollowUpDate != null)
              .toList();
        });

    _syncSubscription = reminderStream.listen((leads) async {
      debugPrint('[ReminderService] Leads changed, rescheduling follow-up alarms for ${leads.length} leads.');
      await _syncFollowUpReminders(leads);
    }, onError: (err) {
      debugPrint('[ReminderService] Error in reminders sync stream: $err');
    });

    final Stream<List<TaskModel>> taskStream = FirebaseFirestore.instance
        .collection('tasks')
        .where(Filter.or(
          Filter('assignedTo', isEqualTo: employeeUid),
          Filter('assignedBy', isEqualTo: employeeUid),
        ))
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList();
        });

    _taskSyncSubscription?.cancel();
    _taskSyncSubscription = taskStream.listen((tasks) async {
      debugPrint('[ReminderService] Tasks changed, handling notifications for ${tasks.length} tasks.');
      await _syncTaskReminders(tasks);
    }, onError: (err) {
      debugPrint('[ReminderService] Error in task sync stream: $err');
    });
  }

  /// Schedules (or re-schedules) a follow-up alarm immediately after Firestore save.
  Future<bool> scheduleFollowUpReminder(Lead lead) async {
    if (!isAndroid) return false;
    if (!_initialized) await init();
    if (!_initialized) return false;

    final followUp = lead.nextFollowUpDate;
    if (followUp == null) return false;

    final now = DateTime.now();
    if (followUp.isAfter(now)) {
      final scheduled = await _scheduleReminder(lead);
      if (scheduled) {
        _scheduledLeadNotificationIds.add(_getStableHash(lead.id));
      }
      return scheduled;
    }

    await _cancelNotification(_getStableHash(lead.id));
    return false;
  }

  Future<void> resyncOnResume() async {
    if (!isAndroid || !_initialized || _activeEmployeeUid == null) return;

    final uid = _activeEmployeeUid!;
    debugPrint('[ReminderService] Resyncing reminders on app resume for $uid');

    try {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      _exactAlarmsAllowed =
          await androidImplementation?.canScheduleExactNotifications() ?? false;

      final leadSnapshot = await FirebaseFirestore.instance
          .collection('leads')
          .where('assignedTo', isEqualTo: uid)
          .get();
      final leads = leadSnapshot.docs
          .map((doc) => Lead.fromFirestore(doc))
          .where((lead) => lead.nextFollowUpDate != null)
          .toList();
      await _syncFollowUpReminders(leads);

      final taskSnapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where(Filter.or(
            Filter('assignedTo', isEqualTo: uid),
            Filter('assignedBy', isEqualTo: uid),
          ))
          .where('isCompleted', isEqualTo: false)
          .get();
      final tasks =
          taskSnapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
      await _syncTaskReminders(tasks);
    } catch (e) {
      debugPrint('[ReminderService] Resume resync failed: $e');
    }
  }

  Future<void> stopSync() async {
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _taskSyncSubscription?.cancel();
    _taskSyncSubscription = null;
    _activeEmployeeUid = null;
    _scheduledLeadNotificationIds = {};
    _scheduledTaskNotificationIds = {};
    _immediateTaskNotifiedIds.clear();
    await cancelAllReminders();
    debugPrint('[ReminderService] Sync stopped and alarms wiped.');
  }

  Future<void> cancelAllReminders() async {
    if (!isAndroid) return;
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('[ReminderService] All scheduled reminders canceled.');
    } catch (e) {
      debugPrint('[ReminderService] Failed to cancel alarms: $e');
    }
  }

  Future<void> _syncFollowUpReminders(List<Lead> leads) async {
    if (!_initialized) return;

    final now = DateTime.now();
    final nextIds = <int>{};

    for (final lead in leads) {
      final followUp = lead.nextFollowUpDate;
      if (followUp == null) continue;

      if (followUp.isAfter(now)) {
        final id = _getStableHash(lead.id);
        final scheduled = await _scheduleReminder(lead);
        if (scheduled) nextIds.add(id);
      } else {
        await _cancelNotification(_getStableHash(lead.id));
      }
    }

    for (final staleId in _scheduledLeadNotificationIds.difference(nextIds)) {
      await _cancelNotification(staleId);
    }
    _scheduledLeadNotificationIds = nextIds;
  }

  Future<void> _syncTaskReminders(List<TaskModel> tasks) async {
    if (!_initialized) return;

    final now = DateTime.now();
    final nextIds = <int>{};

    for (final task in tasks) {
      if (task.createdAt.isAfter(now.subtract(const Duration(minutes: 3))) &&
          !_immediateTaskNotifiedIds.contains(task.id)) {
        await _showImmediateTaskNotification(task);
        _immediateTaskNotifiedIds.add(task.id);
      }

      if (task.dueDate.isAfter(now)) {
        final id = _getStableHash('task_${task.id}');
        await _scheduleTaskReminder(task);
        nextIds.add(id);
      }
    }

    for (final staleId in _scheduledTaskNotificationIds.difference(nextIds)) {
      await _cancelNotification(staleId);
    }
    _scheduledTaskNotificationIds = nextIds;
  }

  Future<void> _cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id: id);
    } catch (e) {
      debugPrint('[ReminderService] Failed to cancel notification $id: $e');
    }
  }

  /// Converts a wall-clock [target] (local [DateTime]) into the exact instant
  /// to fire, computed as a duration from "now".
  ///
  /// This is intentionally timezone-database independent: even if
  /// [FlutterTimezone] returns an identifier that `timezone` can't map (and we
  /// fall back to UTC), the alarm still fires at the correct real-world moment
  /// because we schedule by elapsed duration rather than re-interpreting the
  /// wall-clock components inside `tz.local`.
  tz.TZDateTime _toScheduledInstant(DateTime target) {
    final diff = target.difference(DateTime.now());
    return tz.TZDateTime.now(tz.local).add(diff);
  }

  String _followUpBody(Lead lead) {
    final companyDetails = lead.company.isNotEmpty ? ' (${lead.company})' : '';
    final req =
        lead.productsSummary.isNotEmpty ? lead.productsSummary : lead.requirement;
    return 'Follow-up is due for ${lead.name}$companyDetails.\nRequirement: $req';
  }

  Future<bool> _scheduleReminder(Lead lead) async {
    if (!isAndroid || !_initialized) return false;

    final followUp = lead.nextFollowUpDate;
    if (followUp == null) return false;

    final id = _getStableHash(lead.id);
    final scheduledTime = _toScheduledInstant(followUp);
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduledTime.isAfter(now)) return false;

    final bodyText = _followUpBody(lead);

    final attempts = <({
      AndroidNotificationDetails details,
      AndroidScheduleMode mode,
    })>[
      (
        details: _followUpAndroidDetails,
        mode: _exactAlarmsAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      ),
      (
        details: _followUpAndroidDetailsFallback,
        mode: _exactAlarmsAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      ),
      (
        details: _followUpAndroidDetailsFallback,
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
      ),
    ];

    for (final attempt in attempts) {
      try {
        await _notificationsPlugin.zonedSchedule(
          id: id,
          title: 'Follow-up Reminder',
          body: bodyText,
          scheduledDate: scheduledTime,
          notificationDetails: NotificationDetails(android: attempt.details),
          androidScheduleMode: attempt.mode,
        );
        debugPrint(
          '[ReminderService] Alarm scheduled for lead [${lead.name}] at $scheduledTime '
          '(ID: $id, mode: ${attempt.mode}, exactAllowed: $_exactAlarmsAllowed)',
        );
        return true;
      } on PlatformException catch (e) {
        debugPrint(
          '[ReminderService] Schedule attempt failed for [${lead.name}] '
          '(mode: ${attempt.mode}): ${e.code} ${e.message}',
        );
        if (e.code == 'exact_alarms_not_permitted') {
          _exactAlarmsAllowed = false;
        }
      } catch (e) {
        debugPrint('[ReminderService] Schedule attempt failed for [${lead.name}]: $e');
      }
    }

    return false;
  }

  Future<void> _showImmediateTaskNotification(TaskModel task) async {
    if (!isAndroid || !_initialized) return;

    final id = _getStableHash('immediate_${task.id}');

    const androidDetails = AndroidNotificationDetails(
      'new_tasks',
      'New Tasks',
      channelDescription: 'Notifications for newly assigned tasks',
      icon: _smallIcon,
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.show(
        id: id,
        title: 'New Task Assigned',
        body: task.title,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[ReminderService] Failed to show immediate task notification: $e');
    }
  }

  Future<void> _scheduleTaskReminder(TaskModel task) async {
    if (!isAndroid || !_initialized) return;

    final id = _getStableHash('task_${task.id}');
    final due = task.dueDate;
    final dueAt9 = DateTime(due.year, due.month, due.day, 9, 0);
    if (dueAt9.isBefore(DateTime.now())) return;
    final scheduledTime = _toScheduledInstant(dueAt9);

    const androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      channelDescription: 'Reminders for due tasks',
      icon: _smallIcon,
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: 'Task Due Today!',
        body: task.title,
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: _exactAlarmsAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[ReminderService] Failed to schedule zoned alarm for task: $e');
    }
  }

  int _getStableHash(String string) {
    int hash = 5381;
    for (int i = 0; i < string.length; i++) {
      hash = ((hash << 5) + hash) + string.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash;
  }
}
