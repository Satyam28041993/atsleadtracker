import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Lead sources every install starts with.
///
/// The live list lives in Firestore at `settings/sources_config`; this is the
/// seed for a fresh install and the fallback when that document can't be read.
/// [SourceService.ensureDefaultsPresent] merges any missing entry into an
/// existing document.
const List<String> kDefaultLeadSources = <String>[
  'Tradeindia',
  'India Mart',
  'Direct Lead',
  'Reference Lead',
  'Repair',
];

class SourceService {
  SourceService._({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final SourceService instance = SourceService._();

  final FirebaseFirestore _firestore;
  bool _initialized = false;
  List<String> _cachedSources = kDefaultLeadSources;

  final StreamController<List<String>> _sourcesController =
      StreamController<List<String>>.broadcast();

  DocumentReference<Map<String, dynamic>> get _sourcesDocRef =>
      _firestore.collection('settings').doc('sources_config');

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final snap = await _sourcesDocRef.get();
      if (!snap.exists) {
        await _sourcesDocRef.set(<String, dynamic>{
          'sources': List<String>.from(kDefaultLeadSources),
        });
        _cachedSources = List<String>.from(kDefaultLeadSources);
        _sourcesController.add(_cachedSources);
      } else {
        final list = snap.data()?['sources'];
        if (list is List) {
          _cachedSources = list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else {
          _cachedSources = List<String>.from(kDefaultLeadSources);
        }
        _sourcesController.add(_cachedSources);
      }
    } catch (_) {
      _cachedSources = List<String>.from(kDefaultLeadSources);
      _sourcesController.add(_cachedSources);
    }

    _sourcesDocRef.snapshots().listen((doc) {
      if (doc.exists) {
        final list = doc.data()?['sources'];
        if (list is List) {
          _cachedSources = list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          _sourcesController.add(_cachedSources);
        }
      }
    });
  }

  /// Adds any [kDefaultLeadSources] entry missing from the live document.
  ///
  /// Shipping a new default doesn't change `settings/sources_config` on an
  /// install that already has one, so new options would never show up. Rules
  /// allow `settings` updates for admins only, so call this from an admin
  /// session; it is a no-op when nothing is missing.
  Future<bool> ensureDefaultsPresent() async {
    await _ensureInitialized();
    final existing = _cachedSources
        .map((s) => s.toLowerCase().trim())
        .toSet();
    final missing = kDefaultLeadSources
        .where((s) => !existing.contains(s.toLowerCase()))
        .toList();
    if (missing.isEmpty) return false;
    try {
      await saveSources(<String>[..._cachedSources, ...missing]);
      return true;
    } catch (_) {
      // Non-admin, or offline. Harmless — an admin will do it later.
      return false;
    }
  }

  Future<List<String>> getSources() async {
    await _ensureInitialized();
    return _cachedSources;
  }

  Stream<List<String>> watchSources() async* {
    await _ensureInitialized();
    yield _cachedSources;
    yield* _sourcesController.stream;
  }

  Future<void> saveSources(List<String> sources) async {
    await _ensureInitialized();
    final cleaned = sources.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      await _sourcesDocRef.set(<String, dynamic>{
        'sources': List<String>.from(kDefaultLeadSources),
      });
      _cachedSources = List<String>.from(kDefaultLeadSources);
    } else {
      await _sourcesDocRef.set(<String, dynamic>{
        'sources': cleaned,
      });
      _cachedSources = cleaned;
    }
    _sourcesController.add(_cachedSources);
  }
}
