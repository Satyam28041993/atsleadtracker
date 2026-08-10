import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Registers this device's FCM token against the signed-in user's Firestore
/// profile, and renders push notifications that arrive while the app is in the
/// foreground (FCM never auto-displays those).
///
/// This is the server-reachable half of follow-up reminders. [ReminderService]
/// schedules on-device AlarmManager alarms, but those only get (re)armed while
/// the app is actually running — so a lead that was rescheduled or reassigned
/// after the employee last opened the app would silently miss its reminder.
/// A Cloud Scheduler job (`checkDueFollowUpReminders`) instead reads Firestore
/// every couple of minutes and pushes straight to this device's token. Android
/// displays FCM "notification" payloads itself when the app is backgrounded or
/// killed, so no Dart code needs to be alive for the reminder to land.
///
/// Everything here is best-effort: any failure is logged and swallowed so a
/// missing token or a denied permission can never block sign-in.
class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService instance =
      PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  String? _activeUid;
  bool _localNotificationsReady = false;

  /// Must match the channel [ReminderService] creates on-device, the
  /// `default_notification_channel_id` in AndroidManifest.xml, and the
  /// `channelId` the Cloud Function sends — otherwise a pushed reminder would
  /// land on a different channel with different sound/importance settings.
  static const String _followUpChannelId = 'followup_reminders_v5';
  static const String _smallIcon = 'ic_notification';

  /// Only Android is wired up today: iOS is not a build target for this app,
  /// and on web FCM would need a service worker + VAPID key that aren't set up.
  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Call after sign-in with the employee's uid. Safe to call repeatedly.
  Future<void> init(String employeeUid) async {
    if (!_isSupported) return;
    if (employeeUid.trim().isEmpty) return;

    _activeUid = employeeUid;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
        '[PushNotificationService] Permission: ${settings.authorizationStatus}',
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Permission request failed: $e');
    }

    await _ensureLocalNotificationsReady();
    await _saveTokenIfAvailable(employeeUid);

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        final uid = _activeUid;
        if (uid != null) _saveToken(uid, token);
      },
      onError: (Object e) =>
          debugPrint('[PushNotificationService] Token refresh error: $e'),
    );

    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
      onError: (Object e) =>
          debugPrint('[PushNotificationService] Foreground stream error: $e'),
    );
  }

  Future<void> _ensureLocalNotificationsReady() async {
    if (_localNotificationsReady) return;
    const androidSettings = AndroidInitializationSettings(_smallIcon);
    const initSettings = InitializationSettings(android: androidSettings);
    try {
      await _localNotifications.initialize(settings: initSettings);
      _localNotificationsReady = true;
    } catch (e) {
      debugPrint('[PushNotificationService] Local init failed: $e');
    }
  }

  /// Android suppresses the tray banner for FCM "notification" payloads while
  /// the app is frontmost, so we draw it ourselves on the same channel.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _ensureLocalNotificationsReady();
    if (!_localNotificationsReady) return;

    try {
      await _localNotifications.show(
        id: message.hashCode & 0x7FFFFFFF,
        title: notification.title ?? 'Follow-up Reminder',
        body: notification.body ?? '',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _followUpChannelId,
            'Follow-up Reminders',
            channelDescription: 'Follow-up reminders with custom ringtone',
            icon: _smallIcon,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            ticker: 'Follow-up Reminder',
          ),
        ),
        payload: message.data['leadId'] as String?,
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Foreground display failed: $e');
    }
  }

  Future<void> _saveTokenIfAvailable(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(uid, token);
    } catch (e) {
      debugPrint('[PushNotificationService] getToken failed: $e');
    }
  }

  /// Writes only `fcmToken` — never a whole-document set — so no other field on
  /// the user profile can be touched by this service.
  Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(
        <String, dynamic>{'fcmToken': token},
      );
      debugPrint('[PushNotificationService] Token saved for $uid');
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to save token: $e');
    }
  }

  /// Called on sign-out. Clears the stored token so a pushed reminder can't
  /// land on a device where somebody else has since signed in.
  Future<void> stop() async {
    final uid = _activeUid;
    _activeUid = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _foregroundSub?.cancel();
    _foregroundSub = null;

    if (!_isSupported || uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(
        <String, dynamic>{'fcmToken': FieldValue.delete()},
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Token clear failed: $e');
    }
  }
}
