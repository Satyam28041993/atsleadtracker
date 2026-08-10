import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'storage_upload.dart';

/// A file the user picked and we uploaded, ready to be stored on the lead.
class LeadAttachment {
  const LeadAttachment({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

/// Uploads PO / invoice copies for a lead to Firebase Storage.
///
/// Files live under `lead_attachments/{leadId}/{kind}/{timestamp}_{name}`, so a
/// re-upload never overwrites the previous copy — the old object stays in the
/// bucket and only the lead's pointer moves. Nothing here deletes storage
/// objects, so a mis-click can always be recovered from the bucket.
class LeadAttachmentService {
  LeadAttachmentService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Guards against someone attaching a 200 MB scan from a phone.
  static const int maxBytes = 15 * 1024 * 1024;

  static const List<String> allowedExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'doc',
    'docx',
    'xls',
    'xlsx',
  ];

  /// Opens the file picker and uploads the chosen file.
  ///
  /// Returns `null` when the user cancels. Throws [LeadAttachmentException]
  /// with a human-readable message on any failure, so callers can surface it
  /// directly in a SnackBar.
  Future<LeadAttachment?> pickAndUpload({
    required String leadId,
    required String kind,
  }) async {
    if (leadId.trim().isEmpty) {
      throw const LeadAttachmentException(
        'Save the lead once before attaching a file.',
      );
    }

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: 'Select file to attach',
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        // Needed so the bytes are available for upload on every platform,
        // including web where there is no readable file path.
        withData: true,
      );
    } catch (e) {
      debugPrint('[LeadAttachmentService] Picker failed: $e');
      throw const LeadAttachmentException('Could not open the file picker.');
    }

    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const LeadAttachmentException('That file could not be read.');
    }
    if (bytes.length > maxBytes) {
      throw LeadAttachmentException(
        'File is too large (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). '
        'Maximum is ${maxBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final safeName = _sanitizeFileName(file.name);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('lead_attachments/$leadId/$kind/${stamp}_$safeName');

    try {
      await uploadBytes(
        ref,
        bytes,
        SettableMetadata(
          contentType: _contentTypeFor(safeName),
          customMetadata: <String, String>{
            'leadId': leadId,
            'kind': kind,
            'originalName': file.name,
          },
        ),
      );
      final url = await ref.getDownloadURL();
      return LeadAttachment(url: url, fileName: file.name);
    } catch (e) {
      debugPrint('[LeadAttachmentService] Upload failed: $e');
      throw const LeadAttachmentException(
        'Upload failed. Check your connection and try again.',
      );
    }
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.length <= 80 ? cleaned : cleaned.substring(cleaned.length - 80);
  }

  static String _contentTypeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }
}

class LeadAttachmentException implements Exception {
  const LeadAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}
