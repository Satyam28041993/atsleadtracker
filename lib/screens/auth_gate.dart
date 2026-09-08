import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/secure_session_store.dart';
import '../services/session_cache.dart';
import 'admin_dashboard.dart';
import 'employee_dashboard.dart';
import 'login_screen.dart';

/// Routes by auth state and Firestore `users/{uid}.role`.
///
/// Waits for Firebase Auth to restore the persisted session before showing the
/// login screen, so killing the app does not look like a logout.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _service;
  StreamSubscription<User?>? _authSub;
  User? _user;
  bool _sessionReady = false;
  bool _hadCachedSession = false;
  DateTime? _sessionRestoredAt;

  @override
  void initState() {
    super.initState();
    _service = widget.authService ?? AuthService();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      _hadCachedSession =
          await SessionCache.readUid() != null ||
          (!kIsWeb && await SecureSessionStore.hasCredentials());
    } catch (e) {
      debugPrint('[AuthGate] Cached session probe failed: $e');
      _hadCachedSession = false;
    }
    final restored = await AuthService.waitForPersistedSession();
    if (!mounted) return;

    setState(() {
      _user = restored;
      _sessionReady = true;
      if (restored != null) _sessionRestoredAt = DateTime.now();
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      if (user != null) {
        await SessionCache.save(uid: user.uid, email: user.email);
        setState(() {
          _user = user;
          _sessionRestoredAt = DateTime.now();
        });
        return;
      }

      // Ignore a brief null right after cold start while Firebase settles.
      if (_user != null && _sessionRestoredAt != null) {
        final elapsed = DateTime.now().difference(_sessionRestoredAt!);
        if (elapsed.inSeconds < 8) {
          final restored = await AuthService.trySilentSignIn();
          if (restored != null && mounted) {
            setState(() {
              _user = restored;
              _sessionRestoredAt = DateTime.now();
            });
          }
          return;
        }
      }

      setState(() => _user = null);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return _LoadingScreen(
        message: _hadCachedSession
            ? 'Restoring your session…'
            : 'Starting app…',
      );
    }

    final user = _user ?? _service.currentUser;
    if (user == null) {
      return LoginScreen(authService: _service);
    }

    return _RoleRouter(authService: _service, user: user);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _RoleRouter extends StatefulWidget {
  const _RoleRouter({required this.authService, required this.user});

  final AuthService authService;
  final User user;

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = widget.authService.getUserRole(widget.user.uid);
  }

  @override
  void didUpdateWidget(covariant _RoleRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _roleFuture = widget.authService.getUserRole(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Loading your profile…');
        }

        if (roleSnapshot.hasError) {
          // A failed profile read is usually transient (offline, Firestore
          // unavailable). Retry the read rather than throwing the session
          // away — signing out here made a network blip look like a logout.
          return _RoleErrorScreen(
            message: _messageForProfileError(roleSnapshot.error),
            retryLabel: 'Try again',
            onRetry: () => setState(() {
              _roleFuture = widget.authService.getUserRole(widget.user.uid);
            }),
            onSignOut: () => widget.authService.signOut(),
          );
        }

        final role = roleSnapshot.data;
        switch (role) {
          case 'admin':
            return AdminDashboard(authService: widget.authService);
          case 'employee':
            return EmployeeDashboard(authService: widget.authService);
          default:
            return _RoleErrorScreen(
              message: role == null
                  ? 'Your account has no role assigned. Contact an administrator.'
                  : 'Unknown role "$role". Contact an administrator.',
              onRetry: () => widget.authService.signOut(),
            );
        }
      },
    );
  }
}

String _messageForProfileError(Object? error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You signed in, but your profile could not be loaded (permission denied). An administrator must update Firestore security rules or your user record.';
      case 'unavailable':
        return 'Could not reach the database. Check your internet connection and try again.';
      default:
        return 'Could not load your profile (${error.code}). Please try again.';
    }
  }
  return 'Could not load your profile. Please try again.';
}

class _RoleErrorScreen extends StatelessWidget {
  const _RoleErrorScreen({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Back to sign in',
    this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  /// Shown as a secondary action when [onRetry] does something other than
  /// signing out, so the user still has a way back to the login screen.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: Text(retryLabel),
              ),
              if (onSignOut != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Back to sign in'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
