import 'package:cloud_firestore/cloud_firestore.dart';

/// Catalog item for analyzers / industrial equipment (B2B CRM).
class Product {
  const Product({
    required this.id,
    required this.name,
    this.make = '',
    this.model = '',
    this.hsnNo = '',
    this.specification = '',
    this.accessories = '',
    this.parametersMeasured = '',
    this.basePrice = 0.0,
    this.imageUrl = '',
    this.productOverview = '',
    this.keyFeatures = '',
  });

  final String id;
  final String name;
  final String make;
  final String model;
  final String hsnNo;
  final String specification;
  final String accessories;
  final String parametersMeasured;
  final double basePrice;
  final String imageUrl;
  final String productOverview;
  final String keyFeatures;

  factory Product.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Product(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      make: (data['make'] as String? ?? '').trim(),
      model: (data['model'] as String? ?? '').trim(),
      hsnNo: (data['hsnNo'] as String? ?? data['hsnCode'] as String? ?? '').trim(),
      specification: (data['specification'] as String? ?? '').trim(),
      accessories: (data['accessories'] as String? ?? '').trim(),
      parametersMeasured: (data['parametersMeasured'] as String? ?? '').trim(),
      basePrice: _parseDouble(data['basePrice']),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      productOverview: (data['productOverview'] as String? ?? '').trim(),
      keyFeatures: (data['keyFeatures'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'name': name.trim(),
      'make': make.trim(),
      'model': model.trim(),
      'hsnNo': hsnNo.trim(),
      'specification': specification.trim(),
      'accessories': accessories.trim(),
      'parametersMeasured': parametersMeasured.trim(),
      'basePrice': basePrice,
      'imageUrl': imageUrl.trim(),
      'productOverview': productOverview.trim(),
      'keyFeatures': keyFeatures.trim(),
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? make,
    String? model,
    String? hsnNo,
    String? specification,
    String? accessories,
    String? parametersMeasured,
    double? basePrice,
    String? imageUrl,
    String? productOverview,
    String? keyFeatures,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      make: make ?? this.make,
      model: model ?? this.model,
      hsnNo: hsnNo ?? this.hsnNo,
      specification: specification ?? this.specification,
      accessories: accessories ?? this.accessories,
      parametersMeasured: parametersMeasured ?? this.parametersMeasured,
      basePrice: basePrice ?? this.basePrice,
      imageUrl: imageUrl ?? this.imageUrl,
      productOverview: productOverview ?? this.productOverview,
      keyFeatures: keyFeatures ?? this.keyFeatures,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '')) ?? 0;
    return 0;
  }
}
