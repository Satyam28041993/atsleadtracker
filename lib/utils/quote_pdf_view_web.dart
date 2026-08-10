// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> showQuotePdfPreview(
  BuildContext context, {
  required Uint8List bytes,
  String title = 'Quotation PDF',
}) async {
  final blob = html.Blob(<Uint8List>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final filename = _safePdfFilename(title);

  void openPdf() {
    final anchor = html.AnchorElement(href: url)
      ..target = '_blank'
      ..rel = 'noopener';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  void downloadPdf() {
    final anchor = html.AnchorElement(href: url)..download = filename;
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'PDF ready hai. Browser security ki wajah se preview app ke andar embed nahi kiya ja raha; native PDF viewer me open karein.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: openPdf,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open PDF'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: downloadPdf,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download PDF'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } finally {
    unawaited(
      Future<void>.delayed(const Duration(minutes: 5), () {
        html.Url.revokeObjectUrl(url);
      }),
    );
  }
}

String _safePdfFilename(String title) {
  final stem = title
      .trim()
      .replaceAll(RegExp(r'[^\w\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return '${stem.isEmpty ? 'quotation' : stem}.pdf';
}
