import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/settings_model.dart';

class MessageTemplateService {
  MessageTemplateService._({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final MessageTemplateService instance = MessageTemplateService._();

  final FirebaseFirestore _firestore;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _templateSub;
  final StreamController<String> _templateController =
      StreamController<String>.broadcast();

  String? _cachedTemplate;
  bool _initialized = false;

  DocumentReference<Map<String, dynamic>> get _templateDocRef => _firestore
      .collection(SettingsModel.collectionName)
      .doc(SettingsModel.whatsappDocId);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    final snap = await _templateDocRef.get();
    if (!snap.exists) {
      await _templateDocRef.set(<String, dynamic>{
        'template': SettingsModel.defaultTemplate,
      });
      _cachedTemplate = SettingsModel.defaultTemplate;
      _templateController.add(_cachedTemplate!);
    } else {
      _cachedTemplate = _normalizeTemplate(snap.data()?['template'] as String?);
      _templateController.add(_cachedTemplate!);
      if ((snap.data()?['template'] as String?)?.trim().isEmpty ?? true) {
        await _templateDocRef.set(<String, dynamic>{
          'template': _cachedTemplate,
        }, SetOptions(merge: true));
      }
    }

    _templateSub ??= _templateDocRef.snapshots().listen((doc) async {
      if (!doc.exists) {
        await _templateDocRef.set(<String, dynamic>{
          'template': SettingsModel.defaultTemplate,
        });
        _cachedTemplate = SettingsModel.defaultTemplate;
      } else {
        _cachedTemplate = _normalizeTemplate(
          doc.data()?['template'] as String?,
        );
      }
      _templateController.add(_cachedTemplate!);
    });
  }

  String _normalizeTemplate(String? raw) {
    final normalized = raw?.trim() ?? '';
    if (normalized.isEmpty) return SettingsModel.defaultTemplate;
    return normalized;
  }

  Future<String> getTemplate() async {
    await _ensureInitialized();
    return _cachedTemplate ?? SettingsModel.defaultTemplate;
  }

  Stream<String> watchTemplate() async* {
    await _ensureInitialized();
    if (_cachedTemplate != null) yield _cachedTemplate!;
    yield* _templateController.stream;
  }

  Future<void> saveTemplate(String template) async {
    await _ensureInitialized();
    final normalized = _normalizeTemplate(template);
    await _templateDocRef.set(<String, dynamic>{'template': normalized});
    _cachedTemplate = normalized;
    _templateController.add(normalized);
  }
}
