class AdditionalQuoteItem {
  const AdditionalQuoteItem({
    required this.description,
    this.specification = '',
    this.qty = '',
    this.unitRate = 0.0,
    this.amount = 0.0,
    this.itemType = 'additional',
  });

  final String description;
  final String specification;
  final String qty;
  final double unitRate;
  final double amount;

  /// `'calibration'` or `'additional'` (default). Missing on legacy docs.
  final String itemType;

  bool get isCalibration => itemType == 'calibration';

  factory AdditionalQuoteItem.fromJson(Map<String, dynamic> json) {
    return AdditionalQuoteItem(
      description: json['description'] as String? ?? '',
      specification: json['specification'] as String? ?? '',
      qty: json['qty'] as String? ?? '',
      unitRate: (json['unitRate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      itemType: json['itemType'] as String? ?? 'additional',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'specification': specification,
      'qty': qty,
      'unitRate': unitRate,
      'amount': amount,
      'itemType': itemType,
    };
  }
}

/// A single quoted product line. A quotation can contain one or more of these.
class QuoteProduct {
  const QuoteProduct({
    required this.productName,
    this.make = '',
    this.model = '',
    this.hsnNo = '',
    this.specification = '',
    this.accessories = '',
    this.documentAndCertificate = '',
    this.parametersMeasured = '',
    this.quantity = 1,
    this.unitPrice = 0.0,
    this.productImageUrl = '',
    this.srNo = '',
    this.productOverview = '',
    this.keyFeatures = '',
  });

  final String productName;
  final String make;
  final String model;
  final String hsnNo;
  final String specification;
  final String accessories;
  final String documentAndCertificate;
  final String parametersMeasured;
  final int quantity;
  final double unitPrice;
  final String productImageUrl;
  final String srNo;
  final String productOverview;
  final String keyFeatures;

  double get total => quantity * unitPrice;

  factory QuoteProduct.fromJson(Map<String, dynamic> json) {
    return QuoteProduct(
      productName: json['productName'] as String? ?? '',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      hsnNo: json['hsnNo'] as String? ?? '',
      specification: json['specification'] as String? ?? '',
      accessories: json['accessories'] as String? ?? '',
      documentAndCertificate: json['documentAndCertificate'] as String? ?? '',
      parametersMeasured: json['parametersMeasured'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      productImageUrl: json['productImageUrl'] as String? ?? '',
      srNo: json['srNo'] as String? ?? '',
      productOverview: json['productOverview'] as String? ?? '',
      keyFeatures: json['keyFeatures'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'make': make,
      'model': model,
      'hsnNo': hsnNo,
      'specification': specification,
      'accessories': accessories,
      'documentAndCertificate': documentAndCertificate,
      'parametersMeasured': parametersMeasured,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'productImageUrl': productImageUrl,
      'srNo': srNo,
      'productOverview': productOverview,
      'keyFeatures': keyFeatures,
    };
  }
}

class QuoteTerm {
  const QuoteTerm({required this.key, required this.value});
  final String key;
  final String value;

  factory QuoteTerm.fromJson(Map<String, dynamic> json) {
    return QuoteTerm(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
    };
  }
}

class QuoteRequest {
  const QuoteRequest({
    required this.refNo,
    required this.date,
    required this.customerName,
    required this.companyName,
    required this.location,
    required this.email,
    required this.phone,
    required this.products,
    this.additionalItems = const [],
    required this.termsPrices,
    required this.termsPf,
    required this.termsFreight,
    required this.termsPayment,
    required this.termsGst,
    required this.termsExcise,
    required this.termsValidity,
    required this.termsDelivery,
    required this.termsWarranty,
    this.companyType = 'ATEPL',
    this.terms = const [],
    this.discountAmount = 0,
  });

  final String refNo;
  final String date;
  final String customerName;
  final String companyName;
  final String location;
  final String email;
  final String phone;

  /// Quoted products. May be empty for calibration-only quotations.
  final List<QuoteProduct> products;

  final List<AdditionalQuoteItem> additionalItems;

  final String termsPrices;
  final String termsPf;
  final String termsFreight;
  final String termsPayment;
  final String termsGst;
  final String termsExcise;
  final String termsValidity;
  final String termsDelivery;
  final String termsWarranty;
  final String companyType;
  final List<QuoteTerm> terms;

  /// Flat discount in rupees applied to [grossAmount].
  ///
  /// Stored as an amount, not a percentage: the percentage is derived, so a
  /// re-opened quote can't silently drift when a line item changes. GST is a
  /// text term on this quote (nothing multiplies by 0.18), so the discount
  /// simply reduces the quoted base — which is what "GST after discount"
  /// means here.
  final double discountAmount;

  // Backward-compatible convenience getters (delegate to the first product) so
  // existing callers that read single-product fields keep working.
  QuoteProduct get _first =>
      products.isNotEmpty ? products.first : const QuoteProduct(productName: '');
  String get productName => _first.productName;
  String get make => _first.make;
  String get model => _first.model;
  String get hsnNo => _first.hsnNo;
  String get specification => _first.specification;
  String get accessories => _first.accessories;
  String get documentAndCertificate => _first.documentAndCertificate;
  String get parametersMeasured => _first.parametersMeasured;
  int get quantity => _first.quantity;
  double get unitPrice => _first.unitPrice;
  String get productImageUrl => _first.productImageUrl;

  double get primaryTotal {
    double total = 0;
    for (final p in products) {
      total += p.total;
    }
    return total;
  }

  /// Line-item total before any discount.
  double get grossAmount {
    double total = primaryTotal;
    for (final item in additionalItems) {
      total += item.amount;
    }
    return total;
  }

  /// Discount actually applied, never more than the gross.
  double get discountValue => discountAmount <= 0
      ? 0
      : (discountAmount > grossAmount ? grossAmount : discountAmount);

  /// Discount as a percentage of the gross, for display only.
  double get discountPercent =>
      grossAmount <= 0 ? 0 : (discountValue / grossAmount) * 100;

  bool get hasDiscount => discountValue > 0;

  /// Net payable. Deliberately still called `totalAmount` so every existing
  /// reader (lead amount, analytics, backups, the PDF totals row) picks up the
  /// discounted figure without changes.
  double get totalAmount => grossAmount - discountValue;

  factory QuoteRequest.fromJson(Map<String, dynamic> json) {
    List<QuoteProduct> products;
    final rawProducts = json['products'] as List<dynamic>?;
    if (rawProducts != null) {
      // Honor an explicit list, including empty (calibration-only quotes).
      products = rawProducts
          .map((e) => QuoteProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Legacy quotations stored a single product directly on the request.
      products = [
        QuoteProduct(
          productName: json['productName'] as String? ?? '',
          make: json['make'] as String? ?? '',
          model: json['model'] as String? ?? '',
          hsnNo: json['hsnNo'] as String? ?? '',
          specification: json['specification'] as String? ?? '',
          accessories: json['accessories'] as String? ?? '',
          documentAndCertificate: json['documentAndCertificate'] as String? ?? '',
          parametersMeasured: json['parametersMeasured'] as String? ?? '',
          quantity: json['quantity'] as int? ?? 1,
          unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
          productImageUrl: json['productImageUrl'] as String? ?? '',
        ),
      ];
    }

    final termsList = (json['terms'] as List<dynamic>?)
            ?.map((e) => QuoteTerm.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final termsPricesVal = json['termsPrices'] as String? ?? '';
    final termsPfVal = json['termsPf'] as String? ?? '';
    final termsFreightVal = json['termsFreight'] as String? ?? '';
    final termsPaymentVal = json['termsPayment'] as String? ?? '';
    final termsGstVal = json['termsGst'] as String? ?? '';
    final termsExciseVal = json['termsExcise'] as String? ?? '';
    final termsValidityVal = json['termsValidity'] as String? ?? '';
    final termsDeliveryVal = json['termsDelivery'] as String? ?? '';
    final termsWarrantyVal = json['termsWarranty'] as String? ?? '';

    final actualTerms = termsList.isNotEmpty
        ? termsList
        : [
            QuoteTerm(key: 'Prices', value: termsPricesVal),
            QuoteTerm(key: 'P&F', value: termsPfVal),
            QuoteTerm(key: 'Freight', value: termsFreightVal),
            QuoteTerm(key: 'Payment', value: termsPaymentVal),
            QuoteTerm(key: 'GST', value: termsGstVal),
            QuoteTerm(key: 'Excise', value: termsExciseVal),
            QuoteTerm(key: 'Validity', value: termsValidityVal),
            QuoteTerm(key: 'Delivery', value: termsDeliveryVal),
            QuoteTerm(key: 'Warranty', value: termsWarrantyVal),
          ];

    return QuoteRequest(
      refNo: json['refNo'] as String? ?? '',
      date: json['date'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      location: json['location'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      products: products,
      additionalItems: (json['additionalItems'] as List<dynamic>?)
              ?.map((e) => AdditionalQuoteItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      termsPrices: termsPricesVal,
      termsPf: termsPfVal,
      termsFreight: termsFreightVal,
      termsPayment: termsPaymentVal,
      termsGst: termsGstVal,
      termsExcise: termsExciseVal,
      termsValidity: termsValidityVal,
      termsDelivery: termsDeliveryVal,
      termsWarranty: termsWarrantyVal,
      companyType: json['companyType'] as String? ?? 'ATEPL',
      terms: actualTerms,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final firstProduct = _first;
    return {
      'refNo': refNo,
      'date': date,
      'customerName': customerName,
      'companyName': companyName,
      'location': location,
      'email': email,
      'phone': phone,
      'products': products.map((e) => e.toJson()).toList(),
      // Keep legacy single-product fields (first product) for safety so older
      // readers / dashboards that look at these directly still work.
      'productName': firstProduct.productName,
      'make': firstProduct.make,
      'model': firstProduct.model,
      'hsnNo': firstProduct.hsnNo,
      'specification': firstProduct.specification,
      'accessories': firstProduct.accessories,
      'documentAndCertificate': firstProduct.documentAndCertificate,
      'parametersMeasured': firstProduct.parametersMeasured,
      'quantity': firstProduct.quantity,
      'unitPrice': firstProduct.unitPrice,
      'productImageUrl': firstProduct.productImageUrl,
      'additionalItems': additionalItems.map((e) => e.toJson()).toList(),
      'termsPrices': termsPrices,
      'termsPf': termsPf,
      'termsFreight': termsFreight,
      'termsPayment': termsPayment,
      'termsGst': termsGst,
      'termsExcise': termsExcise,
      'termsValidity': termsValidity,
      'termsDelivery': termsDelivery,
      'termsWarranty': termsWarranty,
      'companyType': companyType,
      'terms': terms.map((e) => e.toJson()).toList(),
      'discountAmount': discountAmount,
    };
  }
}
