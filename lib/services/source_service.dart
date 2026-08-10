import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class SourceService {
  SourceService._({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final SourceService instance = SourceService._();

  final FirebaseFirestore _firestore;
  bool _initialized = false;
  List<String> _cachedSources = const ['Tradeindia', 'India Mart'];

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
          'sources': ['Tradeindia', 'India Mart'],
        });
        _cachedSources = ['Tradeindia', 'India Mart'];
        _sourcesController.add(_cachedSources);
      } else {
        final list = snap.data()?['sources'];
        if (list is List) {
          _cachedSources = list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else {
          _cachedSources = ['Tradeindia', 'India Mart'];
        }
        _sourcesController.add(_cachedSources);
      }
    } catch (_) {
      _cachedSources = ['Tradeindia', 'India Mart'];
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
        'sources': ['Tradeindia', 'India Mart'],
      });
      _cachedSources = ['Tradeindia', 'India Mart'];
    } else {
      await _sourcesDocRef.set(<String, dynamic>{
        'sources': cleaned,
      });
      _cachedSources = cleaned;
    }
    _sourcesController.add(_cachedSources);
  }
}
