import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/product_model.dart';
import 'storage_upload.dart';

class ProductService {
  ProductService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _firestore.collection('products');

  Stream<List<Product>> getProductsStream() {
    return _productsRef
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(Product.fromFirestore).toList(growable: false),
        );
  }

  Future<List<Product>> fetchProductsOnce() async {
    final snapshot = await _productsRef.orderBy('name').get();
    return snapshot.docs.map(Product.fromFirestore).toList(growable: false);
  }

  Future<String> addProduct(Product product) async {
    if (product.id.isNotEmpty) {
      await _productsRef.doc(product.id).set(product.toFirestore());
      return product.id;
    } else {
      final doc = await _productsRef.add(product.toFirestore());
      return doc.id;
    }
  }

  Future<void> updateProduct(Product product) async {
    await _productsRef.doc(product.id).update(product.toFirestore());
  }

  Future<void> deleteProduct(String id) async {
    final doc = await _productsRef.doc(id).get();
    final data = doc.data();
    if (data != null) {
      final imageUrl = data['imageUrl'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(imageUrl);
          await ref.delete();
        } catch (_) {
          // Ignore if image doesn't exist
        }
      }
    }
    await _productsRef.doc(id).delete();
  }

  String _normalizeImageExtension(String extension) {
    final cleaned = extension.trim().replaceAll('.', '').toLowerCase();
    if (cleaned == 'jpeg') return 'jpg';
    return cleaned.isEmpty ? 'png' : cleaned;
  }

  String _imageContentType(String extension) {
    switch (extension) {
      case 'jpg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/$extension';
    }
  }

  Future<void> _ensureSignedInForUpload() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'You must be signed in to upload product images. Please log in again.',
      );
    }
    try {
      await user.getIdToken();
    } catch (_) {
      throw StateError(
        'Your session expired. Please log out and sign in again, then retry.',
      );
    }
  }

  Future<String> uploadProductImage(
    String productId,
    Uint8List bytes,
    String extension,
  ) async {
    if (bytes.isEmpty) {
      throw StateError('Selected image is empty. Please choose another file.');
    }

    await _ensureSignedInForUpload();

    final normalizedExtension = _normalizeImageExtension(extension);
    final ref = _storage
        .ref()
        .child('product_images')
        .child('$productId.$normalizedExtension');

    final metadata = SettableMetadata(
      contentType: _imageContentType(normalizedExtension),
    );

    try {
      final snapshot = await uploadBytes(ref, bytes, metadata);
      return snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw StateError(
          'Image upload denied (${e.code}). Log out, sign in again on '
          'appliedtechnogroup.com, then retry. If it still fails, check '
          'Firebase Storage rules for product_images.',
        );
      }
      throw StateError('Image upload failed: ${e.message ?? e.code}');
    }
  }
}
