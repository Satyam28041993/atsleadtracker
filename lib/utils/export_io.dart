import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether [savePath] means the bytes actually reached the user.
///
/// `FilePicker.saveFile` returns null on web *by design*: it builds a blob and
/// clicks a hidden `<a download>`, so there is no path to report. Treating that
/// null as failure is why every "Exported successfully" message was dead code
/// on web. On desktop and mobile null still means the user cancelled.
bool wasSaved(String? savePath) => kIsWeb || savePath != null;

/// One delivery path for every export in the app.
///
/// Returns true when the file was saved (or, on web, when the download
/// started).
Future<bool> saveExportBytes({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
}) async {
  final ext = fileName.split('.').last.toLowerCase();
  final path = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: <String>[ext],
    bytes: bytes,
  );
  return wasSaved(path);
}
