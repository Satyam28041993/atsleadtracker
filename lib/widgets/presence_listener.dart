import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../presence_stub.dart' if (dart.library.html) '../presence_web.dart'
    as tab_visibility;
import '../services/push_notification_service.dart';
import '../services/reminder_service.dart';

/// Updates `users/{uid}.lastActive` and `isOnline` when the app is foregrounded
/// or the browser tab becomes visible again.
class PresenceListener extends StatefulWidget {
  const PresenceListener({super.key, required this.child});

  final Widget child;

  @override
  State<PresenceListener> createState() => _PresenceListenerState();
}

class _PresenceListenerState extends State<PresenceListener>
    with WidgetsBindingObserver {
  static const Duration _debounce = Duration(seconds: 2);
  DateTime? _lastPing;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _pingPresence();
        ReminderService.instance.init().then((_) {
          ReminderService.instance.startSync(user.uid);
        });
        // Registers the device token so the scheduled Cloud Function can push
        // follow-up reminders even when this app process is not running.
        PushNotificationService.instance.init(user.uid);
      } else {
        ReminderService.instance.stopSync();
        PushNotificationService.instance.stop();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pingPresence());
    tab_visibility.listenTabVisibility(_onTabVisible);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ReminderService.instance.stopSync();
    super.dispose();
  }

  void _onTabVisible() => _pingPresence();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pingPresence();
      ReminderService.instance.resyncOnResume();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _setOffline();
    }
  }

  Future<void> _setOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        <String, dynamic>{'isOnline': false},
      );
    } catch (_) {}
  }

  Future<void> _pingPresence() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    if (_lastPing != null && now.difference(_lastPing!) < _debounce) {
      return;
    }
    _lastPing = now;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
          'isOnline': true,
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
