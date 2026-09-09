import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/lead_model.dart';
import '../../models/product_model.dart';
import '../../models/quote_request.dart';
import '../../models/quotation_model.dart';
import '../../services/pdf_service.dart';
import '../../utils/quote_pdf_save.dart';
import '../../services/product_service.dart';
import '../../services/quotation_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Editable controllers backing a single quoted product line.
class ProductItemFields {
  ProductItemFields({String srNo = ''})
    : nameController = TextEditingController(),
      makeController = TextEditingController(text: 'Applied Techno Systems'),
      modelController = TextEditingController(),
      hsnController = TextEditingController(text: '90271000'),
      overviewController = TextEditingController(),
      featuresController = TextEditingController(),
      specController = TextEditingController(),
      accessoriesController = TextEditingController(),
      documentController = TextEditingController(),
      parametersController = TextEditingController(),
      qtyController = TextEditingController(text: '1'),
      priceController = TextEditingController(),
      srNoController = TextEditingController(text: srNo);

  final TextEditingController nameController;
  final TextEditingController makeController;
  final TextEditingController modelController;
  final TextEditingController hsnController;
  final TextEditingController overviewController;
  final TextEditingController featuresController;
  final TextEditingController specController;
  final TextEditingController accessoriesController;
  final TextEditingController documentController;
  final TextEditingController parametersController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController srNoController;
  String imageUrl = '';

  void dispose() {
    nameController.dispose();
    makeController.dispose();
    modelController.dispose();
    hsnController.dispose();
    overviewController.dispose();
    featuresController.dispose();
    specController.dispose();
    accessoriesController.dispose();
    documentController.dispose();
    parametersController.dispose();
    qtyController.dispose();
    priceController.dispose();
    srNoController.dispose();
  }
}

class AdditionalItemFields {
  AdditionalItemFields({this.itemType = 'additional'})
    : descController = TextEditingController(),
      specController = TextEditingController(),
      qtyController = TextEditingController(text: '1 NO'),
      rateController = TextEditingController();

  final TextEditingController descController;
  final TextEditingController specController;
  final TextEditingController qtyController;
  final TextEditingController rateController;
  String itemType;

  bool get isCalibration => itemType == 'calibration';

  void dispose() {
    descController.dispose();
    specController.dispose();
    qtyController.dispose();
    rateController.dispose();
  }
}

enum _QuotationSaveMode { updateCurrent, createRevision }

class TermItemFields {
  TermItemFields({String key = '', String value = ''})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class QuoteBuilderDialog extends StatefulWidget {
  const QuoteBuilderDialog({
    super.key,
    required this.lead,
    this.productService,
    this.existingQuotation,
    this.initialCompanyType = 'ATEPL',
  });

  final Lead lead;
  final ProductService? productService;
  final QuotationModel? existingQuotation;
  final String initialCompanyType;

  @override
  State<QuoteBuilderDialog> createState() => _QuoteBuilderDialogState();
}

class _QuoteBuilderDialogState extends State<QuoteBuilderDialog> {
  // Client & Ref
  late final TextEditingController _refNoController;
  late final TextEditingController _dateController;
  late final TextEditingController _customerNameController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _locationController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  // Products (one or more)
  final List<ProductItemFields> _products = [];

  // Additional items
  final List<AdditionalItemFields> _additionalItems = [];

  // Terms & Conditions
  final List<TermItemFields> _terms = [];
  late String _companyType;

  // Discount on the quote total. The rupee amount is the source of truth; the
  // percent field is a view onto it, so a changed line item can't silently
  // move the discount. `_syncingDiscount` breaks the two-way feedback loop
  // between the linked fields.
  final TextEditingController _discountPercentController =
      TextEditingController();
  final TextEditingController _discountAmountController =
      TextEditingController();
  double _discountAmount = 0;
  bool _syncingDiscount = false;

  bool _busy = false;
  QuotationModel? _activeQuotation;
  bool _hasCreatedNewRevisionThisSession = false;

  @override
  void initState() {
    super.initState();
    _activeQuotation = widget.existingQuotation;
    final lead = widget.lead;

    final eq = widget.existingQuotation?.quoteRequest;

    if (eq != null) {
      _companyType = eq.companyType.isNotEmpty ? eq.companyType : 'ATEPL';
      _refNoController = TextEditingController(text: eq.refNo);
      _dateController = TextEditingController(text: eq.date);
      _customerNameController = TextEditingController(text: eq.customerName);
      _companyNameController = TextEditingController(text: eq.companyName);
      _locationController = TextEditingController(text: eq.location);
      _emailController = TextEditingController(text: eq.email);
      _phoneController = TextEditingController(text: eq.phone);

      if (eq.products.isNotEmpty) {
        for (var i = 0; i < eq.products.length; i++) {
          _products.add(_productFieldsFrom(eq.products[i], i));
        }
      }

      if (eq.additionalItems.isNotEmpty) {
        for (final item in eq.additionalItems) {
          final fields = AdditionalItemFields(itemType: item.itemType);
          fields.descController.text = item.description;
          fields.specController.text = item.specification;
          fields.qtyController.text = item.qty;
          fields.rateController.text = item.unitRate > 0
              ? item.unitRate.toString()
              : '';
          _additionalItems.add(fields);
        }
      } else {
        if (_companyType != 'ATS') {
          _populateDefaultAdditionalItems();
        }
      }

      for (final term in eq.terms) {
        _terms.add(TermItemFields(key: term.key, value: term.value));
      }

      _discountAmount = eq.discountAmount;
    } else {
      _companyType = widget.initialCompanyType;
      // Ref No generation ATEPL/XXXX/YYYY-YYYY or ATS/XXXX/YYYY-YYYY
      final seq = (100 + DateTime.now().millisecond).toString().padLeft(4, '0');
      final currentYear = DateTime.now().year;
      _refNoController = TextEditingController(
        text: '$_companyType/$seq/$currentYear-${currentYear + 1}',
      );

      // Date formatting dd.MM.yyyy
      final day = DateTime.now().day.toString().padLeft(2, '0');
      final month = DateTime.now().month.toString().padLeft(2, '0');
      _dateController = TextEditingController(text: '$day.$month.$currentYear');

      _customerNameController = TextEditingController(text: lead.name);
      _companyNameController = TextEditingController(text: lead.company);
      _locationController = TextEditingController(
        text: lead.location.isNotEmpty
            ? lead.location
            : 'Mumbai, Maharashtra, India.',
      );
      _emailController = TextEditingController(text: lead.email);
      _phoneController = TextEditingController(text: lead.phone);

      // Prefill all products from lead (supports multiple product lines).
      // Both formats now carry the same product/technical fields, so ATS is
      // seeded exactly like ATEPL.
      final leadProducts = lead.activeProductLines;
      if (leadProducts.isNotEmpty) {
        for (final line in leadProducts) {
          final fields = ProductItemFields();
          fields.nameController.text = line.requirement;
          fields.modelController.text = line.modelNo;
          _products.add(fields);
        }
      } else {
        final first = ProductItemFields();
        first.nameController.text = lead.requirement;
        first.modelController.text = lead.modelNo;
        _products.add(first);
      }

      if (_companyType != 'ATS') {
        // Cable + installation defaults are ATEPL boilerplate; an ATS quote
        // starts with only what the user actually adds.
        _populateDefaultAdditionalItems();
      }
      _populateDefaultTerms(_companyType == 'ATS');
    }

    // Watchers to update Line total
    for (final p in _products) {
      _attachProductListeners(p);
    }
    for (final item in _additionalItems) {
      item.qtyController.addListener(_onTotalsChanged);
      item.rateController.addListener(_onTotalsChanged);
    }

    if (widget.existingQuotation == null) {
      _prefillUnitPriceFromCatalog();
    }

    // Render a discount restored from an existing quotation into both fields.
    _syncDiscountFields();
  }

  ProductItemFields _productFieldsFrom(QuoteProduct p, int index) {
    final fields = ProductItemFields(
      srNo: p.srNo.isNotEmpty ? p.srNo : (index + 1).toString(),
    );
    fields.nameController.text = p.productName;
    fields.makeController.text = p.make;
    fields.modelController.text = p.model;
    fields.hsnController.text = p.hsnNo;
    fields.overviewController.text = p.productOverview;
    fields.featuresController.text = p.keyFeatures;
    fields.specController.text = p.specification;
    fields.accessoriesController.text = p.accessories;
    fields.documentController.text = p.documentAndCertificate;
    fields.parametersController.text = p.parametersMeasured;
    fields.qtyController.text = p.quantity.toString();
    fields.priceController.text = p.unitPrice > 0 ? p.unitPrice.toString() : '';
    fields.imageUrl = p.productImageUrl;
    return fields;
  }

  void _attachProductListeners(ProductItemFields p) {
    p.qtyController.addListener(_onTotalsChanged);
    p.priceController.addListener(_onTotalsChanged);
  }

  void _onTotalsChanged() {
    if (!mounted) return;
    setState(() {
      // The rupee discount is fixed, so a changed line item moves the
      // percentage. Re-clamp too: the discount can never exceed the gross.
      final gross = _runningGross();
      if (_discountAmount > gross) _discountAmount = gross;
    });
    _syncDiscountFields();
  }

  void _populateDefaultAdditionalItems() {
    final cableItem = AdditionalItemFields();
    cableItem.descController.text =
        '3 core shielded cable Rs. 135 per meter as per site requirement';
    cableItem.qtyController.text = '1 NO';
    cableItem.rateController.text = '';

    final instItem = AdditionalItemFields();
    instItem.descController.text = 'Installation Commissioning @ 15,000/-';
    instItem.qtyController.text = '1 NO';
    instItem.rateController.text = '15000';

    _additionalItems.addAll([cableItem, instItem]);
  }

  Future<void> _prefillUnitPriceFromCatalog() async {
    final svc = widget.productService;
    if (svc == null) return;
    try {
      final products = await svc.fetchProductsOnce();
      if (!mounted) return;
      if (_products.isEmpty) return;
      setState(() {
        for (final fields in _products) {
          final name = fields.nameController.text.trim();
          if (name.isEmpty) continue;
          final match = _matchProduct(products, name);
          if (match == null) continue;
          _applyCatalogProduct(fields, match);
        }
      });
    } catch (_) {}
  }

  Product? _matchProduct(List<Product> products, String requirement) {
    final r = requirement.trim().toLowerCase();
    if (r.isEmpty) return null;
    for (final p in products) {
      if (p.name.trim().toLowerCase() == r) return p;
    }
    return null;
  }

  void _applyCatalogProduct(ProductItemFields fields, Product catalog) {
    fields.nameController.text = catalog.name;
    fields.makeController.text = catalog.make.isNotEmpty
        ? catalog.make
        : 'Applied Techno Systems';
    fields.modelController.text = catalog.model;
    fields.hsnController.text = catalog.hsnNo.isNotEmpty
        ? catalog.hsnNo
        : '90271000';
    fields.overviewController.text = catalog.productOverview;
    fields.featuresController.text = catalog.keyFeatures;
    fields.specController.text = catalog.specification;
    fields.accessoriesController.text = catalog.accessories;
    fields.parametersController.text = catalog.parametersMeasured;
    if (catalog.basePrice > 0) {
      fields.priceController.text = catalog.basePrice.toStringAsFixed(2);
    }
    fields.imageUrl = catalog.imageUrl;
  }

  /// Catalog used for product-name autocomplete.
  ///
  /// Built once. It used to be constructed inline in the field builder, which
  /// meant a fresh Firestore-backed service and stream subscription on every
  /// rebuild of a product card. Null when there is no catalog to offer.
  late final ProductService? _catalogService = _resolveCatalogService();

  ProductService? _resolveCatalogService() {
    if (widget.productService != null) return widget.productService;
    try {
      return ProductService();
    } catch (_) {
      return null;
    }
  }

  Widget _buildProductNameField(
    ProductItemFields p, {
    bool required = false,
    String label = 'Product / System Name *',
    String hint = 'Search catalog or type a product name',
    String emptyMessage = 'Please enter product name',
  }) {
    final svc = _catalogService;
    return StreamBuilder<List<Product>>(
      // No catalog service (or Firebase unavailable) just means no
      // autocomplete suggestions — the field still accepts a typed name.
      stream: svc?.getProductsStream(),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Product>[];
        return Autocomplete<Product>(
          displayStringForOption: (product) => product.name,
          optionsBuilder: (TextEditingValue tev) {
            final q = tev.text.trim().toLowerCase();
            if (q.isEmpty) return products.take(20);
            return products
                .where((product) => product.name.toLowerCase().contains(q))
                .take(30);
          },
          onSelected: (catalog) {
            setState(() => _applyCatalogProduct(p, catalog));
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
                if (p.nameController.text.isNotEmpty &&
                    textEditingController.text.isEmpty) {
                  textEditingController.text = p.nameController.text;
                }
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.next,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: required
                      ? (value) {
                          if (value == null || value.trim().isEmpty) {
                            return emptyMessage;
                          }
                          return null;
                        }
                      : null,
                  enabled: !_busy,
                  onChanged: (value) {
                    p.nameController.text = value;
                  },
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                );
              },
        );
      },
    );
  }

  @override
  void dispose() {
    _refNoController.dispose();
    _dateController.dispose();
    _customerNameController.dispose();
    _companyNameController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _discountPercentController.dispose();
    _discountAmountController.dispose();

    for (final p in _products) {
      p.dispose();
    }
    for (final item in _additionalItems) {
      item.dispose();
    }
    for (final t in _terms) {
      t.dispose();
    }
    super.dispose();
  }

  void _populateDefaultTerms(bool isAts) {
    for (final t in _terms) {
      t.dispose();
    }
    _terms.clear();

    if (isAts) {
      _terms.addAll([
        TermItemFields(key: 'Prices', value: 'Ex-Works, Mumbai'),
        TermItemFields(key: 'P&F', value: 'Nil'),
        TermItemFields(key: 'Freight', value: 'Extra at actual.'),
        TermItemFields(key: 'Payment', value: '100% Advance'),
        TermItemFields(key: 'GST', value: '18% Extra'),
        TermItemFields(key: 'Excise', value: 'Nil'),
        TermItemFields(key: 'Validity', value: '90 days'),
        TermItemFields(key: 'Delivery', value: '1-2 week'),
      ]);
    } else {
      _terms.addAll([
        TermItemFields(key: 'Prices', value: 'Ex-Works, Mumbai'),
        TermItemFields(key: 'P&F', value: '2% Extra'),
        TermItemFields(key: 'Freight', value: '2% Extra'),
        TermItemFields(key: 'Payment', value: '40% Advance & 60% against PI'),
        TermItemFields(key: 'GST', value: '18%'),
        TermItemFields(key: 'Excise', value: 'Nil'),
        TermItemFields(key: 'Validity', value: '90 days.'),
        TermItemFields(key: 'Delivery', value: '2-3 Weeks'),
        TermItemFields(key: 'Warranty', value: 'One year.'),
      ]);
    }
  }

  void _addTerm() {
    setState(() {
      _terms.add(TermItemFields());
    });
  }

  void _removeTerm(int index) {
    setState(() {
      _terms[index].dispose();
      _terms.removeAt(index);
    });
  }

  void _changeCompanyType(String newType) {
    if (_companyType == newType) return;
    setState(() {
      _companyType = newType;

      // Update Ref No prefix if it starts with the old prefix
      final ref = _refNoController.text.trim();
      final oldPrefix = newType == 'ATS' ? 'ATEPL/' : 'ATS/';
      final newPrefix = newType == 'ATS' ? 'ATS/' : 'ATEPL/';
      if (ref.startsWith(oldPrefix)) {
        _refNoController.text = ref.replaceFirst(oldPrefix, newPrefix);
      }

      _populateDefaultTerms(newType == 'ATS');

      // Both formats hold the same product fields now, so nothing typed so
      // far is thrown away when the letterhead is switched.
      if (_products.isEmpty) {
        final leadProducts = widget.lead.activeProductLines;
        if (leadProducts.isNotEmpty) {
          for (final line in leadProducts) {
            final fields = ProductItemFields();
            fields.nameController.text = line.requirement;
            fields.modelController.text = line.modelNo;
            _products.add(fields);
          }
        } else {
          final first = ProductItemFields();
          first.nameController.text = widget.lead.requirement;
          first.modelController.text = widget.lead.modelNo;
          _products.add(first);
        }
        for (final p in _products) {
          _attachProductListeners(p);
        }
      }
      if (newType != 'ATS' && _additionalItems.isEmpty) {
        _populateDefaultAdditionalItems();
        for (final item in _additionalItems) {
          item.qtyController.addListener(_onTotalsChanged);
          item.rateController.addListener(_onTotalsChanged);
        }
      }
    });
  }

  String _findTermValue(List<QuoteTerm> terms, String key) {
    final term = terms.firstWhere(
      (t) => t.key.toLowerCase() == key.toLowerCase(),
      orElse: () => const QuoteTerm(key: '', value: ''),
    );
    return term.value;
  }

  Future<String> _getEmployeeName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    String empName = user.displayName ?? user.email ?? 'Employee';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists &&
          doc.data() != null &&
          doc.data()!['name'] != null &&
          doc.data()!['name'].toString().trim().isNotEmpty) {
        empName = doc.data()!['name'].toString().trim();
      }
    } catch (_) {}
    return empName;
  }

  int _parseQty(String raw) {
    final v = int.tryParse(raw.trim());
    return (v == null || v < 1) ? 1 : v;
  }

  double _parsePrice(String raw) {
    return double.tryParse(raw.trim().replaceAll(',', '')) ?? 0.0;
  }

  /// Line-item total before the discount.
  double _runningGross() {
    double total = 0;
    for (final p in _products) {
      total +=
          _parseQty(p.qtyController.text) * _parsePrice(p.priceController.text);
    }
    for (final item in _additionalItems) {
      final rate = _parsePrice(item.rateController.text);
      final qtyRaw = item.qtyController.text.trim();
      final qtyNumMatch = RegExp(r'^\d+').firstMatch(qtyRaw);
      final qtyVal = qtyNumMatch != null
          ? (double.tryParse(qtyNumMatch.group(0)!) ?? 1.0)
          : 1.0;
      total += qtyVal * rate;
    }
    return total;
  }

  /// Discount in rupees, clamped to the gross.
  double _runningDiscount() {
    final gross = _runningGross();
    if (_discountAmount <= 0 || gross <= 0) return 0;
    return _discountAmount > gross ? gross : _discountAmount;
  }

  /// Net payable — what the PDF and the lead's deal amount both use.
  double _runningTotal() => _runningGross() - _runningDiscount();

  /// Renders the discount into both linked fields without re-triggering their
  /// onChanged handlers.
  void _syncDiscountFields({bool percent = true, bool amount = true}) {
    _syncingDiscount = true;
    final gross = _runningGross();
    if (amount) {
      _discountAmountController.text = _discountAmount <= 0
          ? ''
          : _trimNumber(_discountAmount);
    }
    if (percent) {
      final pct = (gross <= 0 || _discountAmount <= 0)
          ? 0.0
          : (_runningDiscount() / gross) * 100;
      _discountPercentController.text = pct <= 0 ? '' : _trimNumber(pct);
    }
    _syncingDiscount = false;
  }

  static String _trimNumber(double v) {
    final rounded = (v * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  void _onDiscountPercentChanged(String raw) {
    if (_syncingDiscount) return;
    final pct = (double.tryParse(raw.trim()) ?? 0).clamp(0.0, 100.0);
    final gross = _runningGross();
    setState(() {
      // Round to whole rupees so the PDF's 0-decimal formatting matches the
      // number we actually store.
      _discountAmount = (gross * pct / 100).roundToDouble();
    });
    _syncDiscountFields(percent: false);
  }

  void _onDiscountAmountChanged(String raw) {
    if (_syncingDiscount) return;
    final gross = _runningGross();
    final amt = (double.tryParse(raw.trim().replaceAll(',', '')) ?? 0)
        .clamp(0.0, gross <= 0 ? double.maxFinite : gross);
    setState(() => _discountAmount = amt);
    _syncDiscountFields(amount: false);
  }

  bool get _hasValidProduct {
    for (final p in _products) {
      final name = p.nameController.text.trim();
      final q = int.tryParse(p.qtyController.text.trim());
      if (name.isNotEmpty && q != null && q >= 1) return true;
    }
    return false;
  }

  bool get _hasValidAdditionalLine {
    for (final item in _additionalItems) {
      if (item.descController.text.trim().isEmpty) continue;
      final qtyRaw = item.qtyController.text.trim();
      if (qtyRaw.isEmpty) continue;
      return true;
    }
    return false;
  }

  bool get _actionsEnabled {
    if (_busy) return false;
    return _hasValidProduct || _hasValidAdditionalLine;
  }

  String _digitsOnlyPhone(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  QuoteRequest _buildQuoteRequest() {
    final products = _products
        .where((p) => p.nameController.text.trim().isNotEmpty)
        .map((p) {
          return QuoteProduct(
            productName: p.nameController.text.trim(),
            make: p.makeController.text.trim(),
            model: p.modelController.text.trim(),
            hsnNo: p.hsnController.text.trim(),
            productOverview: p.overviewController.text.trim(),
            keyFeatures: p.featuresController.text.trim(),
            specification: p.specController.text.trim(),
            accessories: p.accessoriesController.text.trim(),
            documentAndCertificate: p.documentController.text.trim(),
            parametersMeasured: p.parametersController.text.trim(),
            quantity: _parseQty(p.qtyController.text),
            unitPrice: _parsePrice(p.priceController.text),
            productImageUrl: p.imageUrl,
            srNo: p.srNoController.text.trim(),
          );
        })
        .toList();

    final addItems = _additionalItems
        .where((item) => item.descController.text.trim().isNotEmpty)
        .map((item) {
          final rate = _parsePrice(item.rateController.text);
          final qtyRaw = item.qtyController.text.trim();
          final qtyNumMatch = RegExp(r'^\d+').firstMatch(qtyRaw);
          final qtyVal = qtyNumMatch != null
              ? (double.tryParse(qtyNumMatch.group(0)!) ?? 1.0)
              : 1.0;
          return AdditionalQuoteItem(
            description: item.descController.text,
            specification: item.specController.text.trim(),
            qty: item.qtyController.text,
            unitRate: rate,
            amount: qtyVal * rate,
            itemType: item.itemType,
          );
        })
        .toList()
      ..sort((a, b) {
        if (a.isCalibration == b.isCalibration) return 0;
        return a.isCalibration ? -1 : 1;
      });

    final terms = _terms.map((t) {
      return QuoteTerm(
        key: t.keyController.text.trim(),
        value: t.valueController.text.trim(),
      );
    }).toList();

    return QuoteRequest(
      refNo: _refNoController.text.trim(),
      date: _dateController.text.trim(),
      customerName: _customerNameController.text.trim(),
      companyName: _companyNameController.text.trim(),
      location: _locationController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      products: products,
      additionalItems: addItems,
      termsPrices: _findTermValue(terms, 'Prices'),
      termsPf: _findTermValue(terms, 'P&F'),
      termsFreight: _findTermValue(terms, 'Freight'),
      termsPayment: _findTermValue(terms, 'Payment'),
      termsGst: _findTermValue(terms, 'GST'),
      termsExcise: _findTermValue(terms, 'Excise'),
      termsValidity: _findTermValue(terms, 'Validity'),
      termsDelivery: _findTermValue(terms, 'Delivery'),
      termsWarranty: _findTermValue(terms, 'Warranty'),
      companyType: _companyType,
      terms: terms,
      discountAmount: _runningDiscount(),
    );
  }

  bool get _shouldAskRevisionChoice =>
      _activeQuotation != null && !_hasCreatedNewRevisionThisSession;

  String _buildRevisionRefNo(String baseRef, int revision) {
    final parts = baseRef.split('/');
    if (parts.length >= 3) {
      final lastPart = parts.last;
      final headParts = parts.sublist(0, parts.length - 1).join('/');
      return '$headParts-R$revision/$lastPart';
    }
    return '$baseRef-R$revision';
  }

  Future<_QuotationSaveMode?> _askQuotationSaveMode() async {
    final active = _activeQuotation;
    if (active == null || !mounted) return _QuotationSaveMode.createRevision;

    final nextRevision = active.revision + 1;
    final baseRef = active.baseRefNo.isNotEmpty
        ? active.baseRefNo
        : active.currentRefNo;
    final currentRef = active.currentRefNo.isNotEmpty
        ? active.currentRefNo
        : _refNoController.text.trim();
    final revisionRef = _buildRevisionRefNo(baseRef, nextRevision);

    return showDialog<_QuotationSaveMode>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Reference number choose karein'),
        content: Text(
          'Is quotation ko kaise save karna hai?\n\n'
          'Current: $currentRef\n'
          'New revision: $revisionRef',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_QuotationSaveMode.updateCurrent),
            child: Text('Update $currentRef'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_QuotationSaveMode.createRevision),
            child: Text('Create R$nextRevision'),
          ),
        ],
      ),
    );
  }

  Future<QuoteRequest> _saveQuotationToDb(
    QuoteRequest quote, {
    _QuotationSaveMode? saveMode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return quote;

    final svc = QuotationService();

    String empName = user.displayName ?? user.email ?? 'Employee';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists &&
          doc.data() != null &&
          doc.data()!['name'] != null &&
          doc.data()!['name'].toString().trim().isNotEmpty) {
        empName = doc.data()!['name'].toString().trim();
      }
    } catch (_) {}

    if (_activeQuotation == null) {
      // Brand new
      final baseRef = quote.refNo;
      final newQuote = QuotationModel(
        id: '',
        leadId: widget.lead.id,
        employeeId: user.uid,
        employeeName: empName,
        createdAt: DateTime.now(),
        baseRefNo: baseRef,
        currentRefNo: baseRef,
        revision: 0,
        quoteRequest: quote,
      );
      _activeQuotation = await svc.saveQuotation(newQuote);
      _hasCreatedNewRevisionThisSession = true;
      return quote;
    } else {
      if (!_hasCreatedNewRevisionThisSession) {
        final mode = saveMode ?? _QuotationSaveMode.createRevision;
        if (mode == _QuotationSaveMode.updateCurrent) {
          final currentRef = _activeQuotation!.currentRefNo.isNotEmpty
              ? _activeQuotation!.currentRefNo
              : quote.refNo;
          final updatedQuoteRequest = QuoteRequest.fromJson({
            ...quote.toJson(),
            'refNo': currentRef,
          });
          final updatedQuote = _activeQuotation!.copyWith(
            currentRefNo: currentRef,
            quoteRequest: updatedQuoteRequest,
          );
          _activeQuotation = await svc.saveQuotation(updatedQuote);
          _refNoController.text = currentRef;
          return updatedQuoteRequest;
        }

        // We are editing a previous quote, create a new revision
        final newRev = _activeQuotation!.revision + 1;
        final baseRef = _activeQuotation!.baseRefNo.isNotEmpty
            ? _activeQuotation!.baseRefNo
            : quote.refNo;
        final newRefNo = _buildRevisionRefNo(baseRef, newRev);

        // Update the ref number in the quote request too
        final updatedQuote = QuoteRequest.fromJson({
          ...quote.toJson(),
          'refNo': newRefNo,
        });

        final newQuote = QuotationModel(
          id: '', // New document
          leadId: widget.lead.id,
          employeeId: user.uid, // new editor
          employeeName: empName,
          createdAt: DateTime.now(),
          baseRefNo: baseRef,
          currentRefNo: newRefNo,
          revision: newRev,
          quoteRequest: updatedQuote,
        );
        _activeQuotation = await svc.saveQuotation(newQuote);
        _hasCreatedNewRevisionThisSession = true;
        // Update controller so UI shows the new ref no
        _refNoController.text = newRefNo;
        return updatedQuote;
      } else {
        // We already created a new revision this session, just update it
        final updatedQuote = _activeQuotation!.copyWith(quoteRequest: quote);
        _activeQuotation = await svc.saveQuotation(updatedQuote);
        return quote;
      }
    }
  }

  /// Extracts the short quotation number from a ref like `ATEPL/1069/2026-2027`
  /// -> `1069` (keeps revision suffixes like `1069-R1`).
  String _shortQuoteNumber() {
    final ref = _refNoController.text.trim();
    if (ref.isEmpty) return '';
    final parts = ref.split('/');
    String candidate;
    if (parts.length >= 2) {
      // Middle segment is the running quotation number.
      candidate = parts[1].trim();
    } else {
      candidate = ref;
    }
    return candidate.replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  String _buildFilename() {
    final nameSource = _companyNameController.text.trim().isNotEmpty
        ? _companyNameController.text.trim()
        : _customerNameController.text.trim();
    final safeName = nameSource.isEmpty
        ? 'quotation'
        : nameSource.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final number = _shortQuoteNumber();
    if (number.isEmpty) return '${safeName}_quotation.pdf';
    return '${safeName}_$number.pdf';
  }

  Future<void> _saveOnly() async {
    if (!_actionsEnabled) return;
    final messenger = ScaffoldMessenger.of(context);
    final askRevisionChoice = _shouldAskRevisionChoice;
    final saveMode = askRevisionChoice ? await _askQuotationSaveMode() : null;
    if (askRevisionChoice && saveMode == null) return;
    setState(() => _busy = true);
    try {
      QuoteRequest quote = _buildQuoteRequest();
      quote = await _saveQuotationToDb(quote, saveMode: saveMode);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Quotation saved successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Save Error: $e\n$stack');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not save quotation: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _getEmployeeMobile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['mobile']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showPdfSavedFeedback({
    required String filename,
    required String message,
    String? path,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF16A34A),
          size: 40,
        ),
        title: const Text('PDF saved'),
        content: Text(
          '$message\n\nFile: $filename',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          if (path != null)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                OpenFile.open(path);
              },
              child: const Text('Open PDF'),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf() async {
    if (!_actionsEnabled) return;
    final messenger = ScaffoldMessenger.of(context);
    final askRevisionChoice = _shouldAskRevisionChoice;
    final saveMode = askRevisionChoice ? await _askQuotationSaveMode() : null;
    if (askRevisionChoice && saveMode == null) return;
    setState(() => _busy = true);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generating PDF…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      QuoteRequest quote = _buildQuoteRequest();
      quote = await _saveQuotationToDb(quote, saveMode: saveMode);
      final mobile = await _getEmployeeMobile();
      final empName = await _getEmployeeName();
      final bytes = await PdfService().generateQuoteData(
        widget.lead,
        quote,
        creatorMobile: mobile,
        creatorName: empName,
      );
      final filename = _buildFilename();

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Download started: $filename'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final saved = await saveQuotePdf(bytes: bytes, filename: filename);
      if (!mounted) return;

      if (saved.success) {
        await _showPdfSavedFeedback(
          filename: filename,
          message: saved.message ?? 'Saved to Downloads folder.',
          path: saved.path,
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(saved.error ?? 'Could not save PDF.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Download Error: $e\n$stack');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not download PDF: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsappQuote() async {
    if (!_actionsEnabled) return;
    final messenger = ScaffoldMessenger.of(context);
    final digits = _digitsOnlyPhone(_phoneController.text);
    if (digits.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Add a valid phone number on the customer details first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      QuoteRequest quote = _buildQuoteRequest();
      quote = await _saveQuotationToDb(quote);
      final mobile = await _getEmployeeMobile();
      final empName = await _getEmployeeName();
      final bytes = await PdfService().generateQuoteData(
        widget.lead,
        quote,
        creatorMobile: mobile,
        creatorName: empName,
      );
      final filename = _buildFilename();

      final name = _customerNameController.text.trim();
      final greeting = name.isEmpty ? 'Hi there' : 'Hi $name';
      final text =
          '$greeting, please find attached your quotation from '
          'Applied Techno Engineers.';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        final uri = Uri.parse(
          'https://wa.me/$digits?text=${Uri.encodeComponent(text)}',
        );
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not open WhatsApp.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/pdf', name: filename)],
        text: text,
        subject: 'Quotation from Applied Techno Engineers',
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not share quotation.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addProduct() {
    setState(() {
      final nextSrNo = (_products.length + 1).toString();
      final p = ProductItemFields(srNo: nextSrNo);
      _attachProductListeners(p);
      _products.add(p);
    });
  }

  void _removeProduct(int index) {
    setState(() {
      _products[index].dispose();
      _products.removeAt(index);
    });
  }

  void _addCalibration() {
    setState(() {
      final item = AdditionalItemFields(itemType: 'calibration');
      item.qtyController.addListener(_onTotalsChanged);
      item.rateController.addListener(_onTotalsChanged);
      _additionalItems.add(item);
    });
  }

  void _addCustomLineItem() {
    setState(() {
      final item = AdditionalItemFields();
      item.qtyController.addListener(_onTotalsChanged);
      item.rateController.addListener(_onTotalsChanged);
      _additionalItems.add(item);
    });
  }

  void _removeAdditionalItem(int index) {
    setState(() {
      _additionalItems[index].dispose();
      _additionalItems.removeAt(index);
    });
  }

  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// Wide enough to lay fields out in two columns instead of one tall stack.
  ///
  /// The dialog used to be pinned to 720x620 whatever the screen, so on a
  /// desktop it showed a handful of fields at a time and scrolling pushed the
  /// context off the top. It now takes the space that is actually available.
  bool _isWideLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1000;

  /// Lays [children] out in [columns] columns, or stacked when narrow.
  Widget _fieldGrid(
    List<Widget> children, {
    required int columns,
    double gap = 14,
  }) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.skip(i).take(columns).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: gap),
              // Pad the final row so a lone field keeps its column width
              // instead of stretching across the dialog.
              Expanded(child: c < slice.length ? slice[c] : const SizedBox()),
            ],
          ],
        ),
      );
      if (i + columns < children.length) rows.add(SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// Heading for a group of fields, so the form reads as sections rather than
  /// one undifferentiated column of boxes.
  Widget _sectionHeading(
    ThemeData theme,
    String title, {
    String? subtitle,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One of the two linked discount inputs.
  ///
  /// No floating [InputDecoration.labelText]: in a box this narrow the label
  /// filled the whole field when empty, so there was visibly nowhere to type.
  /// The unit sits in a prefix/suffix instead, and the pair is captioned once.
  Widget _buildDiscountField({
    required ThemeData theme,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? prefix,
    String? suffix,
    required String tooltip,
    bool compact = false,
  }) {
    final unitStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: compact ? 104 : 132,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: '0',
            prefixText: prefix,
            prefixStyle: unitStyle,
            suffixText: suffix,
            suffixStyle: unitStyle,
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: compact ? 8 : 12,
            ),
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildTotalAmountBar(ThemeData theme, double total, bool compact) {
    final gross = _runningGross();
    final discount = _runningDiscount();
    final hasDiscount = discount > 0;

    final amount = Text(
      'INR ${_formatPrice(total)}/-',
      style:
          (compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)
              ?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
    );
    final label = Text(
      hasDiscount
          ? 'Net Quoted Amount (IN Rs)'
          : 'Total Quoted Amount (IN Rs)',
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
    );

    // Enter either field; the other follows. The rupee amount is what gets
    // saved, so the percentage can never drift out of sync with it.
    final percentField = _buildDiscountField(
      theme: theme,
      controller: _discountPercentController,
      suffix: ' %',
      tooltip: 'Discount as a percentage of the sub total',
      onChanged: _onDiscountPercentChanged,
      compact: compact,
    );
    final amountField = _buildDiscountField(
      theme: theme,
      controller: _discountAmountController,
      prefix: '₹ ',
      tooltip: 'Discount in rupees',
      onChanged: _onDiscountAmountChanged,
      compact: compact,
    );

    // On a phone the caption and both boxes cannot share one line, and the
    // bottom bar has little vertical room to spare — so keep it to one row of
    // fields with a short inline caption.
    final discountRow = compact
        ? Row(
            children: [
              Expanded(
                child: Text(
                  'Discount',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              percentField,
              const SizedBox(width: 8),
              amountField,
            ],
          )
        : Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Discount',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Type either box — the other follows.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              percentField,
              const SizedBox(width: 10),
              amountField,
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 12,
          horizontal: compact ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasDiscount) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Sub Total',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    'INR ${_formatPrice(gross)}/-',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            discountRow,
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: label),
                const SizedBox(width: 8),
                amount,
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool compact) {
    final btnHeight = compact ? 36.0 : 44.0;
    final btnPadding = EdgeInsets.symmetric(
      horizontal: compact ? 12 : 16,
      vertical: compact ? 8 : 12,
    );
    final iconSize = compact ? 18.0 : 24.0;

    final downloadBtn = FilledButton.icon(
      onPressed: _actionsEnabled ? _downloadPdf : null,
      icon: _busy
          ? SizedBox(
              width: iconSize,
              height: iconSize,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(Icons.picture_as_pdf_rounded, size: iconSize),
      label: Text(
        _busy ? 'Please wait…' : 'Save & Download PDF',
        style: compact ? const TextStyle(fontSize: 13) : null,
      ),
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? double.infinity : 0, btnHeight),
        padding: btnPadding,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      ),
    );
    final updateBtn = OutlinedButton.icon(
      onPressed: _actionsEnabled ? _saveOnly : null,
      icon: Icon(Icons.save_outlined, size: iconSize),
      label: Text(
        'Update',
        style: compact ? const TextStyle(fontSize: 13) : null,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(compact ? 0 : 0, btnHeight),
        padding: btnPadding,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      ),
    );
    final whatsappBtn = FilledButton.tonalIcon(
      onPressed: _actionsEnabled ? _whatsappQuote : null,
      icon: Icon(
        Icons.chat_rounded,
        color: const Color(0xFF25D366),
        size: iconSize,
      ),
      label: Text(
        'WhatsApp Share',
        style: compact ? const TextStyle(fontSize: 13) : null,
      ),
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? 0 : double.infinity, btnHeight),
        padding: btnPadding,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          downloadBtn,
          const SizedBox(height: 6),
          if (!kIsWeb)
            Row(
              children: [
                Expanded(child: updateBtn),
                const SizedBox(width: 6),
                Expanded(child: whatsappBtn),
              ],
            )
          else
            updateBtn,
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: updateBtn),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: downloadBtn),
          ],
        ),
        if (!kIsWeb) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: whatsappBtn),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _runningTotal();
    final compact = _isCompactLayout(context);
    final screen = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 32,
        vertical: compact ? 8 : 20,
      ),
      child: ConstrainedBox(
        // Take the screen that is actually there. The old 720x620 cap meant a
        // desktop showed only a few fields at a time, and scrolling pushed the
        // section you were filling off the top.
        constraints: BoxConstraints(
          maxWidth: compact ? screen.width : 1180,
          maxHeight: screen.height * (compact ? 0.96 : 0.92),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 12 : 16,
            compact ? 12 : 16,
            compact ? 4 : 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                Text(
                  'Generate Professional Quotation',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'ATEPL',
                        label: Text('ATEPL Format'),
                        icon: Icon(Icons.business_rounded, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'ATS',
                        label: Text('ATS Format'),
                        icon: Icon(Icons.settings_suggest_rounded, size: 16),
                      ),
                    ],
                    selected: {_companyType},
                    onSelectionChanged: (Set<String> newSelection) {
                      _changeCompanyType(newSelection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Generate Professional Quotation',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'ATEPL',
                          label: Text('ATEPL Format'),
                          icon: Icon(Icons.business_rounded, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: 'ATS',
                          label: Text('ATS Format'),
                          icon: Icon(Icons.settings_suggest_rounded, size: 16),
                        ),
                      ],
                      selected: {_companyType},
                      onSelectionChanged: (Set<String> newSelection) {
                        _changeCompanyType(newSelection.first);
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              SizedBox(height: compact ? 8 : 12),
              Expanded(
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelStyle: compact
                            ? theme.textTheme.labelMedium
                            : null,
                        tabs: const [
                          Tab(text: 'Client & Ref'),
                          Tab(text: 'Product Details'),
                          Tab(text: 'Additional Items'),
                          Tab(text: 'Terms'),
                        ],
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildClientTab(compact),
                            _buildProductTab(theme),
                            _buildAdditionalItemsTab(theme),
                            _buildTermsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 12),
              _buildTotalAmountBar(theme, total, compact),
              SizedBox(height: compact ? 6 : 12),
              _buildActionButtons(compact),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style: compact
                      ? TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        )
                      : null,
                  child: Text(
                    'Cancel',
                    style: compact ? const TextStyle(fontSize: 13) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientTab(bool compact) {
    final theme = Theme.of(context);
    final cols = _isWideLayout(context) ? 2 : 1;

    InputDecoration deco(String label, {String? hint, String? help}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: help,
        border: const OutlineInputBorder(),
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        top: 4,
        right: compact ? 0 : 4,
        bottom: 16,
      ),
      children: [
        _sectionHeading(
          theme,
          'Quotation reference',
          icon: Icons.tag_rounded,
          subtitle: 'Printed at the top of the PDF.',
        ),
        _fieldGrid(
          columns: cols,
          [
            TextFormField(
              controller: _refNoController,
              decoration: deco(
                'Quotation Ref No. *',
                help: 'e.g. $_companyType/0609/2026-2027',
              ),
            ),
            TextFormField(
              controller: _dateController,
              decoration: deco('Date *', help: 'dd.mm.yyyy'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeading(
          theme,
          'Who this quotation is for',
          icon: Icons.badge_outlined,
          subtitle: 'Leave the contact name blank and the letter addresses '
              'the company instead.',
        ),
        _fieldGrid(
          columns: cols,
          [
            TextFormField(
              controller: _customerNameController,
              decoration: deco('Customer Name', hint: 'Contact person'),
            ),
            TextFormField(
              controller: _companyNameController,
              decoration: deco('Company Name'),
            ),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: deco('Email ID'),
            ),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: deco('Contact No.'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _locationController,
          maxLines: 2,
          decoration: deco(
            'Location / Client Address',
            help: 'Appears under the company name on the PDF.',
          ),
        ),
      ],
    );
  }

  Widget _buildProductTab(ThemeData theme) {
    final calibrationIndexes = <int>[];
    for (var i = 0; i < _additionalItems.length; i++) {
      if (_additionalItems[i].isCalibration) calibrationIndexes.add(i);
    }
    final isEmpty = _products.isEmpty && calibrationIndexes.isEmpty;

    return Column(
      children: [
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Product'),
              ),
              TextButton.icon(
                onPressed: _addCalibration,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Add Calibration'),
              ),
            ],
          ),
        ),
        Expanded(
          child: isEmpty
              ? Center(
                  child: Text(
                    'No products or calibration added yet. Click above to add items.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [
                    for (var i = 0; i < _products.length; i++)
                      _buildProductCard(theme, i),
                    for (var i = 0; i < calibrationIndexes.length; i++)
                      _buildCalibrationCard(
                        theme,
                        calibrationIndexes[i],
                        i + 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCalibrationCard(ThemeData theme, int itemIndex, int displayNo) {
    final item = _additionalItems[itemIndex];
    final rate = _parsePrice(item.rateController.text);
    final qtyRaw = item.qtyController.text.trim();
    final qtyNumMatch = RegExp(r'^\d+').firstMatch(qtyRaw);
    final qtyVal = qtyNumMatch != null
        ? (double.tryParse(qtyNumMatch.group(0)!) ?? 1.0)
        : 1.0;
    final amount = qtyVal * rate;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Calibration #$displayNo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                onPressed: () => _removeAdditionalItem(itemIndex),
                tooltip: 'Remove calibration',
              ),
            ],
          ),
          TextFormField(
            controller: item.descController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description *',
              hintText: 'Each comma starts a new line on the PDF',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Qty *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: item.rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit Rate',
                    border: OutlineInputBorder(),
                    prefixText: 'Rs ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Rs. ${_formatPrice(amount)}/-',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ThemeData theme, int index) {
    final p = _products[index];
    final compact = _isCompactLayout(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Product #${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                onPressed: () => _removeProduct(index),
                tooltip: 'Remove product',
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildProductNameField(p, required: index == 0),
          const SizedBox(height: 14),
          _fieldGrid(
            columns: compact ? 1 : 3,
            [
              TextFormField(
                controller: p.makeController,
                decoration: const InputDecoration(
                  labelText: 'Make',
                  border: OutlineInputBorder(),
                ),
              ),
              TextFormField(
                controller: p.modelController,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
              ),
              TextFormField(
                controller: p.hsnController,
                decoration: const InputDecoration(
                  labelText: 'HSN No.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionHeading(
            theme,
            'Pricing',
            icon: Icons.currency_rupee_rounded,
            subtitle: 'Quantity x unit rate becomes this line\'s amount.',
          ),
          _fieldGrid(
            columns: compact ? 1 : 2,
            [
              TextFormField(
                controller: p.qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Quantity *',
                  border: OutlineInputBorder(),
                ),
              ),
              TextFormField(
                controller: p.priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit Rate (Base Price) *',
                  border: OutlineInputBorder(),
                  prefixText: 'Rs ',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionHeading(
            theme,
            'Technical content',
            icon: Icons.article_outlined,
            subtitle: 'Everything below prints on the quotation. Leave a box '
                'empty to drop that section from the PDF.',
          ),
          _fieldGrid(
            columns: _isWideLayout(context) ? 2 : 1,
            [
              TextFormField(
                controller: p.overviewController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Product Overview',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Compact and rugged instrument...',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: p.featuresController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Key Feature',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Simultaneous multi-gas measurement...',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: p.specController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Technical Specification',
                  helperText: 'One bullet per line',
                  border: OutlineInputBorder(),
                  hintText:
                      'Response Time : Instantaneous\nAccuracy: +/- 0.05%',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: p.parametersController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Parameter Measured',
                  helperText: 'One per line: Gas, Sensor, Range, Resolution',
                  border: OutlineInputBorder(),
                  hintText: 'O2, EC, 0-25% V/V, 0.1%\nCO, NDIR, 0-50% V/V, 0.1%',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: p.accessoriesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Accessories',
                  helperText: 'One bullet per line',
                  border: OutlineInputBorder(),
                  hintText: 'Calibration Certificate, User Manual, etc.',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: p.documentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Document and Certificate',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalItemsTab(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addCustomLineItem,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Custom Line Item'),
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final regularIndexes = <int>[];
              for (var i = 0; i < _additionalItems.length; i++) {
                if (!_additionalItems[i].isCalibration) {
                  regularIndexes.add(i);
                }
              }
              if (regularIndexes.isEmpty) {
                return Center(
                  child: Text(
                    'No additional line items yet. Click above to add some (e.g. cables, services).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                  itemCount: regularIndexes.length,
                  itemBuilder: (context, displayIndex) {
                    final index = regularIndexes[displayIndex];
                    final item = _additionalItems[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Additional Item #${displayIndex + 1}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _removeAdditionalItem(index),
                                tooltip: 'Remove row',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: item.descController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Item Description / Scope *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: item.specController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText:
                                  'Specification (optional, one bullet per line)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: item.qtyController,
                                  decoration: const InputDecoration(
                                    labelText: 'Qty (e.g. 1 NO, 10 meters)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: item.rateController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Unit Rate (INR, optional)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTermsTab() {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addTerm,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Term & Condition'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _terms.length,
            itemBuilder: (context, index) {
              final term = _terms[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: term.keyController,
                        decoration: const InputDecoration(
                          labelText: 'Key / Label',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: term.valueController,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _removeTerm(index),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatPrice(double value) {
    final format = value.toStringAsFixed(0);
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formatted = format.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return formatted;
  }
}
