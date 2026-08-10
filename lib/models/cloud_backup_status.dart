import 'package:cloud_firestore/cloud_firestore.dart';

/// Status written by the scheduled Cloud Function at `settings/automatic_backup`.
class CloudBackupStatus {
  const CloudBackupStatus({
    required this.status,
    required this.outputUri,
    required this.bucket,
    required this.schedule,
    this.operationName = '',
    this.errorMessage = '',
    this.lastStartedAt,
    this.lastCompletedAt,
    this.lastFailedAt,
    this.updatedAt,
  });

  static const String docPath = 'settings/automatic_backup';
  static const String defaultBucket = 'atsleadtracker-firestore-backups';

  final String status;
  final String outputUri;
  final String bucket;
  final String schedule;
  final String operationName;
  final String errorMessage;
  final DateTime? lastStartedAt;
  final DateTime? lastCompletedAt;
  final DateTime? lastFailedAt;
  final DateTime? updatedAt;

  bool get isConfigured => status.isNotEmpty;

  factory CloudBackupStatus.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    if (!doc.exists) {
      return const CloudBackupStatus(
        status: 'not_configured',
        outputUri: '',
        bucket: defaultBucket,
        schedule: 'every 3 days at 3:00 AM IST',
      );
    }

    final data = doc.data() ?? <String, dynamic>{};
    return CloudBackupStatus(
      status: (data['status'] as String? ?? 'unknown').trim(),
      outputUri: (data['outputUri'] as String? ?? '').trim(),
      bucket: (data['bucket'] as String? ?? defaultBucket).trim(),
      schedule: (data['schedule'] as String? ?? 'every 3 days at 3:00 AM IST')
          .trim(),
      operationName: (data['operationName'] as String? ?? '').trim(),
      errorMessage: (data['errorMessage'] as String? ?? '').trim(),
      lastStartedAt: _toDate(data['lastStartedAt']),
      lastCompletedAt: _toDate(data['lastCompletedAt']),
      lastFailedAt: _toDate(data['lastFailedAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
