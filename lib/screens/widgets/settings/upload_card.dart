import 'package:flutter/material.dart';

import '../../../services/bulk_upload_service.dart';

class UploadCard extends StatelessWidget {
  const UploadCard({
    required this.description,
    required this.loadingUserContext,
    required this.downloadingTemplate,
    required this.uploadingLeads,
    required this.onDownload,
    required this.onSelectAndUpload,
    required this.progress,
    this.onPurge,
    this.purgingLeads = false,
    this.isTenderMode = false,
    super.key,
  });

  final String description;
  final bool loadingUserContext;
  final bool downloadingTemplate;
  final bool uploadingLeads;
  final VoidCallback onDownload;
  final VoidCallback onSelectAndUpload;
  final BulkUploadProgress? progress;
  final VoidCallback? onPurge;
  final bool purgingLeads;
  final bool isTenderMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressText = (progress != null && progress!.totalRows > 0)
        ? 'Uploading ${progress!.processedRows}/${progress!.totalRows} leads'
        : 'Preparing upload...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9E2EC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Drag and drop your Excel here',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'or click Upload Leads to browse files (.xlsx, .xls)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Tooltip(
              message: 'Download the latest Excel template',
              child: OutlinedButton.icon(
                onPressed:
                    loadingUserContext || downloadingTemplate || uploadingLeads
                    ? null
                    : onDownload,
                icon: downloadingTemplate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  downloadingTemplate
                      ? 'Downloading...'
                      : isTenderMode
                          ? 'Download Tender Template'
                          : 'Download Template',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(180, 44),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Select an Excel file to upload',
              child: FilledButton.icon(
                onPressed:
                    loadingUserContext || downloadingTemplate || uploadingLeads
                    ? null
                    : onSelectAndUpload,
                icon: uploadingLeads
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_rounded, size: 18),
                label: Text(
                  uploadingLeads
                      ? 'Uploading...'
                      : isTenderMode
                          ? 'Upload Tender Leads'
                          : 'Upload Leads',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  minimumSize: const Size(150, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (onPurge != null)
              Tooltip(
                message:
                    'Delete all CRM leads (requires your login password)',
                child: OutlinedButton.icon(
                  onPressed:
                      loadingUserContext || downloadingTemplate || uploadingLeads || purgingLeads
                      ? null
                      : onPurge,
                  icon: purgingLeads
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.redAccent,
                          ),
                        )
                      : const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                  label: const Text(
                    'Purge All Leads',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(170, 44),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (uploadingLeads) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress != null && progress!.totalRows > 0
                  ? progress!.processedRows / progress!.totalRows
                  : null,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  progressText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              if (progress != null && progress!.totalRows > 0)
                Text(
                  '${((progress!.processedRows / progress!.totalRows) * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
