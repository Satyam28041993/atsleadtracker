import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'quote_pdf_view_stub.dart'
    if (dart.library.html) 'quote_pdf_view_web.dart' as impl;

Future<void> showQuotePdfPreview(
  BuildContext context, {
  required Uint8List bytes,
  String title = 'Quotation PDF',
}) {
  return impl.showQuotePdfPreview(context, bytes: bytes, title: title);
}
