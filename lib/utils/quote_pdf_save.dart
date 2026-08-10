import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_save_directory/file_save_directory.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QuotePdfSaveResult {
  const QuotePdfSaveResult({
    required this.success,
    this.path,
    this.message,
    this.error,
  });

  final bool success;
  final String? path;
  final String? message;
  final String? error;
}

/// Saves a quotation PDF where the user can find it (Downloads on Android).
Future<QuotePdfSaveResult> saveQuotePdf({
  required Uint8List bytes,
  required String filename,
  bool openAfterSave = true,
}) async {
  if (kIsWeb) {
    return const QuotePdfSaveResult(
      success: false,
      error: 'Use browser download on web.',
    );
  }

  final baseName = filename.toLowerCase().endsWith('.pdf')
      ? filename.substring(0, filename.length - 4)
      : filename;

  if (Platform.isAndroid || Platform.isIOS) {
    final result = await FileSaveDirectory.instance.saveFile(
      fileName: baseName,
      fileBytes: bytes,
      location: SaveLocation.downloads,
      openAfterSave: false,
    );

    if (result.success && result.path != null) {
      if (openAfterSave) {
        await OpenFile.open(result.path!);
      }
      return QuotePdfSaveResult(
        success: true,
        path: result.path,
        message: result.message ?? 'Saved to Downloads',
      );
    }

    if (result.needsPermission) {
      return const QuotePdfSaveResult(
        success: false,
        error: 'Storage permission required. Allow access in Settings.',
      );
    }

    if (result.error != null) {
      return QuotePdfSaveResult(success: false, error: result.error);
    }
  }

  return _saveViaShareFallback(bytes, filename);
}

Future<QuotePdfSaveResult> _saveViaShareFallback(
  Uint8List bytes,
  String filename,
) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/$filename').writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      subject: filename,
      text: 'Quotation PDF — save to Downloads from the share menu.',
    );
    return QuotePdfSaveResult(
      success: true,
      path: file.path,
      message: 'Choose "Save" or "Files" in the share menu to store the PDF.',
    );
  } catch (e) {
    return QuotePdfSaveResult(success: false, error: e.toString());
  }
}
