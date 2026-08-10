import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for optional "stay signed in" credentials on mobile.
class SecureSessionStore {
  SecureSessionStore._();

  static const _emailKey = 'auth_email';
  static const _passwordKey = 'auth_password';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> save({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    await _storage.write(key: _emailKey, value: email.trim());
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<({String email, String password})?> read() async {
    if (kIsWeb) return null;
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null ||
        email.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return (email: email.trim(), password: password);
  }

  static Future<bool> hasCredentials() async {
    final creds = await read();
    return creds != null;
  }

  static Future<void> clear() async {
    if (kIsWeb) return;
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
