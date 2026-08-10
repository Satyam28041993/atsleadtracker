import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/cloud_backup_status.dart';

class CloudBackupCard extends StatelessWidget {
  const CloudBackupCard({super.key});

  static final DateFormat _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc(CloudBackupStatus.docPath)
          .snapshots(),
      builder: (context, snapshot) {
        final status = snapshot.hasData
            ? CloudBackupStatus.fromFirestore(snapshot.data!)
            : const CloudBackupStatus(
                status: 'loading',
                outputUri: '',
                bucket: CloudBackupStatus.defaultBucket,
                schedule: 'every 3 days at 3:00 AM IST',
              );

        final isActive = status.status == 'completed' ||
            status.status == 'running' ||
            status.status == 'exporting';
        final bgColor =
            isActive ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC);
        final borderColor =
            isActive ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIcon(status.status),
                    color: _statusColor(status.status),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusLabel(status.status),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (status.lastCompletedAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Last backup: ${_dateFmt.format(status.lastCompletedAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ] else if (status.status == 'failed') ...[
                          const SizedBox(height: 2),
                          Text(
                            'Last backup failed',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (status.errorMessage.isNotEmpty &&
                status.status == 'failed') ...[
              const SizedBox(height: 8),
              Text(
                status.errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'running':
      case 'exporting':
        return Icons.sync_rounded;
      case 'failed':
        return Icons.error_outline;
      case 'not_configured':
        return Icons.cloud_off_outlined;
      default:
        return Icons.cloud_queue_outlined;
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF16A34A);
      case 'running':
      case 'exporting':
        return const Color(0xFF2563EB);
      case 'failed':
        return const Color(0xFFDC2626);
      case 'not_configured':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF64748B);
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Auto backup active';
      case 'running':
      case 'exporting':
        return 'Backup running…';
      case 'failed':
        return 'Auto backup inactive';
      case 'not_configured':
        return 'Auto backup not set up';
      case 'loading':
        return 'Checking…';
      default:
        return 'Auto backup inactive';
    }
  }
}
