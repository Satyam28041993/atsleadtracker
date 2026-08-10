import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight backup of the last successful login so the app can wait for
/// Firebase Auth to restore the session after a cold start / app kill.
class SessionCache {
  SessionCache._();

  static const _uidKey = 'session_uid';
  static const _emailKey = 'session_email';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[SessionCache] SharedPreferences unavailable: $e');
      return null;
    }
  }

  static Future<void> save({required String uid, String? email}) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(_uidKey, uid);
    if (email != null && email.trim().isNotEmpty) {
      await prefs.setString(_emailKey, email.trim());
    }
  }

  static Future<String?> readUid() async {
    final prefs = await _prefs();
    if (prefs == null) return null;
    final uid = prefs.getString(_uidKey);
    if (uid == null || uid.trim().isEmpty) return null;
    return uid.trim();
  }

  static Future<String?> readEmail() async {
    final prefs = await _prefs();
    if (prefs == null) return null;
    final email = prefs.getString(_emailKey);
    if (email == null || email.trim().isEmpty) return null;
    return email.trim();
  }

  static Future<void> clear() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.remove(_uidKey);
    await prefs.remove(_emailKey);
  }
}
