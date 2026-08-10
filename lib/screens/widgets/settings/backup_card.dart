import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/backup_service.dart';

class BackupCard extends StatelessWidget {
  const BackupCard({
    required this.backingUpKind,
    required this.onBackup,
    super.key,
  });

  final BackupKind? backingUpKind;
  final Future<void> Function(BackupKind kind) onBackup;

  @override
  Widget build(BuildContext context) {
    return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _BackupButton(
              label: 'Backup Leads',
              icon: Icons.groups_outlined,
              kind: BackupKind.leads,
              loading: backingUpKind == BackupKind.leads,
              onPressed: backingUpKind == null
                  ? () => onBackup(BackupKind.leads)
                  : null,
            ),
            _BackupButton(
              label: 'Backup Tenders',
              icon: Icons.gavel_outlined,
              kind: BackupKind.tenders,
              loading: backingUpKind == BackupKind.tenders,
              onPressed: backingUpKind == null
                  ? () => onBackup(BackupKind.tenders)
                  : null,
            ),
            _BackupButton(
              label: 'Backup Quotations',
              icon: Icons.request_quote_outlined,
              kind: BackupKind.quotations,
              loading: backingUpKind == BackupKind.quotations,
              onPressed: backingUpKind == null
                  ? () => onBackup(BackupKind.quotations)
                  : null,
            ),
            _BackupButton(
              label: 'Backup Products',
              icon: Icons.inventory_2_outlined,
              kind: BackupKind.products,
              loading: backingUpKind == BackupKind.products,
              onPressed: backingUpKind == null
                  ? () => onBackup(BackupKind.products)
                  : null,
            ),
          ],
        );
  }
}

class _BackupButton extends StatelessWidget {
  const _BackupButton({
    required this.label,
    required this.icon,
    required this.kind,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final BackupKind kind;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1D4ED8),
        side: const BorderSide(color: Color(0xFFBFDBFE)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

Future<String?> saveBackupToDevice(
  BackupFile file, {
  String? dialogTitle,
}) {
  final ext = file.fileName.split('.').last.toLowerCase();
  return FilePicker.saveFile(
    dialogTitle: dialogTitle ?? 'Save backup',
    fileName: file.fileName,
    type: FileType.custom,
    allowedExtensions: <String>[ext],
    bytes: file.bytes,
  );
}

Future<QuotationBackupOption?> askQuotationBackupOption(
  BuildContext context,
) {
  return showDialog<QuotationBackupOption>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Quotation Backup'),
      content: const Text(
        'Kya download karna hai?\n\n'
        '• CSV — summary list (Excel)\n'
        '• ZIP — saari quotation PDF files\n'
        '• Dono — CSV aur ZIP alag-alag save honge',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(QuotationBackupOption.csv),
          child: const Text('CSV'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(QuotationBackupOption.zip),
          child: const Text('ZIP (PDFs)'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(QuotationBackupOption.both),
          child: const Text('Dono'),
        ),
      ],
    ),
  );
}
