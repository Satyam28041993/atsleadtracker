import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Future<void> showQuotePdfPreview(
  BuildContext context, {
  required Uint8List bytes,
  String title = 'Quotation PDF',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 800,
        height: 600,
        child: PdfPreview(
          build: (format) => bytes,
          allowPrinting: true,
          allowSharing: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
          pdfPreviewPageDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    ),
  );
}
