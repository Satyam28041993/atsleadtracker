import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

/// Time-based greeting plus welcome line using Firestore `users/{uid}.name`.
class DashboardWelcomeHeader extends StatelessWidget {
  const DashboardWelcomeHeader({
    super.key,
    required this.uid,
    required this.isAdmin,
    this.authService,
  });

  final String uid;
  final bool isAdmin;
  final AuthService? authService;

  static String greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = authService ?? AuthService();
    final theme = Theme.of(context);

    return StreamBuilder<String?>(
      stream: auth.watchUserName(uid),
      builder: (context, snapshot) {
        final name = snapshot.data;
        final welcomeName = name ?? (isAdmin ? 'Admin' : 'there');

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${greetingForNow()},',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF657084),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Welcome, $welcomeName',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D2638),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
