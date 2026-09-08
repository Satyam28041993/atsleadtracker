import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'secure_session_store.dart';
import 'session_cache.dart';

/// Handles Firebase Authentication and Firestore-backed user roles.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Waits for Firebase Auth to restore the session, then silently re-signs in
  /// from encrypted credentials when Firebase lost the in-memory session.
  /// In-flight/settled restore, so the two callers (main.dart before runApp,
  /// AuthGate.initState) share one run instead of racing two.
  static Future<User?>? _restoreFuture;

  static Future<User?> waitForPersistedSession() {
    return _restoreFuture ??= _restorePersistedSession();
  }

  static Future<User?> _restorePersistedSession() async {
    // Deliberately NO setPersistence() call here.
    //
    // firebase_auth_web already installs [indexedDBLocalPersistence,
    // browserLocalPersistence] by default. Persistence.LOCAL maps to
    // browserLocalPersistence *only*, so setting it downgrades us to
    // localStorage and, worse, runs while the JS SDK is still restoring:
    // setPersistence migrates by deleting the user from the old store before
    // writing to the new one, so losing that race left the session in neither
    // store. That was the "refresh logs me out" bug.
    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _persistUser(user);
        return user;
      }

      // These only decide how long we wait. If storage is unavailable (private
      // window, blocked site data) they must not abort the restore below —
      // that would drop us straight to the login screen.
      String? cachedUid;
      var hasSecureCreds = false;
      try {
        cachedUid = await SessionCache.readUid();
        hasSecureCreds = await SecureSessionStore.hasCredentials();
      } catch (e) {
        debugPrint('[AuthService] Session hint lookup failed: $e');
      }

      // Web has no silent re-sign-in fallback (trySilentSignIn returns null
      // there), so Firebase's own restore is the only chance — wait longer.
      final retrySeconds = (cachedUid != null || hasSecureCreds || kIsWeb)
          ? 5
          : 2;
      final deadline = DateTime.now().add(Duration(seconds: retrySeconds));

      debugPrint('[AuthService] Restoring session…');

      while (DateTime.now().isBefore(deadline)) {
        user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _persistUser(user);
          debugPrint('[AuthService] Session restored for ${user.uid}');
          return user;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      try {
        // Wait for a SIGNED-IN event, not merely the first event. The stream
        // can emit a null before the restore finishes, and `.first` would lock
        // that null in and sign the user out on every refresh.
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }

      if (user != null) {
        await _persistUser(user);
        return user;
      }

      // Firebase did not restore — silently sign in again from secure storage.
      user = await trySilentSignIn();
      if (user != null) {
        debugPrint('[AuthService] Silent sign-in restored ${user.uid}');
        return user;
      }

      return null;
    } catch (e) {
      debugPrint('[AuthService] Session restore failed: $e');
      final user = await trySilentSignIn();
      return user ?? FirebaseAuth.instance.currentUser;
    }
  }

  /// Re-authenticates using credentials saved after the last successful login.
  static Future<User?> trySilentSignIn() async {
    if (kIsWeb) return null;

    final creds = await SecureSessionStore.read();
    if (creds == null) return null;

    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: creds.email,
        password: creds.password,
      );
      final user = result.user;
      if (user != null) {
        await _persistUser(user);
      }
      return user;
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] Silent sign-in failed: ${e.code}');
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-login-credentials' ||
          e.code == 'user-not-found' ||
          e.code == 'user-disabled') {
        await SecureSessionStore.clear();
        await SessionCache.clear();
      }
      return null;
    } catch (e) {
      debugPrint('[AuthService] Silent sign-in error: $e');
      return null;
    }
  }

  static Future<void> _persistUser(User user) {
    return SessionCache.save(uid: user.uid, email: user.email);
  }

  /// Signs in with email and password. Throws [FirebaseAuthException] on failure.
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await SessionCache.save(uid: user.uid, email: user.email ?? email);
      if (rememberMe && !kIsWeb) {
        await SecureSessionStore.save(email: email.trim(), password: password);
      } else {
        await SecureSessionStore.clear();
      }
    }
    return cred;
  }

  /// Returns the cached signed-in user, if any.
  User? get currentUser => _auth.currentUser;

  /// Signs out the current user and clears all local session data.
  Future<void> signOut() async {
    await SessionCache.clear();
    await SecureSessionStore.clear();
    await _auth.signOut();
    // Drop the memoised restore so a later sign-in re-runs it instead of
    // replaying this signed-out result.
    _restoreFuture = null;
  }

  /// Verifies the signed-in user's login password (Firebase re-authentication).
  Future<void> reauthenticateWithPassword({required String password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'You are not signed in.',
      );
    }
    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'This account does not use email/password login.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Reads `role` from `users/{uid}`. Returns `null` if missing or invalid.
  Future<String?> getUserRole(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final role = doc.data()?['role'];
    if (role is! String) return null;
    return role.trim();
  }

  Stream<String?> watchUserName(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snap) {
      final raw = snap.data()?['name'];
      if (raw is! String) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    });
  }

  Future<String> getCurrentUserDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return 'System';

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final name = doc.data()?['name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }

    final email = user.email;
    if (email != null && email.trim().isNotEmpty) {
      return email.trim();
    }

    return 'System';
  }
}
